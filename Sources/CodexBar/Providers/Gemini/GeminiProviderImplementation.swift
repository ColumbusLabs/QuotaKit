import CodexBarCore
import Foundation

struct GeminiProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .gemini
    let style: IconStyle = .gemini

    func makeFetch(context: ProviderBuildContext) -> @Sendable () async throws -> UsageSnapshot {
        {
            let probe = GeminiStatusProbe()
            let snap = try await probe.fetch()
            return snap.toUsageSnapshot()
        }
    }
}
