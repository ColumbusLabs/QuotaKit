import CodexBarSync
import SwiftUI

/// Dedicated Moonshot / Kimi API balance card. Moonshot is a balance-
/// based provider (top up, spend, no quota window).
///
/// Populated only when `ProviderUsageSnapshot.moonshotBalance` is
/// non-nil (Mac 0.26.2+ on the `moonshot` provider, which was added
/// by upstream PR #911 in v0.26.0).
struct MoonshotBalanceCard: View {
    let balance: SyncMoonshotBalance
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "moonshot_balance_title", defaultValue: "Account balance"))
                    .font(.headline)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(self.formattedAmount)
                    .font(.title2.monospacedDigit().bold())
                    .foregroundStyle(self.tintColor)
                if let currency = balance.balanceCurrency, !currency.isEmpty {
                    Text(currency)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let region = balance.region, !region.isEmpty {
                Text(String(format: String(localized: "moonshot_region_format", defaultValue: "Region: %@"), region))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("moonshot-balance-card")
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance.balanceAmount)) ?? "\(balance.balanceAmount)"
    }
}

#Preview {
    MoonshotBalanceCard(
        balance: SyncMoonshotBalance(
            balanceAmount: 58.40,
            balanceCurrency: "CNY",
            region: "cn-default",
            updatedAt: Date()),
        tintColor: Color(red: 0.24, green: 0.31, blue: 0.88))
        .padding()
}
