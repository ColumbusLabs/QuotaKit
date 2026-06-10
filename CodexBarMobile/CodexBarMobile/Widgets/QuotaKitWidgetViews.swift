import CodexBarSync
import Foundation
import SwiftUI
import WidgetKit

enum QuotaKitWidgetUsageWindow: String, CaseIterable, Sendable {
    case session
    case weekly

    var localizedTitle: String {
        switch self {
        case .session:
            String(localized: "Session")
        case .weekly:
            String(localized: "Weekly")
        }
    }
}

struct QuotaKitWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaKitWidgetSnapshot?
    let isUnlocked: Bool
    let isPreview: Bool
    var usageWindow: QuotaKitWidgetUsageWindow = .session
}

extension QuotaKitWidgetSnapshot.Provider {
    func window(for usageWindow: QuotaKitWidgetUsageWindow) -> Window? {
        switch usageWindow {
        case .session:
            return self.windows.first(where: Self.isSessionWindow)
                ?? self.windows.first
        case .weekly:
            return self.windows.first(where: Self.isWeeklyWindow)
                ?? self.windows.dropFirst().first
                ?? self.windows.first
        }
    }

    private static func isSessionWindow(_ window: Window) -> Bool {
        let title = window.title.localizedLowercase
        return title.contains("session")
            || title.contains("hour")
            || title.contains(String(localized: "Session").localizedLowercase)
    }

    private static func isWeeklyWindow(_ window: Window) -> Bool {
        let title = window.title.localizedLowercase
        return title.contains("week")
            || title.contains(String(localized: "Weekly").localizedLowercase)
    }
}

struct QuotaKitWidgetView: View {
    let entry: QuotaKitWidgetEntry
    let overrideFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var family

    init(entry: QuotaKitWidgetEntry, overrideFamily: WidgetFamily? = nil) {
        self.entry = entry
        self.overrideFamily = overrideFamily
    }

    var body: some View {
        let family = self.overrideFamily ?? self.family
        Group {
            if !self.entry.isUnlocked {
                QuotaKitWidgetLockedView(family: family)
            } else if let snapshot = self.entry.snapshot,
                      let provider = snapshot.primaryProvider
            {
                switch family {
                case .systemMedium:
                    QuotaKitWidgetMediumView(
                        snapshot: snapshot,
                        usageWindow: self.entry.usageWindow)
                case .accessoryRectangular:
                    QuotaKitWidgetAccessoryRectangularView(
                        provider: provider,
                        usageWindow: self.entry.usageWindow)
                case .accessoryCircular:
                    QuotaKitWidgetAccessoryCircularView(
                        provider: provider,
                        usageWindow: self.entry.usageWindow)
                default:
                    QuotaKitWidgetSmallView(
                        provider: provider,
                        usageWindow: self.entry.usageWindow)
                }
            } else {
                QuotaKitWidgetEmptyView(family: family)
            }
        }
        .background(Color.black)
        .containerBackground(for: .widget) {
            Color.black
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Brand accent local to the widget target: `Design/QuotaKitTheme.swift`
/// is not compiled into the widget extension, so this mirrors
/// `QuotaKitTheme.brandAccent`. Usage colors come from the shared
/// `QuotaUsageColor` + `ProviderColorPalette` sources.
private enum WidgetPalette {
    static let brandAccent = Color(red: 1.0, green: 0.73, blue: 0.08)
}

private struct WidgetBrandHeader: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(WidgetPalette.brandAccent)
                .frame(width: 6, height: 6)
            Text(String(localized: "QuotaKit"))
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }
}

/// The main app's usage bar (`UsageProgressBarView`) configured for the
/// widget's remaining-percent display: provider-tinted fill and the same
/// triple-stripe pace marker showing where usage was expected to be
/// (gap to the right of the fill = deficit, to the left = buffer).
private struct WidgetUsageBar: View {
    let window: QuotaKitWidgetSnapshot.Provider.Window
    let tint: Color

    var body: some View {
        UsageProgressBarView(
            progressFraction: (100 - self.window.usedPercent) / 100,
            tintColor: QuotaUsageColor.color(usedPercent: self.window.usedPercent, tint: self.tint),
            trackColor: Color.white.opacity(0.17),
            markerPercents: [],
            pacePercent: self.window.pace?.widgetMarkerRemainingPercent,
            paceColor: self.window.pace?.widgetStripeColor(onTrackTint: self.tint) ?? self.tint)
    }
}

/// Live data-age indicator. The relative `Text` style keeps counting up
/// between timeline refreshes without re-rendering the widget.
private struct WidgetSyncBadge: View {
    let lastSynced: Date

    /// Mirrors `SyncFreshnessState.staleThreshold`; evaluated when the
    /// timeline entry renders, so the tint can lag until the next refresh.
    private var isStale: Bool {
        Date().timeIntervalSince(self.lastSynced) > 3600
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 8, weight: .semibold))
            Text("Synced \(self.lastSynced, style: .relative) ago")
        }
        .font(.caption2)
        .foregroundStyle(self.isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
        .lineLimit(1)
    }
}

private struct WidgetPaceChip: View {
    let pace: SyncUsagePace
    var compact = false

    var body: some View {
        if let deltaText = self.pace.widgetDeltaText {
            HStack(spacing: 2) {
                Image(systemName: self.pace.deltaPercent < 0
                    ? "arrowtriangle.up.fill"
                    : "arrowtriangle.down.fill")
                    .font(.system(size: self.compact ? 6 : 7, weight: .bold))
                Text(deltaText)
                    .font(self.compact ? .caption2.monospacedDigit() : .caption.monospacedDigit())
                    .fontWeight(.semibold)
            }
            .foregroundStyle(self.pace.widgetColor)
            .padding(.horizontal, self.compact ? 5 : 7)
            .padding(.vertical, self.compact ? 2 : 3)
            .background(self.pace.widgetColor.opacity(0.18), in: Capsule())
            .lineLimit(1)
        }
    }
}

private struct QuotaKitWidgetSmallView: View {
    let provider: QuotaKitWidgetSnapshot.Provider
    let usageWindow: QuotaKitWidgetUsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(WidgetPalette.brandAccent)
                    .frame(width: 7, height: 7)
                Text(self.provider.providerName)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            if let window = self.provider.window(for: self.usageWindow) {
                Text(window.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 2)

                Spacer(minLength: 2)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(verbatim: "\(Int(window.remainingPercent.rounded()))")
                            .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                        Text(verbatim: "%")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                    Spacer(minLength: 2)

                    if let pace = window.pace {
                        WidgetPaceChip(pace: pace)
                    }
                }

                WidgetUsageBar(
                    window: window,
                    tint: ProviderColorPalette.color(for: self.provider.id))
                    .padding(.top, 10)

                if let pace = window.pace {
                    WidgetPaceFooter(pace: pace)
                        .padding(.top, 8)
                }
            } else {
                Spacer(minLength: 4)
                Text(self.provider.statusMessage ?? String(localized: "No quota window"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// "11% in deficit · Projected 4 days" — pace label tinted, projection muted.
private struct WidgetPaceFooter: View {
    let pace: SyncUsagePace

    var body: some View {
        Group {
            if let rightLabel = self.pace.rightLabel, !rightLabel.isEmpty {
                Text(self.pace.leftLabel)
                    .foregroundColor(self.pace.widgetColor)
                    + Text(verbatim: " · ")
                    .foregroundColor(.secondary)
                    + Text(rightLabel)
                    .foregroundColor(.secondary)
            } else {
                Text(self.pace.leftLabel)
                    .foregroundColor(self.pace.widgetColor)
            }
        }
        .font(.caption2)
        .fontWeight(.medium)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }
}

private struct QuotaKitWidgetMediumView: View {
    let snapshot: QuotaKitWidgetSnapshot
    let usageWindow: QuotaKitWidgetUsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                WidgetBrandHeader()
                Spacer()
                WidgetSyncBadge(lastSynced: self.snapshot.generatedAt)
            }

            let providers = Array(self.snapshot.providers.prefix(3))
            ForEach(providers) { provider in
                let window = provider.window(for: self.usageWindow)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(provider.providerName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(window?.title
                            ?? provider.statusMessage
                            ?? String(localized: "No quota window"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        if let window {
                            if let pace = window.pace {
                                WidgetPaceChip(pace: pace, compact: true)
                            }
                            Text(verbatim: "\(Int(window.remainingPercent.rounded()))%")
                                .font(.subheadline.monospacedDigit())
                                .fontWeight(.semibold)
                        } else {
                            Image(systemName: provider.isError ? "exclamationmark.triangle" : "minus")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let window {
                        WidgetUsageBar(
                            window: window,
                            tint: ProviderColorPalette.color(for: provider.id))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

private struct QuotaKitWidgetAccessoryRectangularView: View {
    let provider: QuotaKitWidgetSnapshot.Provider
    let usageWindow: QuotaKitWidgetUsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(provider.providerName)
                .font(.headline)
                .lineLimit(1)
            if let window = provider.window(for: self.usageWindow) {
                Text(String(
                    format: String(localized: "%lld%% left · %@"),
                    Int64(window.remainingPercent.rounded()),
                    window.title))
                    .font(.caption)
                    .lineLimit(1)
                if let paceText = window.pace?.widgetDisplayText {
                    Text(paceText)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(window.pace?.widgetColor ?? Color.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(provider.statusMessage ?? String(localized: "No quota window"))
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }
}

private struct QuotaKitWidgetAccessoryCircularView: View {
    let provider: QuotaKitWidgetSnapshot.Provider
    let usageWindow: QuotaKitWidgetUsageWindow

    var body: some View {
        if let window = provider.window(for: self.usageWindow) {
            Gauge(value: window.remainingPercent, in: 0...100) {
                Text(String(localized: "Quota"))
            } currentValueLabel: {
                Text(verbatim: "\(Int(window.remainingPercent.rounded()))")
                    .font(.caption2.monospacedDigit())
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            Image(systemName: provider.isError ? "exclamationmark.triangle" : "minus")
        }
    }
}

private struct QuotaKitWidgetLockedView: View {
    let family: WidgetFamily

    var body: some View {
        switch self.family {
        case .accessoryCircular:
            Image(systemName: "lock.fill")
        case .accessoryRectangular:
            VStack(alignment: .center, spacing: 2) {
                Text(String(localized: "QuotaKit Pro"))
                    .font(.headline)
                Text(String(localized: "Unlock widgets"))
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        default:
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(WidgetPalette.brandAccent)
                Text(String(localized: "QuotaKit Pro"))
                    .font(.headline)
                Text(String(
                    format: String(localized: "Widgets are included with %@."),
                    ProductConfig.launchPriceCopy))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct QuotaKitWidgetEmptyView: View {
    let family: WidgetFamily

    var body: some View {
        switch self.family {
        case .accessoryCircular:
            Image(systemName: "hourglass")
        case .accessoryRectangular:
            VStack(alignment: .center, spacing: 2) {
                Text(String(localized: "QuotaKit"))
                    .font(.headline)
                Text(String(localized: "Open the app after Mac sync"))
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        default:
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Open the app after your Mac syncs to refresh widget data."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

enum QuotaKitWidgetPreviewData {
    static let simulatorSnapshot = QuotaKitWidgetSnapshot(
        generatedAt: Date(),
        providers: [Self.claudeProvider(lastUpdated: Date())])

    static let snapshot = QuotaKitWidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 1_803_000_000),
        providers: [
            .init(
                id: "codex",
                providerName: "Codex",
                lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
                statusMessage: nil,
                isError: false,
                windows: [
                    .init(
                        title: "Session",
                        usedPercent: 37,
                        remainingPercent: 63,
                        resetsAt: Date(timeIntervalSince1970: 1_803_018_000),
                        pace: .init(
                            stage: .slightlyBehind,
                            deltaPercent: -5,
                            expectedUsedPercent: 42,
                            actualUsedPercent: 37,
                            leftLabel: "5% in reserve",
                            rightLabel: "Lasts until reset")),
                    .init(
                        title: "Weekly",
                        usedPercent: 18,
                        remainingPercent: 82,
                        resetsAt: Date(timeIntervalSince1970: 1_803_400_000),
                        pace: .init(
                            stage: .slightlyBehind,
                            deltaPercent: -9,
                            expectedUsedPercent: 27,
                            actualUsedPercent: 18,
                            leftLabel: "9% in reserve",
                            rightLabel: "Lasts until reset")),
                ]),
            Self.claudeProvider(lastUpdated: Date(timeIntervalSince1970: 1_803_000_000)),
        ])

    private static func claudeProvider(lastUpdated: Date) -> QuotaKitWidgetSnapshot.Provider {
        .init(
            id: "claude",
            providerName: "Claude",
            lastUpdated: lastUpdated,
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "Session",
                    usedPercent: 61,
                    remainingPercent: 39,
                    resetsAt: lastUpdated.addingTimeInterval(2 * 60 * 60),
                    pace: .init(
                        stage: .ahead,
                        deltaPercent: 11,
                        expectedUsedPercent: 50,
                        actualUsedPercent: 61,
                        leftLabel: "11% in deficit",
                        rightLabel: "Projected empty in 2h")),
            ])
    }
}

private extension SyncUsagePace {
    var widgetDisplayText: String {
        if let rightLabel, !rightLabel.isEmpty {
            return "\(self.leftLabel) · \(rightLabel)"
        }
        return self.leftLabel
    }

    /// Unsigned delta magnitude ("11%"); the chip's triangle carries the
    /// direction (up = reserve, down = deficit). Nil when on pace.
    var widgetDeltaText: String? {
        let reserve = Int((-self.deltaPercent).rounded())
        guard reserve != 0 else { return nil }
        return "\(abs(reserve))%"
    }

    var widgetColor: Color {
        if self.deltaPercent > 0 { return .red }
        if self.deltaPercent < 0 { return .green }
        return .secondary
    }

    /// Marker x-position on the widget's remaining-percent bar; mirrors
    /// `UsageCardView.paceDisplayPercent` in `.remaining` display mode.
    var widgetMarkerRemainingPercent: Double? {
        guard self.stage != .onTrack else { return nil }
        return 100 - self.expectedUsedPercent.clamped(to: 0...100)
    }

    /// Mirrors `UsageCardView.paceStripeColor`.
    func widgetStripeColor(onTrackTint: Color) -> Color {
        if self.deltaPercent > 0 { return .red }
        if self.deltaPercent < 0 { return .green }
        return onTrackTint
    }
}
