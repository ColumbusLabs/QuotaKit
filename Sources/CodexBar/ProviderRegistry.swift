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
        let codexMeta = metadata[.codex]!
        let claudeMeta = metadata[.claude]!
        let codexSpec = ProviderSpec(
            style: .codex,
            isEnabled: { settings.isProviderEnabled(provider: .codex, metadata: codexMeta) },
            fetch: { try await codexFetcher.loadLatestUsage() })

        let claudeSpec = ProviderSpec(
            style: .claude,
            isEnabled: { settings.isProviderEnabled(provider: .claude, metadata: claudeMeta) },
            fetch: {
                let usage = try await claudeFetcher.loadLatestUsage(model: "sonnet")
                return UsageSnapshot(
                    primary: usage.primary,
                    secondary: usage.secondary,
                    tertiary: usage.opus,
                    updatedAt: usage.updatedAt,
                    accountEmail: usage.accountEmail,
                    accountOrganization: usage.accountOrganization,
                    loginMethod: usage.loginMethod)
            })

        return [.codex: codexSpec, .claude: claudeSpec]
    }

    private static let defaultMetadata: [UsageProvider: ProviderMetadata] = ProviderDefaults.metadata
}
