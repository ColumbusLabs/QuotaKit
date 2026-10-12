import Foundation
import LiteCore
import Testing

struct ClaudeProbeTests {
    private static let now = ClaudeFixtures.now

    private static func authorization(_ request: URLRequest) -> String? {
        request.value(forHTTPHeaderField: "Authorization")
    }

    @Test
    func `a successful fetch returns windows, plan and identity`() async throws {
        let transport = ClaudeStubTransport()
        let probe = ClaudeSeams().makeProbe(transport: transport)

        let result = try await probe.fetch(now: Self.now).get()

        #expect(result.windows.map(\.label) == ["Session", "Weekly", "Sonnet"])
        #expect(result.windows.map(\.usedPercent) == [12.5, 30, 5])
        #expect(result.plan == "Claude Max 20x")
        #expect(result.accountEmail == "user@example.com")
        #expect(result.accountIdentities == ["claude:email:user@example.com"])
    }

    @Test
    func `the usage request matches the full app on the wire`() async throws {
        let transport = ClaudeStubTransport()
        _ = await ClaudeSeams().makeProbe(transport: transport).fetch(now: Self.now)

        // Expectations from the full app's `ClaudeOAuthResetCreditsTests.swift`
        // (`OAuth requests reset inventory without suppressing spend or changing authentication`).
        let request = try #require(transport.usageRequests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage?cedar_ember=1")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer keychain-token")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "claude-cli/2.1.0 (external, cli)")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.timeoutInterval == 30)

        // `ClaudeOAuthTests.swift` (`O auth profile request decodes nested account identity`).
        let profile = try #require(transport.profileRequests.first)
        #expect(profile.url?.absoluteString == "https://api.anthropic.com/api/oauth/profile")
        #expect(profile.httpMethod == "GET")
        #expect(profile.value(forHTTPHeaderField: "Authorization") == "Bearer keychain-token")
        #expect(profile.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(profile.value(forHTTPHeaderField: "anthropic-beta") == nil)
    }

    @Test
    func `an expired token fails without any request`() async {
        var seams = ClaudeSeams()
        seams.secret = StubKeychainSecret(token: "expired-token", expiresAt: ClaudeFixtures.past)
        let transport = ClaudeStubTransport()

        let result = await seams.makeProbe(transport: transport).fetch(now: Self.now)

        #expect(result == .failure(.tokenExpired))
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: [
        (400, "{}"),
        (403, #"{"error":"inventory not allowed"}"#),
    ])
    func `400 or a 403 without user profile retries once without cedar_ember`(status: Int, body: String) async throws {
        let transport = ClaudeStubTransport { request in
            if request.url?.path == "/api/oauth/profile" {
                return .http(status: 200, body: ClaudeFixtures.profileJSON)
            }
            return request.url?.query == nil
                ? .http(status: 200, body: ClaudeFixtures.usageJSON)
                : .http(status: status, body: body)
        }

        let result = try await ClaudeSeams().makeProbe(transport: transport).fetch(now: Self.now).get()

        #expect(result.windows.count == 3)
        // `ClaudeOAuthResetCreditsTests.swift`
        // (`unsupported inventory query retries once with legacy identity and retains ordinary usage`).
        let usage = transport.usageRequests
        #expect(usage.map { $0.url?.query } == ["cedar_ember=1", nil])
        #expect(usage.map { $0.value(forHTTPHeaderField: "User-Agent") } == [
            "claude-cli/2.1.0 (external, cli)",
            "claude-code/2.1.0",
        ])
        #expect(usage.allSatisfy {
            Self.authorization($0) == "Bearer keychain-token"
                && $0.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20"
        })
    }

    @Test
    func `a failed retry reports its own status`() async {
        let transport = ClaudeStubTransport(usage: .http(status: 403, body: #"{"error":"forbidden"}"#))

        let result = await ClaudeSeams().makeProbe(transport: transport).fetch(now: Self.now)

        #expect(result == .failure(.server(statusCode: 403)))
        #expect(transport.usageRequests.count == 2)
    }

    @Test
    func `a 403 mentioning user profile is a scope error and is not retried`() async {
        // The body from the full app's `ClaudeOAuthTests.swift` (`includes body in O auth403 error`).
        let body = "HTTP 403: OAuth token does not meet scope requirement user:profile"
        let transport = ClaudeStubTransport(usage: .http(status: 403, body: body))

        let result = await ClaudeSeams().makeProbe(transport: transport).fetch(now: Self.now)

        #expect(result == .failure(.signInRequired))
        #expect(transport.requests.count == 1)
    }

    @Test
    func `a 401 re-resolves once and retries with the new token`() async throws {
        var seams = ClaudeSeams()
        seams.secret = StubKeychainSecret([
            .success(ClaudeFixtures.credentialsJSON(token: "revoked-token")),
            .success(ClaudeFixtures.credentialsJSON(token: "fresh-token")),
        ])
        let metadata = seams.metadata
        let transport = ClaudeStubTransport { request in
            if request.url?.path == "/api/oauth/profile" {
                return .http(status: 200, body: ClaudeFixtures.profileJSON)
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer revoked-token" {
                // Claude Code has since rewritten its item with a new token.
                metadata.state = .found(modifiedAt: Date(timeIntervalSince1970: 1_700_009_999))
                return .http(status: 401, body: #"{"error":"invalid token"}"#)
            }
            return .http(status: 200, body: ClaudeFixtures.usageJSON)
        }

        let result = try await seams.makeProbe(transport: transport).fetch(now: Self.now).get()

        #expect(result.windows.count == 3)
        #expect(transport.usageRequests.map(Self.authorization) == ["Bearer revoked-token", "Bearer fresh-token"])
        #expect(seams.cache.clears == 1)
        #expect(seams.secret.reads == 2)
    }

    @Test
    func `a 401 with no newer token is sign in required after one request`() async {
        let seams = ClaudeSeams()
        let transport = ClaudeStubTransport(usage: .http(status: 401, body: "{}"))

        let result = await seams.makeProbe(transport: transport).fetch(now: Self.now)

        #expect(result == .failure(.signInRequired))
        #expect(transport.requests.count == 1)
        #expect(seams.secret.reads == 1)
    }

    @Test
    func `a 401 on the retried token is sign in required`() async {
        var seams = ClaudeSeams()
        seams.secret = StubKeychainSecret([
            .success(ClaudeFixtures.credentialsJSON(token: "first-token")),
            .success(ClaudeFixtures.credentialsJSON(token: "second-token")),
        ])
        let metadata = seams.metadata
        let transport = ClaudeStubTransport { _ in
            metadata.state = .found(modifiedAt: Date(timeIntervalSince1970: 1_700_009_999))
            return .http(status: 401, body: "{}")
        }

        let result = await seams.makeProbe(transport: transport).fetch(now: Self.now)

        #expect(result == .failure(.signInRequired))
        #expect(transport.usageRequests.map(Self.authorization) == ["Bearer first-token", "Bearer second-token"])
    }

    @Test
    func `a 429 blocks the token for at least five minutes without further requests`() async {
        let transport = ClaudeStubTransport(usage: .http(
            status: 429,
            body: #"{"error":"rate_limit_error"}"#,
            headers: ["Retry-After": "60"]))
        let probe = ClaudeSeams().makeProbe(transport: transport)
        let until = Self.now.addingTimeInterval(300)

        #expect(await probe.fetch(now: Self.now) == .failure(.rateLimited(until: until)))
        #expect(transport.requests.count == 1)

        // Same token, still blocked: no request at all.
        #expect(await probe.fetch(now: Self.now.addingTimeInterval(120)) == .failure(.rateLimited(until: until)))
        #expect(transport.requests.count == 1)

        // After the block the probe asks again.
        _ = await probe.fetch(now: until)
        #expect(transport.requests.count == 2)
    }

    @Test
    func `a long Retry-After is honoured, in seconds or as an HTTP date`() async {
        let seconds = ClaudeStubTransport(usage: .http(status: 429, body: "{}", headers: ["Retry-After": "900"]))
        #expect(
            await ClaudeSeams().makeProbe(transport: seconds).fetch(now: Self.now)
                == .failure(.rateLimited(until: Self.now.addingTimeInterval(900))))

        // 1_800_000_000 is Fri, 15 Jan 2027 08:00:00 GMT; an hour later:
        let date = ClaudeStubTransport(usage: .http(
            status: 429,
            body: "{}",
            headers: ["Retry-After": "Fri, 15 Jan 2027 09:00:00 GMT"]))
        #expect(
            await ClaudeSeams().makeProbe(transport: date).fetch(now: Self.now)
                == .failure(.rateLimited(until: Self.now.addingTimeInterval(3600))))
    }

    @Test
    func `server and network failures are reported`() async {
        let server = ClaudeStubTransport(usage: .http(status: 503, body: "unavailable"))
        #expect(
            await ClaudeSeams().makeProbe(transport: server).fetch(now: Self.now)
                == .failure(.server(statusCode: 503)))
        #expect(server.requests.count == 1)

        let offline = ClaudeStubTransport(usage: .error(.notConnectedToInternet))
        let result = await ClaudeSeams().makeProbe(transport: offline).fetch(now: Self.now)
        guard case let .failure(.network(message)) = result else {
            Issue.record("Expected a network failure, got \(result)")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test
    func `an unrecognised body fails without a profile request`() async {
        let transport = ClaudeStubTransport(usage: .http(status: 200, body: #"{"something_new": {}}"#))

        #expect(await ClaudeSeams().makeProbe(transport: transport).fetch(now: Self.now) == .failure(
            .unrecognizedResponse))
        #expect(transport.profileRequests.isEmpty)
    }

    @Test
    func `the profile is fetched once per token`() async throws {
        var seams = ClaudeSeams()
        seams.secret = StubKeychainSecret([
            .success(ClaudeFixtures.credentialsJSON(token: "token-a", expiresAt: Self.now.addingTimeInterval(600))),
            .success(ClaudeFixtures.credentialsJSON(token: "token-b")),
        ])
        let transport = ClaudeStubTransport()
        let probe = seams.makeProbe(transport: transport)

        _ = try await probe.fetch(now: Self.now).get()
        let second = try await probe.fetch(now: Self.now.addingTimeInterval(60)).get()
        #expect(transport.profileRequests.count == 1)
        #expect(transport.usageRequests.count == 2)
        #expect(second.accountIdentities == ["claude:email:user@example.com"])

        // token-a expires and Claude Code writes token-b: a new fingerprint, so one more profile request.
        seams.metadata.state = .found(modifiedAt: Date(timeIntervalSince1970: 1_700_009_999))
        _ = try await probe.fetch(now: Self.now.addingTimeInterval(700)).get()
        #expect(transport.profileRequests.map(Self.authorization) == ["Bearer token-a", "Bearer token-b"])
    }

    @Test
    func `a profile failure doesn't fail the fetch and is retried later`() async throws {
        let transport = ClaudeStubTransport { request in
            request.url?.path == "/api/oauth/profile"
                ? .http(status: 500, body: "oops")
                : .http(status: 200, body: ClaudeFixtures.usageJSON)
        }
        var seams = ClaudeSeams()
        seams.secret = StubKeychainSecret(token: "keychain-token", expiresAt: Self.now.addingTimeInterval(86400))
        let probe = seams.makeProbe(transport: transport)

        let result = try await probe.fetch(now: Self.now).get()
        #expect(result.windows.count == 3)
        #expect(result.accountEmail == nil)
        #expect(result.accountIdentities.isEmpty)

        _ = try await probe.fetch(now: Self.now.addingTimeInterval(60)).get()
        #expect(transport.profileRequests.count == 1)

        _ = try await probe.fetch(now: Self.now.addingTimeInterval(ClaudeProbe.profileRetryInterval)).get()
        #expect(transport.profileRequests.count == 2)
    }

    @Test
    func `concurrent fetches do not duplicate credential or profile work`() async {
        let seams = ClaudeSeams()
        let transport = ClaudeStubTransport()
        let probe = seams.makeProbe(transport: transport)

        async let first = probe.fetch(now: Self.now)
        async let second = probe.fetch(now: Self.now)
        let results = await [first, second]

        #expect(results.allSatisfy { (try? $0.get())?.windows.count == 3 })
        #expect(transport.usageRequests.count <= 2)
        #expect(transport.profileRequests.count == 1)
        #expect(seams.secret.reads == 1)
    }
}
