import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct VercelBudgetStrategySelectionTests {
    @Test
    func `configured token selects the budget script without a gateway key`() async throws {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .vercel)
        let config = ProviderConfig(
            id: UsageProvider.vercel.instanceID,
            workspaceID: "team_fixture",
            pluginSecrets: ["VERCEL_ACCESS_TOKEN": "fixture-token"])
        let environment = try #require(descriptor.credentials).applyConfig(base: [:], config: config)
        #expect(environment["VERCEL_ACCESS_TOKEN"] == "fixture-token")
        #expect(environment["VERCEL_TEAM_ID"] == "team_fixture")
        #expect(environment["AI_GATEWAY_API_KEY"] == nil)

        let tokenOnly = ProviderCutoverTestSupport.context(environment: environment)
        let strategies = await descriptor.fetchPlan.pipeline.resolveStrategies(tokenOnly)
        #expect(strategies.map(\.id) == ["vercel-budget.js"])
        let keyOnly = ProviderCutoverTestSupport.context(environment: ["AI_GATEWAY_API_KEY": "fixture-gateway"])
        #expect(await descriptor.fetchPlan.pipeline.resolveStrategies(keyOnly).map(\.id) == ["vercel.js"])

        let strategy = VercelProviderDescriptor.budgetStrategy(transport: Self.transport())
        #expect(await strategy.isAvailable(tokenOnly))
        let result = try await strategy.fetch(tokenOnly)
        #expect(result.strategyID == "vercel-budget.js")
        #expect(result.usage.identity?.providerID == .vercel)
        #expect(result.usage.primary?.usedPercent == 25)
    }

    private static func transport() -> ProviderHTTPTransportHandler {
        ProviderHTTPTransportHandler { request in
            let url = try #require(request.url)
            #expect(url.host == "api.vercel.com")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            let body: String
            switch url.path {
            case "/v2/user":
                body = #"{"user":{"id":"fixtureUser","email":"fixture@example.com"}}"#
            case "/ai-gateway/budgets/list":
                body = #"{"budgets":[{"scopeType":"user","scopeId":"usr_fixtureUser","currentSpend":30,"limitAmount":120,"refreshPeriod":"monthly","active":true,"archived":false}]}"#
            default:
                Issue.record("Unexpected Vercel request path: \(url.path)")
                body = "{}"
            }
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]))
            return (Data(body.utf8), response)
        }
    }
}
