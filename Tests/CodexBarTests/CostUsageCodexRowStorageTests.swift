import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageCodexRowStorageTests {
    enum ReadMode: CaseIterable {
        case report, scan, cache, snapshot
    }

    @Test
    func `storage interning preserves decoded values without scanner normalization`() throws {
        let row = CostUsageScanner.CodexUsageRow(
            day: "2026-08-01",
            model: "gpt-5",
            turnID: "synthetic-turn-storage-copy",
            eventIndex: 1,
            input: 2,
            cached: 3,
            output: 4,
            reasoning: 1,
            knownCostNanos: 5,
            unpricedTokens: 6)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var fields = try #require(JSONSerialization.jsonObject(with: encoder.encode(row)) as? [String: Any])
        // The decoder preserves this value; routing through the scanner initializer would clamp it.
        fields["reasoning"] = 99
        let decoded = try JSONDecoder().decode(
            CostUsageScanner.CodexUsageRow.self,
            from: JSONSerialization.data(withJSONObject: fields))
        let shared = CostUsageScanner.CodexUsageRow(sharingTurnIDFrom: decoded, pool: CostUsageRowStringPool())
        #expect(shared.reasoning == 99)
        #expect(try encoder.encode(shared) == encoder.encode(decoded))
    }

    @Test(arguments: ReadMode.allCases)
    func `retained Codex rows share identical turn strings without changing their bytes`(mode: ReadMode) async throws {
        let fixture = try CostUsageTestEnvironment()
        defer { fixture.cleanup() }
        let store = CostUsageStore(cacheRoot: fixture.cacheRoot)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let turns: [String?] = [
            nil,
            "synthetic-turn-caf\u{e9}-00000001",
            "synthetic-turn-cafe\u{301}-00000001",
            "synthetic-turn-third-0000000001",
        ]
        let rows = (0..<10000).map { index in
            CostUsageScanner.CodexUsageRow(
                day: "2026-08-01",
                model: "gpt-5",
                rawModel: "synthetic-original-model",
                turnID: turns[index % turns.count],
                eventIndex: index,
                timestampUnixMs: 1_785_542_400_000 + Int64(index),
                input: index,
                cached: 2,
                output: 3,
                reasoning: 1,
                knownCostNanos: Int64(index),
                pricingModel: "synthetic-priced-model",
                pricingMode: index.isMultiple(of: 2) ? "priority" : nil,
                responseID: "synthetic-response-\(index)",
                requestMirrorKeys: ["synthetic-mirror-\(index)"])
        }
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        let paths = ["/synthetic/first.jsonl", "/synthetic/second.jsonl"]
        cache.files[paths[0]] = CostUsageFileUsage(
            mtimeUnixMs: 1, size: 0, days: [:], codexRows: Array(rows.prefix(5000)))
        cache.files[paths[1]] = CostUsageFileUsage(
            mtimeUnixMs: 1, size: 0, days: [:], codexRows: Array(rows.suffix(5000)))
        #expect(!store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01")).catchUpRequired)
        let loaded: CostUsageCache
        switch mode {
        case .report:
            let view = store.syncLoadCodexReadView(calendar: calendar, purpose: .report)
            loaded = try #require(Mirror(reflecting: view).children.first { $0.label == "cache" }?.value
                as? CostUsageCache)
        case .scan:
            let scan = store.syncLoadCodexScan(calendar: calendar)
            loaded = scan.cache
            scan.release()
        case .cache:
            loaded = store.syncLoadCodexCache(calendar: calendar, loadTokenSnapshots: false)
        case .snapshot:
            loaded = await CostUsageStore.decodeCodexCache(from: store.readSnapshot())
        }
        let actual = paths.flatMap { loaded.files[$0]?.codexRows ?? [] }
        #expect(actual.count == rows.count)
        let strings = actual.compactMap(\.turnID)
        let identities = try Set(strings.map { value in
            try #require(value.utf8.withContiguousStorageIfAvailable { UInt(bitPattern: $0.baseAddress) })
        })
        print("[codex-row-storage] mode=\(mode) rows=\(actual.count) turnAllocations=\(identities.count)")
        #expect(identities.count == turns.compactMap(\.self).count)
        #expect(Set(strings.map { Data($0.utf8) }) == Set(turns.compactMap(\.self).map { Data($0.utf8) }))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(actual) == encoder.encode(rows))
    }
}
