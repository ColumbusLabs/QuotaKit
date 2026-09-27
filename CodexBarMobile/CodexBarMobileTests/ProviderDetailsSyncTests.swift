import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Provider detail sync")
struct ProviderDetailsSyncTests {
    @Test
    func `Copilot seat credits render from synced detail rows`() throws {
        let details = [SyncProviderDetailSection(
            title: "Credits",
            rows: [.init(label: "Credits used", value: "12 / 50", secondaryValue: "Resets next month")])]
        let snapshot = ProviderUsageSnapshot(
            providerID: "copilot",
            providerName: "Copilot",
            primary: nil,
            secondary: nil,
            accountEmail: "same-login @ api.example.ghe.com",
            loginMethod: "Enterprise",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            providerDetails: details)
        let roundTrip = try JSONDecoder().decode(
            ProviderUsageSnapshot.self,
            from: JSONEncoder().encode(snapshot))
        #expect(roundTrip.providerDetails == details)
        #expect(ProviderDetailSectionDispatcher.sections(for: roundTrip, hasRateWindowPace: false)
            .map(\.id) == ["provider-details"])
    }

    @Test
    func `detail-only provider survives the wire and dispatches on iPhone`() throws {
        let details = [SyncProviderDetailSection(
            title: "Account balance",
            rows: [.init(label: "Available balance", value: "$95.50")])]
        let snapshot = ProviderUsageSnapshot(
            providerID: "atlascloud",
            providerName: "Atlas Cloud",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "API",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            providerDetails: details)
        let encoded = try JSONEncoder().encode(snapshot)
        let roundTrip = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: encoded)
        #expect(roundTrip.providerDetails == details)
        #expect(ProviderDetailSectionDispatcher.sections(for: roundTrip, hasRateWindowPace: false)
            .map(\.id) == ["provider-details"])

        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "providerDetails")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        #expect(try JSONDecoder().decode(ProviderUsageSnapshot.self, from: legacyData).providerDetails == nil)
    }
}
