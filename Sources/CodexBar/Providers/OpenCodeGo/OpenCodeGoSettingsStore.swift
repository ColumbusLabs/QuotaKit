import CodexBarCore
import Foundation

extension SettingsStore {
    var opencodegoWorkspaceID: String {
        get { self.configSnapshot.providerConfig(for: .opencodego)?.workspaceID ?? "" }
        set { self[providerConfig: .opencodego, field: .workspace] = newValue }
    }

    var opencodegoCookieHeader: String {
        get { self.configSnapshot.providerConfig(for: .opencodego)?.sanitizedCookieHeader ?? "" }
        set {
            self.updateProviderConfig(provider: .opencodego) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .opencodego, field: "cookieHeader", value: newValue)
        }
    }

    var opencodegoCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .opencodego, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .opencodego) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .opencodego, field: "cookieSource", value: newValue.rawValue)
        }
    }

    var opencodegoDashboardURL: URL {
        OpenCodeGoUsageFetcher.dashboardURL(workspaceID: self.opencodegoWorkspaceID)
    }

    func ensureOpenCodeGoCookieLoaded() {}
}

extension SettingsStore {
    func opencodegoSettingsSnapshot(tokenOverride: TokenAccountOverride?) -> ProviderSettingsSnapshot
        .OpenCodeProviderSettings
    {
        let cookieSettings: ProviderSettingsSnapshot.CookieProviderSettings = self.resolvedCookieSettings(
            provider: .opencodego,
            configuredSource: self.opencodegoCookieSource,
            configuredHeader: self.opencodegoCookieHeader,
            tokenOverride: tokenOverride)
        return ProviderSettingsSnapshot.OpenCodeProviderSettings(
            cookieSource: cookieSettings.cookieSource,
            manualCookieHeader: cookieSettings.manualCookieHeader,
            workspaceID: self.providerConfig(for: .opencodego)?.sanitizedWorkspaceID)
    }
}
