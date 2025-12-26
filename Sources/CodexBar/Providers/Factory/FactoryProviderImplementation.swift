import CodexBarCore
import Foundation

struct FactoryProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .factory
    let style: IconStyle = .factory

    func makeFetch(context: ProviderBuildContext) -> @Sendable () async throws -> UsageSnapshot {
        {
            let probe = FactoryStatusProbe()
            let snap = try await probe.fetch()
            return snap.toUsageSnapshot()
        }
    }
}
