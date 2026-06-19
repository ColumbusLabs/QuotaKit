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

    private func deviceStatus(
        timestamp: Date,
        percent: Int = 80) -> SyncDeviceStatus
    {
        SyncDeviceStatus(
            deviceID: "mac-A",
            deviceName: "Mac A",
            appVersion: "0.33.0",
            mobileVersion: "1.11.1",
            syncTimestamp: timestamp,
            powerStatus: SyncDevicePowerStatus(
                batteryPercent: percent,
                state: .battery,
                updatedAt: timestamp))
    }

    private actor DeviceStatusPushGate {
        private var shouldPauseFirstPush = true
        private var isPaused = false
        private var pausedWaiters: [CheckedContinuation<Void, Never>] = []
        private var releaseContinuation: CheckedContinuation<Void, Never>?

        func pauseFirstPush() async {
            guard self.shouldPauseFirstPush else { return }
            self.shouldPauseFirstPush = false
            await withCheckedContinuation { continuation in
                self.releaseContinuation = continuation
                self.isPaused = true
                let waiters = self.pausedWaiters
                self.pausedWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume()
                }
            }
        }

        func waitUntilPaused() async {
            guard !self.isPaused else { return }
            await withCheckedContinuation { continuation in
                self.pausedWaiters.append(continuation)
            }
        }

        func release() {
            self.releaseContinuation?.resume()
            self.releaseContinuation = nil
        }
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
    func deviceStatusWritesAreSerializedAndDrainLatestPendingStatus() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-status-serialized")
        settings.iCloudSyncEnabled = true
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let gate = DeviceStatusPushGate()
        mock.deviceStatusPushDelay = {
            await gate.pauseFirstPush()
        }
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        let older = self.deviceStatus(timestamp: Date(timeIntervalSince1970: 1_800_000_000), percent: 80)
        let newer = self.deviceStatus(timestamp: Date(timeIntervalSince1970: 1_800_000_300), percent: 79)

        let firstTask = Task { @MainActor in
            await coordinator.pushDeviceStatusForTesting(older, force: true)
        }
        await gate.waitUntilPaused()

        let secondResult = await coordinator.pushDeviceStatusForTesting(newer, force: true)
        #expect(secondResult.succeeded == true)
        #expect(mock.deviceStatusPushCount == 1)
        #expect(mock.maxConcurrentDeviceStatusPushes == 1)

        await gate.release()
        _ = await firstTask.value

        #expect(mock.deviceStatusPushCount == 2)
        #expect(mock.maxConcurrentDeviceStatusPushes == 1)
        #expect(mock.deviceStatusPushes.map(\.syncTimestamp) == [
            older.syncTimestamp,
            newer.syncTimestamp,
        ])
        #expect(mock.lastDeviceStatus == newer)
    }

    @Test
    func olderDeviceStatusAfterNewerSuccessfulPushIsSkipped() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-status-stale")
        settings.iCloudSyncEnabled = true
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        let newer = self.deviceStatus(timestamp: Date(timeIntervalSince1970: 1_800_000_300), percent: 79)
        let older = self.deviceStatus(timestamp: Date(timeIntervalSince1970: 1_800_000_000), percent: 80)

        await coordinator.pushDeviceStatusForTesting(newer, force: true)
        await coordinator.pushDeviceStatusForTesting(older, force: true)

        #expect(mock.deviceStatusPushCount == 1)
        #expect(mock.lastDeviceStatus == newer)
    }

    @Test
    func deviceStatusFailureDoesNotFailProviderSyncStatus() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-status-failure")
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
        mock.nextDeviceStatusResult = .failure("DeviceStatus unavailable")
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        #expect(mock.deviceStatusPushCount == 1)
        #expect(mock.pushCount == 1)
        #expect(mock.perProviderCallCount == 1)
        #expect(coordinator.lastSyncSucceeded == true)
        #expect(coordinator.lastSyncMessageIsWarning == false)
        #expect(coordinator.lastSyncMessage == nil)
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
