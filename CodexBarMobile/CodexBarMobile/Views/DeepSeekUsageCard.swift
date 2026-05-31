import CodexBarSync
import SwiftUI

/// DeepSeek web-session usage + cost card. Renders when
/// `ProviderUsageSnapshot.deepSeekUsage` is populated (upstream v0.30.0
/// #1166). Hidden for Mac versions older than 0.31.0 — the field stays nil
/// and the generic balance window keeps rendering.
///
/// Shows today / this-month tokens · cost · requests, an optional balance
/// breakdown, and a compact daily sparkline when history is present. The
/// account balance itself also still appears on the generic primary window
/// (a formatted string from the Mac side), so this card focuses on the new
/// usage/cost signal.
struct DeepSeekUsageCard: View {
    let usage: SyncDeepSeekUsage
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(String(localized: "deepseek_usage_title", defaultValue: "DeepSeek usage"))
                    .font(.headline)
                Spacer()
                if let model = usage.topModel, !model.isEmpty {
                    self.modelBadge(model)
                }
            }

            self.usageRow(
                label: String(localized: "deepseek_today_label", defaultValue: "Today"),
                tokens: usage.todayTokens,
                cost: usage.todayCost,
                requests: usage.todayRequests)

            self.usageRow(
                label: String(localized: "deepseek_month_label", defaultValue: "This month"),
                tokens: usage.monthTokens,
                cost: usage.monthCost,
                requests: usage.monthRequests)

            if let balance = self.balanceText {
                HStack {
                    Text(String(localized: "deepseek_balance_label", defaultValue: "Balance"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(balance)
                        .font(.caption.bold().monospacedDigit())
                }
            }

            if !usage.daily.isEmpty {
                self.sparkline
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deepseek-usage-card")
    }

    private func modelBadge(_ name: String) -> some View {
        Text(name)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(self.tintColor.opacity(0.16)))
            .foregroundStyle(self.tintColor)
    }

    private func usageRow(label: String, tokens: Int, cost: Double?, requests: Int) -> some View {
        let symbol = Self.currencySymbol(usage.currency)
        var parts = ["\(Self.formatTokens(tokens)) tok"]
        if let cost { parts.append("\(symbol)\(String(format: "%.2f", cost))") }
        parts.append("\(Self.formatInt(requests)) req")
        return HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(parts.joined(separator: " · "))
                .font(.subheadline.monospacedDigit())
        }
    }

    private var balanceText: String? {
        guard let total = usage.totalBalanceUSD else { return nil }
        let symbol = Self.currencySymbol(usage.currency)
        return "\(symbol)\(String(format: "%.2f", total))"
    }

    private var sparkline: some View {
        let values = usage.daily.map(\.totalTokens)
        let maxValue = max(values.max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 1)
                    .fill(self.tintColor.opacity(0.55))
                    .frame(height: max(2, CGFloat(value) / CGFloat(maxValue) * 28))
            }
        }
        .frame(height: 28)
        .accessibilityHidden(true)
    }

    private static func currencySymbol(_ currency: String) -> String {
        currency == "CNY" ? "¥" : "$"
    }

    private static func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", Double(value) / 1_000) }
        return "\(value)"
    }

    private static func formatInt(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

#Preview {
    DeepSeekUsageCard(
        usage: SyncDeepSeekUsage(
            todayTokens: 1_250_000, monthTokens: 28_400_000,
            todayCost: 0.42, monthCost: 9.85,
            todayRequests: 312, monthRequests: 7_240,
            topModel: "deepseek-chat", currency: "USD",
            totalBalanceUSD: 12.5, grantedBalanceUSD: 5.0, toppedUpBalanceUSD: 7.5,
            daily: (0..<14).map {
                SyncDeepSeekDaily(dayKey: "2025-11-\($0 + 1)", totalTokens: 1_000_000 + $0 * 90000, cost: 0.3, requestCount: 240)
            },
            updatedAt: Date()),
        tintColor: Color(red: 0.30, green: 0.42, blue: 1.0))
        .padding()
}
