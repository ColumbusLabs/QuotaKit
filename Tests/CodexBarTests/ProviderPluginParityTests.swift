#if canImport(JavaScriptCore)
import Foundation
import Testing
@testable import CodexBarCore

struct ProviderPluginParityTests {
    @Test
    func `prototype flag prepends JS without changing the default pipeline`() async {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .synthetic)
        let defaultStrategies = await descriptor.fetchPlan.pipeline.resolveStrategies(
            Self.context(environment: ["SYNTHETIC_API_KEY": "fixture-key"]))
        let prototypeStrategies = await descriptor.fetchPlan.pipeline.resolveStrategies(
            Self.context(environment: [
                "SYNTHETIC_API_KEY": "fixture-key",
                ProviderPluginPrototype.environmentKey: "1",
            ]))

        #expect(defaultStrategies.map(\.id) == ["synthetic.api"])
        #expect(prototypeStrategies.map(\.id) == ["synthetic.js", "synthetic.api"])
        #expect(prototypeStrategies[0].shouldFallback(
            on: ProviderPluginError.script("fixture"),
            context: Self.context(environment: [:])) == false)
    }

    @Test
    func `Synthetic fixture has Swift and JS snapshot parity`() async throws {
        let body = """
        {
          "plan": "Starter",
          "weeklyTokenLimit": {
            "nextRegenAt": "2026-04-17T05:19:30.000Z",
            "percentRemaining": 98.05884722222223,
            "maxCredits": "$36.00",
            "remainingCredits": "$35.30",
            "nextRegenCredits": "$0.72"
          },
          "rollingFiveHourLimit": {
            "nextTickAt": "2026-04-17T03:44:11.000Z",
            "tickPercent": 0.05,
            "remaining": 600,
            "max": 750,
            "limited": false
          },
          "search": {
            "hourly": {
              "limit": 250,
              "requests": 2,
              "renewsAt": "2026-04-17T04:30:01.494Z"
            }
          }
        }
        """
        let transport = Self.transport(body: body)
        let now = Date(timeIntervalSince1970: 1_775_000_000)

        let swift = try await SyntheticUsageFetcher.fetchUsage(
            apiKey: "fixture-key",
            now: now,
            transport: transport).toUsageSnapshot()
        let runtime = try ProviderPluginRuntime(bundledPlugin: "synthetic", transport: transport)
        let script = try await runtime.fetchUsage(secrets: ["SYNTHETIC_API_KEY": "fixture-key"], now: now)

        Self.expectCoreParity(swift, script)
    }

    @Test
    func `Venice fixture has Swift and JS snapshot parity`() async throws {
        let body = """
        {
          "canConsume": true,
          "consumptionCurrency": "BUNDLED_CREDITS",
          "balances": { "diem": "50.0", "usd": "10.0" },
          "diemEpochAllocation": "100.0"
        }
        """
        let transport = Self.transport(body: body)
        let now = Date(timeIntervalSince1970: 1_775_000_000)

        let swift = try await VeniceUsageFetcher.fetchUsage(
            apiKey: "fixture-key",
            transport: transport).toUsageSnapshot()
        let runtime = try ProviderPluginRuntime(bundledPlugin: "venice", transport: transport)
        let script = try await runtime.fetchUsage(secrets: ["VENICE_API_KEY": "fixture-key"], now: now)

        Self.expectCoreParity(swift, script)
    }

    @Test
    func `Crof fixture has Swift and JS snapshot parity`() async throws {
        let body = #"{"credits":9.9999,"requests_plan":1000,"usable_requests":998}"#
        let transport = Self.transport(body: body)
        let now = Date()

        let swift = try await CrofUsageFetcher.fetchUsage(
            apiKey: "fixture-key",
            session: transport).toUsageSnapshot()
        let runtime = try ProviderPluginRuntime(bundledPlugin: "crof", transport: transport)
        let script = try await runtime.fetchUsage(secrets: ["CROF_API_KEY": "fixture-key"], now: now)

        Self.expectCoreParity(swift, script)
    }

    private static func transport(body: String) -> ProviderHTTPTransportHandler {
        ProviderHTTPTransportHandler { request in
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]))
            return (Data(body.utf8), response)
        }
    }

    private static func context(environment: [String: String]) -> ProviderFetchContext {
        ProviderFetchContext(
            runtime: .app,
            sourceMode: .api,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: nil,
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: ProviderPluginParityClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }

    private static func expectCoreParity(_ swift: UsageSnapshot, _ script: UsageSnapshot) {
        #expect(swift.primary == script.primary)
        #expect(swift.secondary == script.secondary)
        #expect(swift.tertiary == script.tertiary)
        #expect(swift.extraRateWindows == script.extraRateWindows)
        #expect(swift.subscriptionRenewsAt == script.subscriptionRenewsAt)
        #expect(swift.subscriptionExpiresAt == script.subscriptionExpiresAt)
        #expect(swift.providerCost?.used == script.providerCost?.used)
        #expect(swift.providerCost?.limit == script.providerCost?.limit)
        #expect(swift.providerCost?.currencyCode == script.providerCost?.currencyCode)
        #expect(swift.providerCost?.period == script.providerCost?.period)
        #expect(swift.providerCost?.resetsAt == script.providerCost?.resetsAt)
        #expect(swift.providerCost?.nextRegenAmount == script.providerCost?.nextRegenAmount)
        #expect(swift.identity?.providerID == script.identity?.providerID)
        #expect(swift.identity?.accountEmail == script.identity?.accountEmail)
        #expect(swift.identity?.accountOrganization == script.identity?.accountOrganization)
        #expect(swift.identity?.loginMethod == script.identity?.loginMethod)
        #expect(swift.identity?.accountID == script.identity?.accountID)
    }
}

private struct ProviderPluginParityClaudeFetcher: ClaudeUsageFetching {
    func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
        throw ProviderPluginError.script("unused")
    }

    func debugRawProbe(model _: String) async -> String {
        "unused"
    }

    func detectVersion() -> String? {
        nil
    }
}
#endif
