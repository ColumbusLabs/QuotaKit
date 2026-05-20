import CodexBarSync
import SwiftUI

/// Claude "Extra usage" / spend-limit metric. Shown on Enterprise and
/// Team-with-extra-usage plans where Anthropic exposes a monthly
/// dollar cap separate from the session / weekly token quotas. Only
/// rendered when `ProviderUsageSnapshot.claudeExtraUsage` is non-nil.
///
/// When `isEnabled == false`, the card collapses to a single
/// "Extra usage disabled" caption so the user knows the lane exists
/// but isn't active.
struct ClaudeExtraUsageCard: View {
    let extraUsage: SyncClaudeExtraUsage
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.header
            if extraUsage.isEnabled {
                self.gauge
                self.detailRow
            } else {
                Text(String(localized: "claude_extra_usage_disabled", defaultValue: "Extra usage is disabled on the Anthropic console."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("claude-extra-usage-card")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(String(localized: "claude_extra_usage_title", defaultValue: "Extra usage"))
                .font(.headline)
            if let tier = extraUsage.planTier, !tier.isEmpty {
                Text(tier)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(self.tintColor.opacity(0.15)))
                    .foregroundStyle(self.tintColor)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var gauge: some View {
        if let percent = extraUsage.utilization {
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.18))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(self.tintColor.gradient)
                            .frame(width: proxy.size.width * CGFloat(max(0, min(1, percent / 100))))
                    }
                }
                .frame(height: 8)
                Text(String(format: "%.1f%%", percent))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailRow: some View {
        HStack {
            if let spend = extraUsage.monthlySpendUSD {
                if let limit = extraUsage.monthlyLimitUSD {
                    Text(String(format: String(localized: "claude_extra_usage_spend_limit_format", defaultValue: "%@ / %@"), Self.formatUSD(spend), Self.formatUSD(limit)))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(self.tintColor)
                } else {
                    Text(Self.formatUSD(spend))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(self.tintColor)
                }
            }
            Spacer()
            Text(String(localized: "claude_extra_usage_period", defaultValue: "This month"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static func formatUSD(_ value: Double) -> String { CostFormatting.usd(value) }
}

#Preview {
    VStack(spacing: 12) {
        ClaudeExtraUsageCard(
            extraUsage: SyncClaudeExtraUsage(
                utilization: 38.5,
                monthlySpendUSD: 38.50,
                monthlyLimitUSD: 100.00,
                isEnabled: true,
                planTier: "Enterprise",
                updatedAt: Date()),
            tintColor: .orange)
        ClaudeExtraUsageCard(
            extraUsage: SyncClaudeExtraUsage(
                utilization: nil,
                monthlySpendUSD: nil,
                monthlyLimitUSD: nil,
                isEnabled: false,
                planTier: "Team",
                updatedAt: Date()),
            tintColor: .orange)
    }
    .padding()
}
