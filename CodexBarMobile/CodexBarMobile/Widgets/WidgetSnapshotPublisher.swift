import CodexBarSync
import Foundation

enum WidgetSnapshotPublisher {
    private nonisolated(unsafe) static var lastPublishedSnapshot: QuotaKitWidgetSnapshot?

    static func publish(
        from snapshot: SyncedUsageSnapshot,
        generatedAt: Date = Date(),
        isProUnlocked: Bool = ProEntitlementCacheStore.load() != nil,
        saveSnapshot: (QuotaKitWidgetSnapshot) -> Void = { QuotaKitWidgetSnapshotStore.save($0) },
        reloadTimelines: () -> Void = WidgetTimelineRefresher.reloadAllTimelines)
    {
        guard isProUnlocked else {
            self.clear(reloadTimelines: true, reloadTimelinesAction: reloadTimelines)
            return
        }

        let widgetSnapshot = QuotaKitWidgetSnapshotBuilder.makeSnapshot(
            from: snapshot,
            generatedAt: generatedAt)
        let reloadSnapshot = Self.reloadFingerprint(for: widgetSnapshot)

        saveSnapshot(widgetSnapshot)

        if reloadSnapshot != self.lastPublishedSnapshot {
            self.lastPublishedSnapshot = reloadSnapshot
            reloadTimelines()
        }
    }

    static func clear(
        reloadTimelines: Bool = true,
        reloadTimelinesAction: () -> Void = WidgetTimelineRefresher.reloadAllTimelines)
    {
        QuotaKitWidgetSnapshotStore.clear()
        self.lastPublishedSnapshot = nil
        if reloadTimelines {
            reloadTimelinesAction()
        }
    }

    static func resetPublishedDataForTests() {
        self.lastPublishedSnapshot = nil
    }

    private static func reloadFingerprint(for snapshot: QuotaKitWidgetSnapshot) -> QuotaKitWidgetSnapshot {
        QuotaKitWidgetSnapshot(
            schemaVersion: snapshot.schemaVersion,
            generatedAt: Date(timeIntervalSince1970: 0),
            lastSyncedAt: snapshot.lastSyncedAt,
            providers: snapshot.providers)
    }
}
