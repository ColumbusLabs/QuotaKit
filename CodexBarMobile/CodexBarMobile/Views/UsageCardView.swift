import CodexBarSync
import SwiftUI

enum UsageCardLayout {
    case standard
    case compact
}

struct UsageCardView: View {
    @Environment(\.quotaKitTheme) private var theme
    let label: String
    let window: SyncRateWindow
    var tintColor: Color = .blue
    var layout: UsageCardLayout = .standard
    var percentageAccessibilityIdentifier: String?
    /// Quota warning thresholds expressed as **remaining percent**, as
    /// resolved by Mac's `SettingsStore` per (provider, window). `nil`
    /// → fall back to `SyncQuotaWarningConfig.macDefaults` so a sync
    /// gap with an old Mac doesn't leave the bar marker-less. `[]`
    /// → user explicitly cleared all thresholds; render no markers.
    /// See Research/020 §R7.4 for the 16-cell device matrix proof.
    var quotaWarningThresholds: [Int]?
    /// Whether to render warning markers at all. Mirrors Mac's per
    /// (provider, window) enable flag.
    var quotaWarningsEnabled: Bool = true
    @AppStorage(MobileSettingsKeys.showRemainingUsage) private var showRemainingUsage =
        UserDefaults.standard.string(forKey: MobileSettingsKeys.usagePercentDisplayMode) == UsagePercentDisplayMode.remaining.rawValue
    /// Global "hide warning markers" toggle (iOS 1.7.0, mirrors upstream
    /// PR #918). The quota-warning notification is unaffected — only the
    /// tick-mark on the usage bar is hidden when true.
    @AppStorage(MobileSettingsKeys.hideQuotaWarningMarkers) private var hideQuotaWarningMarkers = false

    var body: some View {
        VStack(alignment: .leading, spacing: self.layout == .compact ? 6 : 10) {
            // Header row
            HStack(alignment: .firstTextBaseline) {
                Text(self.label)
                    .font(self.layout == .compact ? .caption.weight(.semibold) : .subheadline)
                    .fontWeight(.semibold)
                if self.shouldShowWarningIcon {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(self.usageColor)
                        .accessibilityLabel(Text("Quota warning"))
                        .accessibilityIdentifier("usage.warning.icon")
                }
                Spacer()
                self.percentageLabel
                    .modifier(AccessibilityIdentifierModifier(
                        identifier: self.percentageAccessibilityIdentifier))
            }

            UsageProgressBarView(
                progressFraction: self.displayMode.progressFraction(for: self.window),
                tintColor: self.usageColor,
                trackColor: self.theme.border,
                markerPercents: self.markerDisplayPercents,
                pacePercent: self.paceDisplayPercent,
                paceColor: self.paceStripeColor)

            // Reset info
            if let resetsAt = self.window.resetsAt {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                    Text("\(String(localized: "Resets")) \(resetsAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            } else if let description = self.window.resetDescription {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                    Text(description)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            if let pace = self.window.pace {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        self.paceLeftLabel(pace.leftLabel)
                        Spacer(minLength: 8)
                        if let rightLabel = pace.rightLabel, !rightLabel.isEmpty {
                            self.paceRightLabel(rightLabel)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        self.paceLeftLabel(pace.leftLabel)
                        if let rightLabel = pace.rightLabel, !rightLabel.isEmpty {
                            self.paceRightLabel(rightLabel)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("usage.pace")
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var percentageLabel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(self.displayMode.percentageValueText(for: self.window))
                    .font(self.layout == .compact ? .headline.monospacedDigit() : .title2.monospacedDigit())
                    .fontWeight(.bold)

                Text(self.displayMode.percentSuffix)
                    .font(self.layout == .compact ? .subheadline : .title3)
                    .fontWeight(.bold)
            }
            .foregroundColor(self.usageColor)
            .fixedSize(horizontal: true, vertical: false)

            Text(self.displayMode.percentageText(for: self.window))
                .font(.title3.monospacedDigit())
                .fontWeight(.bold)
                .foregroundColor(self.usageColor)
                .fixedSize(horizontal: true, vertical: false)
        }
        .layoutPriority(1)
    }

    private var displayMode: UsagePercentDisplayMode {
        self.showRemainingUsage ? .remaining : .used
    }

    private func paceLeftLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(self.paceTextColor)
            .lineLimit(1)
    }

    private func paceRightLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(Color.primary.opacity(0.72))
            .lineLimit(1)
    }

    /// Marker x-positions on the bar, in **used percent** units (0…100).
    /// Mac's `QuotaWarningConfig` stores **remaining percent** (e.g.
    /// `[50, 20]` = "warn at 50% remaining" + "warn at 20% remaining"),
    /// which on a used-percent bar maps to positions `100 - threshold`
    /// (= 50% and 80% used). Defensive clamp + dedupe + sort lets us
    /// render even if the wire payload contains out-of-range values
    /// from a future Mac config schema.
    private var markerUsedPercents: [Int] {
        let raw: [Int]
        if let configured = self.quotaWarningThresholds {
            raw = configured
        } else {
            raw = SyncQuotaWarningConfig.macDefaults
        }
        let mapped = raw
            .map { 100 - max(0, min(100, $0)) }
            .filter { $0 > 0 && $0 < 100 }
        return Array(Set(mapped)).sorted()
    }

    private var markerDisplayPercents: [Double] {
        guard self.quotaWarningsEnabled, !self.hideQuotaWarningMarkers else { return [] }
        return self.markerUsedPercents.map { usedPercent in
            switch self.displayMode {
            case .used:
                Double(usedPercent)
            case .remaining:
                Double(100 - usedPercent)
            }
        }
    }

    var paceDisplayPercent: Double? {
        guard let pace = self.window.pace else { return nil }
        return Self.paceDisplayPercent(for: pace, displayMode: self.displayMode)
    }

    static func paceDisplayPercent(
        for pace: SyncUsagePace,
        displayMode: UsagePercentDisplayMode) -> Double?
    {
        guard pace.stage != .onTrack else { return nil }
        let expected = pace.expectedUsedPercent.clamped(to: 0...100)
        switch displayMode {
        case .used:
            return expected
        case .remaining:
            return 100 - expected
        }
    }

    private var paceStripeColor: Color {
        guard let pace = self.window.pace else { return .clear }
        if pace.deltaPercent > 0 { return .red }
        if pace.deltaPercent < 0 { return .green }
        return self.tintColor
    }

    private var paceTextColor: Color {
        guard let pace = self.window.pace else { return .secondary }
        if pace.deltaPercent > 0 { return .red }
        if pace.deltaPercent < 0 { return .green }
        return self.tintColor
    }

    /// True once the user crosses the most critical warning threshold —
    /// matches Mac's notification firing semantics where the lowest
    /// remaining-percent threshold is the highest used-percent position.
    private var shouldShowWarningIcon: Bool {
        guard self.quotaWarningsEnabled else { return false }
        guard let maxMarker = self.markerUsedPercents.max() else { return false }
        return Int(self.window.usedPercent.rounded()) >= maxMarker
    }

    private var usageColor: Color {
        QuotaUsageColor.color(usedPercent: self.window.usedPercent, tint: self.tintColor)
    }
}

// MARK: - Previews

#Preview("Low Usage") {
    UsageCardView(
        label: "Session (5h)",
        window: SyncRateWindow(
            usedPercent: 25,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(3600 * 3),
            resetDescription: nil),
        tintColor: Color(red: 0.82, green: 0.55, blue: 0.28),
        quotaWarningThresholds: [50, 20])
    .padding()
}

#Preview("High Usage") {
    UsageCardView(
        label: "Weekly",
        window: SyncRateWindow(
            usedPercent: 92,
            windowMinutes: 10_080,
            resetsAt: Date().addingTimeInterval(3600 * 24),
            resetDescription: nil),
        tintColor: .purple,
        quotaWarningThresholds: [50, 20])
    .padding()
}

#Preview("Custom Thresholds") {
    UsageCardView(
        label: "Session (5h)",
        window: SyncRateWindow(
            usedPercent: 65,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(3600 * 3),
            resetDescription: nil),
        tintColor: .indigo,
        quotaWarningThresholds: [70, 40, 10])
    .padding()
}
