import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct XAPIPluginTests {
    @Test(arguments: BundledPluginTestSupport.engines)
    func `console dollar balances include free credits without inventing a quota`(
        engine: ProviderPluginEngineKind) async throws
    {
        let fixture = Fixture()
        let usage = try await Self.fetch(engine, fixture)
        #expect(usage.primary == nil)
        #expect(usage.secondary == nil)
        #expect(usage.providerCost?.balance == 12.4)
        #expect(usage.providerCost?.used == 0)
        #expect(usage.providerCost?.limit == 0)
        #expect(usage.providerCost?.currencyCode == "USD")
        #expect(usage.details.flatMap(\.rows).first { $0.label == "Balance" }?.value == "$12.40")
        #expect(usage.details.flatMap(\.rows).first { $0.label == "Purchased credits" }?.value == "$10.40")
        #expect(usage.details.flatMap(\.rows).first { $0.label == "Free credits" }?.value == "$2.00")
        #expect(await fixture.paths == ["/api/me", "/api/accounts/fixture-account/credits"])
    }

    @Test(arguments: ["0", "-2.15", "0.001"], BundledPluginTestSupport.engines)
    func `zero negative and fractional dollar balances preserve their sign and units`(
        balance: String, engine: ProviderPluginEngineKind) async throws
    {
        let usage = try await Self.fetch(engine, Fixture(credits: "{\"credits\":{\"balance\":\(balance)}}"))
        #expect(usage.providerCost?.balance == Double(balance))
        if balance == "-2.15" {
            #expect(usage.details.flatMap(\.rows).first { $0.label == "Balance" }?.value == "-$2.15")
        }
    }

    @Test(arguments: [
        "{}", "null", "[]", "not-json",
        #"{"credits":{"balance":null}}"#,
        #"{"credits":{"balance":"12.4"}}"#,
        #"{"credits":{"balance":true}}"#,
        #"{"credits":{"balance":1e999}}"#,
        #"{"credits":{"balance":12.4},"freeCredits":{"balance":null}}"#,
    ], BundledPluginTestSupport.engines)
    func `malformed balances stay unknown`(credits: String, engine: ProviderPluginEngineKind) async {
        await #expect {
            try await Self.fetch(engine, Fixture(credits: credits))
        } throws: { ($0 as? ProviderFetchClassifiedError)?.kind == .parseFailure }
    }

    @Test(arguments: ["{}", #"{"account":{"id":"../other"}}"#], BundledPluginTestSupport.engines)
    func `missing or unsafe account IDs never reach a credits route`(
        identity: String, engine: ProviderPluginEngineKind) async
    {
        let fixture = Fixture(identity: identity)
        await #expect {
            try await Self.fetch(engine, fixture)
        } throws: { ($0 as? ProviderFetchClassifiedError)?.kind == .parseFailure }
        #expect(await fixture.paths == ["/api/me"])
    }

    @Test(arguments: [401, 403, 429, 503], BundledPluginTestSupport.engines)
    func `HTTP failures retain their classification`(status: Int, engine: ProviderPluginEngineKind) async {
        let expected: ProviderFetchClassifiedError.Kind = switch status {
        case 401: .authenticationExpired
        case 403: .permissionDenied
        case 429: .rateLimited
        default: .providerUnavailable
        }
        await #expect {
            try await Self.fetch(engine, Fixture(status: status))
        } throws: { ($0 as? ProviderFetchClassifiedError)?.kind == expected }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `integer account identifiers retain their exact value`(engine: ProviderPluginEngineKind) async throws {
        let fixture = Fixture(identity: #"{"account":{"id":42}}"#)
        _ = try await Self.fetch(engine, fixture)
        #expect(await fixture.paths == ["/api/me", "/api/accounts/42/credits"])
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `legacy authentication errors retain the expired session classification`(
        engine: ProviderPluginEngineKind) async
    {
        await #expect {
            try await Self.fetch(engine, Fixture(identity: #"{"errors":[{"code":215}]}"#, status: 400))
        } throws: { ($0 as? ProviderFetchClassifiedError)?.kind == .authenticationExpired }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `disabled cookies make no requests`(engine: ProviderPluginEngineKind) async throws {
        let fixture = Fixture()
        let runtime = try BundledPluginTestSupport.runtime("xapi", engine: engine, transport: fixture)
        await #expect {
            try await runtime.fetchUsage(cookieSource: .off)
        } throws: { ($0 as? ProviderFetchClassifiedError)?.kind == .missingCredential }
        #expect(await fixture.paths.isEmpty)
    }

    private static func fetch(_ engine: ProviderPluginEngineKind, _ fixture: Fixture) async throws -> UsageSnapshot {
        let runtime = try BundledPluginTestSupport.runtime("xapi", engine: engine, transport: fixture)
        return try await runtime.fetchUsage(cookieSessionResolver: { _, _ in await fixture.nextSession() })
    }

    private actor Fixture: ProviderHTTPTransport {
        let credits: String
        let identity: String
        let status: Int
        var paths: [String] = []
        var suppliedSession = false

        init(
            credits: String = #"{"credits":{"balance":10.4},"freeCredits":{"balance":2}}"#,
            identity: String = #"{"account":{"id":"fixture-account"}}"#,
            status: Int = 200)
        {
            self.credits = credits
            self.identity = identity
            self.status = status
        }

        func nextSession() -> ProviderPluginCookieSession? {
            guard !self.suppliedSession else { return nil }
            self.suppliedSession = true
            return .init(
                header: "auth_token=synthetic-session; ct0=synthetic-csrf",
                source: "Synthetic",
                origin: "https://console.x.com")
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let url = try #require(request.url)
            #expect(request.httpMethod == "GET")
            #expect(url.host == "console.x.com")
            #expect(request.value(forHTTPHeaderField: "X-CSRF-Token") == "synthetic-csrf")
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("auth_token=synthetic-session") == true)
            self.paths.append(url.path)
            let body: String
            switch url.path {
            case "/api/me": body = self.identity
            case "/api/accounts/fixture-account/credits", "/api/accounts/42/credits": body = self.credits
            default:
                Issue.record("Unexpected fixture request")
                throw URLError(.badURL)
            }
            return try (Data(body.utf8), #require(HTTPURLResponse(
                url: url,
                statusCode: self.status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])))
        }
    }
}
