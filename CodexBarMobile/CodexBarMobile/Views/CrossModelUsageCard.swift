import CodexBarSync
import SwiftUI

struct CrossModelUsageCard: View {
    let usage: SyncCrossModelUsage
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "CrossModel balance")
                    .font(.headline)
                Spacer(minLength: 8)
                Text(Self.currencyString(self.usage.balance, currency: self.usage.currency))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(self.tintColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if self.usage.uncollected != 0 {
                HStack {
                    Text(verbatim: "Uncollected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.currencyString(self.usage.uncollected, currency: self.usage.currency))
                        .font(.caption.bold().monospacedDigit())
                }
            }

            VStack(spacing: 8) {
                if let daily = self.usage.daily {
                    self.windowRow(label: "Today", window: daily)
                }
                if let weekly = self.usage.weekly {
                    self.windowRow(label: "Week", window: weekly)
                }
                if let monthly = self.usage.monthly {
                    self.windowRow(label: "Month", window: monthly)
                }
            }
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("crossmodel-usage-card")
    }

    private func windowRow(label: String, window: SyncCrossModelUsageWindow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.currencyString(window.cost, currency: self.usage.currency))
                    .font(.subheadline.monospacedDigit())
                Text(verbatim: "\(Self.formatInt(window.totalTokens)) tok / \(Self.formatInt(window.requestCount)) req")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private static func currencyString(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value))
            ?? "\(currency) \(String(format: "%.2f", value))"
    }

    private static func formatInt(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

#Preview {
    CrossModelUsageCard(
        usage: SyncCrossModelUsage(
            currency: "USD",
            balance: 8.06,
            uncollected: 1.24,
            daily: SyncCrossModelUsageWindow(
                cost: 0.42,
                promptTokens: 8100,
                completionTokens: 4367,
                totalTokens: 12467,
                requestCount: 42,
                successCount: 40),
            weekly: SyncCrossModelUsageWindow(
                cost: 2.14,
                promptTokens: 98000,
                completionTokens: 21000,
                totalTokens: 119_000,
                requestCount: 280,
                successCount: 276),
            monthly: SyncCrossModelUsageWindow(
                cost: 5.37,
                promptTokens: 410_000,
                completionTokens: 119_000,
                totalTokens: 529_000,
                requestCount: 3166,
                successCount: 3112),
            updatedAt: Date()),
        tintColor: .blue)
        .padding()
}
