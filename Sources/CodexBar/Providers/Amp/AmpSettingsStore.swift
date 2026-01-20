import CodexBarCore
import Foundation

extension SettingsStore {
    var ampCookieHeader: String {
        get { self.configSnapshot.providerConfig(for: .amp)?.sanitizedCookieHeader ?? "" }
        set {
            self.updateProviderConfig(provider: .amp) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .amp, field: "cookieHeader", value: newValue)
        }
    }

    var ampCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .amp, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .amp) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .amp, field: "cookieSource", value: newValue.rawValue)
        }
    }

    func ensureAmpCookieLoaded() {}
}
