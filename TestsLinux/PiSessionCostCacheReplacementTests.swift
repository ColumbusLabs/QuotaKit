import Foundation
import Testing
@testable import CodexBarCore

struct PiSessionCostCacheReplacementTests {
    @Test
    func `repeated Pi cache saves preserve scan state and provider totals`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-cache-replacement-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let url = PiSessionCostCacheIO.cacheFileURL(cacheRoot: root)

        for revision in 1...10 {
            var cache = PiSessionCostCache()
            cache.lastScanUnixMs = Int64(revision)
            cache.scanSinceKey = "2026-09-06"
            cache.scanUntilKey = "2026-09-07"
            cache.pricingKey = "pricing-\(revision)"
            cache.daysByProvider = ["codex": ["2026-09-06": ["sample-model": PiPackedUsage(
                inputTokens: revision, totalTokens: revision, costNanos: Int64(revision))]]]
            cache.files = [
                "session.jsonl": PiSessionFileUsage(
                    mtimeUnixMs: Int64(revision),
                    size: Int64(revision),
                    parsedBytes: Int64(revision),
                    sessionID: "session-\(revision)",
                    lastModelContext: PiModelContext(providerRawValue: "codex", modelName: "sample-model"),
                    contributions: [:]),
            ]
            PiSessionCostCacheIO.save(cache: cache, cacheRoot: root, calendar: calendar)

            let persisted = try JSONDecoder().decode(PiSessionCostCache.self, from: Data(contentsOf: url))
            #expect(persisted.lastScanUnixMs == cache.lastScanUnixMs)
            #expect(persisted.scanSinceKey == cache.scanSinceKey)
            #expect(persisted.scanUntilKey == cache.scanUntilKey)
            #expect(persisted.pricingKey == cache.pricingKey)
            #expect(persisted.daysByProvider["codex"]?["2026-09-06"]?["sample-model"]?.totalTokens == revision)
            #expect(persisted.daysByProvider["codex"]?["2026-09-06"]?["sample-model"]?.costNanos == Int64(revision))
            #expect(persisted.timeZoneIdentifier == calendar.timeZone.identifier)
            #expect(persisted.files["session.jsonl"]?.sessionID == "session-\(revision)")

            let loaded = PiSessionCostCacheIO.load(cacheRoot: root)
            #expect(loaded.lastScanUnixMs == cache.lastScanUnixMs)
            #expect(loaded.pricingKey == cache.pricingKey)
            #expect(loaded.daysByProvider["codex"]?["2026-09-06"]?["sample-model"]?.totalTokens == revision)
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(files == [url.lastPathComponent])
    }
}
