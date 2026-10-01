import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageClaudeWriteAmplificationTests {
    @Test(arguments: [2, 128], [false, true])
    func `unchanged scans preserve both cache and memo artifacts`(rowCount: Int, forceRescan: Bool) throws {
        let fixture = try Fixture(rowCount: rowCount)
        defer { fixture.env.cleanup() }
        for context in [CostUsageReportContext.regular, .spendDashboard] {
            let initial = try fixture.load(context: context)
            for cycle in 1...3 {
                // Drop the in-process memo as well, exercising the cross-launch baseline.
                CostUsageScanner.evictClaudeReportMemoForTesting(
                    provider: .claude, cacheRoot: fixture.env.cacheRoot, reportContext: context)
                let before = try fixture.stamps(context: context)
                let report = try fixture.load(context: context, cycle: cycle, forceRescan: forceRescan)
                let after = try fixture.stamps(context: context)
                let bytes = zip(before, after).reduce(Int64(0)) { $0 + ($1.0 == $1.1 ? 0 : $1.1.size) }
                print("[claude-json-writes] rows=\(rowCount) context=\(context) force=\(forceRescan) " +
                    "cycle=\(cycle) files=\(zip(before, after).filter { $0 != $1 }.count) bytes=\(bytes)")
                #expect(report.data == initial.data)
                #expect(report.hourly == initial.hourly)
                #expect(report.quotaSlices == initial.quotaSlices)
                #expect(after == before)
                #expect(bytes == 0)
            }
        }
    }

    @Test
    func `unchanged saves survive decoded artifact eviction without encoding`() throws {
        let fixture = try Fixture(rowCount: 128)
        defer { fixture.env.cleanup() }
        _ = try fixture.load(context: .regular)
        let url = fixture.cacheURL(context: .regular)
        let cache = CostUsageClaudeCacheIO.loadArtifact(provider: .claude, cacheRoot: fixture.env.cacheRoot)
        let before = try fixture.stamps(context: .regular)
        let recorder = CostUsageScanner.ClaudeScanWorkRecorder()
        try CostUsageScanner.withClaudeScanWorkRecorderForTesting(recorder) {
            for _ in 0..<3 {
                CostUsageClaudeCacheIO.evictArtifactMemoForTesting(at: url)
                _ = try CostUsageClaudeCacheIO.save(provider: .claude, cache: cache, cacheRoot: fixture.env.cacheRoot)
            }
        }
        #expect(recorder.snapshot().cacheEncodes == 0)
        #expect(recorder.persistenceSnapshot().reads == 0)
        #expect(recorder.persistenceSnapshot().writes == 0)
        #expect(try fixture.stamps(context: .regular) == before)
    }

    @Test
    func `changed content writes once without reading back either artifact`() throws {
        let fixture = try Fixture(rowCount: 2)
        defer { fixture.env.cleanup() }
        _ = try fixture.load(context: .regular)
        let url = fixture.cacheURL(context: .regular)
        var cache = CostUsageClaudeCacheIO.loadArtifact(provider: .claude, cacheRoot: fixture.env.cacheRoot)
        cache.usage.lastScanUnixMs += 1
        let recorder = CostUsageScanner.ClaudeScanWorkRecorder()
        try CostUsageScanner.withClaudeScanWorkRecorderForTesting(recorder) {
            for _ in 0..<3 {
                _ = try CostUsageClaudeCacheIO.save(provider: .claude, cache: cache, cacheRoot: fixture.env.cacheRoot)
            }
        }
        #expect(recorder.snapshot().cacheEncodes == 1)
        #expect(recorder.persistenceSnapshot().writes == 1)
        #expect(recorder.persistenceSnapshot().reads == 0)
        let decoded = try JSONDecoder().decode(CostUsageClaudeCacheArtifact.self, from: Data(contentsOf: url))
        #expect(decoded.usage == cache.usage)
        #expect(decoded.sourceFileIDs == cache.sourceFileIDs)

        let memo = try #require(CostUsageClaudeReportMemo.shared.entry(
            provider: .claude, canonicalCachePath: url.path))
        var inventory = memo.sourceInventory
        inventory.removeAll()
        let memoRecorder = CostUsageScanner.ClaudeScanWorkRecorder()
        CostUsageScanner.withClaudeScanWorkRecorderForTesting(memoRecorder) {
            for _ in 0..<3 {
                CostUsageClaudeReportMemo.shared.store(
                    provider: .claude,
                    canonicalCachePath: url.path,
                    sourceInventory: inventory,
                    reportKey: memo.reportKey,
                    report: memo.report,
                    hasWindowScopedRows: memo.hasWindowScopedRows)
            }
        }
        #expect(memoRecorder.persistenceSnapshot().writes == 1)
        #expect(memoRecorder.persistenceSnapshot().reads == 0)
        CostUsageClaudeReportMemo.shared.evict(provider: .claude, canonicalCachePath: url.path)
        let loaded = try #require(CostUsageClaudeReportMemo.shared.entry(
            provider: .claude, canonicalCachePath: url.path))
        #expect(loaded.sourceInventory.isEmpty)
        #expect(loaded.report.data == memo.report.data)
        #expect(loaded.report.hourly == memo.report.hourly)
        #expect(loaded.report.quotaSlices == memo.report.quotaSlices)
    }

    @Test
    func `identical external replacements still rewrite with matching size and mtime`() throws {
        let fixture = try Fixture(rowCount: 2)
        defer { fixture.env.cleanup() }
        _ = try fixture.load(context: .regular)
        let url = fixture.cacheURL(context: .regular)
        let memoURL = CostUsageClaudeReportMemo.reportMemoFileURL(cacheFileURL: url)
        for artifactURL in [url, memoURL] {
            try FileManager.default.setAttributes([.modificationDate: fixture.day], ofItemAtPath: artifactURL.path)
        }
        CostUsageClaudeReportMemo.shared.evict(provider: .claude, canonicalCachePath: url.path)
        let memo = try #require(CostUsageClaudeReportMemo.shared.entry(
            provider: .claude, canonicalCachePath: url.path))
        let cache = CostUsageClaudeCacheIO.loadArtifact(provider: .claude, cacheRoot: fixture.env.cacheRoot)
        let before = try fixture.stamps(context: .regular)
        for (index, artifactURL) in [url, memoURL].enumerated() {
            try Data(contentsOf: artifactURL).write(to: artifactURL, options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: fixture.day], ofItemAtPath: artifactURL.path)
            let replacement = try #require(CostUsageClaudeFileStamp.read(at: artifactURL))
            #expect(replacement.size == before[index].size)
            #expect(replacement.modifiedSeconds == before[index].modifiedSeconds)
            #expect(replacement.modifiedNanoseconds == before[index].modifiedNanoseconds)
            #expect(replacement.fileID != before[index].fileID)
        }
        let recorder = CostUsageScanner.ClaudeScanWorkRecorder()
        try CostUsageScanner.withClaudeScanWorkRecorderForTesting(recorder) {
            _ = try CostUsageClaudeCacheIO.save(provider: .claude, cache: cache, cacheRoot: fixture.env.cacheRoot)
            CostUsageClaudeReportMemo.shared.store(
                provider: .claude,
                canonicalCachePath: url.path,
                sourceInventory: memo.sourceInventory,
                reportKey: memo.reportKey,
                report: memo.report,
                hasWindowScopedRows: memo.hasWindowScopedRows)
        }
        #expect(recorder.snapshot().cacheEncodes == 1)
        #expect(recorder.persistenceSnapshot().writes == 2)
        #expect(recorder.persistenceSnapshot().reads == 0)
    }

    @Test
    func `legacy sorted JSON loads and rebuilt identical content preserves stamps`() throws {
        let fixture = try Fixture(rowCount: 2)
        defer { fixture.env.cleanup() }
        _ = try fixture.load(context: .regular)
        let url = fixture.cacheURL(context: .regular)
        let original = CostUsageClaudeCacheIO.loadArtifact(provider: .claude, cacheRoot: fixture.env.cacheRoot)
        // The current release's encoder and atomic replacement path, without any new identity memo.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let legacyBytes = try encoder.encode(original)
        let temporaryURL = url.appendingPathExtension("legacy")
        try legacyBytes.write(to: temporaryURL)
        #expect(rename(temporaryURL.path, url.path) == 0)
        CostUsageClaudeCacheIO.evictArtifactMemoForTesting(at: url)
        var loaded = CostUsageClaudeCacheIO.loadArtifact(provider: .claude, cacheRoot: fixture.env.cacheRoot)
        #expect(loaded.usage == original.usage)
        #expect(loaded.sourceFileIDs == original.sourceFileIDs)
        let before = try #require(CostUsageClaudeFileStamp.read(at: url))
        let usage = loaded.usage
        loaded.usage = usage // A rebuilt value has a new UUID even when its serialized bytes are identical.
        #expect(loaded.contentID != original.contentID)
        let recorder = CostUsageScanner.ClaudeScanWorkRecorder()
        try CostUsageScanner.withClaudeScanWorkRecorderForTesting(recorder) {
            for _ in 0..<2 {
                _ = try CostUsageClaudeCacheIO.save(provider: .claude, cache: loaded, cacheRoot: fixture.env.cacheRoot)
            }
        }
        #expect(recorder.snapshot().cacheEncodes == 1)
        #expect(recorder.persistenceSnapshot().writes == 0)
        #expect(recorder.persistenceSnapshot().reads == 0)
        #expect(CostUsageClaudeFileStamp.read(at: url) == before)
        #expect(try Data(contentsOf: url) == legacyBytes)
    }

    @Test
    func `identical save checks cancellation and cannot ignore an external replacement`() throws {
        let fixture = try Fixture(rowCount: 2)
        defer { fixture.env.cleanup() }
        _ = try fixture.load(context: .regular)
        let cache = CostUsageClaudeCacheIO.loadArtifact(provider: .claude, cacheRoot: fixture.env.cacheRoot)
        let before = try fixture.stamps(context: .regular)
        #expect(throws: CancellationError.self) {
            try CostUsageClaudeCacheIO.save(
                provider: .claude,
                cache: cache,
                cacheRoot: fixture.env.cacheRoot,
                checkCancellation: { throw CancellationError() })
        }
        #expect(try fixture.stamps(context: .regular) == before)
        var replacement = cache
        replacement.usage.lastScanUnixMs += 1
        let url = fixture.cacheURL(context: .regular)
        try JSONEncoder().encode(replacement).write(to: url, options: .atomic)
        _ = try CostUsageClaudeCacheIO.save(provider: .claude, cache: cache, cacheRoot: fixture.env.cacheRoot)
        let restored = try JSONDecoder().decode(CostUsageClaudeCacheArtifact.self, from: Data(contentsOf: url))
        #expect(restored.usage == cache.usage)
        #expect(restored.sourceFileIDs == cache.sourceFileIDs)
    }

    @Test
    func `canonically equal model edits persist exact UTF8 bytes`() throws {
        let fixture = try Fixture(rowCount: 1)
        defer { fixture.env.cleanup() }
        _ = try fixture.load(context: .regular)
        var cache = CostUsageClaudeCacheIO.loadArtifact(provider: .claude, cacheRoot: fixture.env.cacheRoot)
        let path = try #require(cache.usage.files.keys.first)
        let row = try #require(cache.usage.files[path]?.claudeRows?.first)
        var fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
        let models = ["synthetic-\u{00E9}", "synthetic-e\u{0301}"]
        #expect(models[0] == models[1])
        for model in models {
            fields["m"] = model
            let data = try JSONSerialization.data(withJSONObject: fields)
            cache.usage.files[path]?.claudeRows = try [JSONDecoder().decode(
                CostUsageScanner.ClaudeUsageRow.self,
                from: data)]
            _ = try CostUsageClaudeCacheIO.save(provider: .claude, cache: cache, cacheRoot: fixture.env.cacheRoot)
            let stored = try JSONDecoder().decode(
                CostUsageClaudeCacheArtifact.self, from: Data(contentsOf: fixture.cacheURL(context: .regular)))
            #expect(stored.usage.files[path]?.claudeRows?.first?.model.utf8.elementsEqual(model.utf8) == true)
        }
    }

    struct Fixture {
        let env: CostUsageTestEnvironment
        let day: Date
        let identityPadding: String

        init(rowCount: Int, identityLength: Int = 0) throws {
            self.identityPadding = String(repeating: "s", count: identityLength)
            self.env = try CostUsageTestEnvironment()
            self.day = try self.env.makeLocalNoon(year: 2026, month: 7, day: 1)
            _ = try self.env.writeClaudeProjectFile(
                relativePath: "session.jsonl", contents: (0..<rowCount).map(self.event).joined())
        }

        func event(index: Int) throws -> String {
            try self.env.jsonl([[
                "type": "assistant", "timestamp": self.env.isoString(for: self.day.addingTimeInterval(Double(index))),
                "requestId": "request-\(self.identityPadding)\(index)",
                "message": [
                    "id": "message-\(self.identityPadding)\(index)",
                    "model": "claude-sonnet-4-20250514",
                    "usage": ["input_tokens": 10, "output_tokens": 5],
                ],
            ]])
        }

        func cacheURL(context: CostUsageReportContext) -> URL {
            CostUsageClaudeCacheIO.cacheFileURL(
                provider: .claude,
                cacheRoot: self.env.cacheRoot,
                reportContext: context)
        }

        func stamps(context: CostUsageReportContext) throws -> [CostUsageClaudeFileStamp] {
            let cache = self.cacheURL(context: context)
            return try [cache, CostUsageClaudeReportMemo.reportMemoFileURL(cacheFileURL: cache)].map {
                try #require(CostUsageClaudeFileStamp.read(at: $0))
            }
        }

        func load(
            context: CostUsageReportContext,
            cycle: Int = 0,
            forceRescan: Bool = false) throws -> CostUsageDailyReport
        {
            var options = CostUsageScanner.Options(
                claudeProjectsRoots: [self.env.claudeProjectsRoot], cacheRoot: self.env.cacheRoot)
            options.refreshMinIntervalSeconds = 0
            options.forceRescan = forceRescan
            return try CostUsageScanner.loadDailyReportCancellable(
                provider: .claude,
                since: self.day.addingTimeInterval(context == .regular ? -29 * 86400 : -364 * 86400),
                until: self.day,
                now: self.day.addingTimeInterval(Double(cycle * 900)),
                options: options,
                reportContext: context,
                checkCancellation: nil)
        }
    }
}
