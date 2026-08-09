import CodexBarCore
import Foundation

struct TokenAccountOverride {
    let provider: UsageProvider
    let account: ProviderTokenAccount
}

enum ProviderTokenAccountSelection {
    @MainActor
    static func selectedAccount(
        provider: UsageProvider,
        settings: SettingsStore,
        override: TokenAccountOverride?) -> ProviderTokenAccount?
    {
        if let override, override.provider == provider {
            return override.account
        }
        return settings.effectiveSelectedTokenAccount(for: provider)
    }

    @MainActor
    static func shouldIncludeOptionalUsage(
        provider _: UsageProvider,
        settings: SettingsStore,
        override _: TokenAccountOverride?) -> Bool
    {
        settings.showOptionalCreditsAndExtraUsage
    }
}
