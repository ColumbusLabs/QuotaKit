#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageClaudeRebuildTests {
    /// Captured from the original ordered reconciliation and packed-day rebuild.
    @Test
    func `seeded cache preserves exact row day and report output`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        var cache = Self.cache(fileCount: 64, rowsPerFile: 50, includeOverflow: true)
        let rows = CostUsageScanner.reconciledClaudeRows(cache: cache)
        CostUsageScanner.rebuildClaudeDays(cache: &cache, rows: rows)
        let report = CostUsageScanner.buildClaudeReportFromCache(
            cache: cache, range: Self.range, now: Self.now, modelsDevCacheRoot: env.cacheRoot)
        #expect(try Self.digest(rows) == "6260cd7640a6e48831af1d67ca2d78ecbe606db0374f5a1f31d8bda3b509a6f5")
        #expect(try Self.digest(cache.days) == "900db7be9b3420d62fccdea6d1ab359528f1b736c95bb332c1eb98a2b8aa4544")
        #expect(try Self.digest(report.hourly.map(CostUsageCodexPreviousReport.HourlyEntry.init))
            == "7e9f76fc6fd41c9755399563e10bfaad51708e0e5e9676abba785af3553133d4")
        #expect(try Self.digest(report.quotaSlices.map(CostUsageCodexPreviousReport.QuotaSlice.init))
            == "ff44af15a44b217acedff8e0d76241c8d32152c36c5d671e2157b9fd557a2093")
        // Compare the optimized accumulation with the prior packed-day algorithm while
        // preserving QuotaKit's report semantics, which differ from upstream's golden report.
        var reference = Self.cache(fileCount: 64, rowsPerFile: 50, includeOverflow: true)
        Self.rebuildReferenceDays(cache: &reference, rows: rows)
        #expect(cache.days == reference.days)
        let referenceReport = CostUsageScanner.buildClaudeReportFromCache(
            cache: reference, range: Self.range, now: Self.now, modelsDevCacheRoot: env.cacheRoot)
        #expect(report.data == referenceReport.data)
        #expect(report.summary == referenceReport.summary)
        #expect(report.hourly == referenceReport.hourly)
        #expect(report.quotaSlices == referenceReport.quotaSlices)
        #expect(cache.days["2026-09-01"]?["fixture/overflow"] == nil)
        #expect(rows.contains { $0.isIncomplete == true })
        #expect(rows.contains { $0.messageId == nil })
    }

    static let now = Date(timeIntervalSince1970: 1_790_769_600) // 2026-09-30 12:00 UTC
    static var range: CostUsageScanner.CostUsageDayRange {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return .init(since: self.now.addingTimeInterval(-29 * 86400), until: self.now, calendar: calendar)
    }

    static func cache(fileCount: Int, rowsPerFile: Int, includeOverflow: Bool = false) -> CostUsageCache {
        var seed: UInt64 = 0xC1A0DE
        func next(_ limit: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int(seed >> 32) % limit
        }
        var cache = CostUsageCache(scanSinceKey: self.range.scanSinceKey, scanUntilKey: self.range.scanUntilKey)
        for file in 0..<fileCount {
            let subagent = file.isMultiple(of: 2)
            let path = String(format: "project/%05d/", file / 2)
                + (subagent ? "subagents/agent.jsonl" : "parent.jsonl")
            var rows: [CostUsageScanner.ClaudeUsageRow] = []
            for index in 0..<rowsPerFile {
                let identity = "\(file / 4)-\(index / 2)"
                let keyKind = index % 8
                let day = next(28) + 1
                rows.append(.init(
                    dayKey: String(format: "2026-09-%02d", day),
                    model: "fixture/model-\(next(3))",
                    sessionId: keyKind == 4 ? " \n\t" : "session-\(file / 4)",
                    messageId: keyKind == 5 ? nil : (keyKind == 6 ? " \n" : "message-\(identity)"),
                    requestId: keyKind < 3 ? "request-\(identity)" : nil,
                    timestampUnixMs: 1_788_264_000_000 + Int64(day - 1) * 86_400_000 + Int64(next(3600)) * 1000,
                    isSidechain: next(4) == 0,
                    pathRole: subagent ? .subagent : .parent,
                    input: next(10000),
                    cacheRead: next(1000),
                    cacheCreate: next(100),
                    cacheCreate1h: next(50),
                    output: next(100),
                    costNanos: next(10_000_000),
                    costPriced: next(5) == 0 ? nil : true,
                    isIncomplete: next(7) == 0 ? true : nil))
            }
            cache.files[path] = .init(mtimeUnixMs: 0, size: 3, days: [:], parsedBytes: 3, claudeRows: rows)
        }
        if includeOverflow {
            let row = CostUsageScanner.ClaudeUsageRow(
                dayKey: "2026-09-01",
                model: "fixture/overflow",
                sessionId: nil,
                messageId: nil,
                requestId: nil,
                timestampUnixMs: nil,
                isSidechain: false,
                pathRole: .parent,
                input: Int.max,
                cacheRead: 0,
                cacheCreate: 0,
                cacheCreate1h: nil,
                output: 1,
                costNanos: 1,
                costPriced: true)
            cache.files["overflow"] = .init(mtimeUnixMs: 0, size: 0, days: [:], claudeRows: [row, row])
        }
        return cache
    }

    private static func rebuildReferenceDays(
        cache: inout CostUsageCache,
        rows: [CostUsageScanner.ClaudeUsageRow])
    {
        var days: [String: [String: [Int]]] = [:]
        var overflowed = Set<String>()
        for row in rows {
            let key = "\(row.dayKey)|\(row.model)"
            guard !overflowed.contains(key) else { continue }
            var models = days[row.dayKey] ?? [:]
            let packed = models[row.model] ?? [0, 0, 0, 0, 0, 0, 0, 0]
            if row.isIncomplete == true {
                models[row.model] = packed
                days[row.dayKey] = models
                continue
            }
            let delta = [
                row.input, row.cacheRead, row.cacheCreate, row.output, row.costNanos, 1,
                (row.costPriced ?? (row.costNanos > 0)) ? 1 : 0, row.cacheCreate1h ?? 0,
            ]
            let summed = zip(packed, delta).compactMap { current, incoming -> Int? in
                let sum = current.addingReportingOverflow(incoming)
                return sum.overflow ? nil : sum.partialValue
            }
            if summed.count == packed.count {
                models[row.model] = summed
            } else {
                overflowed.insert(key)
                models.removeValue(forKey: row.model)
            }
            days[row.dayKey] = models
        }
        cache.days = days
    }

    private static func digest(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try SHA256.hash(data: encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }
}
