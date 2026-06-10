import CodexBarSync
import SwiftUI
import WidgetKit

struct QuotaKitWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaKitWidgetSnapshot?
    let isUnlocked: Bool
    let isPreview: Bool
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
                    QuotaKitWidgetMediumView(snapshot: snapshot)
                case .accessoryRectangular:
                    QuotaKitWidgetAccessoryRectangularView(provider: provider)
                case .accessoryCircular:
                    QuotaKitWidgetAccessoryCircularView(provider: provider)
                default:
                    QuotaKitWidgetSmallView(provider: provider)
                }
            } else {
                QuotaKitWidgetEmptyView(family: family)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

/// Brand colors local to the widget target: `Design/` sources are not
/// compiled into the widget extension, so the accent mirrors
/// `QuotaKitTheme.brandAccent` and the ramp mirrors `QuotaUsageColor`.
private enum WidgetPalette {
    static let brandAccent = Color(red: 1.0, green: 0.73, blue: 0.08)

    static func quotaRamp(usedPercent: Double) -> Color {
        if usedPercent >= 90 { return .red }
        if usedPercent >= 70 { return .orange }
        return .green
    }
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

private struct WidgetQuotaBar: View {
    let usedPercent: Double
    var height: CGFloat = 6

    private var fillFraction: CGFloat {
        CGFloat(max(0, min(100, 100 - self.usedPercent)) / 100)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(WidgetPalette.quotaRamp(usedPercent: self.usedPercent))
                    .frame(width: max(self.height, proxy.size.width * self.fillFraction))
            }
        }
        .frame(height: self.height)
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
            .background(self.pace.widgetColor.opacity(0.13), in: Capsule())
            .lineLimit(1)
        }
    }
}

private struct QuotaKitWidgetSmallView: View {
    let provider: QuotaKitWidgetSnapshot.Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetBrandHeader()

            Spacer(minLength: 4)

            Text(self.provider.providerName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if let window = self.provider.primaryWindow {
                Text(window.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(window.remainingPercent.rounded()))")
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        Text(verbatim: "%")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                    Spacer(minLength: 2)

                    if let pace = window.pace {
                        WidgetPaceChip(pace: pace)
                    }
                }
                .padding(.bottom, 7)

                WidgetQuotaBar(usedPercent: window.usedPercent)

                if let paceText = window.pace?.widgetDisplayText {
                    Text(paceText)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(window.pace?.widgetColor ?? Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.top, 7)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct QuotaKitWidgetMediumView: View {
    let snapshot: QuotaKitWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                WidgetBrandHeader()
                Spacer()
                Text(self.snapshot.generatedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            let providers = Array(self.snapshot.providers.prefix(3))
            ForEach(providers) { provider in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(provider.providerName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(provider.widgetSubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        if let window = provider.primaryWindow {
                            if let pace = window.pace {
                                WidgetPaceChip(pace: pace, compact: true)
                            }
                            Text("\(Int(window.remainingPercent.rounded()))%")
                                .font(.subheadline.monospacedDigit())
                                .fontWeight(.semibold)
                        } else {
                            Image(systemName: provider.isError ? "exclamationmark.triangle" : "minus")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let window = provider.primaryWindow {
                        WidgetQuotaBar(usedPercent: window.usedPercent, height: 4)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct QuotaKitWidgetAccessoryRectangularView: View {
    let provider: QuotaKitWidgetSnapshot.Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(provider.providerName)
                .font(.headline)
                .lineLimit(1)
            if let window = provider.primaryWindow {
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

    var body: some View {
        if let window = provider.primaryWindow {
            Gauge(value: window.remainingPercent, in: 0...100) {
                Text(String(localized: "Quota"))
            } currentValueLabel: {
                Text("\(Int(window.remainingPercent.rounded()))")
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
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "QuotaKit Pro"))
                    .font(.headline)
                Text(String(localized: "Unlock widgets"))
                    .font(.caption)
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                WidgetBrandHeader()
                Spacer(minLength: 8)
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(WidgetPalette.brandAccent)
                    .padding(.bottom, 6)
                Text(String(localized: "QuotaKit Pro"))
                    .font(.headline)
                    .padding(.bottom, 2)
                Text(String(
                    format: String(localized: "Widgets are included with the %@ lifetime unlock."),
                    ProductConfig.launchPriceCopy))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "QuotaKit"))
                    .font(.headline)
                Text(String(localized: "Open the app after Mac sync"))
                    .font(.caption)
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                WidgetBrandHeader()
                Spacer(minLength: 8)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                Text(String(localized: "Open the app after your Mac syncs to refresh widget data."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

enum QuotaKitWidgetPreviewData {
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
                ]),
            .init(
                id: "claude",
                providerName: "Claude",
                lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
                statusMessage: nil,
                isError: false,
                windows: [
                    .init(
                        title: "Session",
                        usedPercent: 61,
                        remainingPercent: 39,
                        resetsAt: Date(timeIntervalSince1970: 1_803_012_000),
                        pace: .init(
                            stage: .ahead,
                            deltaPercent: 11,
                            expectedUsedPercent: 50,
                            actualUsedPercent: 61,
                            leftLabel: "11% in deficit",
                            rightLabel: "Projected empty in 2h")),
                ]),
        ])
}

private extension QuotaKitWidgetSnapshot.Provider {
    var widgetSubtitle: String {
        guard let window = self.primaryWindow else {
            return self.statusMessage ?? String(localized: "No quota window")
        }
        return window.title
    }
}

private extension SyncUsagePace {
    var widgetDisplayText: String {
        if let rightLabel, !rightLabel.isEmpty {
            return "\(self.leftLabel) · \(rightLabel)"
        }
        return self.leftLabel
    }

    /// Signed delta with reserve framed as positive ("+81%" = 81% of the
    /// window still in reserve versus expected pace); nil when on pace.
    var widgetDeltaText: String? {
        let reserve = Int((-self.deltaPercent).rounded())
        guard reserve != 0 else { return nil }
        return String(format: "%+d%%", reserve)
    }

    var widgetColor: Color {
        if self.deltaPercent > 0 { return .red }
        if self.deltaPercent < 0 { return .green }
        return .secondary
    }
}
