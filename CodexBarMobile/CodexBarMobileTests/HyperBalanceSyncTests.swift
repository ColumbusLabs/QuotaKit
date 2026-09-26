import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Hyper balance sync")
struct HyperBalanceSyncTests {
    @Test
    func `Hyper balance round trips and legacy payloads decode without it`() throws {
        let expected = SyncHyperBalance(
            balance: 42.5,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let snapshot = ProviderUsageSnapshot(
            providerID: "hyper",
            providerName: "Charm Hyper",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "API key",
            statusMessage: nil,
            isError: false,
            lastUpdated: expected.updatedAt,
            hyperBalance: expected)

        let encoded = try JSONEncoder().encode(snapshot)
        let roundTrip = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: encoded)
        #expect(roundTrip.hyperBalance == expected)

        var legacyObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "hyperBalance")
        let legacyPayload = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacy = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: legacyPayload)
        #expect(legacy.hyperBalance == nil)
    }

    @Test
    func `Hypercredits card formats a fractional balance without padding`() {
        #expect(HyperBalanceCard.formattedAmount(42.5, locale: Locale(identifier: "en_US_POSIX")) == "42.5")
        #expect(HyperBalanceCard.formattedAmount(42, locale: Locale(identifier: "en_US_POSIX")) == "42")
    }
}
