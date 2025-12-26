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

    init(metadata: [UsageProvider: ProviderMetadata] = ProviderDefaults.metadata) {
        self.metadata = metadata
    }

    @MainActor
    func specs(
        settings: SettingsStore,
        metadata: [UsageProvider: ProviderMetadata],
        codexFetcher: UsageFetcher,
        claudeFetcher: any ClaudeUsageFetching) -> [UsageProvider: ProviderSpec]
    {
        let context = ProviderBuildContext(
            settings: settings,
            metadata: metadata,
            codexFetcher: codexFetcher,
            claudeFetcher: claudeFetcher)

        let implementationsByID: [UsageProvider: any ProviderImplementation] = Dictionary(
            uniqueKeysWithValues: ProviderCatalog.all.map { ($0.id, $0) })

        var specs: [UsageProvider: ProviderSpec] = [:]
        specs.reserveCapacity(UsageProvider.allCases.count)

        for provider in UsageProvider.allCases {
            guard let impl = implementationsByID[provider] else {
                fatalError("Missing ProviderImplementation for \(provider.rawValue)")
            }
            let meta = metadata[provider]!
            let spec = ProviderSpec(
                style: impl.style,
                isEnabled: { settings.isProviderEnabled(provider: provider, metadata: meta) },
                fetch: impl.makeFetch(context: context))
            specs[provider] = spec
        }

        return specs
    }

    private static let defaultMetadata: [UsageProvider: ProviderMetadata] = ProviderDefaults.metadata
}
