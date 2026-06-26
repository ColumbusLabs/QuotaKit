import CodexBarSync
import SwiftUI

/// LLM Proxy meta-provider aggregate card. Renders when
/// `ProviderUsageSnapshot.llmProxyStats` is populated. Surfaces the
/// cross-provider quota state in a single tile: lowest remaining %,
/// credential-pool health, and the top-3 upstream breakdown.
struct LLMProxyStatsCard: View {
    let stats: SyncLLMProxyStats
    let tintColor: Color

    private var headlinePercentText: String? {
        guard let remaining = stats.minimumRemainingPercent else { return nil }
        let used = max(0, min(100, 100 - remaining))
        return "\(Int(used.rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(String(localized: "llmproxy_stats_title", defaultValue: "LLM Proxy aggregate"))
                    .font(.headline)
                Spacer()
                if let text = self.headlinePercentText {
                    Text(text)
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(self.tintColor)
                }
            }

            HStack {
                Text(self.credentialSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let cost = stats.approximateCostUSD, cost > 0 {
                    Text(Self.usd(cost))
                        .font(.caption.bold().monospacedDigit())
                }
            }

            HStack {
                Text(self.requestTokenSummary)
                    .font(.caption.monospacedDigit())
                Spacer()
                if let resetAt = stats.nextResetAt {
                    Text(resetAt, style: .date)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if !self.stats.topProviders.isEmpty {
                Divider()
                self.topProvidersList
            }
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("llmproxy-stats-card")
    }

    private var credentialSummary: String {
        let total = self.stats.credentialCount
        let active = self.stats.activeCredentialCount
        let exhausted = self.stats.exhaustedCredentialCount
        if exhausted > 0 {
            return String(
                format: String(
                    localized: "llmproxy_credentials_with_exhausted_format",
                    defaultValue: "%d / %d keys active · %d exhausted"),
                active, total, exhausted)
        }
        return String(
            format: String(
                localized: "llmproxy_credentials_active_format",
                defaultValue: "%d / %d keys active"),
            active, total)
    }

    private var requestTokenSummary: String {
        "\(Self.formatInt(self.stats.totalRequests)) req · \(Self.formatInt(self.stats.totalTokens)) tok"
    }

    private var topProvidersList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(
                localized: "llmproxy_top_providers_label",
                defaultValue: "Top providers (by requests)"))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(self.stats.topProviders, id: \.name) { p in
                HStack {
                    Text(p.name)
                        .font(.caption.bold())
                    Spacer()
                    Text(self.providerLine(p))
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    private func providerLine(_ p: SyncLLMProxyProviderSummary) -> String {
        var pieces = ["\(Self.formatInt(p.requests)) req", "\(Self.formatInt(p.tokens)) tok"]
        if let cost = p.approximateCostUSD, cost > 0 {
            pieces.append(Self.usd(cost))
        }
        return pieces.joined(separator: " · ")
    }

    private static func usd(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = value < 10 ? 2 : 0
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private static func formatInt(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1000 {
            return String(format: "%.1fk", Double(value) / 1000)
        }
        return "\(value)"
    }
}

#Preview {
    LLMProxyStatsCard(
        stats: SyncLLMProxyStats(
            providerCount: 4,
            credentialCount: 6,
            activeCredentialCount: 5,
            exhaustedCredentialCount: 1,
            totalRequests: 12300,
            totalTokens: 4_500_000,
            approximateCostUSD: 8.40,
            minimumRemainingPercent: 54,
            nextResetAt: Date().addingTimeInterval(9 * 3600),
            topProviders: [
                .init(name: "anthropic", requests: 5200, tokens: 2_100_000, approximateCostUSD: 4.10),
                .init(name: "openai", requests: 4100, tokens: 1_700_000, approximateCostUSD: 3.30),
                .init(name: "groq", requests: 3000, tokens: 700_000, approximateCostUSD: 1.00),
            ],
            updatedAt: Date()),
        tintColor: Color(red: 0.36, green: 0.48, blue: 0.60))
        .padding()
}
