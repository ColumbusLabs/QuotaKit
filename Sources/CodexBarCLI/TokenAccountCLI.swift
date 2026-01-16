import CodexBarCore
import Commander
import Foundation

struct TokenAccountCLISelection: Sendable {
    let label: String?
    let index: Int?
    let allAccounts: Bool

    var usesOverride: Bool {
        self.label != nil || self.index != nil || self.allAccounts
    }
}

enum TokenAccountCLIError: LocalizedError {
    case noAccounts(UsageProvider)
    case accountNotFound(UsageProvider, String)
    case indexOutOfRange(UsageProvider, Int, Int)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case let .noAccounts(provider):
            "No token accounts configured for \(provider.rawValue)."
        case let .accountNotFound(provider, label):
            "No token account labeled '\(label)' for \(provider.rawValue)."
        case let .indexOutOfRange(provider, index, count):
            "Token account index \(index) out of range for \(provider.rawValue) (1-\(count))."
        case let .loadFailed(details):
            "Failed to load token accounts: \(details)"
        }
    }
}

struct TokenAccountCLIContext {
    let selection: TokenAccountCLISelection
    let accountsByProvider: [UsageProvider: ProviderTokenAccountData]

    init(selection: TokenAccountCLISelection, verbose: Bool) throws {
        self.selection = selection
        do {
            self.accountsByProvider = try FileTokenAccountStore().loadAccounts()
        } catch {
            if selection.usesOverride {
                throw TokenAccountCLIError.loadFailed(error.localizedDescription)
            }
            self.accountsByProvider = [:]
            if verbose {
                CodexBarCLI.writeStderr("Warning: token account load failed: \(error.localizedDescription)\n")
            }
        }
    }

    func resolvedAccounts(for provider: UsageProvider) throws -> [ProviderTokenAccount] {
        guard TokenAccountSupportCatalog.support(for: provider) != nil else { return [] }
        guard let data = self.accountsByProvider[provider], !data.accounts.isEmpty else {
            if self.selection.usesOverride {
                throw TokenAccountCLIError.noAccounts(provider)
            }
            return []
        }

        if self.selection.allAccounts {
            return data.accounts
        }

        if let label = self.selection.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            let normalized = label.lowercased()
            if let match = data.accounts.first(where: { $0.label.lowercased() == normalized }) {
                return [match]
            }
            throw TokenAccountCLIError.accountNotFound(provider, label)
        }

        if let index = self.selection.index {
            guard index >= 0, index < data.accounts.count else {
                throw TokenAccountCLIError.indexOutOfRange(provider, index + 1, data.accounts.count)
            }
            return [data.accounts[index]]
        }

        let clamped = data.clampedActiveIndex()
        return [data.accounts[clamped]]
    }

    func settingsSnapshot(for provider: UsageProvider, account: ProviderTokenAccount?) -> ProviderSettingsSnapshot? {
        guard let account,
              let support = TokenAccountSupportCatalog.support(for: provider),
              case .cookieHeader = support.injection
        else {
            return nil
        }

        if provider == .claude, TokenAccountSupportCatalog.isClaudeOAuthToken(account.token) {
            return ProviderSettingsSnapshot(
                debugMenuEnabled: false,
                codex: nil,
                claude: ProviderSettingsSnapshot.ClaudeProviderSettings(
                    usageDataSource: .oauth,
                    webExtrasEnabled: false,
                    cookieSource: .off,
                    manualCookieHeader: nil),
                cursor: nil,
                opencode: nil,
                factory: nil,
                minimax: nil,
                zai: nil,
                copilot: nil,
                augment: nil)
        }

        let header = TokenAccountSupportCatalog.normalizedCookieHeader(account.token, support: support)
        guard !header.isEmpty else { return nil }

        switch provider {
        case .claude:
            return ProviderSettingsSnapshot(
                debugMenuEnabled: false,
                codex: nil,
                claude: ProviderSettingsSnapshot.ClaudeProviderSettings(
                    usageDataSource: .auto,
                    webExtrasEnabled: false,
                    cookieSource: .manual,
                    manualCookieHeader: header),
                cursor: nil,
                opencode: nil,
                factory: nil,
                minimax: nil,
                zai: nil,
                copilot: nil,
                augment: nil)
        case .cursor:
            return ProviderSettingsSnapshot(
                debugMenuEnabled: false,
                codex: nil,
                claude: nil,
                cursor: ProviderSettingsSnapshot.CursorProviderSettings(
                    cookieSource: .manual,
                    manualCookieHeader: header),
                opencode: nil,
                factory: nil,
                minimax: nil,
                zai: nil,
                copilot: nil,
                augment: nil)
        case .opencode:
            return ProviderSettingsSnapshot(
                debugMenuEnabled: false,
                codex: nil,
                claude: nil,
                cursor: nil,
                opencode: ProviderSettingsSnapshot.OpenCodeProviderSettings(
                    cookieSource: .manual,
                    manualCookieHeader: header,
                    workspaceID: nil),
                factory: nil,
                minimax: nil,
                zai: nil,
                copilot: nil,
                augment: nil)
        case .factory:
            return ProviderSettingsSnapshot(
                debugMenuEnabled: false,
                codex: nil,
                claude: nil,
                cursor: nil,
                opencode: nil,
                factory: ProviderSettingsSnapshot.FactoryProviderSettings(
                    cookieSource: .manual,
                    manualCookieHeader: header),
                minimax: nil,
                zai: nil,
                copilot: nil,
                augment: nil)
        case .minimax:
            return ProviderSettingsSnapshot(
                debugMenuEnabled: false,
                codex: nil,
                claude: nil,
                cursor: nil,
                opencode: nil,
                factory: nil,
                minimax: ProviderSettingsSnapshot.MiniMaxProviderSettings(
                    cookieSource: .manual,
                    manualCookieHeader: header),
                zai: nil,
                copilot: nil,
                augment: nil)
        case .augment:
            return ProviderSettingsSnapshot(
                debugMenuEnabled: false,
                codex: nil,
                claude: nil,
                cursor: nil,
                opencode: nil,
                factory: nil,
                minimax: nil,
                zai: nil,
                copilot: nil,
                augment: ProviderSettingsSnapshot.AugmentProviderSettings(
                    cookieSource: .manual,
                    manualCookieHeader: header))
        case .codex, .gemini, .antigravity, .zai, .copilot, .kiro, .vertexai:
            return nil
        }
    }

    func environment(
        base: [String: String],
        provider: UsageProvider,
        account: ProviderTokenAccount?) -> [String: String]
    {
        guard let account,
              let override = TokenAccountSupportCatalog.envOverride(for: provider, token: account.token)
        else {
            return base
        }
        var env = base
        for (key, value) in override {
            env[key] = value
        }
        return env
    }

    func applyAccountLabel(
        _ snapshot: UsageSnapshot,
        provider: UsageProvider,
        account: ProviderTokenAccount) -> UsageSnapshot
    {
        let label = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return snapshot }
        let existing = snapshot.identity(for: provider)
        let email = existing?.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEmail = (email?.isEmpty ?? true) ? label : email
        let identity = ProviderIdentitySnapshot(
            providerID: provider,
            accountEmail: resolvedEmail,
            accountOrganization: existing?.accountOrganization,
            loginMethod: existing?.loginMethod)
        return UsageSnapshot(
            primary: snapshot.primary,
            secondary: snapshot.secondary,
            tertiary: snapshot.tertiary,
            providerCost: snapshot.providerCost,
            zaiUsage: snapshot.zaiUsage,
            cursorRequests: snapshot.cursorRequests,
            updatedAt: snapshot.updatedAt,
            identity: identity)
    }

    func effectiveSourceMode(
        base: ProviderSourceMode,
        provider: UsageProvider,
        account: ProviderTokenAccount?) -> ProviderSourceMode
    {
        guard base == .auto,
              provider == .claude,
              let account,
              TokenAccountSupportCatalog.isClaudeOAuthToken(account.token)
        else {
            return base
        }
        return .oauth
    }
}
