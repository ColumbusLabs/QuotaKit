import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct ReplicatePluginTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: ReplicatePluginTestSupport.engines)
    func `user billing response reports exact spend without quota`(engine: ProviderPluginEngineKind) async throws {
        let calls = ReplicateRequestLog()
        let snapshot = try await Self.fetch(engine: engine, accountKind: "user", username: "fixture-user", calls: calls)

        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary == nil)
        #expect(snapshot.providerCost?.used == 12.34)
        #expect(snapshot.providerCost?.limit == 0)
        #expect(snapshot.providerCost?.balance == 5.5)
        #expect(snapshot.providerCost?.currencyCode == "USD")
        #expect(snapshot.providerCost?.period == "This month")
        #expect(snapshot.identity?.providerID == .replicate)
        #expect(snapshot.identity?.accountID == "fixture-user")
        #expect(snapshot.identity?.accountOrganization == nil)
        #expect(snapshot.details.first?.rows.map(\.label) == ["Spent this month", "Credit balance"])

        let requests = await calls.requests
        #expect(requests.map { $0.url?.path } == [
            "/account/billing",
            "/api/users/fixture-user/invoices",
            "/api/users/fixture-user/unused-credit",
        ])
        #expect(requests.first?.value(forHTTPHeaderField: "Accept") == "text/html")
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == "sessionid=fixture" })
    }

    @Test(arguments: ReplicatePluginTestSupport.engines)
    func `organization billing selects organization invoice endpoints`(engine: ProviderPluginEngineKind) async throws {
        let calls = ReplicateRequestLog()
        let snapshot = try await Self.fetch(
            engine: engine,
            accountKind: "organization",
            username: "fixture-team",
            creditBody: "not-json",
            calls: calls)

        #expect(snapshot.providerCost?.used == 12.34)
        #expect(snapshot.providerCost?.balance == nil)
        #expect(snapshot.identity?.accountID == "fixture-team")
        #expect(snapshot.identity?.accountOrganization == "fixture-team")
        #expect(snapshot.details.first?.rows.map(\.label) == ["Spent this month"])
        let requests = await calls.requests
        #expect(requests.map { $0.url?.path } == [
            "/account/billing",
            "/api/organizations/fixture-team/invoices",
            "/api/organizations/fixture-team/unused-credit",
        ])
    }

    @Test(arguments: ["true", "-1", "\"1e2\"", "\"USD 12\"", "null"], ReplicatePluginTestSupport.engines)
    func `malformed required spend fails closed`(amount: String, engine: ProviderPluginEngineKind) async {
        await Self.expectParseFailure { try await Self.fetch(engine: engine, totalCost: amount) }
    }

    @Test(arguments: ReplicatePluginTestSupport.engines)
    func `unknown billing markup is a parse failure rather than an account fallback`(
        engine: ProviderPluginEngineKind) async
    {
        await Self.expectParseFailure {
            try await Self.fetch(engine: engine, billingHTML: "<html><body>new layout</body></html>")
        }
    }

    @Test(arguments: [
        (401, ProviderFetchClassifiedError.Kind.authenticationExpired),
        (403, .permissionDenied),
        (429, .rateLimited),
        (503, .providerUnavailable),
    ], ReplicatePluginTestSupport.engines)
    func `billing status failures retain their classification`(
        failure: (Int, ProviderFetchClassifiedError.Kind),
        engine: ProviderPluginEngineKind) async
    {
        do {
            _ = try await Self.fetch(engine: engine, billingStatus: failure.0)
            Issue.record("Expected \(failure.1.rawValue)")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == failure.1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(arguments: ReplicatePluginTestSupport.engines)
    func `signed out billing response classifies forbidden status as expired`(engine: ProviderPluginEngineKind) async {
        do {
            _ = try await Self.fetch(
                engine: engine,
                billingHTML: #"<title>Sign in | Replicate</title><a href="/login/github/">Sign in</a>"#,
                billingStatus: 403)
            Issue.record("Expected authentication expiry")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == .authenticationExpired)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private static func fetch(
        engine: ProviderPluginEngineKind,
        accountKind: String = "user",
        username: String = "fixture-user",
        billingHTML: String? = nil,
        totalCost: String = "\"12.34\"",
        billingStatus: Int = 200,
        creditBody: String = #"{"unused_credit":"5.50"}"#,
        calls: ReplicateRequestLog = ReplicateRequestLog()) async throws -> UsageSnapshot
    {
        let runtime = try ReplicatePluginTestSupport.runtime(
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                await calls.append(request)
                let body: String
                switch request.url?.path {
                case "/account/billing":
                    body = billingHTML ?? """
                    <script id="react-component-props" type="application/json">{"account":{"kind":"\(
                        accountKind)","username":"\(username)"}}</script>
                    """
                case "/api/users/\(username)/invoices", "/api/organizations/\(username)/invoices":
                    body = """
                    {"invoices":[{"type":"monthly-usage","ended_before":null,"total_cost_before_adjustments":\(
                        totalCost)}]}
                    """
                case "/api/users/\(username)/unused-credit", "/api/organizations/\(username)/unused-credit":
                    body = creditBody
                default:
                    Issue.record("Unexpected Replicate fixture URL: \(request.url?.absoluteString ?? "missing")")
                    body = "{}"
                }
                let url = try #require(request.url)
                let status = url.path == "/account/billing" ? billingStatus : 200
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json", "Retry-After": "4"]))
                return (Data(body.utf8), response)
            })
        return try await runtime.fetchUsage(now: Self.now, cookieResolver: { provider, domain in
            guard provider == .replicate, domain == "replicate.com" else {
                throw ProviderPluginError.secretAccess("unexpected cookie scope")
            }
            return "sessionid=fixture"
        })
    }

    private static func expectParseFailure(
        operation: () async throws -> UsageSnapshot) async
    {
        do {
            _ = try await operation()
            Issue.record("Expected Replicate parse failure")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == .parseFailure)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private actor ReplicateRequestLog {
    private(set) var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        self.requests.append(request)
    }
}

private enum ReplicatePluginTestSupport {
    #if canImport(JavaScriptCore)
    static let engines: [ProviderPluginEngineKind] = [.quickJS, .javaScriptCore]
    #else
    static let engines: [ProviderPluginEngineKind] = [.quickJS]
    #endif

    static func runtime(
        engine: ProviderPluginEngineKind,
        transport: any ProviderHTTPTransport) throws -> ProviderPluginRuntime
    {
        guard let bundle = CodexBarCoreResources.bundle,
              let url = bundle.url(forResource: "replicate", withExtension: "js")
        else {
            throw ProviderPluginError.load("bundled plugin 'replicate.js' was not found")
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        return try ProviderPluginRuntime(source: source, transport: transport, engine: engine)
    }
}
