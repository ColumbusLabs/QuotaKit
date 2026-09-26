import CodexBarCore
import Foundation

extension UsageStore {
    func credentialAccount(provider: UsageProvider, context: ProviderRefreshOutcomeContext) -> String {
        if let account = Self.warningTokenAccountDiscriminator(context.tokenAccount) { return account }
        // Provider-specific by design: ambient CLI accounts use the refresh's already-validated ownership evidence.
        if provider == .codex { return context.codexSessionQuotaOwnerKey?.rawValue ?? "default" }
        if provider == .claude {
            let identity: String? = if case let .stable(identity) = context.claudeOAuthActiveAccountObservation {
                identity
            } else { nil }
            return self.claudeCredentialNotificationScope(
                identity: identity,
                fingerprint: context.claudeCredentialFingerprint)
        }
        return "default"
    }
}
