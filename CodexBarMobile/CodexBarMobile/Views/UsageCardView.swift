import CodexBarSync
import SwiftUI

struct UsageCardView: View {
    let label: String
    let window: SyncRateWindow
    var tintColor: Color = .blue
    var percentageAccessibilityIdentifier: String?
    @AppStorage(MobileSettingsKeys.showRemainingUsage) private var showRemainingUsage =
        UserDefaults.standard.string(forKey: MobileSettingsKeys.usagePercentDisplayMode) == UsagePercentDisplayMode.remaining.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(alignment: .firstTextBaseline) {
                Text(self.label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                self.percentageLabel
                    .modifier(PercentageAccessibilityIdentifierModifier(
                        identifier: self.percentageAccessibilityIdentifier))
            }

            // Progress bar
            // `scaleEffect(y: 2)` makes SwiftUI's 1pt-tall native ProgressView
            // render as ~2pt — large enough to be visible and satisfy a
            // minimum-touch-target hint on iOS but still compact enough to
            // fit inside the card's 12pt vertical spacing. Removing this
            // makes the bar near-invisible on Retina displays.
            ProgressView(value: self.displayMode.progressFraction(for: self.window))
                .tint(self.usageColor)
                .scaleEffect(y: 2, anchor: .center)

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
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var percentageLabel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(self.displayMode.percentageValueText(for: self.window))
                    .font(.title2.monospacedDigit())
                    .fontWeight(.bold)

                Text(self.displayMode.percentSuffix)
                    .font(.title3)
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

    private var usageColor: Color {
        // 70% (orange warning) / 90% (red critical) thresholds chosen to
        // match the industry-standard quota-warning bands users see on
        // AWS / Azure / GCP dashboards and Apple's built-in Storage UI.
        // These are also the same thresholds used by `BudgetProgressView`;
        // keeping them in sync means every quota-like display across the
        // app turns the same color at the same percentage, so "orange"
        // always reads as "getting close" and "red" as "critical".
        // Changing here requires changing BudgetProgressView symmetrically.
        if self.window.usedPercent >= 90 {
            return .red
        } else if self.window.usedPercent >= 70 {
            return .orange
        } else {
            return self.tintColor
        }
    }
}

private struct PercentageAccessibilityIdentifierModifier: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
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
        tintColor: Color(red: 0.82, green: 0.55, blue: 0.28))
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
        tintColor: .purple)
    .padding()
}
