import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct ZedPluginTests {
    private static let billing = #"""
    {
      "plan": "zed_pro",
      "current_usage": {
        "token_spend": {"spend_in_cents": 250, "limit_in_cents": 1000},
        "edit_predictions": {"used": 12, "limit": 100}
      }
    }
    """#

    @Test(arguments: ZedPluginTestSupport.engines)
    func `web billing maps spend and prediction quota without editor credentials`(
        engine: ProviderPluginEngineKind) async throws
    {
        let requests = LockIsolated<[URLRequest]>([])
        let runtime = try ZedPluginTestSupport.runtime(engine: engine) { request in
            requests.setValue(requests.value + [request])
            #expect(request.url?.absoluteString == "https://cloud.zed.dev/frontend/billing/usage")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "zed.session=fixture-session")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            return try Self.response(request, body: Self.billing)
        }
        let snapshot = try await runtime.fetchUsage(
            cookieResolver: { _, domain in
                #expect(domain == "zed.dev")
                return "zed.session=fixture-session"
            })

        #expect(requests.value.count == 1)
        #expect(snapshot.providerCost?.used == 2.5)
        #expect(snapshot.providerCost?.limit == 10)
        #expect(snapshot.details.first?.rows.map(\.value) == ["$2.50", "$10.00", "$7.50"])
        #expect(snapshot.primary?.usedPercent == 12)
        #expect(snapshot.identity?.loginMethod == "Zed Pro")
        #expect(snapshot.secondary == nil)
        #expect(snapshot.extraRateWindows == nil)
    }

    @Test(arguments: [0.0, 25.0, 250.0, 1500.0], ZedPluginTestSupport.engines)
    func `spend cents remain exact for zero and overage`(cents: Double, engine: ProviderPluginEngineKind) async throws {
        let body = Self.billing.replacingOccurrences(of: "250", with: String(cents))
        let snapshot = try await Self.fetch(body, engine: engine)
        #expect(snapshot.providerCost?.used == cents / 100)
        #expect(snapshot.details.first?.rows.last?.value == UsageFormatter.usdString(max(0, 10 - cents / 100)))
    }

    @Test(arguments: ["null", "missing"], ZedPluginTestSupport.engines)
    func `unknown spend cap is not invented`(cap: String, engine: ProviderPluginEngineKind) async throws {
        let body = cap == "missing"
            ? Self.billing.replacingOccurrences(
                of: "{\"spend_in_cents\": 250, \"limit_in_cents\": 1000}",
                with: "{\"spend_in_cents\": 250}")
            : Self.billing.replacingOccurrences(
                of: "\"limit_in_cents\": 1000",
                with: "\"limit_in_cents\": null")
        let snapshot = try await Self.fetch(body, engine: engine)

        #expect(snapshot.providerCost == nil)
        #expect(snapshot.details.first?.rows.map(\.label) == ["Spent", "Spend limit"])
        #expect(snapshot.details.first?.rows.last?.value == "Not reported")
    }

    @Test(arguments: [401, 403], ZedPluginTestSupport.engines)
    func `expired browser session is rejected for its declared domain`(
        status: Int, engine: ProviderPluginEngineKind) async throws
    {
        let invalidated = LockIsolated<[String]>([])
        let runtime = try ZedPluginTestSupport.runtime(engine: engine) { request in
            try Self.response(request, body: "<html>sign in</html>", status: status)
        }

        await Self.expectFailure(.authenticationExpired) {
            try await runtime.fetchUsage(
                cookieInvalidator: { domain in invalidated.setValue(invalidated.value + [domain]) },
                cookieResolver: { _, _ in "zed.session=fixture-session" })
        }

        #expect(invalidated.value == ["zed.dev"])
    }

    @Test(arguments: ZedPluginTestSupport.engines)
    func `http failures retain actionable classification`(engine: ProviderPluginEngineKind) async {
        for (status, kind) in [
            (429, ProviderFetchClassifiedError.Kind.rateLimited),
            (503, .providerUnavailable),
            (404, .apiFailure),
        ] {
            await Self.expectFailure(kind) {
                try await Self.fetch("{}", engine: engine, status: status)
            }
        }
    }

    @Test(arguments: ZedPluginTestSupport.engines)
    func `browser invalidation cannot name an undeclared cookie domain`(engine: ProviderPluginEngineKind) async throws {
        let source = #"""
        defineProvider({
          id: "zed",
          name: "Zed",
          endpoints: ["https://cloud.zed.dev"],
          settings: [],
          capabilities: ["browser-cookies"],
          cookieDomains: ["zed.dev"],
          fetchUsage(ctx) {
            ctx.browser.rejectCookie("other.example");
            return { primary: { usedPercent: 1 } };
          },
        });
        """#
        let runtime = try ProviderPluginRuntime(source: source, engine: engine)
        let invalidated = LockIsolated<[String]>([])

        await #expect(throws: ProviderPluginError.self) {
            try await runtime.fetchUsage(cookieInvalidator: { domain in
                invalidated.setValue(invalidated.value + [domain])
            })
        }

        #expect(invalidated.value.isEmpty)
    }

    @Test
    func `browser cookie settings default off and require explicit configuration`() throws {
        let registration = ZedProviderDescriptor.descriptor.settingsSection
        for (config, expected) in [
            (ProviderConfig(id: .zed), ProviderCookieSource.off),
            (ProviderConfig(id: .zed, cookieHeader: "zed.session=fixture"), .manual),
            (ProviderConfig(id: .zed, cookieSource: .off), .off),
            (ProviderConfig(id: .zed, cookieSource: .auto), .auto),
        ] {
            let contribution = try #require(registration.credentialContribution(context: .init(
                config: config,
                account: nil)))
            let settings = ProviderSettingsSnapshot(contributions: [contribution])
            #expect(settings[ZedProviderSettingsKey.self]?.cookieSource == expected)
        }
        #expect(ZedProviderDescriptor.descriptor.fetchPlan.sourceModes.contains(.web))
    }

    @Test
    @MainActor
    func `app settings snapshot exposes the opt in without changing the editor default`() async {
        let settings = testSettingsStore(suiteName: "ZedPluginTests-settings")
        let defaultSnapshot = ProviderRegistry.makeSettingsSnapshot(settings: settings, tokenOverride: nil)
        #expect(defaultSnapshot[ZedProviderSettingsKey.self]?.cookieSource == .off)
        #expect(await Self.strategyIDs(settings: defaultSnapshot) == ["zed.local"])

        settings.zedCookieHeader = "zed.session=fixture-only"
        let inferredManualSnapshot = ProviderRegistry.makeSettingsSnapshot(settings: settings, tokenOverride: nil)
        #expect(inferredManualSnapshot[ZedProviderSettingsKey.self]?.cookieSource == .manual)
        #expect(inferredManualSnapshot[ZedProviderSettingsKey.self]?.manualCookieHeader == "zed.session=fixture-only")
        #expect(await Self.strategyIDs(settings: inferredManualSnapshot) == ["zed.web"])

        settings.zedCookieSource = .off
        let explicitOffSnapshot = ProviderRegistry.makeSettingsSnapshot(settings: settings, tokenOverride: nil)
        #expect(explicitOffSnapshot[ZedProviderSettingsKey.self]?.cookieSource == .off)
        #expect(await Self.strategyIDs(settings: explicitOffSnapshot) == ["zed.local"])

        settings.zedCookieSource = .auto
        let automaticSnapshot = ProviderRegistry.makeSettingsSnapshot(settings: settings, tokenOverride: nil)
        #expect(automaticSnapshot[ZedProviderSettingsKey.self]?.cookieSource == .auto)
        #expect(await Self.strategyIDs(settings: automaticSnapshot) == ["zed.web"])

        settings.zedCookieSource = .manual
        settings.zedCookieHeader = "zed.session=fixture-only"
        let manualSnapshot = ProviderRegistry.makeSettingsSnapshot(settings: settings, tokenOverride: nil)
        #expect(manualSnapshot[ZedProviderSettingsKey.self]?.cookieSource == .manual)
        #expect(manualSnapshot[ZedProviderSettingsKey.self]?.manualCookieHeader == "zed.session=fixture-only")
    }

    @MainActor
    private static func strategyIDs(settings: ProviderSettingsSnapshot) async -> [String] {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: .auto,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: settings,
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection, environment: [:]),
            browserDetection: browserDetection)
        let strategies = await ZedProviderDescriptor.descriptor.fetchPlan.pipeline.resolveStrategies(context)
        return strategies.map(\.id)
    }

    private static func fetch(
        _ body: String,
        engine: ProviderPluginEngineKind,
        status: Int = 200) async throws -> UsageSnapshot
    {
        let runtime = try ZedPluginTestSupport.runtime(engine: engine) { request in
            try Self.response(request, body: body, status: status)
        }
        return try await runtime.fetchUsage(cookieResolver: { _, _ in "zed.session=fixture-session" })
    }

    private static func expectFailure(
        _ kind: ProviderFetchClassifiedError.Kind,
        operation: () async throws -> UsageSnapshot) async
    {
        do {
            _ = try await operation()
            Issue.record("Expected \(kind)")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == kind)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private static func response(
        _ request: URLRequest,
        body: String,
        status: Int = 200) throws -> (Data, HTTPURLResponse)
    {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]))
        return (Data(body.utf8), response)
    }
}

enum ZedPluginTestSupport {
    #if canImport(JavaScriptCore)
    static let engines: [ProviderPluginEngineKind] = [.quickJS, .javaScriptCore]
    #else
    static let engines: [ProviderPluginEngineKind] = [.quickJS]
    #endif

    static func runtime(
        engine: ProviderPluginEngineKind,
        transport: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)) throws -> ProviderPluginRuntime
    {
        guard let bundle = CodexBarCoreResources.bundle,
              let url = bundle.url(forResource: "zed", withExtension: "js")
        else {
            throw ProviderPluginError.load("bundled plugin 'zed.js' was not found")
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        return try ProviderPluginRuntime(
            source: source,
            transport: ProviderHTTPTransportHandler(transport),
            engine: engine)
    }
}
