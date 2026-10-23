import Foundation

/// Shared identity matching for Copilot login flows in the app and CLI.
public enum CopilotAccountIdentity {
    public enum Match: Sendable {
        case resolved(ProviderTokenAccount?)
        case ambiguous
    }

    public static func resolveExistingAccount(
        existingAccounts: [ProviderTokenAccount],
        identity: CopilotUsageFetcher.GitHubUserIdentity?,
        label: String,
        issuer: String,
        enterpriseHost: String?,
        legacyIdentityResolver: @escaping @Sendable (ProviderTokenAccount, String?) async
            -> CopilotUsageFetcher.GitHubUserIdentity? = { account, enterpriseHost in
                try? await CopilotUsageFetcher.fetchGitHubIdentity(
                    token: account.token, enterpriseHost: enterpriseHost)
            }) async -> Match
    {
        guard let identity, !existingAccounts.isEmpty else { return .resolved(nil) }
        let stableIdentifier = self.externalIdentifier(for: identity, issuer: issuer)
        let login = self.normalizedGitHubLogin(identity.login)

        if let byID = existingAccounts.first(where: { account in
            self.normalizedExternalIdentifier(account.externalIdentifier) == stableIdentifier
        }) {
            return .resolved(byID)
        }

        if issuer != "api.github.com" {
            // A hostless account may belong to another Enterprise issuer. Its saved token must
            // prove both the user and issuer context before login can update that account.
            guard let enterpriseHost, !enterpriseHost.isEmpty else { return .ambiguous }
            var matched: ProviderTokenAccount?
            var unresolved = false
            for account in existingAccounts where account.externalIdentifier == nil {
                guard let resolved = await legacyIdentityResolver(account, enterpriseHost) else {
                    unresolved = true
                    continue
                }
                if resolved.id == identity.id {
                    guard matched == nil else { return .ambiguous }
                    matched = account
                }
            }
            return unresolved ? .ambiguous : .resolved(matched)
        }

        // Earlier public GitHub accounts stored the login instead of a stable user ID.
        if let byLegacyLogin = existingAccounts.first(where: { account in
            self.normalizedGitHubLogin(account.externalIdentifier) == login
        }) {
            return .resolved(byLegacyLogin)
        }

        var labelFallback: ProviderTokenAccount?
        for account in existingAccounts where account.externalIdentifier == nil {
            if let resolvedIdentity = await legacyIdentityResolver(account, nil) {
                if resolvedIdentity.id == identity.id {
                    return .resolved(account)
                }
            } else if labelFallback == nil,
                      self.displayLabelPrefix(account.label) == self.displayLabelPrefix(label)
            {
                labelFallback = account
            }
        }
        return .resolved(labelFallback)
    }

    public static func externalIdentifier(
        for identity: CopilotUsageFetcher.GitHubUserIdentity,
        issuer: String = "api.github.com") -> String
    {
        issuer == "api.github.com" ? "github:user:\(identity.id)" : "github:\(issuer):user:\(identity.id)"
    }

    private static func normalizedExternalIdentifier(_ identifier: String?) -> String? {
        let trimmed = identifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private static func normalizedGitHubLogin(_ login: String?) -> String? {
        guard let normalized = self.normalizedExternalIdentifier(login), !normalized.hasPrefix("github:")
        else { return nil }
        return normalized
    }

    private static func displayLabelPrefix(_ label: String) -> String {
        (label.components(separatedBy: " (").first ?? label)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
