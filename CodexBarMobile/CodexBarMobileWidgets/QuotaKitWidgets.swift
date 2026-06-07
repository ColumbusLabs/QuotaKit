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
            policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func makeEntry(isPreview: Bool) -> QuotaKitWidgetEntry {
        let isProUnlocked = ProEntitlementCacheStore.load() != nil
        let isUnlocked = isPreview || isProUnlocked
        return QuotaKitWidgetEntry(
            date: Date(),
            snapshot: isPreview ? QuotaKitWidgetPreviewData.snapshot : QuotaKitWidgetSnapshotStore.load(),
            isUnlocked: isUnlocked,
            isPreview: isPreview)
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
