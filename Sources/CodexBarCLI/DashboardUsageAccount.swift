import CodexBarCore
import Crypto
import Foundation

/// Account presentation metadata follows usage, including failed fetches, without changing `/usage` JSON.
/// Public IDs never derive from cache keys, email addresses, or credential fingerprints.
struct DashboardUsageAccount: Sendable {
    let id: String
    let label: String
    let active: Bool

    static func singleAccount(for provider: UsageProvider) -> Self {
        Self(id: "default:\(provider.rawValue)", label: "Account", active: true)
    }

    static func token(_ account: ProviderTokenAccount, active: Bool) -> Self {
        Self(id: "token:\(account.id.uuidString.lowercased())", label: account.label, active: active)
    }

    static func codex(_ account: CodexVisibleAccount) -> Self {
        let source: String = switch account.selectionSource {
        case .liveSystem:
            account.storedAccountID.map { "managed:\($0.uuidString.lowercased())" }
                ?? "system:\(account.workspaceAccountID ?? "default")"
        case let .managedAccount(id):
            "managed:\(id.uuidString.lowercased())"
        case let .profileHome(path):
            "profile:\(CodexHomeScope.normalizedHomePath(path) ?? path)"
        }
        let digest = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        let id: String = if case .managedAccount = account.selectionSource,
                             let storedID = account.storedAccountID
        {
            "codex-managed:\(storedID.uuidString.lowercased())"
        } else if case .liveSystem = account.selectionSource,
                  let storedID = account.storedAccountID
        {
            "codex-managed:\(storedID.uuidString.lowercased())"
        } else {
            "codex:\(digest)"
        }
        return Self(id: id, label: account.displayName, active: account.isActive)
    }
}

extension UsageCommandOutput {
    mutating func attachDashboardAccount(_ account: DashboardUsageAccount?, inventoryIncomplete: Bool = false) {
        for index in self.payload.indices {
            if let account { self.payload[index].dashboardAccount = account }
            self.payload[index].dashboardAccountsIncomplete = self.payload[index].dashboardAccountsIncomplete
                || inventoryIncomplete
        }
    }
}
