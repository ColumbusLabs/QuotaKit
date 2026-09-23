import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(JavaScriptCore)
@preconcurrency import JavaScriptCore
#endif
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite("Charm Hyper provider")
struct HyperProviderTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    #if canImport(JavaScriptCore)
    private static let engines: [ProviderPluginEngineKind] = [.quickJS, .javaScriptCore]
    #else
    private static let engines: [ProviderPluginEngineKind] = [.quickJS]
    #endif

    @Test(arguments: Self.engines)
    func `API source sends only the API key and skips the cookie resolver`(
        engine: ProviderPluginEngineKind) async throws
    {
        let fixture = try await Self.fetch(engine: engine, mode: .api, cookie: "session=unused")

        #expect(fixture.snapshot.hyperBalance == 42.5)
        #expect(fixture.snapshot.providerCost == nil)
        #expect(fixture.snapshot.primary == nil)
        #expect(fixture.snapshot.secondary == nil)
        #expect(fixture.snapshot.details.first?.rows.first?.value.hasSuffix(" HC") == true)
        #expect(fixture.snapshot.identity?.loginMethod == "API key")
        #expect(fixture.cookieResolverCalls.value == 0)
        #expect(fixture.requests.values.count == 1)
        #expect(fixture.requests.values.first?.authorization == "Bearer fixture-key")
        #expect(fixture.requests.values.first?.cookie == nil)
    }

    @Test(arguments: Self.engines)
    func `automatic session is preferred and sends no API key`(engine: ProviderPluginEngineKind) async throws {
        let fixture = try await Self.fetch(engine: engine, cookie: "session=fixture")

        #expect(fixture.snapshot.hyperBalance == 42.5)
        #expect(fixture.snapshot.identity?.loginMethod == "Browser session")
        #expect(fixture.cookieResolverCalls.value == 1)
        #expect(fixture.requests.values.count == 1)
        #expect(fixture.requests.values[0].url == "https://hyper.charm.land/v1/credits")
        #expect(fixture.requests.values[0].method == "GET")
        #expect(fixture.requests.values.first?.cookie == "session=fixture")
        #expect(fixture.requests.values.first?.authorization == nil)
    }

    @Test(arguments: Self.engines)
    func `cookie source off never sends a cookie and falls back to the API key`(
        engine: ProviderPluginEngineKind) async throws
    {
        let fixture = try await Self.fetch(
            engine: engine,
            cookieSource: .off,
            cookie: "session=must-not-be-used")

        #expect(fixture.snapshot.identity?.loginMethod == "API key")
        #expect(fixture.requests.values.count == 1)
        #expect(fixture.requests.values[0].cookie == nil)
        #expect(fixture.requests.values[0].authorization == "Bearer fixture-key")
    }

    @Test(arguments: Self.engines)
    func `manual cookie source uses only the saved cookie header`(engine: ProviderPluginEngineKind) async throws {
        let fixture = try await Self.fetch(
            engine: engine,
            cookieSource: .manual,
            cookie: "session=browser-must-not-be-used",
            manualCookie: "session=manual-fixture")

        #expect(fixture.snapshot.identity?.loginMethod == "Browser session")
        #expect(fixture.cookieResolverCalls.value == 1)
        #expect(fixture.requests.values.count == 1)
        #expect(fixture.requests.values[0].cookie == "session=manual-fixture")
        #expect(fixture.requests.values[0].authorization == nil)
    }

    @Test(arguments: Self.engines)
    func `a rejected automatic session is invalidated before API fallback`(
        engine: ProviderPluginEngineKind) async throws
    {
        let fixture = try await Self.fetch(engine: engine, cookie: "session=stale", sessionStatus: 401)

        #expect(fixture.snapshot.hyperBalance == 42.5)
        #expect(fixture.snapshot.identity?.loginMethod == "API key")
        #expect(fixture.cookieInvalidatorCalls.value == 1)
        #expect(fixture.requests.values.count == 2)
        #expect(fixture.requests.values[0].cookie == "session=stale")
        #expect(fixture.requests.values[0].authorization == nil)
        #expect(fixture.requests.values[1].cookie == nil)
        #expect(fixture.requests.values[1].authorization == "Bearer fixture-key")
    }

    @Test(arguments: Self.engines)
    func `web-only mode reports expired session and never falls back to API`(
        engine: ProviderPluginEngineKind) async
    {
        do {
            _ = try await Self.fetch(engine: engine, mode: .web, cookie: "session=stale", sessionStatus: 401)
            Issue.record("Expected expired session failure")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == .authenticationExpired)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(
        arguments: [
            "{}",
            #"{"balance":-1}"#,
            #"{"balance":"42"}"#,
            #"{"balance":null}"#,
            "null",
            "[]",
            #"{"balance":1e400}"#
        ],
        Self.engines)
    func `malformed Hypercredits balances fail closed`(body: String, engine: ProviderPluginEngineKind) async {
        do {
            _ = try await Self.fetch(engine: engine, mode: .api, body: body)
            Issue.record("Expected invalid balance failure")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == .parseFailure)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(arguments: [
        (401, ProviderFetchClassifiedError.Kind.authenticationExpired),
        (403, .permissionDenied),
        (429, .rateLimited),
        (503, .providerUnavailable),
        (404, .apiFailure),
    ], Self.engines)
    func `API errors are classified without exposing response or credentials`(
        fixture: (Int, ProviderFetchClassifiedError.Kind),
        engine: ProviderPluginEngineKind) async
    {
        do {
            _ = try await Self.fetch(
                engine: engine,
                mode: .api,
                body: "private response fixture-key",
                apiStatus: fixture.0)
            Issue.record("Expected API failure")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == fixture.1)
            #expect(!error.message.contains("private response"))
            #expect(!error.message.contains("fixture-key"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `descriptor keeps Hyper opt in and balance only with cookie settings registered`() throws {
        let descriptor = HyperProviderDescriptor.descriptor
        let credentials = try #require(descriptor.credentials)
        let registration = descriptor.settingsSection

        #expect(descriptor.metadata.displayName == "Charm Hyper")
        #expect(descriptor.metadata.balanceOnly)
        #expect(!descriptor.metadata.defaultEnabled)
        #expect(!descriptor.metadata.widgetSelectable)
        #expect(descriptor.fetchPlan.sourceModes == [.auto, .web, .api])
        #expect(credentials.tokenAccountSupport?.title == "API keys")

        for source in ProviderCookieSource.allCases {
            let header = source == .manual ? "session=fixture" : nil
            let settings = HyperProviderSettings(cookieSource: source, manualCookieHeader: header)
            let snapshot = ProviderSettingsSnapshot(settings, for: HyperProviderSettingsKey.self)
            let resolved = try #require(registration.cookieSettings(from: snapshot))
            #expect(resolved.cookieSource == source)
            #expect(resolved.manualCookieHeader == header)
        }
    }

    @Test
    func `Hyper balance persists on Mac and missing legacy field defaults to nil`() throws {
        let snapshot = try UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [ProviderDetailSection(title: "Hypercredits", rows: [
                .init(label: "Balance", value: "42.5 HC"),
            ])],
            hyperBalance: 42.5,
            updatedAt: Self.now)
        let data = try JSONEncoder().encode(snapshot)
        let roundTrip = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        #expect(roundTrip.hyperBalance == 42.5)

        var legacyPayload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacyPayload.removeValue(forKey: "hyperBalance")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyPayload)
        let legacy = try JSONDecoder().decode(UsageSnapshot.self, from: legacyData)
        #expect(legacy.hyperBalance == nil)
    }

    @Test
    @MainActor
    func `Hypercredits map only to the Hyper sync field and never to currency`() throws {
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            hyperBalance: 18.75,
            updatedAt: Self.now)

        let balance = try #require(SyncCoordinator.mapHyperBalance(provider: .hyper, snapshot: snapshot))
        #expect(balance.balance == 18.75)
        #expect(balance.updatedAt == Self.now)
        #expect(SyncCoordinator.mapHyperBalance(provider: .claude, snapshot: snapshot) == nil)
        #expect(SyncCoordinator.mapHyperBalance(
            provider: .hyper,
            snapshot: UsageSnapshot(primary: nil, secondary: nil, hyperBalance: -.infinity, updatedAt: Self.now)) ==
            nil)
    }

    private struct FetchFixture {
        let snapshot: UsageSnapshot
        let requests: HyperRequestRecorder
        let cookieResolverCalls: HyperCallCounter
        let cookieInvalidatorCalls: HyperCallCounter
    }

    private static func fetch(
        engine: ProviderPluginEngineKind,
        mode: ProviderSourceMode = .auto,
        cookieSource: ProviderCookieSource = .auto,
        body: String = #"{"balance":42.5}"#,
        cookie: String? = nil,
        manualCookie: String? = nil,
        sessionStatus: Int = 200,
        sessionHTML: Bool = false,
        apiStatus: Int = 200) async throws -> FetchFixture
    {
        let requests = HyperRequestRecorder()
        let cookieResolverCalls = HyperCallCounter()
        let cookieInvalidatorCalls = HyperCallCounter()
        let transport = ProviderHTTPTransportHandler { request in
            guard let url = request.url else { throw ProviderPluginError.http("fixture request had no URL") }
            let isSession = request.value(forHTTPHeaderField: "Cookie") != nil
            requests.append(HyperRequestSummary(
                url: url.absoluteString,
                method: request.httpMethod ?? "",
                cookie: request.value(forHTTPHeaderField: "Cookie"),
                authorization: request.value(forHTTPHeaderField: "Authorization")))
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: isSession ? sessionStatus : apiStatus,
                httpVersion: nil,
                headerFields: ["Content-Type": isSession && sessionHTML ? "text/html; charset=utf-8" :
                    "application/json"]))
            let responseBody = isSession && sessionHTML ? "<html>Log in</html>" : body
            return (Data(responseBody.utf8), response)
        }
        let pluginURL = try #require(CodexBarCoreResources.bundle?.url(forResource: "hyper", withExtension: "js"))
        let runtime = try ProviderPluginRuntime(
            source: String(contentsOf: pluginURL, encoding: .utf8),
            transport: transport,
            engine: engine)
        let snapshot = try await runtime.fetchUsage(
            settings: ["SOURCE_MODE": mode.rawValue],
            secrets: ["HYPER_API_KEY": "fixture-key"],
            now: Self.now,
            cookieInvalidator: { domain in
                if domain == "hyper.charm.land" { cookieInvalidatorCalls.increment() }
            },
            cookieResolver: { provider, domain in
                cookieResolverCalls.increment()
                guard provider == .hyper, domain == "hyper.charm.land" else {
                    throw ProviderPluginError.secretAccess("unexpected fixture cookie request")
                }
                guard mode != .api, cookieSource != .off else {
                    throw ProviderPluginError.secretAccess("fixture cookie source is off")
                }
                let resolvedCookie = cookieSource == .manual ? manualCookie : cookie
                guard let resolvedCookie, !resolvedCookie.isEmpty else {
                    throw ProviderPluginError.secretAccess("fixture has no selected session")
                }
                return resolvedCookie
            })
        return FetchFixture(
            snapshot: snapshot,
            requests: requests,
            cookieResolverCalls: cookieResolverCalls,
            cookieInvalidatorCalls: cookieInvalidatorCalls)
    }
}

private struct HyperRequestSummary: Sendable {
    let url: String
    let method: String
    let cookie: String?
    let authorization: String?
}

private final class HyperRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [HyperRequestSummary] = []

    var values: [HyperRequestSummary] {
        self.lock.withLock { self.storedValues }
    }

    func append(_ request: HyperRequestSummary) {
        self.lock.withLock { self.storedValues.append(request) }
    }
}

private final class HyperCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        self.lock.withLock { self.storedValue }
    }

    func increment() {
        self.lock.withLock { self.storedValue += 1 }
    }
}
