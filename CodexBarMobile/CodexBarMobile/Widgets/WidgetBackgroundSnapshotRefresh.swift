import CodexBarSync
import Foundation

enum WidgetBackgroundSnapshotRefreshResult: Equatable {
    case newData
    case noData
    case failed
}

enum WidgetBackgroundSnapshotRefresh {
    static func refresh(
        reader: CloudSyncReader = CloudSyncReader(),
        kvsFallback: SyncedUsageSnapshot? = nil,
        publishSnapshot: (SyncedUsageSnapshot) -> Void = { WidgetSnapshotPublisher.publish(from: $0) },
        clearSnapshot: () -> Void = { WidgetSnapshotPublisher.clear() }
    ) async -> WidgetBackgroundSnapshotRefreshResult {
        async let perProviderResult = reader.fetchPerProviderDeviceSnapshots()
        async let legacyResult = reader.fetchLegacyDeviceSnapshots()
        async let linkagesResult = reader.fetchProviderAccountLinkages()

        return await Self.apply(
            perProvider: perProviderResult,
            legacy: legacyResult,
            linkages: linkagesResult,
            kvsFallback: kvsFallback ?? reader.latestKVSSnapshot(),
            publishSnapshot: publishSnapshot,
            clearSnapshot: clearSnapshot)
    }

    static func apply(
        perProvider: MultiDeviceSyncResult,
        legacy: MultiDeviceSyncResult,
        linkages: [ProviderAccountLinkage] = [],
        kvsFallback: SyncedUsageSnapshot? = nil,
        publishSnapshot: (SyncedUsageSnapshot) -> Void = { WidgetSnapshotPublisher.publish(from: $0) },
        clearSnapshot: () -> Void = { WidgetSnapshotPublisher.clear() }
    ) -> WidgetBackgroundSnapshotRefreshResult {
        let perProviderSnapshots = Self.snapshots(from: perProvider)
        let legacySnapshots = Self.snapshots(from: legacy)
        let firstError = Self.error(from: perProvider) ?? Self.error(from: legacy)

        let fetchedSnapshots = perProviderSnapshots + legacySnapshots
        if let merged = CloudSyncReader.mergeSnapshots(fetchedSnapshots, linkages: linkages) {
            publishSnapshot(merged)
            return .newData
        }

        if let kvsFallback {
            publishSnapshot(kvsFallback)
            return .newData
        }

        if firstError != nil {
            return .failed
        }

        clearSnapshot()
        return .noData
    }

    private static func snapshots(from result: MultiDeviceSyncResult) -> [SyncedUsageSnapshot] {
        switch result {
        case .success(let snapshots):
            snapshots
        case .empty, .error:
            []
        }
    }

    private static func error(from result: MultiDeviceSyncResult) -> CloudSyncError? {
        switch result {
        case .error(let error):
            error
        case .success, .empty:
            nil
        }
    }
}
