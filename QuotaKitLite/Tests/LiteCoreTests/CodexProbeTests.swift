import Foundation
import LiteCore
import Testing

/// Probe behaviour (068 §4.2) against a stub transport and a temporary home. No network, no real credentials.
struct CodexProbeTests {
    private typealias Support = CodexTestSupport

    private static let now = Support.now
    private static let minimumDelay = CodexProbe.minimumRateLimitDelay

    /// CodexOAuthTests.swift, `maps usage windows from O auth`.
    private static let usageBody = """
    {
      "plan_type": "plus",
      "rate_limit": {
        "primary_window": { "used_percent": 22, "reset_at": 1766948068, "limit_window_seconds": 18000 },
        "secondary_window": { "used_percent": 43, "reset_at": 1767407914, "limit_window_seconds": 604800 }
      }
    }
    """

    private static func idToken(email: String = "person@example.com") -> String {
        Support.jwt(#"{"email":"\#(email)"}"#)
    }

    /// A home whose `~/.codex/auth.json` holds `accessToken`, and a probe wired to the given steps.
    private static func makeProbe(
        accessToken: String = Support.accessToken(),
        steps: [StubTransport.Step],
        beforeSend: @escaping @Sendable (Int) -> Void = { _ in }) throws
        -> (probe: CodexProbe, transport: StubTransport, home: Support.Home)
    {
        let home = try Support.Home()
        try home.writeAuth(Support.authJSON(accessToken: accessToken, idToken: self.idToken()))
        let transport = StubTransport(steps, beforeSend: beforeSend)
        return (CodexProbe(transport: transport, authReader: home.reader()), transport, home)
    }

    // MARK: - Success

    @Test
    func `a 200 returns the mapped windows, plan, email and identities`() async throws {
        let (probe, transport, home) = try Self.makeProbe(steps: [StubTransport.respond(200, body: Self.usageBody)])
        defer { home.remove() }

        let result = try await probe.fetch(now: Self.now).get()

        #expect(result.windows.map(\.lane) == [.session, .weekly])
        #expect(result.windows.map(\.usedPercent) == [22, 43])
        #expect(result.plan == "Plus")
        #expect(result.accountEmail == "person@example.com")
        #expect(result.accountIdentities == ["codex:account:account-123", "codex:email:person@example.com"])
        #expect(await transport.requestCount == 1)
    }

    @Test
    func `the request carries the bearer token, account ID and the same headers as the full app`() async throws {
        let token = Support.accessToken()
        let (probe, transport, home) = try Self.makeProbe(
            accessToken: token,
            steps: [StubTransport.respond(200, body: Self.usageBody)])
        defer { home.remove() }

        _ = await probe.fetch(now: Self.now)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "account-123")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "QuotaKit")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test
    func `the account ID header is omitted when auth json has no account`() async throws {
        let home = try Support.Home()
        defer { home.remove() }
        try home.writeAuth(Support.authJSON(accessToken: Support.accessToken(), accountID: nil))
        let transport = StubTransport([StubTransport.respond(200, body: Self.usageBody)])

        _ = await CodexProbe(transport: transport, authReader: home.reader()).fetch(now: Self.now)

        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil)
    }

    @Test
    func `an unrecognised 200 body is an unrecognized response and is not retried`() async throws {
        let (probe, transport, home) = try Self.makeProbe(steps: [StubTransport.respond(200, body: "<html></html>")])
        defer { home.remove() }

        #expect(await probe.fetch(now: Self.now) == .failure(.unrecognizedResponse))
        #expect(await transport.requestCount == 1)
    }

    // MARK: - Expired and missing credentials

    @Test
    func `an expired token returns tokenExpired without making any request`() async throws {
        let expired = Support.accessToken(exp: Int(Self.now.timeIntervalSince1970) - 1)
        let (probe, transport, home) = try Self.makeProbe(
            accessToken: expired,
            steps: [StubTransport.respond(200, body: Self.usageBody)])
        defer { home.remove() }

        #expect(await probe.fetch(now: Self.now) == .failure(.tokenExpired))
        #expect(await transport.requestCount == 0)
    }

    @Test
    func `a token that expires later is used until its exp`() async throws {
        let exp = Int(Self.now.timeIntervalSince1970) + 60
        let (probe, transport, home) = try Self.makeProbe(
            accessToken: Support.accessToken(exp: exp),
            steps: [StubTransport.respond(200, body: Self.usageBody)])
        defer { home.remove() }

        #expect(await (try? probe.fetch(now: Self.now).get()) != nil)
        #expect(await transport.requestCount == 1)
        #expect(await probe.fetch(now: Date(timeIntervalSince1970: TimeInterval(exp))) == .failure(.tokenExpired))
        #expect(await transport.requestCount == 1)
    }

    @Test
    func `a missing auth file or an API key only file means sign in and makes no request`() async throws {
        let home = try Support.Home()
        defer { home.remove() }
        let transport = StubTransport([])
        let probe = CodexProbe(transport: transport, authReader: home.reader())

        #expect(await probe.fetch(now: Self.now) == .failure(.signInRequired))

        try home.writeAuth(#"{ "OPENAI_API_KEY": "sk-test" }"#)
        #expect(await probe.fetch(now: Self.now) == .failure(.signInRequired))
        #expect(await transport.requestCount == 0)
    }

    @Test
    func `an unreadable auth file is tokenUnavailable and makes no request`() async throws {
        let home = try Support.Home()
        defer { home.remove() }
        try home.writeAuth("{ truncated")
        let transport = StubTransport([])

        let result = await CodexProbe(transport: transport, authReader: home.reader()).fetch(now: Self.now)

        #expect(result == .failure(.tokenUnavailable))
        #expect(await transport.requestCount == 0)
    }

    // MARK: - 401

    @Test
    func `a 401 with an unchanged auth file is signInRequired after one request`() async throws {
        let (probe, transport, home) = try Self.makeProbe(steps: [
            StubTransport.respond(401),
            StubTransport.respond(200, body: Self.usageBody),
        ])
        defer { home.remove() }

        #expect(await probe.fetch(now: Self.now) == .failure(.signInRequired))
        #expect(await transport.requestCount == 1)
    }

    @Test
    func `a 401 retries once with the new token when the CLI refreshed auth json`() async throws {
        let home = try Support.Home()
        defer { home.remove() }
        let oldToken = Support.accessToken(exp: Support.farFutureExp)
        let newToken = Support.accessToken(exp: Support.farFutureExp + 1)
        try home.writeAuth(Support.authJSON(accessToken: oldToken, idToken: Self.idToken()))
        let newJSON = Support.authJSON(accessToken: newToken, idToken: Self.idToken())
        let transport = StubTransport(
            [StubTransport.respond(401), StubTransport.respond(200, body: Self.usageBody)],
            beforeSend: { call in
                // The CLI refreshes while the first request is in flight.
                if call == 1 { try? home.writeAuth(newJSON) }
            })

        let result = await CodexProbe(transport: transport, authReader: home.reader()).fetch(now: Self.now)

        #expect(try result.get().windows.count == 2)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == [
            "Bearer \(oldToken)",
            "Bearer \(newToken)",
        ])
    }

    @Test
    func `a second 401 after the retry is signInRequired and does not loop`() async throws {
        let home = try Support.Home()
        defer { home.remove() }
        let newJSON = Support.authJSON(
            accessToken: Support.accessToken(exp: Support.farFutureExp + 1),
            idToken: Self.idToken())
        try home.writeAuth(Support.authJSON(accessToken: Support.accessToken(), idToken: Self.idToken()))
        let transport = StubTransport(
            [StubTransport.respond(401), StubTransport.respond(401), StubTransport.respond(200, body: Self.usageBody)],
            beforeSend: { call in
                if call == 1 { try? home.writeAuth(newJSON) }
            })

        let result = await CodexProbe(transport: transport, authReader: home.reader()).fetch(now: Self.now)

        #expect(result == .failure(.signInRequired))
        #expect(await transport.requestCount == 2)
    }

    @Test
    func `a 401 whose refreshed token is already expired is tokenExpired without a second request`() async throws {
        let home = try Support.Home()
        defer { home.remove() }
        let expiredJSON = Support.authJSON(
            accessToken: Support.accessToken(exp: Int(Self.now.timeIntervalSince1970) - 10),
            idToken: Self.idToken())
        try home.writeAuth(Support.authJSON(accessToken: Support.accessToken(), idToken: Self.idToken()))
        let transport = StubTransport(
            [StubTransport.respond(401), StubTransport.respond(200, body: Self.usageBody)],
            beforeSend: { call in
                if call == 1 { try? home.writeAuth(expiredJSON) }
            })

        let result = await CodexProbe(transport: transport, authReader: home.reader()).fetch(now: Self.now)

        #expect(result == .failure(.tokenExpired))
        #expect(await transport.requestCount == 1)
    }

    @Test
    func `a 401 followed by a missing auth file is signInRequired`() async throws {
        let home = try Support.Home()
        defer { home.remove() }
        try home.writeAuth(Support.authJSON(accessToken: Support.accessToken()))
        let transport = StubTransport(
            [StubTransport.respond(401), StubTransport.respond(200, body: Self.usageBody)],
            beforeSend: { call in
                if call == 1 { try? FileManager.default.removeItem(at: home.defaultCodexHome) }
            })

        let result = await CodexProbe(transport: transport, authReader: home.reader()).fetch(now: Self.now)

        #expect(result == .failure(.signInRequired))
        #expect(await transport.requestCount == 1)
    }

    // MARK: - 429

    @Test
    func `a 429 without Retry-After waits the 5 minute minimum`() async throws {
        let (probe, transport, home) = try Self.makeProbe(steps: [StubTransport.respond(429)])
        defer { home.remove() }

        #expect(await probe.fetch(now: Self.now) == .failure(.rateLimited(until: Self.now.addingTimeInterval(300))))
        #expect(await transport.requestCount == 1)
    }

    @Test
    func `a 429 with a short Retry-After still waits 5 minutes`() async throws {
        let (probe, _, home) = try Self.makeProbe(steps: [StubTransport.respond(429, headers: ["Retry-After": "30"])])
        defer { home.remove() }

        #expect(await probe.fetch(now: Self.now) == .failure(.rateLimited(until: Self.now.addingTimeInterval(300))))
    }

    @Test
    func `a 429 with a long Retry-After in seconds honours it`() async throws {
        let (probe, _, home) = try Self.makeProbe(steps: [StubTransport.respond(429, headers: ["Retry-After": "1800"])])
        defer { home.remove() }

        #expect(await probe.fetch(now: Self.now) == .failure(.rateLimited(until: Self.now.addingTimeInterval(1800))))
    }

    @Test
    func `a 429 with a Retry-After HTTP date honours it`() async throws {
        // 2026-10-11 13:00:00 GMT is one hour after `now`.
        let header = "Sun, 11 Oct 2026 13:00:00 GMT"
        let (probe, _, home) = try Self.makeProbe(steps: [StubTransport.respond(429, headers: ["Retry-After": header])])
        defer { home.remove() }

        #expect(await probe.fetch(now: Self.now) == .failure(.rateLimited(until: Self.now.addingTimeInterval(3600))))
    }

    @Test
    func `a 429 with an unparseable or negative Retry-After falls back to 5 minutes`() async throws {
        for header in ["soon", "-10", "", "nan"] {
            let (probe, _, home) = try Self.makeProbe(steps: [StubTransport.respond(
                429,
                headers: ["Retry-After": header])])
            defer { home.remove() }

            #expect(
                await probe.fetch(now: Self.now) == .failure(.rateLimited(until: Self.now.addingTimeInterval(300))),
                "\(header)")
        }
    }

    // MARK: - 5xx, other statuses, transport errors

    @Test
    func `5xx and unexpected statuses are server errors with the status code`() async throws {
        for status in [500, 502, 503, 504, 403, 404, 302] {
            let (probe, transport, home) = try Self.makeProbe(steps: [StubTransport.respond(status)])
            defer { home.remove() }

            #expect(await probe.fetch(now: Self.now) == .failure(.server(statusCode: status)), "\(status)")
            #expect(await transport.requestCount == 1)
        }
    }

    @Test
    func `a transport error is a network failure and is not retried`() async throws {
        let (probe, transport, home) = try Self.makeProbe(steps: [
            .fail(.notConnectedToInternet),
            StubTransport.respond(200, body: Self.usageBody),
        ])
        defer { home.remove() }

        let result = await probe.fetch(now: Self.now)

        guard case let .failure(.network(message)) = result else {
            Issue.record("Expected a network failure, got \(result)")
            return
        }
        #expect(!message.isEmpty)
        #expect(await transport.requestCount == 1)
    }

    @Test
    func `a timeout is a network failure`() async throws {
        let (probe, _, home) = try Self.makeProbe(steps: [.fail(.timedOut)])
        defer { home.remove() }

        guard case .failure(.network) = await probe.fetch(now: Self.now) else {
            Issue.record("Expected a network failure")
            return
        }
    }

    // MARK: - Misc

    @Test
    func `the probe exposes the auth file the scheduler should watch`() throws {
        let home = try Support.Home()
        defer { home.remove() }
        let probe = CodexProbe(transport: StubTransport([]), authReader: home.reader())

        #expect(probe.authFileURL.lastPathComponent == "auth.json")
        #expect(probe.authFileURL.deletingLastPathComponent().lastPathComponent == ".codex")
    }
}
