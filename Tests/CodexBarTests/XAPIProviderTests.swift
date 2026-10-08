import CodexBarSync
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct XAPIProviderTests {
    @Test
    func `descriptor registers a balance-only cookie provider for safe iPhone export`() {
        let descriptor = XAPIProviderDescriptor.descriptor

        #expect(descriptor.id == .xapi)
        #expect(descriptor.metadata.balanceOnly)
        #expect(!descriptor.metadata.widgetSelectable)
        #expect(descriptor.menuBarMetrics.supported == [.automatic])
        #expect(descriptor.history == .unavailable)
        #expect(descriptor.fetchPlan.sourceModes == [.auto, .web])
        #expect(descriptor.metadata.browserCookieOrder == [.chrome])
        #expect(descriptor.snapshotExport.allowsIPhoneSync)
        #expect(descriptor.snapshotExport.allowsWidgets)
        #expect(descriptor.presentation.cost(snapshot: UsageSnapshot(
            primary: nil,
            secondary: nil,
            updatedAt: Date())).menuCardStyle == .hidden)
        #expect(ProviderDescriptorRegistry.descriptor(for: .xapi).id == .xapi)
    }

    @Test
    func `sync exports prepaid status and details without a zero-dollar budget`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cost = ProviderCostSnapshot(
            used: 0,
            limit: 0,
            currencyCode: "USD",
            period: "Prepaid credits",
            balance: 12.4,
            updatedAt: now)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: cost,
            details: [ProviderDetailSection.makeSection(title: "Credits", rows: [
                .makeRow(label: "Balance", value: "$12.40", usageValue: 12.4),
                .makeRow(label: "Purchased credits", value: "$10.40"),
                .makeRow(label: "Free credits", value: "$2.00"),
            ])],
            updatedAt: now)

        #expect(SyncCoordinator.syncedStatusMessage(
            provider: .xapi,
            snapshot: snapshot,
            providerCost: cost,
            error: nil,
            rateWindows: []) == "Prepaid credits: USD 12.40")
        #expect(SyncCoordinator.syncBudgetSnapshot(provider: .xapi, providerCost: cost) == nil)
        #expect(SyncCoordinator.mapProviderDetails(provider: .xapi, snapshot: snapshot) == [
            SyncProviderDetailSection(title: "Credits", rows: [
                .init(label: "Balance", value: "$12.40"),
                .init(label: "Purchased credits", value: "$10.40"),
                .init(label: "Free credits", value: "$2.00"),
            ]),
        ])
    }
}
