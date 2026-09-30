import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct HuggingFacePluginTests {
    static let now = Date(timeIntervalSince1970: 1_755_000_000)
    static let billing = #"""
    {"usage":{"inferenceProviders":{"usedNanoUsd":2450000000,"includedNanoUsd":2000000000,
    "limitNanoUsd":0,"numRequests":128,"periodEnd":"2025-09-01T00:00:00Z"}}}
    """#
    static let gpu = #"{"base":1500,"current":900,"resetsAt":"2025-08-31T18:00:00Z"}"#

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `billing and optional quota project through both engines`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(engine: engine)
        #expect(snapshot.primary == nil)
        #expect(snapshot.providerCost?.resetsAt == nil)
        #expect(snapshot.secondary?.usedPercent == 40)
        #expect(abs((snapshot.providerCost?.used ?? -1) - 0.45) < 0.000001)
        #expect(snapshot.providerCost?.limit == 0)
        #expect(snapshot.identity?.providerID == .huggingface)
        #expect(snapshot.identity?.accountID == "fixture-a")
        #expect(snapshot.identity?.loginMethod == "PRO")
        #expect(snapshot.identity?.accountOrganization == nil)
        #expect(snapshot.details[0].rows.map(\.label) == [
            "Billable usage",
            "Gross inference usage",
            "Included inference amount",
            "Requests",
        ])
        #expect(snapshot.details[1].rows.map(\.value) == ["10 min", "15 min"])
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `spend without a denominator has no invented quota`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(
            billing: #"""
            {"usage":{"inferenceProviders":{"usedNanoUsd":300000000,"includedNanoUsd":0,"limitNanoUsd":0}}}
            """#,
            engine: engine,
            optionalStatus: 503)
        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary == nil)
        #expect(snapshot.providerCost?.used == 0.3)
        #expect(snapshot.providerCost?.limit == 0)
        #expect(snapshot.identity == nil)
        #expect(HuggingFaceProviderDescriptor.descriptor.presentation.cost(snapshot: snapshot).menuCardStyle == .hidden)
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `reported spending limit remains a detail instead of a credit allowance`(
        engine: ProviderPluginEngineKind) async throws
    {
        let snapshot = try await Self.fetch(
            billing: #"""
            {"usage":{"inferenceProviders":{"usedNanoUsd":1000000000,
            "includedNanoUsd":0,"limitNanoUsd":4000000000}}}
            """#,
            engine: engine)
        #expect(snapshot.primary == nil)
        #expect(snapshot.providerCost?.limit == 4)
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `included amount above gross usage never creates a negative charge`(
        engine: ProviderPluginEngineKind) async throws
    {
        let snapshot = try await Self.fetch(
            billing: #"{"usage":{"inferenceProviders":{"usedNanoUsd":100000000,"includedNanoUsd":2000000000}}}"#,
            engine: engine)
        #expect(snapshot.providerCost?.used == 0)
        #expect(snapshot.primary == nil)
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `missing deduction cannot silently overstate billable usage`(engine: ProviderPluginEngineKind) async {
        await Self.expectFailure(.parseFailure) {
            try await Self.fetch(
                billing: #"{"usage":{"inferenceProviders":{"usedNanoUsd":100000000}}}"#,
                engine: engine)
        }
    }

    @Test(arguments: ["true", "-1", "\"450000000\"", "1e400", "null"], HuggingFacePluginTestSupport.engines)
    func `malformed required money fails rather than becoming zero`(
        value: String,
        engine: ProviderPluginEngineKind) async
    {
        await Self.expectFailure(.parseFailure) {
            try await Self.fetch(
                billing: "{\"usage\":{\"inferenceProviders\":{\"usedNanoUsd\":\(value)}}}",
                engine: engine)
        }
    }

    @Test(arguments: [
        (401, ProviderFetchClassifiedError.Kind.authenticationExpired),
        (403, .permissionDenied),
        (429, .rateLimited),
        (503, .providerUnavailable)
    ], HuggingFacePluginTestSupport.engines)
    func `billing failures retain actionable classification`(
        failure: (Int, ProviderFetchClassifiedError.Kind),
        engine: ProviderPluginEngineKind) async
    {
        await Self.expectFailure(failure.1) {
            try await Self.fetch(billing: "<html>error</html>", engine: engine, billingStatus: failure.0)
        }
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `identity cache is isolated per token and expires with the fetch clock`(
        engine: ProviderPluginEngineKind) async throws
    {
        let calls = HuggingFaceRequestLog()
        let runtime = try Self.runtime(
            engine: engine,
            billing: Self.billing.replacingOccurrences(of: ",\"periodEnd\":\"2025-09-01T00:00:00Z\"", with: ""),
            calls: calls)
        let first = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-a"], now: Self.now, sourceMode: .api, cookieSource: .off)
        let other = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-b"], now: Self.now, sourceMode: .api, cookieSource: .off)
        let again = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-a"],
            now: Self.now.addingTimeInterval(60),
            sourceMode: .api,
            cookieSource: .off)
        #expect(first.identity?.accountID == "fixture-a")
        #expect(other.identity?.accountID == "fixture-b")
        #expect(again.identity?.accountID == "fixture-a")
        #expect(await calls.whoamiCount == 2)
        _ = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-a"],
            now: Self.now.addingTimeInterval(13 * 60 * 60),
            sourceMode: .api,
            cookieSource: .off)
        #expect(await calls.whoamiCount == 3)
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `report cutoffs and profile dates cannot become quota resets`(
        engine: ProviderPluginEngineKind) async throws
    {
        let calls = HuggingFaceRequestLog()
        let runtime = try HuggingFacePluginTestSupport.runtime(
            "huggingface",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                await calls.append(request)
                let body: String = switch request.url?.path {
                case "/api/settings/billing/usage-v2":
                    await calls.billingCount == 1
                        ? Self.billing
                        : Self.billing.replacingOccurrences(of: "2025-09-01", with: "2025-10-01")
                case "/api/whoami-v2":
                    #"{"type":"user","id":"fixture-a","name":"fixture-a","periodEnd":1756684800}"#
                default:
                    Self.gpu
                }
                return try Self.response(request, body: body)
            })
        let before = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-a"],
            now: Date(timeIntervalSince1970: 1_756_684_790),
            sourceMode: .api,
            cookieSource: .off)
        let after = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-a"],
            now: Date(timeIntervalSince1970: 1_756_684_810),
            sourceMode: .api,
            cookieSource: .off)
        #expect(before.primary == nil)
        #expect(after.primary == nil)
        #expect(before.providerCost?.resetsAt == nil)
        #expect(after.providerCost?.resetsAt == nil)
        #expect(await calls.whoamiCount == 1)
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `profile dates do not imply an inference reset`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try Self.runtime(
            engine: engine,
            billing: Self.billing.replacingOccurrences(of: ",\"periodEnd\":\"2025-09-01T00:00:00Z\"", with: ""))
        let snapshot = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-a"],
            now: Date(timeIntervalSince1970: 1_756_900_000),
            sourceMode: .api,
            cookieSource: .off)
        #expect(snapshot.primary?.resetsAt == nil)
        #expect(snapshot.providerCost?.resetsAt == nil)
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `billing request uses UTC month bounds and required authority`(engine: ProviderPluginEngineKind) async throws {
        let calls = HuggingFaceRequestLog()
        let runtime = try Self.runtime(engine: engine, calls: calls)
        _ = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-a"], now: Self.now, sourceMode: .api, cookieSource: .off)
        let request = try #require(await calls.requests.first)
        #expect(request.url?.host == "huggingface.co")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-a")
        #expect(request.timeoutInterval == 15)
        let url = try #require(request.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "startDate" }?.value == "1754006400")
        #expect(query.first { $0.name == "endDate" }?.value == "1755000000")
    }

    @Test
    func `retained production strategy caches identities across refreshes`() async throws {
        let calls = HuggingFaceRequestLog()
        let strategy = HuggingFaceScriptFetchStrategy(transport: Self.transport(calls: calls))
        for token in ["fixture-a", "fixture-b", "fixture-a"] {
            let result = try await strategy.fetch(Self.context(token: token))
            #expect(result.usage.identity?.accountID == token)
        }
        #expect(await calls.whoamiCount == 2)
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `prepaid balance requires matching API and browser user identities`(
        engine: ProviderPluginEngineKind) async throws
    {
        let calls = HuggingFaceRequestLog()
        let runtime = try Self.walletRuntime(engine: engine, browserUserID: "account-a", calls: calls)
        let snapshot = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-token"],
            now: Self.now,
            sourceMode: .auto,
            cookieSource: .manual,
            cookieResolver: { _, _ in "session=synthetic-cookie" })

        #expect(snapshot.providerCost?.balance == 12.5)
        #expect(snapshot.details.last?.title == "Credits")
        #expect(snapshot.details.last?.rows.first?.value == "$12.50")
        let presentation = HuggingFaceProviderDescriptor.descriptor.presentation.cost(snapshot: snapshot)
        #expect(presentation.menuCardStyle == .payAsYouGoSpend)
        #expect(presentation.replacedDetailRows["Credits"]?.contains("Prepaid balance") == true)
        let requests = await calls.requests
        let apiRequests = requests.filter { $0.value(forHTTPHeaderField: "Authorization") != nil }
        let cookieRequests = requests.filter { $0.value(forHTTPHeaderField: "Cookie") != nil }
        #expect(apiRequests.count == 3)
        #expect(apiRequests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token" })
        #expect(cookieRequests.count == 2)
        #expect(cookieRequests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(cookieRequests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == "session=synthetic-cookie" })
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `billing entity id matching the API user keeps the prepaid balance`(
        engine: ProviderPluginEngineKind) async throws
    {
        let calls = HuggingFaceRequestLog()
        let runtime = try Self.walletRuntime(
            engine: engine,
            billingHTML: Self.billingHTML(entityIDJSON: #""account-a""#),
            browserUserID: "account-a",
            calls: calls)
        let snapshot = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-token"],
            now: Self.now,
            sourceMode: .auto,
            cookieSource: .manual,
            cookieResolver: { _, _ in "session=synthetic-cookie" })

        #expect(snapshot.providerCost?.balance == 12.5)
    }

    @Test(
        arguments: [#""account-b""#, "null", "42", #""  ""#, #"" account-a ""#],
        HuggingFacePluginTestSupport.engines)
    func `malformed or mismatched billing entity id omits the prepaid balance`(
        entityIDJSON: String,
        engine: ProviderPluginEngineKind) async throws
    {
        let calls = HuggingFaceRequestLog()
        let runtime = try Self.walletRuntime(
            engine: engine,
            billingHTML: Self.billingHTML(entityIDJSON: entityIDJSON),
            browserUserID: "account-a",
            calls: calls)
        let snapshot = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-token"],
            now: Self.now,
            sourceMode: .auto,
            cookieSource: .manual,
            cookieResolver: { _, _ in "session=synthetic-cookie" })

        #expect(snapshot.providerCost?.balance == nil)
        #expect(try abs(#require(snapshot.providerCost?.used) - 0.45) < 1e-12)
        #expect(snapshot.details.last?.title == "ZeroGPU")
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `legacy prepaid balance converts unique invoice cents`(engine: ProviderPluginEngineKind) async throws {
        let calls = HuggingFaceRequestLog()
        let runtime = try Self.walletRuntime(
            engine: engine,
            billingHTML: #"<div data-props="{&quot;invoiceCreditsCents&quot;:425}"></div>"#,
            browserUserID: "account-a",
            calls: calls)
        let snapshot = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-token"],
            now: Self.now,
            sourceMode: .auto,
            cookieSource: .manual,
            cookieResolver: { _, _ in "session=synthetic-cookie" })
        #expect(snapshot.providerCost?.balance == 4.25)
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `legacy balance with a matching entity id remains supported`(engine: ProviderPluginEngineKind) async throws {
        let calls = HuggingFaceRequestLog()
        let runtime = try Self.walletRuntime(
            engine: engine,
            billingHTML: Self.legacyBillingHTML(entityIDJSON: #""account-a""#),
            browserUserID: "account-a",
            calls: calls)
        let snapshot = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-token"],
            now: Self.now,
            sourceMode: .auto,
            cookieSource: .manual,
            cookieResolver: { _, _ in "session=synthetic-cookie" })

        #expect(snapshot.providerCost?.balance == 4.25)
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `legacy balance with a mismatched entity id is omitted`(engine: ProviderPluginEngineKind) async throws {
        let calls = HuggingFaceRequestLog()
        let runtime = try Self.walletRuntime(
            engine: engine,
            billingHTML: Self.legacyBillingHTML(entityIDJSON: #""account-b""#),
            browserUserID: "account-a",
            calls: calls)
        let snapshot = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-token"],
            now: Self.now,
            sourceMode: .auto,
            cookieSource: .manual,
            cookieResolver: { _, _ in "session=synthetic-cookie" })

        #expect(snapshot.providerCost?.balance == nil)
        #expect(try abs(#require(snapshot.providerCost?.used) - 0.45) < 1e-12)
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `mismatched browser identity suppresses prepaid balance`(engine: ProviderPluginEngineKind) async throws {
        let calls = HuggingFaceRequestLog()
        let runtime = try Self.walletRuntime(engine: engine, browserUserID: "account-b", calls: calls)
        let snapshot = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-token"],
            now: Self.now,
            sourceMode: .auto,
            cookieSource: .manual,
            cookieResolver: { _, _ in "session=synthetic-cookie" })
        #expect(snapshot.providerCost?.balance == nil)
        #expect(try abs(#require(snapshot.providerCost?.used) - 0.45) < 1e-12)
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `ambiguous prepaid balances are omitted without failing usage`(engine: ProviderPluginEngineKind) async throws {
        let calls = HuggingFaceRequestLog()
        let first = #"{&quot;entity&quot;:{&quot;type&quot;:&quot;user&quot;,&quot;currentBalanceUsd&quot;:5}}"#
        let second = #"{&quot;entity&quot;:{&quot;type&quot;:&quot;user&quot;,&quot;currentBalanceUsd&quot;:7}}"#
        let html = "<div data-props=\"\(first)\"></div><div data-props=\"\(second)\"></div>"
        let runtime = try Self.walletRuntime(
            engine: engine, billingHTML: html, browserUserID: "account-a", calls: calls)
        let snapshot = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-token"],
            now: Self.now,
            sourceMode: .auto,
            cookieSource: .manual,
            cookieResolver: { _, _ in "session=synthetic-cookie" })
        #expect(snapshot.providerCost?.balance == nil)
        #expect(try abs(#require(snapshot.providerCost?.used) - 0.45) < 1e-12)
        #expect(snapshot.details.last?.title == "ZeroGPU")
    }

    @Test(arguments: HuggingFacePluginTestSupport.engines)
    func `disabled cookies and API mode never request the browser wallet`(
        engine: ProviderPluginEngineKind) async throws
    {
        let calls = HuggingFaceRequestLog()
        let runtime = try Self.walletRuntime(engine: engine, browserUserID: "account-a", calls: calls)
        let cookieResolver: ProviderPluginRuntime.CookieResolver = { _, _ in
            await calls.noteCookieResolverCall()
            return "session=synthetic-cookie"
        }
        let apiSnapshot = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-token"],
            now: Self.now,
            sourceMode: .api,
            cookieSource: .auto,
            cookieResolver: cookieResolver)
        let disabledSnapshot = try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-token"],
            now: Self.now,
            sourceMode: .auto,
            cookieSource: .off,
            cookieResolver: cookieResolver)
        #expect(apiSnapshot.providerCost?.balance == nil)
        #expect(disabledSnapshot.providerCost?.balance == nil)
        #expect(await calls.cookieResolverCalls == 0)
        let requests = await calls.requests
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil })
    }

    static func fetch(
        billing: String = Self.billing,
        engine: ProviderPluginEngineKind,
        billingStatus: Int = 200,
        optionalStatus: Int = 200) async throws -> UsageSnapshot
    {
        let runtime = try Self.runtime(
            engine: engine, billing: billing, billingStatus: billingStatus, optionalStatus: optionalStatus)
        return try await runtime.fetchUsage(
            secrets: ["HF_TOKEN": "fixture-a"], now: Self.now, sourceMode: .api, cookieSource: .off)
    }

    private static func runtime(
        engine: ProviderPluginEngineKind,
        billing: String = Self.billing,
        billingStatus: Int = 200,
        optionalStatus: Int = 200,
        calls: HuggingFaceRequestLog = HuggingFaceRequestLog()) throws -> ProviderPluginRuntime
    {
        try HuggingFacePluginTestSupport.runtime(
            "huggingface",
            engine: engine,
            transport: self.transport(
                billing: billing, billingStatus: billingStatus, optionalStatus: optionalStatus, calls: calls))
    }

    private static func walletRuntime(
        engine: ProviderPluginEngineKind,
        billingHTML: String = #"""
        <div
        data-props="{&quot;entity&quot;:{&quot;type&quot;:&quot;user&quot;,&quot;currentBalanceUsd&quot;:12.5}}"></div>
        """#,
        browserUserID: String,
        calls: HuggingFaceRequestLog) throws -> ProviderPluginRuntime
    {
        try HuggingFacePluginTestSupport.runtime(
            "huggingface",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                await calls.append(request)
                switch request.url?.path {
                case "/api/settings/billing/usage-v2":
                    return try Self.response(request, body: Self.billing)
                case "/api/spaces/zero-gpu/quota":
                    return try Self.response(request, body: Self.gpu)
                case "/settings/billing":
                    return try Self.response(request, body: billingHTML, contentType: "text/html")
                case "/api/whoami-v2":
                    let id = request.value(forHTTPHeaderField: "Authorization") == nil
                        ? browserUserID
                        : "account-a"
                    return try Self.response(
                        request,
                        body: #"{"type":"user","id":"\#(id)","name":"fixture-user"}"#)
                default:
                    return try Self.response(request, body: "{}")
                }
            })
    }

    private static func billingHTML(entityIDJSON: String) -> String {
        let props = #"{"entity":{"id":\#(entityIDJSON),"type":"user","currentBalanceUsd":12.5}}"#
        let escapedProps = props.replacingOccurrences(of: "\"", with: "&quot;")
        return #"<div data-props="\#(escapedProps)"></div>"#
    }

    private static func legacyBillingHTML(entityIDJSON: String) -> String {
        let props = #"{"entity":{"id":\#(entityIDJSON)},"invoiceCreditsCents":425}"#
        let escapedProps = props.replacingOccurrences(of: "\"", with: "&quot;")
        return #"<div data-props="\#(escapedProps)"></div>"#
    }

    private static func transport(
        billing: String = Self.billing,
        billingStatus: Int = 200,
        optionalStatus: Int = 200,
        calls: HuggingFaceRequestLog) -> ProviderHTTPTransportHandler
    {
        ProviderHTTPTransportHandler { request in
            await calls.append(request)
            let path = request.url?.path
            let isBilling = path == "/api/settings/billing/usage-v2"
            let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(
                of: "Bearer ",
                with: "")
                ?? "missing"
            let profile = "{\"type\":\"user\",\"id\":\"\(token)\",\"name\":\"\(token)\","
                + "\"email\":\"tester@example.com\",\"isPro\":true,"
                + "\"periodEnd\":\(token == "fixture-a" ? 1_756_700_000 : 1_756_800_000)}"
            let body = isBilling ? billing : path == "/api/whoami-v2" ? profile : Self.gpu
            return try Self.response(request, body: body, status: isBilling ? billingStatus : optionalStatus)
        }
    }

    private static func response(
        _ request: URLRequest,
        body: String,
        status: Int = 200,
        contentType: String = "application/json") throws -> (Data, URLResponse)
    {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]))
        return (Data(body.utf8), response)
    }

    private static func expectFailure(
        _ kind: ProviderFetchClassifiedError.Kind,
        operation: () async throws -> UsageSnapshot) async
    {
        do {
            _ = try await operation()
            Issue.record("Expected \(kind.rawValue)")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == kind)
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }
    }

    private static func context(token: String) -> ProviderFetchContext {
        let environment = ["HF_TOKEN": token]
        return ProviderFetchContext(
            runtime: .app,
            sourceMode: .api,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: nil,
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: HuggingFaceUnusedClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }
}

private actor HuggingFaceRequestLog {
    private(set) var requests: [URLRequest] = []
    private(set) var cookieResolverCalls = 0
    var whoamiCount: Int {
        self.requests.count(where: { $0.url?.path == "/api/whoami-v2" })
    }

    var billingCount: Int {
        self.requests.count(where: { $0.url?.path == "/api/settings/billing/usage-v2" })
    }

    func append(_ request: URLRequest) {
        self.requests.append(request)
    }

    func noteCookieResolverCall() {
        self.cookieResolverCalls += 1
    }
}

private struct HuggingFaceUnusedClaudeFetcher: ClaudeUsageFetching {
    func detectVersion() -> String? {
        nil
    }

    func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
        throw CancellationError()
    }

    func debugRawProbe(model _: String) async -> String {
        "unused"
    }
}

enum HuggingFacePluginTestSupport {
    #if canImport(JavaScriptCore)
    static let engines: [ProviderPluginEngineKind] = [.quickJS, .javaScriptCore]
    #else
    static let engines: [ProviderPluginEngineKind] = [.quickJS]
    #endif

    static func runtime(
        _ bundledPlugin: String,
        engine: ProviderPluginEngineKind,
        transport: any ProviderHTTPTransport) throws -> ProviderPluginRuntime
    {
        guard let bundle = CodexBarCoreResources.bundle,
              let url = bundle.url(forResource: bundledPlugin, withExtension: "js")
        else {
            throw ProviderPluginError.load("bundled plugin '\(bundledPlugin).js' was not found")
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        return try ProviderPluginRuntime(source: source, transport: transport, engine: engine)
    }
}
