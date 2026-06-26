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
        guard let percent = cost.budgetUsedPercent else { return self.tintColor }
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        return self.tintColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.header

            self.spendRow

            if self.cost.monthlyBudgetUSD != nil {
                self.budgetProgress
            }

            if let activityText = Self.activityLineText(for: cost) {
                Text(activityText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let region = cost.region, !region.isEmpty {
                Text(String(format: String(localized: "bedrock_region_format", defaultValue: "Region: %@"), region))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
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
            Text(Self.formatUSD(self.cost.monthlySpendUSD))
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
                    Text(String(
                        format: String(localized: "bedrock_budget_used_format", defaultValue: "%d%% of monthly budget"),
                        Int(percent.rounded())))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let budget = cost.monthlyBudgetUSD {
                        let remaining = max(budget - self.cost.monthlySpendUSD, 0)
                        Text(String(
                            format: String(localized: "bedrock_budget_remaining_format", defaultValue: "%@ left"),
                            Self.formatUSD(remaining)))
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

    // MARK: - Text helpers (introspectable for C1 regression tests)

    //
    // These produce the exact strings the SwiftUI body renders. Tests
    // pin them so a future format-string drift (or a re-introduction
    // of the C1 bug where region was the loginMethod composite) shows
    // up as a failed assertion on the visible string itself.

    /// String the view renders on the "Region: ..." line — or nil if
    /// the region field is missing/empty (line is omitted entirely).
    static func regionLineText(for cost: SyncBedrockCost) -> String? {
        guard let region = cost.region, !region.isEmpty else { return nil }
        return String(format: String(localized: "bedrock_region_format", defaultValue: "Region: %@"), region)
    }

    /// String the view renders on the spend row — e.g. "$19.10" or
    /// "$19.10 / $50.00".
    static func spendRowText(for cost: SyncBedrockCost) -> String {
        let spend = Self.formatUSD(cost.monthlySpendUSD)
        guard let budget = cost.monthlyBudgetUSD else { return spend }
        return "\(spend) / \(Self.formatUSD(budget))"
    }

    static func activityLineText(for cost: SyncBedrockCost) -> String? {
        var parts: [String] = []
        if let input = cost.inputTokens, let output = cost.outputTokens {
            parts.append(String(
                format: String(localized: "bedrock_tokens_format", defaultValue: "%@ tokens"),
                Self.formatCount(input + output)))
        }
        if let requestCount = cost.requestCount {
            parts.append(String(
                format: String(localized: "bedrock_requests_format", defaultValue: "%@ requests"),
                Self.formatCount(requestCount)))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private static func formatCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000)
        }
        return "\(value)"
    }
}

#Preview {
    BedrockCostCard(
        cost: SyncBedrockCost(
            monthlySpendUSD: 19.1,
            monthlyBudgetUSD: 50.0,
            inputTokens: 4_200_000,
            outputTokens: 1_100_000,
            requestCount: 321,
            region: "us-east-1",
            budgetUsedPercent: 38.2,
            updatedAt: Date()),
        tintColor: Color(red: 1.0, green: 0.6, blue: 0.0))
        .padding()
}
