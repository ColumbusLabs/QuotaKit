import Charts
import CodexBarSync
import SwiftUI

/// Anthropic Admin API per-org usage section on the Claude detail
/// page. Mirrors the OpenAI Admin API Dashboard layout (Today / 7d /
/// 30d summary cards + top models + top cost items). Only rendered
/// when `ProviderUsageSnapshot.claudeAdminUsage` is non-nil — Mac
/// surfaces this when an Anthropic Admin API key
/// (`sk-ant-admin…`) is configured in Preferences → Providers →
/// Claude.
struct ClaudeAdminUsageCard: View {
    let usage: SyncClaudeAdminUsage
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.header
            self.summaryGrid
            if !self.usage.topModels.isEmpty {
                self.topModelsSection
            }
            if !self.usage.topCostItems.isEmpty {
                self.topCostItemsSection
            }
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("claude-admin-usage-card")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(String(localized: "claude_admin_title", defaultValue: "Anthropic Admin API"))
                .font(.headline)
            Spacer()
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10)
        {
            self.summaryCard(
                title: String(localized: "claude_admin_today", defaultValue: "Today"),
                summary: self.usage.latestDay)
            self.summaryCard(
                title: String(localized: "claude_admin_7days", defaultValue: "7 Days"),
                summary: self.usage.last7Days)
            self.summaryCard(
                title: String(localized: "claude_admin_30days", defaultValue: "30 Days"),
                summary: self.usage.last30Days)
        }
    }

    private func summaryCard(title: String, summary: SyncClaudeAdminWindowSummary?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Text(summary.map { Self.formatUSD($0.costUSD) } ?? "—")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(self.tintColor)
            if let summary {
                Text(Self.formatTokens(summary.totalTokens))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08)))
    }

    private var topModelsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "claude_admin_top_models", defaultValue: "Top models"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(self.usage.topModels.prefix(5)) { model in
                HStack {
                    Text(model.name)
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(Self.formatTokens(model.totalTokens))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var topCostItemsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "claude_admin_top_cost_items", defaultValue: "Top cost items"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(self.usage.topCostItems.prefix(5)) { item in
                HStack {
                    Text(item.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(Self.formatUSD(item.costUSD))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private static func formatUSD(_ value: Double) -> String {
        CostFormatting.usd(value)
    }

    private static func formatTokens(_ count: Int) -> String {
        CostFormatting.tokens(count)
    }
}

#Preview {
    ClaudeAdminUsageCard(
        usage: SyncClaudeAdminUsage(
            last30Days: SyncClaudeAdminWindowSummary(
                costUSD: 286.52,
                totalTokens: 8_125_000,
                inputTokens: 4_120_000,
                outputTokens: 1_205_000,
                cacheCreationInputTokens: 320_000,
                cacheReadInputTokens: 2_480_000),
            last7Days: SyncClaudeAdminWindowSummary(
                costUSD: 72.31,
                totalTokens: 2_140_000,
                inputTokens: 980_000,
                outputTokens: 310_000,
                cacheCreationInputTokens: 60000,
                cacheReadInputTokens: 790_000),
            latestDay: SyncClaudeAdminWindowSummary(
                costUSD: 11.42,
                totalTokens: 320_000,
                inputTokens: 142_000,
                outputTokens: 48000,
                cacheCreationInputTokens: 9000,
                cacheReadInputTokens: 121_000),
            topModels: [
                SyncClaudeAdminModelBreakdown(name: "claude-sonnet-4-6", totalTokens: 4_220_000),
                SyncClaudeAdminModelBreakdown(name: "claude-opus-4-7", totalTokens: 2_180_000),
            ],
            topCostItems: [
                SyncClaudeAdminCostItem(name: "Input tokens", costUSD: 142.80),
                SyncClaudeAdminCostItem(name: "Output tokens", costUSD: 95.40),
                SyncClaudeAdminCostItem(name: "Cache creation", costUSD: 38.32),
            ],
            updatedAt: Date()),
        tintColor: .orange)
        .padding()
}
