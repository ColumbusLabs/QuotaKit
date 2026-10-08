import CodexBarSync
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct SyncCoordinatorClaudeSubscriptionTests {
    @Test(arguments: [false, true])
    func `Claude billing dates sync separately from quota and preserve calendar precision`(dateOnly: Bool) throws {
        let date = try #require(ISO8601DateParser.parse("2026-11-05T00:00:00.000Z"))
        let snapshot = UsageSnapshot(
            primary: .init(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            details: [.makeSection(title: "Subscription", rows: [
                .makeRow(label: "Token", value: "fixture-secret"),
            ])],
            subscriptionRenewsAt: date,
            subscriptionRenewsAtIsDateOnly: dateOnly,
            updatedAt: date)
        let details = try #require(SyncCoordinator.mapProviderDetails(provider: .claude, snapshot: snapshot))
        #expect(details == [.init(title: "Subscription", rows: [
            .init(label: "Renews", value: dateOnly ? "2026-11-05" : "2026-11-05T00:00:00.000Z"),
        ])])
        #expect(snapshot.primary?.usedPercent == 25)
        let wire = try #require(String(bytes: JSONEncoder().encode(details), encoding: .utf8))
        #expect(!wire.contains("fixture-secret"))
    }

    @Test
    func `scheduled ending wins while successful missing metadata explicitly clears old details`() throws {
        let date = try #require(ISO8601DateParser.parse("2026-11-05T00:00:00Z"))
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            subscriptionExpiresAt: date,
            subscriptionRenewsAt: date,
            subscriptionExpiresAtIsDateOnly: true,
            updatedAt: date)
        #expect(SyncCoordinator.mapProviderDetails(provider: .claude, snapshot: snapshot) == [
            .init(title: "Subscription", rows: [.init(label: "Plan expires", value: "2026-11-05")]),
        ])
        #expect(SyncCoordinator.mapProviderDetails(
            provider: .claude,
            snapshot: UsageSnapshot(primary: nil, secondary: nil, updatedAt: date)) == [])
        #expect(SyncCoordinator.mapProviderDetails(provider: .claude, snapshot: nil) == nil)
    }
}
