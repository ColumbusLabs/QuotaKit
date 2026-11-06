import Foundation
import Testing
@testable import CodexBarCLI

struct CLIServeCacheLifecycleTests {
    @Test
    func `refresh completions discard expired configuration variants without a cache lookup`() async {
        let cache = CLIServeResponseCache()
        let start = Date(timeIntervalSince1970: 1000)
        let policy = CLIServeResponseCache.CachePolicy(ttl: 60, staleTTL: 120)
        let response = CLILocalHTTPResponse(
            status: .ok,
            body: Data(#"[{"provider":"codex","value":1}]"#.utf8),
            usageCacheKeys: ["synthetic-account"])

        for generation in 0..<3 {
            let now = start.addingTimeInterval(Double(generation) * (CLIServeResponseCache.maximumStaleTTL + 1))
            for kind in ["usage", "cost", "dashboard"] {
                let result = await cache.completeFetch(
                    response,
                    for: "\(kind):default:config-\(generation)",
                    policy: policy,
                    now: now,
                    shouldCache: true)
                #expect(result.body == response.body)
            }
            #expect(await cache.cachedEntryCount() == 3)
            #expect(await cache.cachedStaleVariantCount() == 3)
        }
        await cache.operations.shutdown()
    }
}
