import CodexBarSync
import SwiftUI

struct HyperBalanceCard: View {
    let balance: SyncHyperBalance
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Hypercredits")
                .font(.headline)

            Text("\(Self.formattedAmount(self.balance.balance)) HC")
                .font(.title2.monospacedDigit().bold())
                .foregroundStyle(self.tintColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hyper-balance-card")
    }

    static func formattedAmount(_ amount: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

#Preview {
    HyperBalanceCard(
        balance: SyncHyperBalance(balance: 42.5, updatedAt: Date()),
        tintColor: Color(red: 1, green: 96 / 255, blue: 1))
        .padding()
}
