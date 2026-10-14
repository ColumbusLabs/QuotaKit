import CodexBarCore
import Foundation

extension SettingsStore {
    var commandcodeUsageDataSource: ProviderSourceMode {
        get { self.configSnapshot.providerConfig(for: .commandcode)?.source ?? .auto }
        set {
            self.updateProviderConfig(provider: .commandcode) { entry in
                entry.source = newValue == .auto ? nil : newValue
            }
            self.logProviderModeChange(provider: .commandcode, field: "source", value: newValue.rawValue)
        }
    }

    var commandcodeAPIKey: String {
        get { self[providerConfig: .commandcode, field: .apiKey] }
        set { self[providerConfig: .commandcode, field: .apiKey] = newValue }
    }

    var commandcodeCookieHeader: String {
        get { self.configSnapshot.providerConfig(for: .commandcode)?.sanitizedCookieHeader ?? "" }
        set {
            self.updateProviderConfig(provider: .commandcode) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .commandcode, field: "cookieHeader", value: newValue)
        }
    }

    var commandcodeCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .commandcode, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .commandcode) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .commandcode, field: "cookieSource", value: newValue.rawValue)
        }
    }

    func ensureCommandCodeCookieLoaded() {}
}

extension SettingsStore {
    func commandcodeSettingsSnapshot(tokenOverride: TokenAccountOverride?) -> ProviderSettingsSnapshot
    .CommandCodeProviderSettings {
        self.resolvedCookieSettings(
            provider: .commandcode,
            configuredSource: self.commandcodeCookieSource,
            configuredHeader: self.commandcodeCookieHeader,
            tokenOverride: tokenOverride)
    }
}
