import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct SyncCoordinatorDeviceStatusTests {
    private func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func makeUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
    }

    @Test
    func pushIncludesPowerStatusAndStandaloneDeviceStatus() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-power-status")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: Date()),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let snapshotPowerStatus = try #require(mock.lastSnapshot?.powerStatus)
        let deviceStatus = try #require(mock.lastDeviceStatus)
        let snapshotDeviceID = try #require(mock.lastSnapshot?.deviceID)
        #expect(mock.deviceStatusPushCount == 1)
        #expect(deviceStatus.deviceID == snapshotDeviceID)
        #expect(deviceStatus.powerStatus == snapshotPowerStatus)
    }

    @Test
    func shouldPushDeviceStatusIgnoresOnlyUpdatedAtDrift() {
        let oldStatus = SyncDeviceStatus(
            deviceID: "mac-A",
            deviceName: "Mac A",
            appVersion: "0.33.0",
            mobileVersion: "1.11.1",
            syncTimestamp: Date(timeIntervalSince1970: 1_800_000_000),
            powerStatus: SyncDevicePowerStatus(
                batteryPercent: 80,
                state: .battery,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)))
        let timestampOnlyChange = SyncDeviceStatus(
            deviceID: "mac-A",
            deviceName: "Mac A",
            appVersion: "0.33.0",
            mobileVersion: "1.11.1",
            syncTimestamp: Date(timeIntervalSince1970: 1_800_000_300),
            powerStatus: SyncDevicePowerStatus(
                batteryPercent: 80,
                state: .battery,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_300)))
        let percentChange = SyncDeviceStatus(
            deviceID: "mac-A",
            deviceName: "Mac A",
            appVersion: "0.33.0",
            mobileVersion: "1.11.1",
            syncTimestamp: Date(timeIntervalSince1970: 1_800_000_600),
            powerStatus: SyncDevicePowerStatus(
                batteryPercent: 79,
                state: .battery,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_600)))

        #expect(SyncCoordinator.shouldPushDeviceStatus(timestampOnlyChange, after: oldStatus) == false)
        #expect(SyncCoordinator.shouldPushDeviceStatus(percentChange, after: oldStatus) == true)
    }
}
