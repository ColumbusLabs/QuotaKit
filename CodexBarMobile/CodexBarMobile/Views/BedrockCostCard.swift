import CodexBarSync
import SwiftUI

/// Dedicated AWS Bedrock cost card. Bedrock is a cost-forward provider
/// (not quota-bar based) — monthly spend + optional budget with a
/// percentage gauge and the active AWS region.
///
/// Populated only when `ProviderUsageSnapshot.bedrockCost` is non-nil
/// (Mac 0.26.2+ on the `bedrock` provider, which was added by upstream
/// PR #897 in v0.26.0).
struct BedrockCostCard: View {
    let cost: SyncBedrockCost
    let tintColor: Color

    private var fraction: Double {
        guard let percent = cost.budgetUsedPercent else { return 0 }
        return min(max(percent / 100, 0), 1)
    }

    private var statusColor: Color {
        guard let percent = cost.budgetUsedPercent else { return tintColor }
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        return tintColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.header

            self.spendRow

            if cost.monthlyBudgetUSD != nil {
                self.budgetProgress
            }

            if let region = cost.region, !region.isEmpty {
                Text(String(format: String(localized: "bedrock_region_format", defaultValue: "Region: %@"), region))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bedrock-cost-card")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(String(localized: "bedrock_monthly_spend", defaultValue: "Bedrock monthly spend"))
                .font(.headline)
            Spacer()
        }
    }

    private var spendRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Self.formatUSD(cost.monthlySpendUSD))
                .font(.title2.monospacedDigit().bold())
                .foregroundStyle(self.statusColor)
            if let budget = cost.monthlyBudgetUSD {
                Text("/ \(Self.formatUSD(budget))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var budgetProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: self.fraction)
                .progressViewStyle(.linear)
                .tint(self.statusColor)
            if let percent = cost.budgetUsedPercent {
                HStack {
                    Text(String(format: String(localized: "bedrock_budget_used_format", defaultValue: "%d%% of monthly budget"), Int(percent.rounded())))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let budget = cost.monthlyBudgetUSD {
                        let remaining = max(budget - cost.monthlySpendUSD, 0)
                        Text(String(format: String(localized: "bedrock_budget_remaining_format", defaultValue: "%@ left"), Self.formatUSD(remaining)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private static func formatUSD(_ value: Double) -> String {
        CostFormatting.usd(value)
    }
}

#Preview {
    BedrockCostCard(
        cost: SyncBedrockCost(
            monthlySpendUSD: 19.1,
            monthlyBudgetUSD: 50.0,
            inputTokens: 4_200_000,
            outputTokens: 1_100_000,
            region: "us-east-1",
            budgetUsedPercent: 38.2,
            updatedAt: Date()),
        tintColor: Color(red: 1.0, green: 0.6, blue: 0.0))
        .padding()
}
