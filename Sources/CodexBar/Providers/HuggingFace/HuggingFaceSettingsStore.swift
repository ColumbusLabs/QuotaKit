import CodexBarCore
import Foundation

extension SettingsStore {
    var huggingFaceCookieHeader: String {
        get { self.configSnapshot.providerConfig(for: .huggingface)?.sanitizedCookieHeader ?? "" }
        set {
            self.updateProviderConfig(provider: .huggingface) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .huggingface, field: "cookieHeader", value: newValue)
        }
    }

    var huggingFaceCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .huggingface, fallback: .off) }
        set {
            self.updateProviderConfig(provider: .huggingface) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .huggingface, field: "cookieSource", value: newValue.rawValue)
        }
    }

    func huggingFaceSettingsSnapshot(tokenOverride: TokenAccountOverride?) -> HuggingFaceProviderSettings {
        self.resolvedCookieSettings(
            provider: .huggingface,
            configuredSource: self.huggingFaceCookieSource,
            configuredHeader: self.huggingFaceCookieHeader,
            tokenOverride: tokenOverride)
    }
}
