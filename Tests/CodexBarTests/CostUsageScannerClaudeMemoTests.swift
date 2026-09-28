import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageScannerClaudeMemoTests {
    @Test(arguments: [false, true])
    func `atomic transcript replacement discards prior rows in warm and cold processes`(cold: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 1)
        let file = try self.writeEvent(env: env, day: day, path: "project/session.jsonl", id: "old", input: 1000)
        let options = self.options(env: env)
        #expect(self.load(day: day, options: options).summary?.totalInputTokens == 1000)
        let original = try #require(CostUsageClaudeFileStamp.read(at: file))
        var first = self.event(env: env, day: day, id: "replacement-first", input: 7)
        first["fixturePadding"] = String(repeating: "x", count: Int(original.size) + 32)
        let replacement = try env.jsonl([first, self.event(env: env, day: day, id: "replacement-last", input: 17)])
        try Data(replacement.utf8).write(to: file, options: .atomic)
        let changed = try #require(CostUsageClaudeFileStamp.read(at: file))
        #expect(changed.fileID != original.fileID)
        #expect(changed.size > original.size)
        if cold {
            CostUsageScanner.evictClaudeReportMemoForTesting(provider: .claude, cacheRoot: env.cacheRoot)
        }

        let (report, work) = self.recordedLoad(day: day, options: options)
        #expect(work.transcriptParses == 1)
        #expect(work.incrementalTranscriptParses == 0)
        #expect(report.summary?.totalInputTokens == 24)
    }

    @Test(arguments: [false, true])
    func `same size and timestamp replacement still reparses`(cold: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 1)
        let file = try self.writeEvent(env: env, day: day, path: "project/session.jsonl", id: "same", input: 1000)
        try FileManager.default.setAttributes([.modificationDate: day], ofItemAtPath: file.path)
        let options = self.options(env: env)
        _ = self.load(day: day, options: options)
        let original = try #require(CostUsageClaudeFileStamp.read(at: file))
        let replacement = try env.jsonl([self.event(env: env, day: day, id: "same", input: 2000)])
        try Data(replacement.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: day], ofItemAtPath: file.path)
        let changed = try #require(CostUsageClaudeFileStamp.read(at: file))
        #expect(changed.fileID != original.fileID)
        #expect(changed.size == original.size)
        #expect(changed.mtimeUnixMs == original.mtimeUnixMs)
        if cold {
            CostUsageScanner.evictClaudeReportMemoForTesting(provider: .claude, cacheRoot: env.cacheRoot)
        }

        let (report, work) = self.recordedLoad(day: day, options: options)
        #expect(report.summary?.totalInputTokens == 2000)
        #expect(work.transcriptParses == 1)
        #expect(work.incrementalTranscriptParses == 0)
    }

    @Test
    func `legacy cache without identities is rebuilt before append reuse`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 1)
        let file = try self.writeEvent(env: env, day: day, path: "project/session.jsonl", id: "same", input: 10)
        var options = self.options(env: env)
        options.refreshMinIntervalSeconds = 60
        _ = self.load(day: day, options: options)
        let artifact = CostUsageClaudeCacheIO.loadArtifact(provider: .claude, cacheRoot: env.cacheRoot)
        let path = try #require(artifact.usage.files.keys.first)
        #expect(artifact.sourceFileIDs[path] == CostUsageClaudeFileStamp.read(at: file)?.fileID)
        try JSONEncoder().encode(artifact.usage).write(to: self.cacheURL(env: env))
        CostUsageScanner.evictClaudeReportMemoForTesting(provider: .claude, cacheRoot: env.cacheRoot)

        let (report, work) = self.recordedLoad(day: day, options: options)
        #expect(report.summary?.totalInputTokens == 10)
        #expect(work.transcriptParses == 1)
        #expect(work.incrementalTranscriptParses == 0)
        let refreshed = CostUsageClaudeCacheIO.loadArtifact(provider: .claude, cacheRoot: env.cacheRoot)
        #expect(refreshed.sourceFileIDs[path] == CostUsageClaudeFileStamp.read(at: file)?.fileID)
    }

    @Test
    func `identity cache keeps empty rows and prunes removed transcripts`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 1)
        let file = try env.writeClaudeProjectFile(relativePath: "project/empty.jsonl", contents: "{}\n")
        let options = self.options(env: env)
        _ = self.load(day: day, options: options)
        let artifact = CostUsageClaudeCacheIO.loadArtifact(provider: .claude, cacheRoot: env.cacheRoot)
        let path = try #require(artifact.usage.files.keys.first)
        #expect(artifact.usage.files[path]?.claudeRows == [])
        #expect(artifact.sourceFileIDs[path] == CostUsageClaudeFileStamp.read(at: file)?.fileID)
        CostUsageScanner.evictClaudeReportMemoForTesting(provider: .claude, cacheRoot: env.cacheRoot)
        #expect(self.recordedLoad(day: day, options: options).1.transcriptParses == 0)

        try FileManager.default.removeItem(at: file)
        _ = self.load(day: day, options: options)
        let pruned = CostUsageClaudeCacheIO.loadArtifact(provider: .claude, cacheRoot: env.cacheRoot)
        #expect(pruned.usage.files.isEmpty)
        #expect(pruned.sourceFileIDs.isEmpty)
    }

    @Test
    func `Claude parser changes use the current cache generation`() {
        let root = URL(fileURLWithPath: "/tmp/quotakit-claude-cache-generation", isDirectory: true)

        #expect(
            CostUsageClaudeCacheIO.cacheFileURL(provider: .claude, cacheRoot: root).lastPathComponent
                == "claude-v12.json")
    }

    @Test
    func `identical Claude cache saves retain the artifact stamp`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let cacheURL = CostUsageClaudeCacheIO.cacheFileURL(provider: .claude, cacheRoot: env.cacheRoot)
        var cache = CostUsageCache()
        cache.lastScanUnixMs = 1
        let firstSave = try CostUsageClaudeCacheIO.save(
            provider: .claude, cache: cache, cacheRoot: env.cacheRoot)
        let first = try #require(firstSave)
        let bytes = try Data(contentsOf: cacheURL)

        let secondSave = try CostUsageClaudeCacheIO.save(
            provider: .claude, cache: cache, cacheRoot: env.cacheRoot)
        let second = try #require(secondSave)
        #expect(second == first)
        #expect(try Data(contentsOf: cacheURL) == bytes)

        cache.lastScanUnixMs = 2
        let updatedSave = try CostUsageClaudeCacheIO.save(
            provider: .claude, cache: cache, cacheRoot: env.cacheRoot)
        _ = try #require(updatedSave)
        #expect(CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: env.cacheRoot).lastScanUnixMs == 2)
    }

    @Test
    func `unchanged cache artifacts decode once and same size replacement invalidates the memo`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 1)
        _ = try self.writeEvent(env: env, day: day, path: "project/session.jsonl", id: "first", input: 10)
        let options = self.options(env: env)
        _ = self.load(day: day, options: options)
        let cacheURL = self.cacheURL(env: env)
        let originalStamp = try #require(CostUsageClaudeFileStamp.read(at: cacheURL))
        let originalAttributes = try FileManager.default.attributesOfItem(atPath: cacheURL.path)
        let originalMtime = try #require(originalAttributes[.modificationDate] as? Date)

        CostUsageClaudeCacheIO.evictArtifactMemoForTesting(at: cacheURL)
        let warmRecorder = CostUsageScanner.ClaudeScanWorkRecorder()
        let warmArtifact = CostUsageScanner.withClaudeScanWorkRecorderForTesting(warmRecorder) {
            var artifact = CostUsageClaudeCacheArtifact()
            for _ in 0..<4 {
                artifact = CostUsageClaudeCacheIO.loadArtifact(provider: .claude, cacheRoot: env.cacheRoot)
            }
            return artifact
        }
        #expect(warmRecorder.snapshot().cacheDecodes == 1)
        #expect(!warmArtifact.usage.files.isEmpty)
        let unchangedSaveRecorder = CostUsageScanner.ClaudeScanWorkRecorder()
        let unchangedStamp = CostUsageScanner.withClaudeScanWorkRecorderForTesting(unchangedSaveRecorder) {
            try? CostUsageClaudeCacheIO.save(
                provider: .claude,
                cache: warmArtifact,
                cacheRoot: env.cacheRoot)
        }
        #expect(unchangedStamp == originalStamp)
        #expect(unchangedSaveRecorder.snapshot().cacheEncodes == 0)

        var replacement = warmArtifact
        replacement.usage.lastScanUnixMs += 1
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(replacement).write(to: cacheURL, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: originalMtime], ofItemAtPath: cacheURL.path)
        let replacementStamp = try #require(CostUsageClaudeFileStamp.read(at: cacheURL))
        #expect(replacementStamp.fileID != originalStamp.fileID)
        #expect(replacementStamp.size == originalStamp.size)
        #expect(replacementStamp.mtimeUnixMs == originalStamp.mtimeUnixMs)

        let replacementRecorder = CostUsageScanner.ClaudeScanWorkRecorder()
        let reloaded = CostUsageScanner.withClaudeScanWorkRecorderForTesting(replacementRecorder) {
            CostUsageClaudeCacheIO.loadArtifact(provider: .claude, cacheRoot: env.cacheRoot)
        }
        #expect(replacementRecorder.snapshot().cacheDecodes == 1)
        #expect(reloaded.usage.lastScanUnixMs == replacement.usage.lastScanUnixMs)
    }

    @Test
    func `schema two artifact rebuilds from source and preserves the report window`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let previousDay = try env.makeLocalNoon(year: 2026, month: 6, day: 30)
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 1)
        _ = try self.writeEvent(
            env: env, day: previousDay, path: "project/previous.jsonl", id: "previous", input: 10)
        _ = try self.writeEvent(env: env, day: day, path: "project/current.jsonl", id: "current", input: 20)
        let options = self.options(env: env)
        let initial = self.load(since: previousDay, until: day, now: day, options: options)
        #expect(initial.summary?.totalInputTokens == 30)
        #expect(initial.data.count == 2)

        let cacheURL = self.cacheURL(env: env)
        var legacy = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as? [String: Any])
        legacy["version"] = 2
        try JSONSerialization.data(withJSONObject: legacy).write(to: cacheURL, options: .atomic)

        let (upgraded, work) = self.recordedLoad(
            since: previousDay, until: day, now: day, options: options)

        #expect(upgraded.data == initial.data)
        #expect(upgraded.summary == initial.summary)
        #expect(work.cacheDecodes == 1)
        #expect(work.transcriptParses == 2)
        let rebuilt = CostUsageClaudeCacheIO.loadArtifact(provider: .claude, cacheRoot: env.cacheRoot)
        #expect(rebuilt.usage.version == 3)
        #expect(rebuilt.usage.files.count == 2)
        #expect(rebuilt.usage.days.count == 2)
    }

    @Test
    func `compact Claude cache rows round trip every field`() throws {
        let row = CostUsageScanner.ClaudeUsageRow(
            dayKey: "2026-07-01",
            model: "synthetic-model",
            sessionId: "session",
            messageId: "message",
            requestId: "request",
            timestampUnixMs: 123,
            isSidechain: true,
            pathRole: .subagent,
            input: 1,
            cacheRead: 2,
            cacheCreate: 3,
            cacheCreate1h: 4,
            output: 5,
            costNanos: 6,
            costPriced: false,
            isIncomplete: true)
        let data = try JSONEncoder().encode(row)
        let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(data.count < 240)
        #expect(fields.count == 16)
        #expect(fields["d"] as? String == row.dayKey)
        #expect(fields["dayKey"] == nil)
        #expect(try JSONDecoder().decode(CostUsageScanner.ClaudeUsageRow.self, from: data) == row)
    }

    @Test
    func `identical warm refresh only inventories sources`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 1)
        _ = try self.writeEvent(env: env, day: day, path: "project/session.jsonl", id: "first", input: 10)
        let options = self.options(env: env)
        let initial = self.load(day: day, options: options)
        let cacheURL = self.cacheURL(env: env)
        let cacheStamp = CostUsageClaudeFileStamp.read(at: cacheURL)

        let (warm, metrics) = self.recordedLoad(day: day, options: options)

        #expect(warm.data == initial.data)
        #expect(warm.summary == initial.summary)
        #expect(metrics == CostUsageScanner.ClaudeScanWorkMetrics())
        #expect(CostUsageClaudeFileStamp.read(at: cacheURL) == cacheStamp)
    }

    @Test
    func `cold process restores the compatible report memo`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 1)
        _ = try self.writeEvent(env: env, day: day, path: "project/first.jsonl", id: "first", input: 10)
        _ = try self.writeEvent(env: env, day: day, path: "project/second.jsonl", id: "second", input: 20)
        let options = self.options(env: env)
        let initial = self.load(day: day, options: options)
        let memoURL = CostUsageClaudeReportMemo.reportMemoFileURL(cacheFileURL: self.cacheURL(env: env))
        #expect(FileManager.default.fileExists(atPath: memoURL.path))
        CostUsageScanner.evictClaudeReportMemoForTesting(provider: .claude, cacheRoot: env.cacheRoot)

        let (restarted, metrics) = self.recordedLoad(day: day, options: options)

        #expect(restarted.data == initial.data)
        #expect(restarted.summary == initial.summary)
        #expect(!initial.quotaSlices.isEmpty)
        #expect(restarted.hourly == initial.hourly)
        #expect(restarted.quotaSlices == initial.quotaSlices)
        #expect(metrics == CostUsageScanner.ClaudeScanWorkMetrics())
    }

    @Test
    func `cold memo preserves priced and unpriced requests at one timestamp`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 1)
        _ = try self.writeEvent(env: env, day: day, path: "project/priced.jsonl", id: "priced", input: 100)
        _ = try self.writeEvent(
            env: env,
            day: day,
            path: "project/unpriced.jsonl",
            id: "unpriced",
            input: 200,
            model: "fixture-model-without-price")
        let options = self.options(env: env)
        let initial = self.load(day: day, options: options)
        let slice = try #require(initial.quotaSlices.first)
        #expect(slice.totalTokens == 300)
        #expect(slice.tokensAreComplete)
        #expect(slice.costUSD != nil)
        #expect(!slice.costIsComplete)
        CostUsageScanner.evictClaudeReportMemoForTesting(provider: .claude, cacheRoot: env.cacheRoot)
        let (restarted, metrics) = self.recordedLoad(day: day, options: options)
        #expect(restarted.quotaSlices == initial.quotaSlices)
        #expect(restarted.hourly == initial.hourly)
        #expect(metrics == CostUsageScanner.ClaudeScanWorkMetrics())
    }

    @Test(arguments: [nil, 0, 4, CostUsageClaudeReportMemo.reportSemanticsVersion + 1] as [Int?])
    func `cold process rejects reports from incompatible semantics`(revision: Int?) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 1)
        let sourceURL = try self.writeEvent(env: env, day: day, path: "project/session.jsonl", id: "first", input: 10)
        let options = self.options(env: env)
        let initial = self.load(day: day, options: options)
        let sourceStamp = CostUsageClaudeFileStamp.read(at: sourceURL)
        let memoURL = CostUsageClaudeReportMemo.reportMemoFileURL(cacheFileURL: self.cacheURL(env: env))
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: memoURL)) as? [String: Any])
        envelope["reportSemanticsVersion"] = revision
        envelope["report"] = [
            "type": "codexbar-claude-report-memo", "data": [],
            "summary": ["totalTokens": 9999, "totalCostUSD": 9999],
        ]
        try JSONSerialization.data(withJSONObject: envelope).write(to: memoURL)
        CostUsageScanner.evictClaudeReportMemoForTesting(provider: .claude, cacheRoot: env.cacheRoot)

        let (restarted, metrics) = self.recordedLoad(day: day, options: options)

        #expect(restarted.data == initial.data)
        #expect(restarted.summary == initial.summary)
        #expect(!initial.quotaSlices.isEmpty)
        #expect(restarted.hourly == initial.hourly)
        #expect(restarted.quotaSlices == initial.quotaSlices)
        #expect(metrics.transcriptParses == 0)
        #expect(CostUsageClaudeFileStamp.read(at: sourceURL) == sourceStamp)
        let rewritten = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: memoURL)) as? [String: Any])
        #expect(rewritten["reportSemanticsVersion"] as? Int == CostUsageClaudeReportMemo.reportSemanticsVersion)
    }

    @Test
    func `nested source addition invalidates the memo`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 2)
        _ = try self.writeEvent(env: env, day: day, path: "project/session.jsonl", id: "first", input: 10)
        let options = self.options(env: env)
        _ = self.load(day: day, options: options)
        _ = try self.writeEvent(
            env: env,
            day: day,
            path: "project/nested/deeper/session.jsonl",
            id: "nested",
            input: 20)

        let (report, metrics) = self.recordedLoad(day: day, options: options)

        #expect(report.summary?.totalInputTokens == 30)
        #expect(metrics.transcriptParses == 1)
        #expect(metrics.cacheEncodes == 1)
    }

    @Test
    func `source append invalidates the memo and parses the delta`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 3)
        let fileURL = try self.writeEvent(
            env: env,
            day: day,
            path: "project/session.jsonl",
            id: "first",
            input: 10)
        let options = self.options(env: env)
        _ = self.load(day: day, options: options)
        let appended = try env.jsonl([self.event(env: env, day: day, id: "second", input: 20)])
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(appended.utf8))
        try handle.close()

        let (report, metrics) = self.recordedLoad(day: day, options: options)

        #expect(report.summary?.totalInputTokens == 30)
        #expect(metrics.transcriptParses == 1)
        #expect(metrics.cacheEncodes == 1)
    }

    @Test
    func `individual source deletion invalidates the memo and removes its rows`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 4)
        let deletedURL = try self.writeEvent(
            env: env,
            day: day,
            path: "project/deleted.jsonl",
            id: "deleted",
            input: 10)
        _ = try self.writeEvent(
            env: env,
            day: day,
            path: "project/retained.jsonl",
            id: "retained",
            input: 20)
        let options = self.options(env: env)
        _ = self.load(day: day, options: options)
        try FileManager.default.removeItem(at: deletedURL)

        let (report, metrics) = self.recordedLoad(day: day, options: options)

        #expect(report.summary?.totalInputTokens == 20)
        #expect(metrics.transcriptParses == 0)
        #expect(metrics.cacheEncodes == 1)
    }

    @Test
    func `missing source root invalidates the memo and deletes cached rows`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 4)
        _ = try self.writeEvent(env: env, day: day, path: "project/session.jsonl", id: "first", input: 10)
        let options = self.options(env: env)
        _ = self.load(day: day, options: options)
        try FileManager.default.removeItem(at: env.claudeProjectsRoot)

        let (report, metrics) = self.recordedLoad(day: day, options: options)

        #expect(report.data.isEmpty)
        #expect(metrics.transcriptParses == 0)
        #expect(metrics.cacheEncodes == 1)
    }

    @Test
    func `external atomic cache replacement invalidates the memo`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 5)
        _ = try self.writeEvent(env: env, day: day, path: "project/session.jsonl", id: "first", input: 10)
        let options = self.options(env: env)
        let initial = self.load(day: day, options: options)
        let cacheURL = self.cacheURL(env: env)
        let originalStamp = try #require(CostUsageClaudeFileStamp.read(at: cacheURL))
        let cacheData = try Data(contentsOf: cacheURL)
        try cacheData.write(to: cacheURL, options: [.atomic])
        let replacementStamp = try #require(CostUsageClaudeFileStamp.read(at: cacheURL))
        #expect(replacementStamp.fileID != originalStamp.fileID)

        let (report, metrics) = self.recordedLoad(day: day, options: options)

        #expect(report.data == initial.data)
        #expect(metrics.cacheDecodes == 1)
        #expect(metrics.transcriptParses == 0)
        #expect(metrics.cacheEncodes == 0)
    }

    @Test
    func `force rescan bypasses an exact memo hit`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 6)
        _ = try self.writeEvent(env: env, day: day, path: "project/session.jsonl", id: "first", input: 10)
        var options = self.options(env: env)
        _ = self.load(day: day, options: options)
        options.forceRescan = true

        let (report, metrics) = self.recordedLoad(day: day, options: options)

        #expect(report.summary?.totalInputTokens == 10)
        #expect(metrics.transcriptParses == 1)
        #expect(metrics.cacheEncodes == 1)
        #expect(metrics.repricedRows == 1)
    }

    @Test
    func `pricing replacement reprices without parsing or rewriting the claude cache`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 7)
        let model = "claude-test-memo-pricing"
        _ = try self.writeEvent(
            env: env,
            day: day,
            path: "project/session.jsonl",
            id: "first",
            input: 100,
            model: model)
        #expect(try ModelsDevCache.save(
            catalog: self.catalog(model: model, inputRate: 10),
            fetchedAt: day,
            cacheRoot: env.cacheRoot))
        let options = self.options(env: env)
        let first = self.load(day: day, options: options)
        let cacheURL = self.cacheURL(env: env)
        let cacheStamp = CostUsageClaudeFileStamp.read(at: cacheURL)
        #expect(abs((first.summary?.totalCostUSD ?? 0) - 0.001) < 0.000000001)
        #expect(try ModelsDevCache.save(
            catalog: self.catalog(model: model, inputRate: 20),
            fetchedAt: day.addingTimeInterval(1),
            cacheRoot: env.cacheRoot))

        let (repriced, metrics) = self.recordedLoad(day: day, options: options)

        #expect(abs((repriced.summary?.totalCostUSD ?? 0) - 0.002) < 0.000000001)
        #expect(metrics.transcriptParses == 0)
        #expect(metrics.cacheEncodes == 0)
        #expect(metrics.repricedRows == 1)
        #expect(CostUsageClaudeFileStamp.read(at: cacheURL) == cacheStamp)
    }

    @Test
    func `timezone change invalidates the memo and rebuilds the cache`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 8)
        _ = try self.writeEvent(env: env, day: day, path: "project/session.jsonl", id: "first", input: 10)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var options = self.options(env: env, calendar: utc)
        _ = self.load(day: day, options: options)
        var shifted = Calendar(identifier: .gregorian)
        shifted.timeZone = try #require(TimeZone(secondsFromGMT: 3600))
        options.calendar = shifted

        let (report, metrics) = self.recordedLoad(day: day, options: options)

        #expect(report.summary?.totalInputTokens == 10)
        #expect(metrics.transcriptParses == 1)
        #expect(metrics.cacheEncodes == 1)
    }

    @Test
    func `cancellation preserves disk and the prior memo`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 9)
        _ = try self.writeEvent(env: env, day: day, path: "project/session.jsonl", id: "first", input: 10)
        var options = self.options(env: env)
        _ = self.load(day: day, options: options)
        let cacheURL = self.cacheURL(env: env)
        let diskBefore = try Data(contentsOf: cacheURL)
        let stampBefore = CostUsageClaudeFileStamp.read(at: cacheURL)
        options.forceRescan = true
        var checks = 0

        #expect(throws: CancellationError.self) {
            _ = try CostUsageScanner.loadDailyReportCancellable(
                provider: .claude,
                since: day,
                until: day,
                now: day.addingTimeInterval(1),
                options: options,
                checkCancellation: {
                    checks += 1
                    if checks == 4 {
                        throw CancellationError()
                    }
                })
        }
        #expect(try Data(contentsOf: cacheURL) == diskBefore)
        #expect(CostUsageClaudeFileStamp.read(at: cacheURL) == stampBefore)

        options.forceRescan = false
        let (_, metrics) = self.recordedLoad(day: day, options: options)
        #expect(metrics == CostUsageScanner.ClaudeScanWorkMetrics())
    }

    private func options(
        env: CostUsageTestEnvironment,
        calendar: Calendar = .current) -> CostUsageScanner.Options
    {
        var options = CostUsageScanner.Options(
            claudeProjectsRoots: [env.claudeProjectsRoot],
            cacheRoot: env.cacheRoot,
            calendar: calendar)
        options.refreshMinIntervalSeconds = 0
        return options
    }

    private func load(day: Date, options: CostUsageScanner.Options) -> CostUsageDailyReport {
        self.load(since: day, until: day, now: day, options: options)
    }

    private func load(
        since: Date,
        until: Date,
        now: Date,
        options: CostUsageScanner.Options) -> CostUsageDailyReport
    {
        CostUsageScanner.loadDailyReport(
            provider: .claude,
            since: since,
            until: until,
            now: now,
            options: options)
    }

    private func recordedLoad(
        day: Date,
        options: CostUsageScanner.Options) -> (CostUsageDailyReport, CostUsageScanner.ClaudeScanWorkMetrics)
    {
        self.recordedLoad(since: day, until: day, now: day, options: options)
    }

    private func recordedLoad(
        since: Date,
        until: Date,
        now: Date,
        options: CostUsageScanner.Options) -> (CostUsageDailyReport, CostUsageScanner.ClaudeScanWorkMetrics)
    {
        let recorder = CostUsageScanner.ClaudeScanWorkRecorder()
        let report = CostUsageScanner.withClaudeScanWorkRecorderForTesting(recorder) {
            self.load(since: since, until: until, now: now, options: options)
        }
        return (report, recorder.snapshot())
    }

    private func writeEvent(
        env: CostUsageTestEnvironment,
        day: Date,
        path: String,
        id: String,
        input: Int,
        model: String = "claude-sonnet-4-20250514") throws -> URL
    {
        try env.writeClaudeProjectFile(
            relativePath: path,
            contents: env.jsonl([self.event(env: env, day: day, id: id, input: input, model: model)]))
    }

    private func event(
        env: CostUsageTestEnvironment,
        day: Date,
        id: String,
        input: Int,
        model: String = "claude-sonnet-4-20250514") -> [String: Any]
    {
        [
            "type": "assistant",
            "timestamp": env.isoString(for: day),
            "sessionId": "session-\(id)",
            "requestId": "request-\(id)",
            "message": [
                "id": "message-\(id)",
                "model": model,
                "usage": [
                    "input_tokens": input,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": 0,
                    "output_tokens": 0,
                ],
            ],
        ]
    }

    private func catalog(model: String, inputRate: Double) throws -> ModelsDevCatalog {
        try JSONDecoder().decode(ModelsDevCatalog.self, from: Data("""
        {
          "anthropic": {
            "id": "anthropic",
            "models": {
              "\(model)": {
                "id": "\(model)",
                "cost": { "input": \(inputRate), "output": 1 }
              }
            }
          }
        }
        """.utf8))
    }

    private func cacheURL(env: CostUsageTestEnvironment) -> URL {
        CostUsageClaudeCacheIO.cacheFileURL(provider: .claude, cacheRoot: env.cacheRoot)
    }
}
