import CodexBarCore
import Foundation

extension SettingsStore {
    var openRouterAPIToken: String {
        get { self.configSnapshot.providerConfig(for: .openrouter)?.sanitizedAPIKey ?? "" }
        set {
            self.updateProviderConfig(provider: .openrouter) { entry in
                entry.apiKey = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .openrouter, field: "apiKey", value: newValue)
        }
    }

    var openRouterAPIURL: String {
        get { self.configSnapshot.providerConfig(for: .openrouter)?.sanitizedEnterpriseHost ?? "" }
        set {
            self.updateProviderConfig(provider: .openrouter) { entry in
                entry.enterpriseHost = self.normalizedConfigValue(newValue)
            }
        }
    }
}
