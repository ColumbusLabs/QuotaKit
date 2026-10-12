import Foundation
import LiteCore
import Testing

struct ClaudeCredentialResolverTests {
    private static let dateA = Date(timeIntervalSince1970: 1_700_000_000)
    private static let dateB = Date(timeIntervalSince1970: 1_700_003_600)

    private static func token(_ outcome: ClaudeCredentialResolver.Outcome) -> String? {
        guard case let .credentials(credentials) = outcome else { return nil }
        return credentials.accessToken
    }

    @Test
    func `a live credentials file wins without touching the Keychain`() async {
        var seams = ClaudeSeams()
        seams.file = StubCredentialsFile(ClaudeFixtures.credentialsJSON(token: "file-token"))
        let resolver = seams.makeResolver()

        let outcome = await resolver.resolve(now: ClaudeFixtures.now)

        #expect(Self.token(outcome) == "file-token")
        #expect(seams.cache.loads == 0)
        #expect(seams.metadata.reads == 0)
        #expect(seams.secret.reads == 0)
    }

    @Test
    func `an expired credentials file falls through to the Keychain`() async {
        var seams = ClaudeSeams()
        seams.file = StubCredentialsFile(ClaudeFixtures.credentialsJSON(
            token: "stale-file-token",
            expiresAt: ClaudeFixtures.past))
        let resolver = seams.makeResolver()

        #expect(await Self.token(resolver.resolve(now: ClaudeFixtures.now)) == "keychain-token")
        #expect(seams.secret.reads == 1)
    }

    @Test
    func `Lite's cache is used and loaded from the Keychain only once`() async throws {
        var seams = ClaudeSeams()
        seams.cache = try await Self.cacheHolding(
            token: "cached-token",
            expiresAt: ClaudeFixtures.future,
            source: Self.dateA)
        let resolver = seams.makeResolver()

        #expect(await Self.token(resolver.resolve(now: ClaudeFixtures.now)) == "cached-token")
        #expect(await Self.token(resolver.resolve(now: ClaudeFixtures.now)) == "cached-token")
        #expect(seams.cache.loads == 1)
        #expect(seams.metadata.reads == 0)
        #expect(seams.secret.reads == 0)
    }

    @Test
    func `the secret is read only when the modification date changes`() async {
        var seams = ClaudeSeams()
        seams.metadata = StubKeychainMetadata(.found(modifiedAt: Self.dateA))
        seams.secret = StubKeychainSecret([
            .success(ClaudeFixtures.credentialsJSON(token: "old-token", expiresAt: ClaudeFixtures.past)),
            .success(ClaudeFixtures.credentialsJSON(token: "new-token")),
        ])
        let resolver = seams.makeResolver()

        // First read finds an expired token: no refresh, just `.tokenExpired`.
        #expect(await resolver.resolve(now: ClaudeFixtures.now) == .failure(.tokenExpired))
        #expect(seams.secret.reads == 1)

        // Same modification date: the change check runs, `security` doesn't.
        #expect(await resolver.resolve(now: ClaudeFixtures.now) == .failure(.tokenExpired))
        #expect(await resolver.resolve(now: ClaudeFixtures.now) == .failure(.tokenExpired))
        #expect(seams.metadata.reads == 3)
        #expect(seams.secret.reads == 1)

        // Claude Code refreshed and rewrote its item: exactly one more read.
        seams.metadata.state = .found(modifiedAt: Self.dateB)
        #expect(await Self.token(resolver.resolve(now: ClaudeFixtures.now)) == "new-token")
        #expect(seams.secret.reads == 2)

        // The new token is now served from memory.
        #expect(await Self.token(resolver.resolve(now: ClaudeFixtures.now)) == "new-token")
        #expect(seams.metadata.reads == 4)
        #expect(seams.secret.reads == 2)
    }

    @Test
    func `the fingerprint survives a relaunch through the cache`() async {
        var seams = ClaudeSeams()
        seams.metadata = StubKeychainMetadata(.found(modifiedAt: Self.dateA))
        seams.secret = StubKeychainSecret(token: "token", expiresAt: ClaudeFixtures.future)
        #expect(await Self.token(seams.makeResolver().resolve(now: ClaudeFixtures.now)) == "token")
        #expect(seams.secret.reads == 1)

        // A new resolver (a relaunch) with the same cache item, after the token expired and with the Keychain item
        // unchanged: no `security` run.
        let relaunched = seams.makeResolver()
        let later = ClaudeFixtures.future.addingTimeInterval(1)
        #expect(await relaunched.resolve(now: later) == .failure(.tokenExpired))
        #expect(seams.secret.reads == 1)
    }

    @Test
    func `the cache stores the read version but never the refresh token`() async throws {
        let seams = ClaudeSeams()
        _ = await seams.makeResolver().resolve(now: ClaudeFixtures.now)

        let stored = try String(data: #require(seams.cache.data), encoding: .utf8) ?? ""
        #expect(stored.contains("keychain-token"))
        #expect(!stored.contains("never-stored-refresh-token"))
    }

    @Test(arguments: [ClaudeSecretReadFailure.failed, .timedOut])
    func `a failed secret read is token unavailable and is not repeated`(failure: ClaudeSecretReadFailure) async {
        var seams = ClaudeSeams()
        seams.secret = StubKeychainSecret([.failure(failure)])
        let resolver = seams.makeResolver()

        #expect(await resolver.resolve(now: ClaudeFixtures.now) == .failure(.tokenUnavailable))
        #expect(await resolver.resolve(now: ClaudeFixtures.now) == .failure(.tokenUnavailable))
        #expect(seams.secret.reads == 1)
    }

    @Test
    func `unreadable secret payloads map to an actionable failure`() async {
        var garbage = ClaudeSeams()
        garbage.secret = StubKeychainSecret([.success(Data("not json".utf8))])
        #expect(await garbage.makeResolver().resolve(now: ClaudeFixtures.now) == .failure(.tokenUnavailable))

        var mcpOnly = ClaudeSeams()
        mcpOnly.secret = StubKeychainSecret([.success(Data(#"{"mcpOAuth":{"craft":{"accessToken":""}}}"#.utf8))])
        #expect(await mcpOnly.makeResolver().resolve(now: ClaudeFixtures.now) == .failure(.signInRequired))
    }

    @Test
    func `missing or unreadable Keychain metadata never runs security`() async {
        var notFound = ClaudeSeams()
        notFound.metadata = StubKeychainMetadata(.notFound)
        #expect(await notFound.makeResolver().resolve(now: ClaudeFixtures.now) == .failure(.signInRequired))
        #expect(notFound.secret.reads == 0)

        var unavailable = ClaudeSeams()
        unavailable.metadata = StubKeychainMetadata(.unavailable)
        #expect(await unavailable.makeResolver().resolve(now: ClaudeFixtures.now) == .failure(.tokenUnavailable))
        #expect(unavailable.secret.reads == 0)
    }

    @Test
    func `an undated item is read once per launch`() async {
        var seams = ClaudeSeams()
        seams.metadata = StubKeychainMetadata(.found(modifiedAt: nil))
        seams.secret = StubKeychainSecret(token: "token", expiresAt: ClaudeFixtures.past)
        let resolver = seams.makeResolver()

        #expect(await resolver.resolve(now: ClaudeFixtures.now) == .failure(.tokenExpired))
        #expect(await resolver.resolve(now: ClaudeFixtures.now) == .failure(.tokenExpired))
        #expect(seams.secret.reads == 1)
    }

    @Test
    func `invalidating clears the cache but keeps the fingerprint`() async {
        let seams = ClaudeSeams()
        let resolver = seams.makeResolver()
        #expect(await Self.token(resolver.resolve(now: ClaudeFixtures.now)) == "keychain-token")

        await resolver.invalidateCachedToken()

        #expect(seams.cache.clears == 1)
        #expect(seams.cache.data == nil)
        // The Keychain item hasn't changed, so there's no new token to read.
        #expect(await resolver.resolve(now: ClaudeFixtures.now) == .failure(.signInRequired))
        #expect(seams.secret.reads == 1)
    }

    /// Fills a stub cache the way the resolver does, by resolving once against stub Keychain seams.
    private static func cacheHolding(token: String, expiresAt: Date, source: Date) async throws -> StubTokenCache {
        var seams = ClaudeSeams()
        seams.metadata = StubKeychainMetadata(.found(modifiedAt: source))
        seams.secret = StubKeychainSecret(token: token, expiresAt: expiresAt)
        _ = await seams.makeResolver().resolve(now: ClaudeFixtures.now)
        let data = try #require(seams.cache.data)
        return StubTokenCache(data)
    }
}
