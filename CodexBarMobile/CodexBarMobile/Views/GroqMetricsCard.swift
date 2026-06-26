import CodexBarSync
import SwiftUI

/// GroqCloud Enterprise Prometheus metrics card. Renders when
/// `ProviderUsageSnapshot.groqMetrics` is populated (Mac 0.27.0+
/// with an Enterprise key; nil for non-Enterprise keys — iOS falls
/// through to the generic rate-window list there).
///
/// Displays current per-minute rates (requests, tokens) plus the
/// cache-hit percentage when requests > 0.
struct GroqMetricsCard: View {
    let metrics: SyncGroqMetrics
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(String(localized: "groq_metrics_title", defaultValue: "GroqCloud rate"))
                    .font(.headline)
                Spacer()
                if let pct = metrics.cacheHitPercent {
                    Text(String(
                        format: String(localized: "groq_cache_hit_format", defaultValue: "%d%% cache"),
                        Int(pct.rounded())))
                        .font(.caption.bold().monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(self.tintColor.opacity(0.16)))
                        .foregroundStyle(self.tintColor)
                }
            }

            HStack {
                self.metricColumn(
                    label: String(localized: "groq_requests_per_min", defaultValue: "Req/min"),
                    value: Self.formatRate(self.metrics.requestsPerMinute))
                Divider().frame(height: 28)
                self.metricColumn(
                    label: String(localized: "groq_tokens_per_min", defaultValue: "Tok/min"),
                    value: Self.formatRate(self.metrics.tokensPerMinute))
                Divider().frame(height: 28)
                self.metricColumn(
                    label: String(localized: "groq_cache_per_min", defaultValue: "Cache/min"),
                    value: Self.formatRate(self.metrics.cacheHitsPerMinute))
            }
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("groq-metrics-card")
    }

    private func metricColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(self.tintColor)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func formatRate(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        if value >= 10 {
            return String(format: "%.0f", value)
        }
        if value > 0 {
            return String(format: "%.2f", value)
        }
        return "0"
    }
}

#Preview {
    GroqMetricsCard(
        metrics: SyncGroqMetrics(
            requestsPerMinute: 42,
            tokensPerMinute: 18500,
            cacheHitsPerMinute: 28,
            updatedAt: Date()),
        tintColor: Color(red: 0.96, green: 0.31, blue: 0.21))
        .padding()
}
