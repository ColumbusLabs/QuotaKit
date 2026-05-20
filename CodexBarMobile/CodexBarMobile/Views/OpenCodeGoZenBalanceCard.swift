import CodexBarSync
import SwiftUI

/// OpenCode Go Zen workspace balance — the pay-as-you-go USD balance
/// shown beneath the rolling / weekly / monthly rate windows on the
/// OpenCode Go detail page. Only rendered when
/// `ProviderUsageSnapshot.openCodeGoZenBalance` is non-nil (Mac
/// successfully scraped the workspace dashboard).
struct OpenCodeGoZenBalanceCard: View {
    let balance: SyncOpenCodeGoZenBalance
    let tintColor: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "opencodego_zen_balance_title", defaultValue: "Zen balance"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(Self.formatUSD(balance.balanceUSD))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(self.tintColor)
                if let workspace = balance.workspaceID, !workspace.isEmpty {
                    Text(String(format: String(localized: "opencodego_zen_workspace_format", defaultValue: "Workspace · %@"), workspace))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Image(systemName: "wallet.pass.fill")
                .font(.title2)
                .foregroundStyle(self.tintColor.opacity(0.7))
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("opencodego-zen-balance-card")
    }

    private static func formatUSD(_ value: Double) -> String { CostFormatting.usd(value) }
}

#Preview {
    OpenCodeGoZenBalanceCard(
        balance: SyncOpenCodeGoZenBalance(
            balanceUSD: 42.85,
            workspaceID: "ws-abc123def456",
            updatedAt: Date()),
        tintColor: .mint)
        .padding()
}
