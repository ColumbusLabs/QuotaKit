import CodexBarCore
import Foundation

extension SettingsStore {
    var fireworksAPIToken: String {
        get { self.configSnapshot.providerConfig(for: .fireworks)?.sanitizedAPIKey ?? "" }
        set {
            self.updateProviderConfig(provider: .fireworks) { entry in
                entry.apiKey = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .fireworks, field: "apiKey", value: newValue)
        }
    }

    var fireworksAccountSlug: String {
        get { self.configSnapshot.providerConfig(for: .fireworks)?.sanitizedAccountSlug ?? "" }
        set {
            self.updateProviderConfig(provider: .fireworks) { entry in
                entry.accountSlug = self.normalizedConfigValue(newValue)
            }
        }
    }

    var hasFireworksCredentials: Bool {
        guard let config = self.configSnapshot.providerConfig(for: .fireworks) else { return false }
        return config.sanitizedAPIKey != nil
    }

    func persistDiscoveredFireworksAccountSlug(_ accountSlug: String?) {
        guard let accountSlug,
              let normalized = self.normalizedConfigValue(accountSlug),
              self.configSnapshot.providerConfig(for: .fireworks)?.sanitizedAccountSlug != normalized
        else { return }
        // Merge into SettingsStore's current revision so a fetch completion cannot overwrite another
        // pending settings mutation with a stale whole-file snapshot.
        self.updateProviderConfig(provider: .fireworks, affectsBackgroundWork: false) { entry in
            entry.accountSlug = normalized
        }
    }
}

extension SettingsStore {
    func fireworksSettingsSnapshot() -> ProviderSettingsSnapshot.FireworksProviderSettings {
        ProviderSettingsSnapshot.FireworksProviderSettings(accountSlug: self.fireworksAccountSlug)
    }
}
