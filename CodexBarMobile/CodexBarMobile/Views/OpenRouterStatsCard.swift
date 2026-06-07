import CodexBarSync
import SwiftUI

/// OpenRouter balance + credits + per-key usage card (parity gap D).
///
/// Renders only when `SyncOpenRouterStats` is present. Older Mac payloads
/// (< 0.29.0) omit the field and `ProviderDetailView` falls back to the
/// generic key-usage rate window + the "Balance: $X" loginMethod line.
struct OpenRouterStatsCard: View {
    let stats: SyncOpenRouterStats
    var tintColor: Color = .indigo

    private func usd(_ value: Double) -> String { String(format: "$%.2f", value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Credits")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: String(localized: "%@ left"), self.usd(self.stats.balanceUSD)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(self.tintColor)
                    .accessibilityIdentifier("openrouter-balance")
            }

            ProgressView(value: min(max(self.stats.usedPercent / 100, 0), 1)) {
                HStack {
                    Text(String(
                        format: String(localized: "%1$@ of %2$@ used"),
                        self.usd(self.stats.totalUsageUSD),
                        self.usd(self.stats.totalCreditsUSD)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", self.stats.usedPercent))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .tint(self.tintColor)

            if self.hasKeyWindows {
                HStack(spacing: 18) {
                    if let daily = self.stats.keyUsageDailyUSD {
                        self.usageStat(label: String(localized: "Today"), value: self.usd(daily))
                    }
                    if let weekly = self.stats.keyUsageWeeklyUSD {
                        self.usageStat(label: String(localized: "Week"), value: self.usd(weekly))
                    }
                    if let monthly = self.stats.keyUsageMonthlyUSD {
                        self.usageStat(label: String(localized: "Month"), value: self.usd(monthly))
                    }
                }
            }

            if let requests = self.stats.rateLimitRequests, let interval = self.stats.rateLimitInterval {
                Text(String(
                    format: String(localized: "Rate limit: %1$d req / %2$@"),
                    requests,
                    interval))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
    }

    private var hasKeyWindows: Bool {
        self.stats.keyUsageDailyUSD != nil
            || self.stats.keyUsageWeeklyUSD != nil
            || self.stats.keyUsageMonthlyUSD != nil
    }

    @ViewBuilder
    private func usageStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
        }
    }
}
