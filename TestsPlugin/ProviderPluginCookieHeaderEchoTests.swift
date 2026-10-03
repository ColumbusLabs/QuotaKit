import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct ProviderPluginCookieHeaderEchoTests {
    @Test(arguments: BundledPluginTestSupport.engines)
    func `host echoes selected session cookie without exposing cookie records`(
        engine: ProviderPluginEngineKind) async throws
    {
        let runtime = try Self.runtime(engine: engine, script: """
        for await (const session of ctx.browser.sessions('example.test')) {
          if (session.header !== undefined || session.records !== undefined) throw new Error('cookie exposed');
          await ctx.http.get('https://example.test/api', {cookieSession: session.id});
          return {empty:true};
        }
        """, transport: ProviderHTTPTransportHandler { request in
            #expect(request.value(forHTTPHeaderField: "X-Console-Csrf") == "synthetic-csrf")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "csrf=synthetic-csrf; session=fixture")
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data("{}".utf8), response)
        })
        let records = [
            Self.record("session", "fixture"),
            Self.record("csrf", "synthetic-csrf"),
        ]
        _ = try await runtime.fetchUsage(cookieSessionResolver: { _, _ in
            ProviderPluginCookieSession(
                header: "", source: "Synthetic", origin: "https://example.test", records: records)
        })
    }

    @Test(arguments: [
        "{origin:'https://other.test',cookie:'csrf',header:'X-Csrf'}",
        "{origin:'http://example.test',cookie:'csrf',header:'X-Csrf'}",
        "{origin:'https://example.test:444',cookie:'csrf',header:'X-Csrf'}",
        "{origin:'https://example.test/api',cookie:'csrf',header:'X-Csrf'}",
        "{origin:'https://example.test',cookie:'undeclared',header:'X-Csrf'}",
        "{origin:'https://example.test',cookie:'csrf',header:'Cookie'}",
        "{origin:'https://example.test',cookie:'csrf',header:'Host'}",
        "{origin:'https://example.test',cookie:'csrf',header:'Authorization'}",
        "{origin:'https://example.test',cookie:'csrf',header:'X-Csrf',extra:true}",
    ], BundledPluginTestSupport.engines)
    func `echo authority rejects undeclared origins cookies and unsafe headers`(
        echo: String, engine: ProviderPluginEngineKind)
    {
        #expect(throws: ProviderPluginError.self) {
            try ProviderPluginRuntime(source: """
            defineProvider({id:'longcat',name:'Synthetic',settings:[],endpoints:['https://example.test'],
              capabilities:['browser-cookies'],cookieDomains:['example.test'],
              cookiePolicy:{selection:'request-url',cache:'nonpersistent',requiredCookies:['csrf'],headerEcho:\(echo)},
              async fetchUsage(){return {empty:true}}});
            """, engine: engine)
        }
    }

    @Test(arguments: [
        [ProviderPluginCookieRecord(name: "session", value: "fixture", domain: "example.test", hostOnly: true,
            path: "/", secure: true, expires: nil)],
        [ProviderPluginCookieRecord(name: "csrf", value: "one", domain: "example.test", hostOnly: true,
            path: "/", secure: true, expires: nil),
         ProviderPluginCookieRecord(name: "csrf", value: "two", domain: "example.test", hostOnly: true,
            path: "/", secure: true, expires: nil)],
        [ProviderPluginCookieRecord(name: "csrf", value: "", domain: "example.test", hostOnly: true,
            path: "/", secure: true, expires: nil)],
    ], BundledPluginTestSupport.engines)
    func `missing ambiguous and empty echo cookies fail before transport`(
        records: [ProviderPluginCookieRecord], engine: ProviderPluginEngineKind) async throws
    {
        let runtime = try Self.runtime(engine: engine, script: """
        for await (const session of ctx.browser.sessions('example.test')) {
          await ctx.http.get('https://example.test/api', {cookieSession:session.id});
          return {empty:true};
        }
        """, transport: Self.deniedTransport)
        await #expect(throws: (any Error).self) {
            try await runtime.fetchUsage(cookieSessionResolver: { _, _ in
                ProviderPluginCookieSession(
                    header: "", source: "Synthetic", origin: "https://example.test", records: records)
            })
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `scripts cannot override the host echo header`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try Self.runtime(engine: engine, script: """
        for await (const session of ctx.browser.sessions('example.test')) {
          await ctx.http.get('https://example.test/api', {
            cookieSession:session.id, headers:{'x-console-csrf':'forged'}
          });
          return {empty:true};
        }
        """, transport: Self.deniedTransport)
        await #expect(throws: (any Error).self) {
            try await runtime.fetchUsage(cookieSessionResolver: { _, _ in Self.session() })
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `echo is omitted for another declared origin`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try Self.runtime(engine: engine, script: """
        for await (const session of ctx.browser.sessions('example.test')) {
          await ctx.http.get('https://other.test/api', {cookieSession:session.id});
          return {empty:true};
        }
        """, transport: ProviderHTTPTransportHandler { request in
            #expect(request.value(forHTTPHeaderField: "X-Console-Csrf") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == "csrf=other-fixture")
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data("{}".utf8), response)
        })
        let records = [
            Self.record("session", "fixture"),
            Self.record("csrf", "other-fixture", domain: "other.test"),
        ]
        _ = try await runtime.fetchUsage(cookieSessionResolver: { _, _ in
            ProviderPluginCookieSession(
                header: "", source: "Synthetic", origin: "https://example.test", records: records)
        })
    }

    @Test
    func `redirects reselect echo and do not retain it outside cookie scope`() throws {
        let runtime = try Self.runtime(engine: .quickJS, script: "return {empty:true};", transport: Self.deniedTransport)
        let jar = ProviderPluginCookieJar(headerEcho: runtime.manifest.cookiePolicy?.headerEcho)
        let session = ProviderPluginCookieSession(
            header: "", source: "Synthetic", origin: "https://example.test", records: [
                Self.record("session", "fixture"), Self.record("csrf", "synthetic-csrf", path: "/api"),
            ])
        jar.register(session)
        let delegate = ProviderPluginCookieTransport.CookieRedirectDelegate(jar: jar, id: session.id)
        let origin = try #require(URL(string: "https://example.test/api/one"))
        for (target, allowed) in [("https://example.test/api/two", true), ("https://example.test/elsewhere", false)] {
            let url = try #require(URL(string: target))
            var request = URLRequest(url: url)
            request.setValue("stale", forHTTPHeaderField: "X-Console-Csrf")
            let redirected = delegate.redirectedRequest(originalURL: origin, request: request)
            #expect((redirected != nil) == allowed)
            if allowed { #expect(redirected?.value(forHTTPHeaderField: "X-Console-Csrf") == "synthetic-csrf") }
        }
    }

    private static let deniedTransport = ProviderHTTPTransportHandler { _ in
        Issue.record("Denied echo request reached transport")
        throw URLError(.badURL)
    }

    private static func record(
        _ name: String, _ value: String, domain: String = "example.test", path: String = "/")
        -> ProviderPluginCookieRecord
    {
        ProviderPluginCookieRecord(
            name: name, value: value, domain: domain, hostOnly: true, path: path, secure: true, expires: nil)
    }

    private static func session() -> ProviderPluginCookieSession {
        ProviderPluginCookieSession(
            header: "", source: "Synthetic", origin: "https://example.test", records: [
                Self.record("session", "fixture"), Self.record("csrf", "synthetic-csrf"),
            ])
    }

    private static func runtime(
        engine: ProviderPluginEngineKind,
        script: String,
        transport: any ProviderHTTPTransport) throws -> ProviderPluginRuntime
    {
        try ProviderPluginRuntime(source: """
        defineProvider({id:'longcat',name:'Synthetic',settings:[],
          endpoints:['https://example.test','https://other.test'],
          capabilities:['browser-cookies'],cookieDomains:['example.test','other.test'],
          cookiePolicy:{selection:'request-url',cache:'nonpersistent',requiredCookies:['csrf'],
            headerEcho:{origin:'https://example.test',cookie:'csrf',header:'X-Console-Csrf'}},
          async fetchUsage(ctx){\(script)}});
        """, transport: transport, engine: engine)
    }
}
