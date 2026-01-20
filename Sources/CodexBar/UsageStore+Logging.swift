import CodexBarCore

extension UsageStore {
    func logStartupState() {
        let states = self.providerMetadata.keys
            .sorted { $0.rawValue < $1.rawValue }
            .map { provider -> String in
                let enabled = self.settings.isProviderEnabled(
                    provider: provider,
                    metadata: self.providerMetadata[provider]!)
                return "\(provider.rawValue)=\(enabled ? "1" : "0")"
            }
            .joined(separator: ",")
        let enabledProviders = self.providerMetadata.keys
            .filter { provider in
                self.settings.isProviderEnabled(
                    provider: provider,
                    metadata: self.providerMetadata[provider]!)
            }
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
            .joined(separator: ",")

        self.providerLogger.info(
            "Provider enablement at startup",
            metadata: [
                "states": states,
                "enabled": enabledProviders.isEmpty ? "none" : enabledProviders,
            ])
        self.providerLogger.info(
            "Provider mode snapshot",
            metadata: [
                "codexUsageSource": self.settings.codexUsageDataSource.rawValue,
                "claudeUsageSource": self.settings.claudeUsageDataSource.rawValue,
                "codexCookieSource": self.settings.codexCookieSource.rawValue,
                "claudeCookieSource": self.settings.claudeCookieSource.rawValue,
                "cursorCookieSource": self.settings.cursorCookieSource.rawValue,
                "opencodeCookieSource": self.settings.opencodeCookieSource.rawValue,
                "factoryCookieSource": self.settings.factoryCookieSource.rawValue,
                "minimaxCookieSource": self.settings.minimaxCookieSource.rawValue,
                "kimiCookieSource": self.settings.kimiCookieSource.rawValue,
                "augmentCookieSource": self.settings.augmentCookieSource.rawValue,
                "ampCookieSource": self.settings.ampCookieSource.rawValue,
                "openAIWebAccess": self.settings.openAIWebAccessEnabled ? "1" : "0",
                "claudeWebExtras": self.settings.claudeWebExtrasEnabled ? "1" : "0",
            ])
    }
}
