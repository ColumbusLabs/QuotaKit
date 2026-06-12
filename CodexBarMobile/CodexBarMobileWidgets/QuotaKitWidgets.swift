import SwiftUI
import WidgetKit

struct QuotaKitWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaKitWidgetEntry {
        QuotaKitWidgetEntry(
            date: Date(),
            snapshot: QuotaKitWidgetPreviewData.snapshot,
            isUnlocked: true,
            isPreview: true)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (QuotaKitWidgetEntry) -> Void)
    {
        completion(self.makeEntry(isPreview: context.isPreview))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<QuotaKitWidgetEntry>) -> Void)
    {
        let entry = self.makeEntry(isPreview: context.isPreview)
        completion(Timeline(
            entries: [entry],
            policy: .after(QuotaKitWidgetTimelineSchedule.nextRefreshDate(
                after: entry.date,
                lastSyncedAt: entry.snapshot?.lastSyncedAt))))
    }

    private func makeEntry(isPreview: Bool) -> QuotaKitWidgetEntry {
        let isProUnlocked = ProEntitlementCacheStore.load() != nil
        let storedSnapshot = QuotaKitWidgetSnapshotStore.load()
        #if DEBUG && targetEnvironment(simulator)
        let snapshot = isPreview
            ? QuotaKitWidgetPreviewData.snapshot
            : storedSnapshot ?? QuotaKitWidgetPreviewData.simulatorSnapshot
        #else
        let snapshot = isPreview ? QuotaKitWidgetPreviewData.snapshot : storedSnapshot
        #endif
        #if DEBUG && targetEnvironment(simulator)
        let isUnlocked = isPreview || isProUnlocked || snapshot.primaryProvider != nil
        #else
        let isUnlocked = isPreview || isProUnlocked
        #endif
        return QuotaKitWidgetEntry(
            date: Date(),
            snapshot: snapshot,
            isUnlocked: isUnlocked,
            isPreview: isPreview,
            displayMode: QuotaKitWidgetEntryDisplayModeResolver.resolve(isPreview: isPreview))
    }
}

@main
struct QuotaKitWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuotaKitProviderWidget()
    }
}

struct QuotaKitProviderWidget: Widget {
    private let kind = "QuotaKitProviderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: self.kind,
            provider: QuotaKitWidgetProvider())
        { entry in
            QuotaKitWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "QuotaKit"))
        .description(String(localized: "See synced quota status from your Mac."))
        .contentMarginsDisabled()
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular,
        ])
    }
}

#if DEBUG
#Preview(as: .systemSmall) {
    QuotaKitProviderWidget()
} timeline: {
    QuotaKitWidgetEntry(
        date: Date(),
        snapshot: QuotaKitWidgetPreviewData.snapshot,
        isUnlocked: true,
        isPreview: true)
    QuotaKitWidgetEntry(
        date: Date(),
        snapshot: QuotaKitWidgetPreviewData.snapshot,
        isUnlocked: true,
        isPreview: true,
        displayMode: .weekly)
}

#Preview(as: .systemMedium) {
    QuotaKitProviderWidget()
} timeline: {
    QuotaKitWidgetEntry(
        date: Date(),
        snapshot: QuotaKitWidgetPreviewData.snapshot,
        isUnlocked: true,
        isPreview: true)
}

#Preview(as: .accessoryRectangular) {
    QuotaKitProviderWidget()
} timeline: {
    QuotaKitWidgetEntry(
        date: Date(),
        snapshot: QuotaKitWidgetPreviewData.snapshot,
        isUnlocked: true,
        isPreview: true)
}
#endif
