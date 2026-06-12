import CodexBarSync
import Foundation
import SwiftUI
import WidgetKit

struct QuotaKitWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaKitWidgetSnapshot?
    let isUnlocked: Bool
    let isPreview: Bool
    var displayMode: QuotaKitWidgetDisplayMode = .both
}

struct QuotaKitWidgetDisplayWindow: Identifiable, Equatable {
    let mode: QuotaKitWidgetDisplayMode
    let window: QuotaKitWidgetSnapshot.Provider.Window

    var id: String {
        "\(self.mode.rawValue)-\(self.window.title)"
    }

    var title: String {
        self.mode.localizedTitle
    }
}

extension QuotaKitWidgetSnapshot.Provider {
    func window(for displayMode: QuotaKitWidgetDisplayMode) -> Window? {
        switch displayMode {
        case .both:
            return self.sessionWindow(allowPrimaryFallback: true)
        case .session:
            return self.sessionWindow(allowPrimaryFallback: true)
        case .weekly:
            return self.weeklyWindow(allowPrimaryFallback: true)
        }
    }

    func displayWindows(for displayMode: QuotaKitWidgetDisplayMode) -> [QuotaKitWidgetDisplayWindow] {
        switch displayMode {
        case .both:
            let weekly = self.weeklyWindow(allowPrimaryFallback: false)
            let session = self.sessionWindowForBothMode(weekly: weekly)
            var result = session.map {
                [QuotaKitWidgetDisplayWindow(mode: .session, window: $0)]
            } ?? []
            if let weekly,
               session.map({ weekly != $0 }) ?? true
            {
                result.append(QuotaKitWidgetDisplayWindow(mode: .weekly, window: weekly))
            }
            return result
        case .session, .weekly:
            return self.window(for: displayMode).map {
                [QuotaKitWidgetDisplayWindow(mode: displayMode, window: $0)]
            } ?? []
        }
    }

    private func sessionWindow(allowPrimaryFallback: Bool) -> Window? {
        self.windows.first(where: Self.isSessionWindow)
            ?? (allowPrimaryFallback ? self.windows.first : nil)
    }

    private func sessionWindowForBothMode(weekly: Window?) -> Window? {
        if let explicitSession = self.windows.first(where: Self.isSessionWindow) {
            return explicitSession
        }
        if let weekly,
           let primary = self.windows.first,
           primary != weekly
        {
            return primary
        }
        return weekly == nil ? self.windows.first : nil
    }

    private func weeklyWindow(allowPrimaryFallback: Bool) -> Window? {
        self.windows.first(where: Self.isWeeklyWindow)
            ?? self.windows.dropFirst().first
            ?? (allowPrimaryFallback ? self.windows.first : nil)
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
            || Self.hasNumericDayLabel(title)
            || title.contains(String(localized: "Weekly").localizedLowercase)
    }

    private static func hasNumericDayLabel(_ title: String) -> Bool {
        let normalized = title
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let tokens = normalized.split { character in
            !character.isLetter && !character.isNumber
        }

        var previousToken: Substring?
        for token in tokens {
            let tokenText = String(token)
            if (tokenText == "day" || tokenText == "days"),
               previousToken?.allSatisfy(\.isNumber) == true
            {
                return true
            }

            if tokenText.hasSuffix("day") {
                let prefix = tokenText.dropLast(3)
                if !prefix.isEmpty, prefix.allSatisfy(\.isNumber) {
                    return true
                }
            }

            if tokenText.hasSuffix("days") {
                let prefix = tokenText.dropLast(4)
                if !prefix.isEmpty, prefix.allSatisfy(\.isNumber) {
                    return true
                }
            }

            previousToken = token
        }
        return false
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
                        displayMode: self.entry.displayMode)
                case .accessoryRectangular:
                    QuotaKitWidgetAccessoryRectangularView(
                        provider: provider,
                        lastSyncedAt: snapshot.lastSyncedAt,
                        displayMode: self.entry.displayMode)
                case .accessoryCircular:
                    QuotaKitWidgetAccessoryCircularView(
                        provider: provider,
                        displayMode: self.entry.displayMode)
                default:
                    QuotaKitWidgetSmallView(
                        provider: provider,
                        lastSyncedAt: snapshot.lastSyncedAt,
                        displayMode: self.entry.displayMode)
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
enum WidgetSyncBadgeFreshness {
    static func isStale(lastSynced: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastSynced) > QuotaKitWidgetTimelineSchedule.staleThreshold
    }
}

private struct WidgetSyncBadge: View {
    let lastSynced: Date
    var showsIcon = true
    var compact = false

    /// Mirrors `SyncFreshnessState.staleThreshold`; evaluated when the
    /// timeline entry renders, so the tint can lag until the next refresh.
    private var isStale: Bool {
        WidgetSyncBadgeFreshness.isStale(lastSynced: self.lastSynced)
    }

    var body: some View {
        HStack(spacing: self.compact ? 2 : 3) {
            if self.showsIcon {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: self.compact ? 7 : 8, weight: .semibold))
            }
            Text(String(localized: "Synced"))
                + Text(verbatim: " ")
                + Text(self.lastSynced, style: .relative)
        }
        .font(self.compact ? .system(size: 9, weight: .medium) : .caption2)
        .foregroundStyle(self.isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
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

private struct WidgetCompactWindowRow: View {
    let providerID: String
    let displayWindow: QuotaKitWidgetDisplayWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(self.displayWindow.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: "\(Int(self.displayWindow.window.remainingPercent.rounded()))%")
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            WidgetUsageBar(
                window: self.displayWindow.window,
                tint: ProviderColorPalette.color(for: self.providerID))
                .frame(height: 5)
        }
    }
}

private struct WidgetCompactWindowColumn: View {
    let providerID: String
    let displayWindow: QuotaKitWidgetDisplayWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(self.displayWindow.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(verbatim: "\(Int(self.displayWindow.window.remainingPercent.rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            WidgetUsageBar(
                window: self.displayWindow.window,
                tint: ProviderColorPalette.color(for: self.providerID))
                .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuotaKitWidgetSmallView: View {
    let provider: QuotaKitWidgetSnapshot.Provider
    let lastSyncedAt: Date
    let displayMode: QuotaKitWidgetDisplayMode

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
                WidgetSyncBadge(
                    lastSynced: self.lastSyncedAt,
                    showsIcon: false,
                    compact: true)
            }

            if self.displayMode == .both {
                let displayWindows = self.provider.displayWindows(for: self.displayMode)
                if displayWindows.isEmpty {
                    Spacer(minLength: 4)
                    Text(self.provider.statusMessage ?? String(localized: "No quota window"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 6)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(displayWindows) { displayWindow in
                            WidgetCompactWindowRow(
                                providerID: self.provider.id,
                                displayWindow: displayWindow)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else if let window = self.provider.window(for: self.displayMode) {
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
    let displayMode: QuotaKitWidgetDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: self.displayMode == .both ? 8 : 11) {
            HStack {
                WidgetBrandHeader()
                Spacer()
                WidgetSyncBadge(lastSynced: self.snapshot.lastSyncedAt)
            }

            let providers = Array(self.snapshot.providers.prefix(3))
            ForEach(providers) { provider in
                let window = provider.window(for: self.displayMode)
                let displayWindows = provider.displayWindows(for: self.displayMode)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(provider.providerName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(self.subtitle(
                            for: provider,
                            window: window,
                            displayWindows: displayWindows))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        if self.displayMode == .both {
                            if displayWindows.isEmpty {
                                Image(systemName: provider.isError ? "exclamationmark.triangle" : "minus")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let window {
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

                    if self.displayMode == .both {
                        if !displayWindows.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(displayWindows) { displayWindow in
                                    WidgetCompactWindowColumn(
                                        providerID: provider.id,
                                        displayWindow: displayWindow)
                                }
                            }
                        }
                    } else if let window {
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

    private func subtitle(
        for provider: QuotaKitWidgetSnapshot.Provider,
        window: QuotaKitWidgetSnapshot.Provider.Window?,
        displayWindows: [QuotaKitWidgetDisplayWindow]) -> String
    {
        if self.displayMode == .both,
           !displayWindows.isEmpty
        {
            return displayWindows.map(\.title).joined(separator: " · ")
        }
        return window?.title
            ?? provider.statusMessage
            ?? String(localized: "No quota window")
    }
}

enum QuotaKitWidgetAccessoryRectangularPresentation {
    static func detailText(
        for provider: QuotaKitWidgetSnapshot.Provider,
        displayMode: QuotaKitWidgetDisplayMode) -> String
    {
        if displayMode == .both {
            let displayWindows = provider.displayWindows(for: displayMode)
            guard !displayWindows.isEmpty else {
                return provider.statusMessage ?? String(localized: "No quota window")
            }
            return displayWindows.map { displayWindow in
                String(
                    format: String(localized: "%@ %lld%%"),
                    displayWindow.title,
                    Int64(displayWindow.window.remainingPercent.rounded()))
            }.joined(separator: " · ")
        }

        guard let window = provider.window(for: displayMode) else {
            return provider.statusMessage ?? String(localized: "No quota window")
        }
        return String(
            format: String(localized: "%lld%% left · %@"),
            Int64(window.remainingPercent.rounded()),
            window.title)
    }
}

private struct QuotaKitWidgetAccessoryRectangularView: View {
    let provider: QuotaKitWidgetSnapshot.Provider
    let lastSyncedAt: Date
    let displayMode: QuotaKitWidgetDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(provider.providerName)
                .font(.headline)
                .lineLimit(1)
            Text(QuotaKitWidgetAccessoryRectangularPresentation.detailText(
                for: self.provider,
                displayMode: self.displayMode))
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            WidgetSyncBadge(
                lastSynced: self.lastSyncedAt,
                showsIcon: false,
                compact: true)
        }
    }
}

private struct QuotaKitWidgetAccessoryCircularView: View {
    let provider: QuotaKitWidgetSnapshot.Provider
    let displayMode: QuotaKitWidgetDisplayMode

    var body: some View {
        if let window = provider.window(for: self.displayMode) {
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
