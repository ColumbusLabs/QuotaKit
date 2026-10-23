import Commander
import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

/// `quotakit serve` defaults dashboard identity to redacted and only exposes full
/// account identities after an explicit command-line opt-in.
struct CLIServeDashboardIdentityTests {
    @Test
    func `an absent identity flag decodes to redacted`() {
        #expect(CodexBarCLI.decodeDashboardIdentityMode(from: ParsedValues(
            positional: [],
            options: [:],
            flags: [])) == .redacted)
    }

    @Test
    func `dashboard operation key separates identity modes`() throws {
        let redacted = try CodexBarCLI.serveDashboardOperationKey(
            identityMode: .redacted,
            usageBarsShowUsed: false,
            provider: nil)
        let full = try CodexBarCLI.serveDashboardOperationKey(
            identityMode: .full,
            usageBarsShowUsed: false,
            provider: nil)

        #expect(redacted != full)
    }

    @Test
    func `dashboard operation key separates usage bars fill preferences`() throws {
        let used = try CodexBarCLI.serveDashboardOperationKey(
            identityMode: .full,
            usageBarsShowUsed: true,
            provider: nil)
        let remaining = try CodexBarCLI.serveDashboardOperationKey(
            identityMode: .full,
            usageBarsShowUsed: false,
            provider: nil)

        #expect(used != remaining)
    }

    @Test
    func `returning to an expired dashboard identity rebuilds before responding`() async throws {
        let store = testConfigStore(suiteName: "CLIServeDashboardIdentityTests-\(UUID().uuidString)")
        defer { try? store.deleteIfPresent() }
        let config = CodexBarConfig(providers: UsageProvider.allCases.map {
            ProviderConfig(id: $0.instanceID, enabled: false)
        })
        try store.save(config)
        let cache = CLIServeResponseCache()
        let showUsed = CodexBarCLI.usageBarsShowUsedFromDefaults()
        let token = try CodexBarCLI.serveConfigCacheToken(for: config)
        for (mode, interval, body) in [
            (DashboardIdentityMode.redacted, 0.001, "expired-redacted-snapshot"),
            (DashboardIdentityMode.full, 60, "fresh-full-snapshot"),
        ] {
            let key = try CodexBarCLI.serveDashboardOperationKey(
                identityMode: mode, usageBarsShowUsed: showUsed, provider: nil)
            _ = await CodexBarCLI.cachedServeResponse(
                key: key, cache: cache, refreshInterval: interval, configFingerprint: token)
            {
                CLILocalHTTPResponse(status: .ok, body: Data(body.utf8))
            }
        }
        try await Task.sleep(nanoseconds: 25_000_000)
        let runtime = ServeRuntime(
            configStore: store,
            cache: cache,
            providerOperations: CLIServeOperationCoordinator(),
            costOperations: CLIServeOperationCoordinator(),
            refreshInterval: 60,
            requestTimeout: 5,
            healthVersion: "0.0.0-test",
            dashboardAuth: CLIServeDashboardAuth(bearer: "fixture-token"),
            dashboardIdentityMode: .redacted,
            dashboardIdentityWasExplicit: true,
            bindHost: "127.0.0.1")
        let response = await CodexBarCLI.handleServeRequest(CLILocalHTTPRequest(
            method: "GET",
            target: "/dashboard/v1/snapshot",
            host: "localhost",
            path: "/dashboard/v1/snapshot",
            queryItems: [:],
            authorization: "Bearer fixture-token"), runtime: runtime)

        #expect(response.status == .ok)
        #expect(response.body != Data("expired-redacted-snapshot".utf8))
        await cache.operations.shutdown()
        await runtime.providerOperations.shutdown()
        await runtime.costOperations.shutdown()
    }

    @Test
    func `warm dashboard responses retain the requested fill mode through toggles`() async throws {
        let cache = CLIServeResponseCache()
        let counter = DashboardFillBuildCounter()
        for showUsed in [false, true, false, true] {
            let key = try CodexBarCLI.serveDashboardOperationKey(
                identityMode: .redacted,
                usageBarsShowUsed: showUsed,
                provider: "codex")
            let response = await CodexBarCLI.cachedServeResponse(
                key: key, cache: cache, refreshInterval: 60, configFingerprint: "synthetic-config")
            {
                let build = await counter.increment()
                return CLILocalHTTPResponse(
                    status: .ok,
                    body: Data("{\"usageBarsShowUsed\":\(showUsed),\"build\":\(build)}".utf8))
            }
            let payload = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
            #expect(payload["usageBarsShowUsed"] as? Bool == showUsed)
        }
        #expect(await counter.count == 2)
    }
}

private actor DashboardFillBuildCounter {
    private(set) var count = 0

    func increment() -> Int {
        self.count += 1
        return self.count
    }
}
