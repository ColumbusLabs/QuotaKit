import CodexBarCore

extension UsageStore {
    func performRuntimeAction(_ action: ProviderRuntimeAction, for provider: UsageProvider) async {
        guard let runtime = self.providerRuntimes[provider.instanceID] else { return }
        let context = ProviderRuntimeContext(provider: provider, settings: self.settings, store: self)
        await runtime.perform(action: action, context: context)
    }

    func updateProviderRuntimes() {
        for (instanceID, runtime) in self.providerRuntimes {
            guard let provider = instanceID.firstPartyProvider else { continue }
            let context = ProviderRuntimeContext(provider: provider, settings: self.settings, store: self)
            if self.isEnabled(provider) {
                runtime.start(context: context)
            } else {
                runtime.stop(context: context)
            }
            runtime.settingsDidChange(context: context)
        }
    }

    func refreshClaudeSwapAfterUserSettingsChange() {
        guard ProviderInteractionContext.current == .userInitiated else { return }
        // Provider-specific by design: this explicit Settings action reconciles Claude's optional swap runtime.
        guard let runtime = self.providerRuntimes[UsageProvider.claude.instanceID] as? ClaudeProviderRuntime else {
            return
        }
        runtime.refreshSwapConfigurationAfterUserChange(context: ProviderRuntimeContext(
            provider: .claude,
            settings: self.settings,
            store: self))
    }
}
