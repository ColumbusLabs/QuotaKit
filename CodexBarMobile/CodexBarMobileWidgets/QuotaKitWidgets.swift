import AppIntents
import SwiftUI
import WidgetKit

enum QuotaWindowOption: String, CaseIterable, AppEnum {
    case primary
    case secondary

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Quota Window")
    static let caseDisplayRepresentations: [QuotaWindowOption: DisplayRepresentation] = [
        .primary: "Primary (session / 5-hour)",
        .secondary: "Secondary (weekly)",
    ]

    var slot: QuotaKitWidgetWindowSlot {
        switch self {
        case .primary: .primary
        case .secondary: .secondary
        }
    }
}

struct QuotaKitWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "QuotaKit Widget"
    static let description = IntentDescription("Choose which rate-limit window the widget shows.")

    @Parameter(title: "Quota window", default: .primary)
    var window: QuotaWindowOption
}

struct QuotaKitWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaKitWidgetEntry {
        QuotaKitWidgetEntry(
            date: Date(),
            snapshot: QuotaKitWidgetPreviewData.snapshot,
            isUnlocked: true,
            isPreview: true)
    }

    func snapshot(
        for configuration: QuotaKitWidgetConfigurationIntent,
        in context: Context) async -> QuotaKitWidgetEntry
    {
        self.makeEntry(
            isPreview: context.isPreview,
            windowSlot: configuration.window.slot)
    }

    func timeline(
        for configuration: QuotaKitWidgetConfigurationIntent,
        in context: Context) async -> Timeline<QuotaKitWidgetEntry>
    {
        let entry = self.makeEntry(
            isPreview: context.isPreview,
            windowSlot: configuration.window.slot)
        return Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    private func makeEntry(
        isPreview: Bool,
        windowSlot: QuotaKitWidgetWindowSlot) -> QuotaKitWidgetEntry
    {
        let isProUnlocked = ProEntitlementCacheStore.load() != nil
        let isUnlocked = isPreview || isProUnlocked
        return QuotaKitWidgetEntry(
            date: Date(),
            snapshot: isPreview ? QuotaKitWidgetPreviewData.snapshot : QuotaKitWidgetSnapshotStore.load(),
            isUnlocked: isUnlocked,
            isPreview: isPreview,
            windowSlot: windowSlot)
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
        AppIntentConfiguration(
            kind: self.kind,
            intent: QuotaKitWidgetConfigurationIntent.self,
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
    QuotaKitWidgetEntry(
        date: Date(),
        snapshot: QuotaKitWidgetPreviewData.snapshot,
        isUnlocked: true,
        isPreview: true,
        windowSlot: .secondary)
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
