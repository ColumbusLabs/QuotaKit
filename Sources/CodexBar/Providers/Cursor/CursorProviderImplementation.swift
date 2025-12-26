import CodexBarCore
import Foundation

struct CursorProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .cursor
    let style: IconStyle = .cursor

    func makeFetch(context: ProviderBuildContext) -> @Sendable () async throws -> UsageSnapshot {
        {
            let probe = CursorStatusProbe()
            let snap = try await probe.fetch()
            return snap.toUsageSnapshot()
        }
    }
}
