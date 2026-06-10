import AppIntents
import SwiftUI
import WidgetKit

extension QuotaKitWidgetUsageWindow: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Usage Window")
    }

    static var caseDisplayRepresentations: [QuotaKitWidgetUsageWindow: DisplayRepresentation] {
        [
            .session: DisplayRepresentation(title: "Session"),
            .weekly: DisplayRepresentation(title: "Weekly"),
        ]
    }
}

struct QuotaKitWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "QuotaKit"
    static let description = IntentDescription("Choose whether this widget shows session or weekly quota usage.")
    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$usageWindow)")
    }

    @Parameter(title: "Usage Window", default: QuotaKitWidgetUsageWindow.session)
    var usageWindow: QuotaKitWidgetUsageWindow

    init(usageWindow: QuotaKitWidgetUsageWindow = .session) {
        self.usageWindow = usageWindow
    }

    init() {
        self.init(usageWindow: .session)
    }
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
            usageWindow: configuration.usageWindow)
    }

    func timeline(
        for configuration: QuotaKitWidgetConfigurationIntent,
        in context: Context) async -> Timeline<QuotaKitWidgetEntry>
    {
        let entry = self.makeEntry(
            isPreview: context.isPreview,
            usageWindow: configuration.usageWindow)
        return Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    private func makeEntry(
        isPreview: Bool,
        usageWindow: QuotaKitWidgetUsageWindow) -> QuotaKitWidgetEntry
    {
        let isProUnlocked = ProEntitlementCacheStore.load() != nil
        let snapshot = isPreview ? QuotaKitWidgetPreviewData.snapshot : QuotaKitWidgetSnapshotStore.load()
        #if DEBUG && targetEnvironment(simulator)
        let isUnlocked = isPreview || isProUnlocked || snapshot != nil
        #else
        let isUnlocked = isPreview || isProUnlocked
        #endif
        return QuotaKitWidgetEntry(
            date: Date(),
            snapshot: snapshot,
            isUnlocked: isUnlocked,
            isPreview: isPreview,
            usageWindow: usageWindow)
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
        usageWindow: .weekly)
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
