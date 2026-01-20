import CodexBarCore
import Foundation

extension SettingsStore {
    var kimiManualCookieHeader: String {
        get { self.configSnapshot.providerConfig(for: .kimi)?.sanitizedCookieHeader ?? "" }
        set {
            self.updateProviderConfig(provider: .kimi) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .kimi, field: "cookieHeader", value: newValue)
        }
    }

    var kimiCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .kimi, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .kimi) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .kimi, field: "cookieSource", value: newValue.rawValue)
        }
    }

    func ensureKimiAuthTokenLoaded() {}
}
