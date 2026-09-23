import Foundation
import Testing
@testable import CodexBarCore

enum CursorTransportSessionRoute: CaseIterable, Equatable, Sendable {
    case app
    case stored
}

@Suite(.serialized)
struct CursorTransportIdentityTests {
    @Test(arguments: [CursorTransportSessionRoute.app, .stored])
    func `resolved Cursor session errors preserve transport identity`(route: CursorTransportSessionRoute) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-transport-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let failure = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, userInfo: [
            NSLocalizedDescriptionKey: "fixture transport failure",
            "fixture-marker": "preserved",
        ])
        let outcome = try await KeychainCacheStore.withServiceOverrideForTesting("cursor-transport-identity") {
            try await KeychainCacheStore.withImplicitTestStoreForTesting {
                try await CookieHeaderCache.withLegacyBaseURLOverrideForTesting(root.appendingPathComponent("legacy")) {
                    CookieHeaderCache.clear(provider: .cursor)
                    defer { CookieHeaderCache.clear(provider: .cursor) }
                    let sessionStore = CursorSessionStore(fileURL: root.appendingPathComponent("cursor-session.json"))
                    let appSession: CursorAppAuthSession?
                    if route == .app {
                        appSession = try CursorAppAuthSession(accessToken: makeCursorAppAuthToken())
                    } else {
                        appSession = nil
                        let cookie = try #require(HTTPCookie(properties: [
                            .domain: "cursor-web.test",
                            .path: "/",
                            .name: "WorkosCursorSessionToken",
                            .value: "synthetic-session",
                        ]))
                        await sessionStore.setCookies([cookie])
                    }
                    let transport = ProviderHTTPTransportStub { request in
                        let url = try #require(request.url)
                        if url.path == "/api/usage-summary" { throw failure }
                        let response = try #require(HTTPURLResponse(
                            url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
                        return (Data("{}".utf8), response)
                    }
                    let probe = try CursorStatusProbe(
                        baseURL: #require(URL(string: "https://cursor-web.test")),
                        browserDetection: BrowserDetection(cacheTTL: 0),
                        browserCookieImportOrder: [],
                        urlSession: transport,
                        appAuthStore: CursorAppAuthSessionProviderStub(session: appSession),
                        sessionStore: sessionStore,
                        conditionalMutationCoordinator: CookieHeaderCache.ConditionalMutationCoordinator())
                    do {
                        _ = try await probe.fetch(
                            allowCachedSessions: route == .stored,
                            allowAppAuthFallback: route == .app)
                        Issue.record("Expected the injected Cursor transport failure")
                        return await (
                            NSError(domain: "missing-fixture-error", code: 1) as any Error,
                            transport.requests())
                    } catch {
                        await sessionStore.clearCookies()
                        return await (error as any Error, transport.requests())
                    }
                }
            }
        }

        let wrapped = outcome.0 as NSError
        #expect(wrapped.domain == NSURLErrorDomain)
        #expect(wrapped.code == NSURLErrorCannotFindHost)
        #expect(wrapped.userInfo["fixture-marker"] as? String == "preserved")
        #expect(wrapped.localizedDescription == "Cursor API error: fixture transport failure")
        let summaryRequest = try #require(outcome.1.first { $0.url?.path == "/api/usage-summary" })
        if route == .stored {
            #expect(summaryRequest.value(forHTTPHeaderField: "Cookie") ==
                "WorkosCursorSessionToken=synthetic-session")
        }
    }

    @Test(arguments: [CursorTransportSessionRoute.app, .stored])
    func `resolved Cursor task cancellation remains typed`(route: CursorTransportSessionRoute) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-transport-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = try await KeychainCacheStore.withServiceOverrideForTesting("cursor-transport-cancel") {
            try await KeychainCacheStore.withImplicitTestStoreForTesting {
                try await CookieHeaderCache.withLegacyBaseURLOverrideForTesting(root.appendingPathComponent("legacy")) {
                    CookieHeaderCache.clear(provider: .cursor)
                    defer { CookieHeaderCache.clear(provider: .cursor) }
                    let sessionStore = CursorSessionStore(fileURL: root.appendingPathComponent("cursor-session.json"))
                    let appSession: CursorAppAuthSession?
                    if route == .app {
                        appSession = try CursorAppAuthSession(accessToken: makeCursorAppAuthToken())
                    } else {
                        appSession = nil
                        let cookie = try #require(HTTPCookie(properties: [
                            .domain: "cursor-web.test",
                            .path: "/",
                            .name: "WorkosCursorSessionToken",
                            .value: "synthetic-session",
                        ]))
                        await sessionStore.setCookies([cookie])
                    }
                    let transport = ProviderHTTPTransportStub { request in
                        let url = try #require(request.url)
                        if url.path == "/api/usage-summary" { throw CancellationError() }
                        let response = try #require(HTTPURLResponse(
                            url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
                        return (Data("{}".utf8), response)
                    }
                    let probe = try CursorStatusProbe(
                        baseURL: #require(URL(string: "https://cursor-web.test")),
                        browserDetection: BrowserDetection(cacheTTL: 0),
                        browserCookieImportOrder: [],
                        urlSession: transport,
                        appAuthStore: CursorAppAuthSessionProviderStub(session: appSession),
                        sessionStore: sessionStore,
                        conditionalMutationCoordinator: CookieHeaderCache.ConditionalMutationCoordinator())
                    do {
                        _ = try await probe.fetch(
                            allowCachedSessions: route == .stored,
                            allowAppAuthFallback: route == .app)
                        Issue.record("Expected cancellation")
                        return NSError(domain: "missing-fixture-error", code: 1) as any Error
                    } catch {
                        await sessionStore.clearCookies()
                        return error as any Error
                    }
                }
            }
        }

        #expect(outcome is CancellationError)
    }
}
