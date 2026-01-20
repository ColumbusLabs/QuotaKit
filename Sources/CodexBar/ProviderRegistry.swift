import CodexBarCore
import Foundation

struct ProviderSpec {
    let style: IconStyle
    let isEnabled: @MainActor () -> Bool
    let fetch: () async -> ProviderFetchOutcome
}

struct ProviderRegistry {
    let metadata: [UsageProvider: ProviderMetadata]

    static let shared: ProviderRegistry = .init()

    init(metadata: [UsageProvider: ProviderMetadata] = ProviderDescriptorRegistry.metadata) {
        self.metadata = metadata
    }

    @MainActor
    func specs(
        settings: SettingsStore,
        metadata: [UsageProvider: ProviderMetadata],
        codexFetcher: UsageFetcher,
        claudeFetcher: any ClaudeUsageFetching,
        browserDetection: BrowserDetection) -> [UsageProvider: ProviderSpec]
    {
        var specs: [UsageProvider: ProviderSpec] = [:]
        specs.reserveCapacity(UsageProvider.allCases.count)

        for provider in UsageProvider.allCases {
            let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
            let meta = metadata[provider]!
            let spec = ProviderSpec(
                style: descriptor.branding.iconStyle,
                isEnabled: { settings.isProviderEnabled(provider: provider, metadata: meta) },
                fetch: {
                    let sourceMode = ProviderCatalog.implementation(for: provider)?
                        .sourceMode(context: ProviderSourceModeContext(provider: provider, settings: settings))
                        ?? .auto
                    let snapshot = await MainActor.run {
                        Self.makeSettingsSnapshot(settings: settings, tokenOverride: nil)
                    }
                    let env = await MainActor.run {
                        Self.makeEnvironment(
                            base: ProcessInfo.processInfo.environment,
                            provider: provider,
                            settings: settings,
                            tokenOverride: nil)
                    }
                    let verbose = settings.isVerboseLoggingEnabled
                    let context = ProviderFetchContext(
                        runtime: .app,
                        sourceMode: sourceMode,
                        includeCredits: false,
                        webTimeout: 60,
                        webDebugDumpHTML: false,
                        verbose: verbose,
                        env: env,
                        settings: snapshot,
                        fetcher: codexFetcher,
                        claudeFetcher: claudeFetcher,
                        browserDetection: browserDetection)
                    return await descriptor.fetchOutcome(context: context)
                })
            specs[provider] = spec
        }

        return specs
    }

    @MainActor
    static func makeSettingsSnapshot(
        settings: SettingsStore,
        tokenOverride: TokenAccountOverride?) -> ProviderSettingsSnapshot
    {
        settings.ensureTokenAccountsLoaded()

        return ProviderSettingsSnapshot.make(
            debugMenuEnabled: settings.debugMenuEnabled,
            debugKeepCLISessionsAlive: settings.debugKeepCLISessionsAlive,
            codex: settings.codexSettingsSnapshot(tokenOverride: tokenOverride),
            claude: settings.claudeSettingsSnapshot(tokenOverride: tokenOverride),
            cursor: settings.cursorSettingsSnapshot(tokenOverride: tokenOverride),
            opencode: settings.opencodeSettingsSnapshot(tokenOverride: tokenOverride),
            factory: settings.factorySettingsSnapshot(tokenOverride: tokenOverride),
            minimax: settings.minimaxSettingsSnapshot(tokenOverride: tokenOverride),
            zai: settings.zaiSettingsSnapshot(),
            copilot: settings.copilotSettingsSnapshot(),
            kimi: settings.kimiSettingsSnapshot(tokenOverride: tokenOverride),
            augment: settings.augmentSettingsSnapshot(tokenOverride: tokenOverride),
            amp: settings.ampSettingsSnapshot(tokenOverride: tokenOverride),
            jetbrains: settings.jetbrainsSettingsSnapshot())
    }

    @MainActor
    static func makeEnvironment(
        base: [String: String],
        provider: UsageProvider,
        settings: SettingsStore,
        tokenOverride: TokenAccountOverride?) -> [String: String]
    {
        let account = ProviderTokenAccountSelection.selectedAccount(
            provider: provider,
            settings: settings,
            override: tokenOverride)
        var env = base
        if let account, let override = TokenAccountSupportCatalog.envOverride(
            for: provider,
            token: account.token)
        {
            for (key, value) in override {
                env[key] = value
            }
        }
        return ProviderConfigEnvironment.applyAPIKeyOverride(
            base: env,
            provider: provider,
            config: settings.providerConfig(for: provider))
    }
}
