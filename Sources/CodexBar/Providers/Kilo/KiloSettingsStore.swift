import CodexBarCore
import Foundation

extension SettingsStore {
    var kiloAPIToken: String {
        get { self.configSnapshot.providerConfig(for: .kilo)?.sanitizedAPIKey ?? "" }
        set {
            self.updateProviderConfig(provider: .kilo) { entry in
                entry.apiKey = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .kilo, field: "apiKey", value: newValue)
        }
    }
}
