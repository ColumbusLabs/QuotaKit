import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)

@Suite(.serialized)
struct NotionSessionStoreTests {
    @Test
    func `session files are owner only and round trip`() async throws {
        let (directory, fileURL) = try Self.makeSessionLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = NotionSessionStore(fileURL: fileURL)
        await writer.setSession(tokenV2: "stored-token", sourceLabel: "Chrome")

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)

        let reader = NotionSessionStore(fileURL: fileURL)
        let session = try #require(await reader.getSession())
        #expect(session.tokenV2 == "stored-token")
        #expect(session.cookieHeader == "token_v2=stored-token")
        #expect(session.sourceLabel == "Chrome")
    }

    @Test
    func `loading repairs legacy session file permissions`() async throws {
        let (directory, fileURL) = try Self.makeSessionLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = NotionSessionStore(fileURL: fileURL)
        await writer.setSession(tokenV2: "legacy-token", sourceLabel: "Chrome")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)

        let reader = NotionSessionStore(fileURL: fileURL)
        #expect(await reader.getSession()?.tokenV2 == "legacy-token")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)
    }

    @Test
    func `separate store instances reject stale writes and rejection clears`() async throws {
        let (directory, fileURL) = try Self.makeSessionLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = NotionSessionStore(fileURL: fileURL)
        let second = NotionSessionStore(fileURL: fileURL)
        await first.setSession(tokenV2: "session-a", sourceLabel: "Fixture A")
        let observed = try await first.observe()
        await second.setSession(tokenV2: "session-b", sourceLabel: "Fixture B")

        #expect(try await first.clearSessionIfCurrent(observed, matchingTokenV2: "session-a") == false)
        #expect(await first.getSession()?.tokenV2 == "session-b")
    }

    @Test
    func `stale imported login cannot replace paired cookie and session state`() async throws {
        let (directory, fileURL) = try Self.makeSessionLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await Self.withIsolatedCookieCache {
            let first = NotionSessionStore(fileURL: fileURL)
            let second = NotionSessionStore(fileURL: fileURL)
            let sessionObservation = try await first.observe()
            let cookieObservation = CookieHeaderCache.observeForConditionalMutation(provider: .notion)
            await second.setSession(tokenV2: "session-b", sourceLabel: "Fixture B")

            let stored = try await first.setSessionIfCurrentAndStoreCookie(
                sessionObservation,
                tokenV2: "session-a",
                sourceLabel: "Fixture A",
                cookieObservation: cookieObservation,
                cookieHeader: "token_v2=session-a")
            #expect(!stored)
            #expect(await first.getSession()?.tokenV2 == "session-b")
            #expect(CookieHeaderCache.load(provider: .notion) == nil)
        }
    }

    @Test
    func `validated login stores sidecar and cookie as one conditional transaction`() async throws {
        let (directory, fileURL) = try Self.makeSessionLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await Self.withIsolatedCookieCache {
            let store = NotionSessionStore(fileURL: fileURL)
            let sessionObservation = try await store.observe()
            let cookieObservation = CookieHeaderCache.observeForConditionalMutation(provider: .notion)
            let stored = try await store.setSessionIfCurrentAndStoreCookie(
                sessionObservation,
                tokenV2: "synthetic-session",
                sourceLabel: "Fixture",
                cookieObservation: cookieObservation,
                cookieHeader: "token_v2=synthetic-session")
            #expect(stored)
            #expect(await store.getSession()?.tokenV2 == "synthetic-session")
            #expect(CookieHeaderCache.load(provider: .notion)?.cookieHeader == "token_v2=synthetic-session")
        }
    }

    private static func makeSessionLocation() throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-notion-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("notion-session.json"))
    }

    private static func withIsolatedCookieCache<T>(
        _ operation: () async throws -> T) async rethrows -> T
    {
        try await KeychainCacheStore.withServiceOverrideForTesting("notion-session-\(UUID().uuidString)") {
            let legacy = FileManager.default.temporaryDirectory
                .appendingPathComponent("notion-cookie-legacy-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: legacy) }
            return try await CookieHeaderCache.withLegacyBaseURLOverrideForTesting(legacy) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }
                return try await operation()
            }
        }
    }
}

#endif
