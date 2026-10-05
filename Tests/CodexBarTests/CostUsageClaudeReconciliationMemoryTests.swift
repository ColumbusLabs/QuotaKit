import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized, CostUsageClaudeCacheFixtures())
struct CostUsageClaudeReconciliationMemoryTests {
    @Test
    func `winner payload contains only two indexes`() {
        let priorStride = MemoryLayout<(path: String, row: CostUsageScanner.ClaudeUsageRow)>.stride
        #expect(CostUsageScanner.claudeWinnerPayloadStride == 2 * MemoryLayout<Int>.stride)
        #expect(CostUsageScanner.claudeWinnerPayloadStride * 10 < priorStride)
    }

    /// The prior row-copy implementation is the ordering oracle; reports retain QuotaKit semantics.
    @Test(arguments: 0..<4)
    func `randomized duplicate order preserves exact output`(seed: Int) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        var generator = Generator(state: UInt64(seed))
        var cache = CostUsageClaudeRebuildTests.cache(fileCount: 64, rowsPerFile: 50, includeOverflow: true)
        let files = cache.files.sorted { $0.key < $1.key }.shuffled(using: &generator)
        cache.files = [:]
        for (path, var file) in files {
            file.claudeRows?.shuffle(using: &generator)
            cache.files[path] = file
        }
        cache.files["empty"] = .init(mtimeUnixMs: 0, size: 0, days: [:], claudeRows: [])
        var reference = cache
        let referenceRows = Self.referenceRows(cache: reference)
        let rows = CostUsageScanner.reconciledClaudeRows(cache: cache)
        CostUsageScanner.rebuildClaudeDays(cache: &cache, rows: rows)
        let report = CostUsageScanner.buildClaudeReportFromCache(
            cache: cache,
            range: CostUsageClaudeRebuildTests.range,
            now: CostUsageClaudeRebuildTests.now,
            modelsDevCacheRoot: env.cacheRoot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try [
            encoder.encode(rows), encoder.encode(cache.days), encoder.encode(report),
            encoder.encode(report.hourly.map(CostUsageCodexPreviousReport.HourlyEntry.init)),
            encoder.encode(report.quotaSlices.map(CostUsageCodexPreviousReport.QuotaSlice.init)),
        ]
        CostUsageScanner.rebuildClaudeDays(cache: &reference, rows: referenceRows)
        let referenceReport = CostUsageScanner.buildClaudeReportFromCache(
            cache: reference,
            range: CostUsageClaudeRebuildTests.range,
            now: CostUsageClaudeRebuildTests.now,
            modelsDevCacheRoot: env.cacheRoot)
        let referenceBytes = try [
            encoder.encode(referenceRows), encoder.encode(reference.days), encoder.encode(referenceReport),
            encoder.encode(referenceReport.hourly.map(CostUsageCodexPreviousReport.HourlyEntry.init)),
            encoder.encode(referenceReport.quotaSlices.map(CostUsageCodexPreviousReport.QuotaSlice.init)),
        ]
        #expect(bytes == referenceBytes)
        #expect(cache.days["2026-09-01"]?["fixture/overflow"] == nil)
    }

    @Test
    func `cancellation after reconciliation leaves the cache and memo intact`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let now = CostUsageClaudeRebuildTests.now
        _ = try env.writeClaudeProjectFile(relativePath: "project/session.jsonl", contents: """
        {"type":"assistant","timestamp":"2026-09-30T12:00:00Z","requestId":"fixture-request",
        "message":{"id":"fixture-message","model":"claude-sonnet-4-6",
        "usage":{"input_tokens":10,"output_tokens":1}}}
        """.replacingOccurrences(of: "\n", with: "") + "\n")
        var options = CostUsageScanner.Options(
            claudeProjectsRoots: [env.claudeProjectsRoot],
            cacheRoot: env.cacheRoot,
            calendar: CostUsageClaudeRebuildTests.range.calendar)
        options.refreshMinIntervalSeconds = 0
        let prior = try CostUsageScanner.loadDailyReportCancellable(
            provider: .claude, since: now, until: now, now: now, options: options, checkCancellation: nil)
        let cacheURL = CostUsageClaudeCacheIO.cacheFileURL(provider: .claude, cacheRoot: env.cacheRoot)
        let memoURL = CostUsageClaudeReportMemo.reportMemoFileURL(cacheFileURL: cacheURL)
        let before = try [Data(contentsOf: cacheURL), Data(contentsOf: memoURL)]
        let recorder = CostUsageScanner.ClaudeScanWorkRecorder()
        options.forceRescan = true
        #expect(throws: CancellationError.self) {
            try CostUsageScanner.withClaudeScanWorkRecorderForTesting(recorder) {
                _ = try CostUsageScanner.loadDailyReportCancellable(
                    provider: .claude,
                    since: now,
                    until: now,
                    now: now,
                    options: options,
                    checkCancellation: {
                        if recorder.snapshot().reconciliations > 0 { throw CancellationError() }
                    })
            }
        }
        #expect(recorder.snapshot().reconciliations == 1)
        #expect(try [Data(contentsOf: cacheURL), Data(contentsOf: memoURL)] == before)
        options.forceRescan = false
        let after = try CostUsageScanner.loadDailyReportCancellable(
            provider: .claude, since: now, until: now, now: now, options: options, checkCancellation: nil)
        #expect(after.data == prior.data)
        #expect(after.summary == prior.summary)
        #expect(after.hourly == prior.hourly)
        #expect(after.quotaSlices == prior.quotaSlices)
    }

    private typealias ClaudeUsageRow = CostUsageScanner.ClaudeUsageRow

    private enum ClaudeRowKey: Hashable, Comparable {
        case request(messageId: String, requestId: String)
        case session(sessionId: String, messageId: String)

        static func < (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.request(lm, lr), .request(rm, rr)): (lm, lr) < (rm, rr)
            case let (.session(ls, lm), .session(rs, rm)): (ls, lm) < (rs, rm)
            case (.request, .session): true
            case (.session, .request): false
            }
        }
    }

    private static func claudeCanonicalRowKey(_ row: ClaudeUsageRow) -> ClaudeRowKey? {
        guard let messageId = row.messageId else { return nil }
        if let requestId = row.requestId {
            return .request(messageId: messageId, requestId: requestId)
        }
        guard !messageId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let sessionId = row.sessionId,
              !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return .session(sessionId: sessionId, messageId: messageId)
    }

    private static func claudeRowWins(
        lhs: (path: String, row: ClaudeUsageRow),
        rhs: (path: String, row: ClaudeUsageRow)) -> Bool
    {
        if (lhs.row.isIncomplete == true) != (rhs.row.isIncomplete == true) {
            return lhs.row.isIncomplete != true
        }
        if lhs.row.isSidechain != rhs.row.isSidechain {
            return rhs.row.isSidechain
        }
        if lhs.row.pathRole != rhs.row.pathRole {
            return rhs.row.pathRole == .subagent
        }
        return lhs.path < rhs.path
    }

    private static func referenceRows(cache: CostUsageCache) -> [ClaudeUsageRow] {
        var rows: [ClaudeUsageRow] = []
        var winners: [ClaudeRowKey: (path: String, row: ClaudeUsageRow)] = [:]

        for path in cache.files.keys.sorted() {
            guard let fileRows = cache.files[path]?.claudeRows else { continue }
            for row in fileRows {
                guard let canonicalKey = Self.claudeCanonicalRowKey(row) else {
                    rows.append(row)
                    continue
                }
                let candidate = (path: path, row: row)
                if let existing = winners[canonicalKey] {
                    if Self.claudeRowWins(lhs: candidate, rhs: existing) {
                        winners[canonicalKey] = candidate
                    }
                } else {
                    winners[canonicalKey] = candidate
                }
            }
        }

        rows.append(contentsOf: winners.keys.sorted().compactMap { winners[$0]?.row })
        return rows
    }

    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            self.state = self.state &* 6_364_136_223_846_793_005 &+ 1
            return self.state
        }
    }
}
