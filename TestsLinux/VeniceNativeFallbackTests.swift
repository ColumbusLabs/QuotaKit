#if !canImport(JavaScriptCore)
import CodexBarCore
import Foundation
import Testing

struct VeniceNativeFallbackTests {
    @Test(arguments: [
        ("USD", Optional(0.09549), Optional(3.0), "$0.10"),
        ("USD", Optional(-0.25), Optional(3.0), "-$0.25"),
        ("DIEM", Optional(0.5), Optional(-2.0), "DIEM -2.00"),
        ("DIEM", Optional(0.5), nil, "$0.50"),
        ("USD", nil, nil, "Balance unavailable for API calls"),
    ])
    func `native fallback retains blocked balances`(
        currency: String, usd: Double?, diem: Double?, expected: String)
    {
        let snapshot = VeniceUsageSnapshot(
            canConsume: false,
            consumptionCurrency: currency,
            diemBalance: diem,
            usdBalance: usd,
            diemEpochAllocation: 100,
            updatedAt: Date()).toUsageSnapshot()
        #expect(snapshot.primary?.usedPercent == 100)
        #expect(snapshot.primary?.resetDescription == expected)
    }
}
#endif
