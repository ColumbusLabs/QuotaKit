import CodexBarCore
import Foundation

struct CodexProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .codex
    let style: IconStyle = .codex

    func makeFetch(context: ProviderBuildContext) -> @Sendable () async throws -> UsageSnapshot {
        { try await context.codexFetcher.loadLatestUsage() }
    }

    @MainActor
    func settingsToggles(context: ProviderSettingsContext) -> [ProviderSettingsToggleDescriptor] {
        []
    }
}
