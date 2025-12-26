import CodexBarCore
import Foundation

struct AntigravityProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .antigravity
    let style: IconStyle = .antigravity

    func makeFetch(context: ProviderBuildContext) -> @Sendable () async throws -> UsageSnapshot {
        {
            let probe = AntigravityStatusProbe()
            let snap = try await probe.fetch()
            return try snap.toUsageSnapshot()
        }
    }
}
