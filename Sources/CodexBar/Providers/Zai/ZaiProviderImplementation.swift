import CodexBarCore
import Foundation

struct ZaiProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .zai
    let style: IconStyle = .zai

    func makeFetch(context: ProviderBuildContext) -> @Sendable () async throws -> UsageSnapshot {
        {
            guard let apiKey = ZaiSettingsReader.apiToken() else {
                throw ZaiSettingsError.missingToken
            }
            let usage = try await ZaiUsageFetcher.fetchUsage(apiKey: apiKey)
            return usage.toUsageSnapshot()
        }
    }
}
