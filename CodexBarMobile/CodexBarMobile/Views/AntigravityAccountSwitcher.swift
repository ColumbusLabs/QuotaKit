import CodexBarSync
import SwiftUI

/// Antigravity OAuth multi-account list. Read-only display on iOS
/// (the active account is selected on Mac side via the menu; iOS just
/// reflects the current state).
///
/// Populated only when `ProviderUsageSnapshot.antigravityAccounts`
/// is non-nil and has more than one entry. Mac SyncCoordinator
/// stubs this to `nil` for the initial 0.26.2 fold-in; the field is
/// reserved for the follow-up plumbing that reads
/// `SettingsStore.tokenAccountsData(for: .antigravity)`.
struct AntigravityAccountSwitcher: View {
    let accounts: SyncMultiAccountList
    let tintColor: Color

    private var sortedAccounts: [SyncMultiAccountEntry] {
        self.accounts.accounts.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return lhs.email < rhs.email
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "antigravity_accounts_title", defaultValue: "Linked Google accounts"))
                    .font(.headline)
                Spacer()
                Text("\(self.accounts.accounts.count)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(self.tintColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(self.tintColor.opacity(0.15)))
            }

            VStack(spacing: 6) {
                ForEach(self.sortedAccounts, id: \.email) { entry in
                    self.row(for: entry)
                }
            }
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("antigravity-account-switcher")
    }

    private func row(for entry: SyncMultiAccountEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(entry.isActive ? self.tintColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.email)
                    .font(.subheadline.monospacedDigit())
                    .lineLimit(1)
                    .truncationMode(.middle)
                if entry.isActive {
                    Text(String(localized: "antigravity_active_account", defaultValue: "Active on Mac"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let expiry = entry.expiresAt {
                    Text(self.expiryText(for: expiry))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(entry.isActive ? self.tintColor.opacity(0.08) : Color.secondary.opacity(0.05)))
    }

    private func expiryText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return String(
            format: String(localized: "antigravity_token_expires_format", defaultValue: "Token %@"),
            formatter.localizedString(for: date, relativeTo: Date()))
    }
}

#Preview {
    AntigravityAccountSwitcher(
        accounts: SyncMultiAccountList(
            accounts: [
                SyncMultiAccountEntry(
                    email: "primary@example.com",
                    isActive: true,
                    expiresAt: Date().addingTimeInterval(3600 * 12)),
                SyncMultiAccountEntry(
                    email: "team-alt@example.com",
                    isActive: false,
                    expiresAt: Date().addingTimeInterval(3600 * 36)),
            ],
            activeIndex: 0),
        tintColor: Color(red: 0.78, green: 0.21, blue: 0.54))
        .padding()
}
