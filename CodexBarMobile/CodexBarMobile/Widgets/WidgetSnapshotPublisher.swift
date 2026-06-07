import CodexBarSync
import Foundation

enum WidgetSnapshotPublisher {
    nonisolated(unsafe) private static var lastPublishedData: Data?

    static func publish(from snapshot: SyncedUsageSnapshot) {
        guard ProEntitlementCacheStore.load() != nil else {
            self.clear(reloadTimelines: true)
            return
        }

        let widgetSnapshot = QuotaKitWidgetSnapshotBuilder.makeSnapshot(from: snapshot)
        guard let encoded = try? CloudSyncConstants.makeJSONEncoder().encode(widgetSnapshot) else {
            QuotaKitWidgetSnapshotStore.save(widgetSnapshot)
            return
        }

        QuotaKitWidgetSnapshotStore.save(widgetSnapshot)

        if encoded != self.lastPublishedData {
            self.lastPublishedData = encoded
            WidgetTimelineRefresher.reloadAllTimelines()
        }
    }

    static func clear(reloadTimelines: Bool = true) {
        QuotaKitWidgetSnapshotStore.clear()
        self.lastPublishedData = nil
        if reloadTimelines {
            WidgetTimelineRefresher.reloadAllTimelines()
        }
    }

    static func resetPublishedDataForTests() {
        self.lastPublishedData = nil
    }
}
