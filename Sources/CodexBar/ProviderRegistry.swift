import CodexBarCore
import Foundation

struct ProviderSpec {
    let style: IconStyle
    let isEnabled: @MainActor () -> Bool
    let fetch: () async throws -> UsageSnapshot
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
        claudeFetcher: any ClaudeUsageFetching) -> [UsageProvider: ProviderSpec]
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
                    let snapshot = await MainActor.run {
                        ProviderSettingsSnapshot(
                            debugMenuEnabled: settings.debugMenuEnabled,
                            claudeUsageDataSource: settings.claudeUsageDataSource,
                            claudeWebExtrasEnabled: settings.claudeWebExtrasEnabled,
                            zaiAPIToken: settings.zaiAPIToken,
                            copilotAPIToken: settings.copilotAPIToken)
                    }
                    let context = ProviderFetchContext(
                        runtime: .app,
                        sourceMode: .auto,
                        includeCredits: false,
                        webTimeout: 60,
                        webDebugDumpHTML: false,
                        verbose: false,
                        env: ProcessInfo.processInfo.environment,
                        settings: snapshot,
                        fetcher: codexFetcher,
                        claudeFetcher: claudeFetcher)
                    let result = try await descriptor.fetch(context: context)
                    return result.usage
                })
            specs[provider] = spec
        }

        return specs
    }

    private static let defaultMetadata: [UsageProvider: ProviderMetadata] = ProviderDescriptorRegistry.metadata
}
