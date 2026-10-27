import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct SyncCoordinatorCommandCodeAccountsTests {
    @Test
    func `saved Command Code sessions sync distinct account records without their cookies`() async throws {
        let settings = testSettingsStore(
            suiteName: "CommandCodeSync-\(UUID().uuidString)",
            prepareDefaults: { $0.set(true, forKey: "providerDetectionCompleted") })
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .commandcode,
            metadata: #require(ProviderDefaults.metadata[.commandcode]),
            enabled: true)
        settings.addTokenAccount(provider: .commandcode, label: "Personal", token: "session=fixture-secret-one")
        settings.addTokenAccount(provider: .commandcode, label: "Work", token: "session=fixture-secret-two")
        settings.setActiveTokenAccountIndex(0, for: .commandcode)
        let accounts = settings.tokenAccounts(for: .commandcode)
        #expect(accounts.count == 2)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        let snapshots = accounts.enumerated().map { index, account in
            let raw = UsageSnapshot(
                primary: RateWindow(
                    usedPercent: index == 0 ? 15 : 85,
                    windowMinutes: 300,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: nil,
                updatedAt: Date())
            return TokenAccountUsageSnapshot(
                account: account,
                snapshot: store.applyAccountLabel(raw, provider: .commandcode, account: account),
                error: nil,
                sourceLabel: nil)
        }
        store._setSnapshotForTesting(snapshots.first?.snapshot, provider: .commandcode)
        store.accountSnapshots[.commandcode] = snapshots
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()
        let exported = mock.lastPerProviderEnvelopes.filter { $0.provider.providerID == "commandcode" }
        #expect(exported.count == 2)
        #expect(Set(exported.compactMap(\.provider.accountEmail)) == ["Personal", "Work"])
        let names = exported.map {
            CloudSyncManager.perProviderRecordName(
                deviceID: $0.deviceID,
                providerID: $0.provider.providerID,
                accountEmail: $0.provider.accountEmail)
        }
        #expect(Set(names).count == 2)
        let encoded = try JSONEncoder().encode(exported.map(\.provider))
        let wire = try #require(String(data: encoded, encoding: .utf8))
        #expect(!wire.contains("fixture-secret"))
        #expect(!wire.contains("session="))
    }
}
