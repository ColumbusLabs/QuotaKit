import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

#if os(macOS)
import SweetCookieKit
#endif

struct ProviderPluginCookieJarTests {
    #if os(macOS)
    @Test
    func `typed cookie importer preserves construction interaction and retry scope`() async {
        let contextualImporter = ProviderInteractionContext.$current.withValue(.userInitiated) {
            BrowserCookieAccessGate.withExplicitRetry {
                let importer: @Sendable (String) throws -> Bool = { domain in
                    domain == "api.example.test"
                        && ProviderInteractionContext.current == .userInitiated
                        && BrowserCookieAccessGate.shouldAttempt(.chrome)
                }
                return BrowserCookieAccessGate.operationPreservingAccessContext(importer)
            }
        }

        let resultAndRestoredContext = await KeychainAccessGate.withTaskOverrideForTesting(false) {
            await ProviderInteractionContext.$current.withValue(.background) {
                await BrowserCookieAccessGate.withDeniedBrowsersForTesting([.chrome]) {
                    let result = try? contextualImporter("api.example.test")
                    return (result, ProviderInteractionContext.current)
                }
            }
        }

        #expect(resultAndRestoredContext.0 == true)
        #expect(resultAndRestoredContext.1 == .background)
    }
    #endif

    @Test
    func `record matcher preserves host domain path secure expiry and ordering`() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let records = [
            Self.record("host", value: "host", domain: "api.example.test", hostOnly: true),
            Self.record("domain", value: "domain", domain: "example.test", hostOnly: false),
            Self.record("path", value: "path", domain: "api.example.test", path: "/foo", hostOnly: true),
            Self.record("expired", value: "old", domain: "api.example.test", expires: now.addingTimeInterval(-1)),
        ]

        #expect(try ProviderPluginCookieRecord.header(
            records,
            for: #require(URL(string: "https://api.example.test/foo/bar")),
            now: now) == "path=path; domain=domain; host=host")
        #expect(try ProviderPluginCookieRecord.header(
            records,
            for: #require(URL(string: "https://api.example.test/foobar")),
            now: now) == "domain=domain; host=host")
        #expect(try ProviderPluginCookieRecord.header(
            records,
            for: #require(URL(string: "https://child.api.example.test/foo")),
            now: now) == "domain=domain")
        #expect(try ProviderPluginCookieRecord.header(
            records,
            for: #require(URL(string: "https://badexample.test/foo")),
            now: now) == nil)
        #expect(try ProviderPluginCookieRecord.header(
            [Self.record("session", value: "safe; forged=yes", domain: "api.example.test")],
            for: #require(URL(string: "https://api.example.test/foo")),
            now: now) == nil)
        #expect(try ProviderPluginCookieRecord.header(
            [Self.record("bad\r\nHost", value: "fixture", domain: "api.example.test")],
            for: #require(URL(string: "https://api.example.test/foo")),
            now: now) == nil)
    }

    @Test
    func `opaque sessions keep cookie values out of serialized JavaScript payload`() throws {
        let session = ProviderPluginCookieSession(
            header: "",
            source: "Fixture",
            origin: "https://api.example.test",
            records: [Self.record("session", value: "secret-fixture", domain: "api.example.test", hostOnly: true)])
        let payload = try session.json(opaque: true)
        #expect(!payload.contains("secret-fixture"))
        #expect(!payload.contains("header"))
        #expect(payload.contains(session.id))
        let legacy = ProviderPluginCookieSession(
            header: "session=secret-fixture",
            source: "Fixture",
            origin: "https://api.example.test")
        #expect(try legacy.json(opaque: false).contains("secret-fixture"))
    }

    @Test
    func `jar rejects invalid url session and caller controlled cookie headers`() throws {
        let jar = ProviderPluginCookieJar()
        let session = ProviderPluginCookieSession(
            header: "",
            source: "Fixture",
            origin: "https://api.example.test",
            records: [Self.record("session", value: "fixture", domain: "api.example.test", hostOnly: true)])
        jar.register(session)
        #expect(try jar
            .header(id: session.id, url: #require(URL(string: "https://api.example.test/usage"))) ==
            "session=fixture")
        for raw in [
            "http://api.example.test/usage",
            "https://api.example.test:444/usage",
            "https://user:pass@api.example.test/usage",
        ] {
            #expect(throws: Error.self) { try jar.header(id: session.id, url: #require(URL(string: raw))) }
        }
        #expect(throws: Error.self) {
            try jar.header(id: "unknown", url: #require(URL(string: "https://api.example.test/usage")))
        }

        var cookieOverride = try URLRequest(url: #require(URL(string: "https://api.example.test/usage")))
        cookieOverride.setValue("session=caller", forHTTPHeaderField: "Cookie")
        #expect(throws: ProviderPluginError.self) {
            try ProviderPluginCookieJar.authenticate(
                &cookieOverride,
                sessionID: session.id,
                required: true,
                jar: jar)
        }

        var hostOverride = try URLRequest(url: #require(URL(string: "https://api.example.test/usage")))
        hostOverride.setValue("api.example.test", forHTTPHeaderField: "Host")
        #expect(throws: ProviderPluginError.self) {
            try ProviderPluginCookieJar.authenticate(
                &hostOverride,
                sessionID: session.id,
                required: true,
                jar: jar)
        }
    }

    @Test
    func `same origin redirect reselects cookies for the new path`() throws {
        let jar = ProviderPluginCookieJar()
        let session = ProviderPluginCookieSession(
            header: "",
            source: "Fixture",
            origin: "https://api.example.test",
            records: [
                Self.record("api", value: "path", domain: "api.example.test", path: "/api", hostOnly: true),
                Self.record("root", value: "wide", domain: "api.example.test", hostOnly: true),
            ])
        jar.register(session)
        let delegate = ProviderPluginCookieTransport.CookieRedirectDelegate(jar: jar, id: session.id)
        let redirected = try URLRequest(url: #require(URL(string: "https://api.example.test/public")))
        let selected = try #require(try delegate.redirectedRequest(
            originalURL: #require(URL(string: "https://api.example.test/api/usage")),
            request: redirected))
        #expect(selected.value(forHTTPHeaderField: "Cookie") == "root=wide")
        #expect(try delegate.redirectedRequest(
            originalURL: #require(URL(string: "https://api.example.test/api/usage")),
            request: URLRequest(url: #require(URL(string: "https://other.example.test/public")))) == nil)
        #expect(try delegate.redirectedRequest(
            originalURL: #require(URL(string: "https://api.example.test/api/usage")),
            request: URLRequest(url: #require(URL(string: "http://api.example.test/public")))) == nil)
    }

    private static func record(
        _ name: String,
        value: String,
        domain: String,
        path: String = "/",
        hostOnly: Bool = false,
        secure: Bool = true,
        expires: Date? = nil) -> ProviderPluginCookieRecord
    {
        ProviderPluginCookieRecord(
            name: name,
            value: value,
            domain: domain,
            hostOnly: hostOnly,
            path: path,
            secure: secure,
            expires: expires)
    }
}
