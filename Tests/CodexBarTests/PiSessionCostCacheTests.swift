import Foundation
import Testing
@testable import CodexBarCore

struct PiSessionCostCacheTests {
    @Test
    func `saving over an existing cache preserves the latest scan and provider state`() throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-pi-cache-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        var initial = PiSessionCostCache()
        initial.lastScanUnixMs = 1
        PiSessionCostCacheIO.save(cache: initial, cacheRoot: cacheRoot)
        #expect(PiSessionCostCacheIO.load(cacheRoot: cacheRoot).lastScanUnixMs == 1)

        var packedUsage = PiPackedUsage()
        packedUsage.inputTokens = 12
        packedUsage.outputTokens = 5
        packedUsage.totalTokens = 17

        var latest = PiSessionCostCache()
        latest.lastScanUnixMs = 2
        latest.scanSinceKey = "2026-09-21"
        latest.scanUntilKey = "2026-09-22"
        latest.pricingKey = "pricing-v2"
        latest.daysByProvider = [
            "openai": [
                "2026-09-22": ["test-model": packedUsage],
            ],
        ]
        latest.files = [
            "session.jsonl": PiSessionFileUsage(
                mtimeUnixMs: 2,
                size: 10,
                parsedBytes: 10,
                sessionID: "session-2",
                lastModelContext: PiModelContext(providerRawValue: "openai", modelName: "test-model"),
                contributions: [:]),
        ]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Bangkok"))
        PiSessionCostCacheIO.save(cache: latest, cacheRoot: cacheRoot, calendar: calendar)

        let reloaded = PiSessionCostCacheIO.load(cacheRoot: cacheRoot)
        #expect(reloaded.lastScanUnixMs == 2)
        #expect(reloaded.scanSinceKey == "2026-09-21")
        #expect(reloaded.scanUntilKey == "2026-09-22")
        #expect(reloaded.timeZoneIdentifier == "Asia/Bangkok")
        #expect(reloaded.pricingKey == "pricing-v2")
        #expect(reloaded.daysByProvider["openai"]?["2026-09-22"]?["test-model"]?.totalTokens == 17)
        #expect(reloaded.files["session.jsonl"]?.sessionID == "session-2")
    }
}
