import CodexBarCore
import Foundation

extension SettingsStore {
    func updateProviderConfig(provider: UsageProvider, mutate: (inout ProviderConfig) -> Void) {
        guard !self.configLoading else { return }
        var config = self.config
        if let index = config.providers.firstIndex(where: { $0.id == provider }) {
            var entry = config.providers[index]
            mutate(&entry)
            config.providers[index] = entry
        } else {
            var entry = ProviderConfig(id: provider)
            mutate(&entry)
            config.providers.append(entry)
        }
        self.config = config.normalized()
        self.schedulePersistConfig()
    }

    func updateProviderTokenAccounts(_ accounts: [UsageProvider: ProviderTokenAccountData]) {
        guard !self.configLoading else { return }
        var config = self.config
        var seen: Set<UsageProvider> = []
        for index in config.providers.indices {
            let provider = config.providers[index].id
            config.providers[index].tokenAccounts = accounts[provider]
            seen.insert(provider)
        }
        for (provider, data) in accounts where !seen.contains(provider) {
            config.providers.append(ProviderConfig(id: provider, tokenAccounts: data))
        }
        self.config = config.normalized()
        self.schedulePersistConfig()
    }

    func setProviderOrder(_ order: [UsageProvider]) {
        guard !self.configLoading else { return }
        let configsByID = Dictionary(uniqueKeysWithValues: self.config.providers.map { ($0.id, $0) })
        var seen: Set<UsageProvider> = []
        var ordered: [ProviderConfig] = []
        ordered.reserveCapacity(max(order.count, self.config.providers.count))

        for provider in order {
            guard !seen.contains(provider) else { continue }
            seen.insert(provider)
            ordered.append(configsByID[provider] ?? ProviderConfig(id: provider))
        }

        for provider in UsageProvider.allCases where !seen.contains(provider) {
            ordered.append(configsByID[provider] ?? ProviderConfig(id: provider))
        }

        var config = self.config
        config.providers = ordered
        self.config = config.normalized()
        self.schedulePersistConfig()
    }

    func normalizedConfigValue(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func schedulePersistConfig() {
        guard !self.configLoading else { return }
        self.configPersistTask?.cancel()
        if Self.isRunningTests {
            do {
                try self.configStore.save(self.config)
            } catch {
                CodexBarLog.logger("config-store").error("Failed to persist config: \(error)")
            }
            return
        }
        let store = self.configStore
        self.configPersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let snapshot = self.config
            let error: (any Error)? = await Task.detached(priority: .utility) {
                do {
                    try store.save(snapshot)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("config-store").error("Failed to persist config: \(error)")
            }
        }
    }
}
