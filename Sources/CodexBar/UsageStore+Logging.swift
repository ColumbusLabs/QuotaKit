import CodexBarCore

extension UsageStore {
    func logStartupState() {
        let modeSnapshot: [String: String] = [
            "codexUsageSource": self.settings.codexUsageDataSource.rawValue,
            "claudeUsageSource": self.settings.claudeUsageDataSource.rawValue,
            "codexCookieSource": self.settings.codexCookieSource.rawValue,
            "claudeCookieSource": self.settings.claudeCookieSource.rawValue,
            "cursorCookieSource": self.settings.cursorCookieSource.rawValue,
            "openAIWebAccess": self.settings.openAIWebAccessEnabled ? "1" : "0",
            "openAIWebBatterySaver": self.settings.openAIWebBatterySaverEnabled ? "1" : "0",
            "backgroundWorkLowPowerMode": self.settings.backgroundWorkLowPowerModeEnabled ? "1" : "0",
            "effectiveOpenAIWebBatterySaver": self.settings.effectiveOpenAIWebBatterySaverEnabled ? "1" : "0",
            "claudeWebExtras": self.settings.claudeWebExtrasEnabled ? "1" : "0",
        ]
        ProviderLogging.logStartupState(
            logger: self.providerLogger,
            providers: Array(self.providerMetadata.keys),
            isEnabled: { provider in
                self.settings.isProviderEnabled(
                    provider: provider,
                    metadata: self.providerMetadata[provider]!)
            },
            modeSnapshot: modeSnapshot)
    }
}
