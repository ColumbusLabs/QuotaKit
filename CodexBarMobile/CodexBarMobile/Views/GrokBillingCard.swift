import CodexBarSync
import SwiftUI

/// Dedicated Grok (xAI) monthly billing card. Renders alongside the
/// generic rate-window list when `ProviderUsageSnapshot.grokBilling`
/// is populated (Mac 0.27.0+ with grok CLI or grok.com web billing).
///
/// Shows monthly spend / limit (when CLI billing is the source) plus
/// the percent badge + reset date. Plan tier is reserved for a future
/// upstream addition.
struct GrokBillingCard: View {
    let billing: SyncGrokBilling
    let tintColor: Color

    private var spendText: String? {
        guard let spend = billing.monthlySpendUSD else { return nil }
        if let limit = billing.monthlyLimitUSD, limit > 0 {
            return "\(Self.usd(spend)) / \(Self.usd(limit))"
        }
        return Self.usd(spend)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(String(localized: "grok_billing_title", defaultValue: "Grok billing"))
                    .font(.headline)
                if let tier = billing.planTier, !tier.isEmpty {
                    Text(tier)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(self.tintColor.opacity(0.16)))
                        .foregroundStyle(self.tintColor)
                }
                Spacer()
                if let percent = billing.monthlyUsedPercent {
                    Text("\(Int(percent.rounded()))%")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(self.tintColor)
                }
            }

            if let spendText {
                HStack {
                    Text(String(localized: "grok_billing_spend_label", defaultValue: "Spend this period"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(spendText)
                        .font(.subheadline.monospacedDigit())
                }
            }

            if let percent = billing.monthlyUsedPercent {
                ProgressView(value: max(0, min(1, percent / 100)))
                    .progressViewStyle(.linear)
                    .tint(self.tintColor)
            }

            if let resetAt = billing.billingPeriodEndDate {
                HStack {
                    Text(String(localized: "grok_billing_reset_label", defaultValue: "Resets"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(resetAt, style: .date)
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grok-billing-card")
    }

    private static func usd(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = value < 10 ? 2 : 0
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

#Preview {
    GrokBillingCard(
        billing: SyncGrokBilling(
            monthlyUsedPercent: 17,
            monthlySpendUSD: 4.20,
            monthlyLimitUSD: 25,
            billingPeriodEndDate: Date().addingTimeInterval(22 * 86400),
            planTier: "Pro",
            updatedAt: Date()),
        tintColor: Color(red: 0.10, green: 0.10, blue: 0.12))
        .padding()
}
