import Foundation
import Testing
@testable import LiteCore

struct AntigravityParserTests {
    static let summary = """
    {
      "response": {
        "groups": [
          {
            "displayName": "Claude and GPT Models",
            "buckets": [
              { "bucketId": "3p-weekly", "displayName": "Weekly Limit", "remainingFraction": 0.33,
                "resetTime": "2026-10-15T09:00:00Z" },
              { "bucketId": "3p-5h", "displayName": "5h Limit", "remainingFraction": 0.7 }
            ]
          },
          {
            "displayName": "Gemini Models",
            "buckets": [
              { "bucketId": "gemini-5h", "displayName": "5h Limit",
                "remaining": { "case": "remainingFraction", "value": 0.12 } },
              { "bucketId": "gemini-weekly", "displayName": "Weekly Limit", "remainingFraction": 0.48 },
              { "bucketId": "gemini-extra", "displayName": "Bonus", "remainingFraction": 0.9 },
              { "bucketId": "gemini-off", "displayName": "Weekly", "window": "weekly", "disabled": true,
                "remainingFraction": 1 }
            ]
          }
        ]
      }
    }
    """

    @Test
    func `buckets become windows with the full app's labels, Gemini first and session before weekly`() throws {
        let windows = try AntigravityParser.quotaWindows(from: Data(Self.summary.utf8))

        #expect(windows.map(\.label) == ["Gemini 5-hour", "Gemini weekly", "Claude/GPT 5-hour", "Claude/GPT weekly"])
        #expect(windows.map(\.lane) == [.session, .weekly, .session, .weekly])
        #expect(windows.map(\.windowMinutes) == [300, 10080, 300, 10080])
        #expect(abs(windows[0].usedPercent - 88) < 0.001)
        #expect(windows[3].resetsAt == ISO8601DateFormatter().date(from: "2026-10-15T09:00:00Z"))
    }

    @Test
    func `an explicit window classifies an opaque bucket`() throws {
        let json = """
        {"groups": [{"displayName": "Gemini Models", "buckets": [
          {"bucketId": "opaque-capacity-17", "displayName": "Generation capacity", "window": "weekly",
           "remaining": {"remainingFraction": 0.75}}]}]}
        """
        let windows = try AntigravityParser.quotaWindows(from: Data(json.utf8))

        #expect(windows.map(\.label) == ["Gemini weekly"])
        #expect(windows.first?.remainingPercent == 75)
    }

    @Test(arguments: ["{}", "not json", #"{"code": 7, "groups": []}"#, #"{"groups": [{"buckets": []}]}"#])
    func `unusable responses are unrecognized`(body: String) {
        #expect(throws: ProbeFailure.unrecognizedResponse) {
            try AntigravityParser.quotaWindows(from: Data(body.utf8))
        }
    }

    @Test
    func `the identity prefers the user tier over plan info`() {
        let json = """
        {"userStatus": {"email": "me@example.com", "userTier": {"name": "Ultra"},
          "planStatus": {"planInfo": {"planDisplayName": "Pro"}}}}
        """
        let identity = AntigravityParser.identity(from: Data(json.utf8))

        #expect(identity.email == "me@example.com")
        #expect(identity.plan == "Ultra")
        #expect(AntigravityParser
            .identity(from: Data(#"{"userStatus": {"planStatus": {"planInfo": {"planName": "Pro"}}}}"#.utf8))
            .plan == "Pro")
    }
}

struct AntigravityProcessTests {
    static let appCommand = "/Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone "
        + "--https_server_port 56140 --csrf_token secret-token"
    static let ideCommand = "/Users/me/.antigravity/extensions/antigravity/bin/language_server_macos_arm "
        + "--csrf_token ide-token --extension_server_port 61000 --extension_server_csrf_token ext-token "
        + "--app_data_dir antigravity-ide"

    @Test
    func `command lines classify as app, IDE, CLI or nothing`() {
        #expect(AntigravityProcess.kind(of: Self.appCommand) == .app)
        #expect(AntigravityProcess.kind(of: Self.ideCommand) == .ide)
        #expect(AntigravityProcess.kind(of: "/opt/homebrew/bin/agy serve") == .cli)
        #expect(AntigravityProcess.kind(of: "/usr/local/bin/language_server --csrf_token x") == nil)
        #expect(AntigravityProcess.kind(of: "/usr/bin/agyle") == nil)
    }

    @Test
    func `the path prefilter keeps candidates only`() {
        #expect(AntigravityProcess
            .isCandidatePath("/Applications/Antigravity.app/Contents/Resources/bin/language_server"))
        #expect(AntigravityProcess.isCandidatePath("/opt/homebrew/bin/agy"))
        #expect(!AntigravityProcess.isCandidatePath("/usr/bin/ssh"))
    }

    @Test
    func `the 2_0 app's HTTPS port is used directly without a socket scan`() {
        var scanned = false
        let endpoints = AntigravityProcess.endpoints(pid: 42, commandLine: Self.appCommand) {
            scanned = true
            return [1]
        }

        #expect(endpoints == [AntigravityEndpoint(
            pid: 42,
            kind: .app,
            scheme: "https",
            port: 56140,
            csrfToken: "secret-token")])
        #expect(!scanned)
    }

    @Test
    func `a zero HTTPS port falls back to the listening sockets`() {
        let command = "/Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone "
            + "--https_server_port 0 --csrf_token tok"
        let endpoints = AntigravityProcess.endpoints(pid: 3, commandLine: command) { [56140, 56142] }

        #expect(endpoints.map(\.port) == [56140, 56142])
        #expect(endpoints.allSatisfy { $0.scheme == "https" })
    }

    @Test
    func `the IDE tries listening ports, then the extension server with both tokens`() {
        let endpoints = AntigravityProcess.endpoints(pid: 7, commandLine: Self.ideCommand) { [50001] }

        #expect(endpoints.map { "\($0.scheme):\($0.port):\($0.csrfToken)" } == [
            "https:50001:ide-token",
            "http:61000:ext-token",
            "http:61000:ide-token",
        ])
    }

    @Test
    func `an app without a token is skipped and the CLI needs none`() {
        let tokenless = "/Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone"

        #expect(AntigravityProcess.endpoints(pid: 1, commandLine: tokenless) { [5] }.isEmpty)
        #expect(AntigravityProcess.endpoints(pid: 2, commandLine: "/opt/homebrew/bin/agy") { [6] }
            == [AntigravityEndpoint(pid: 2, kind: .cli, scheme: "https", port: 6, csrfToken: "")])
    }

    @Test
    func `procargs2 yields argv and never the environment`() {
        var data = Data()
        var argc = Int32(2).littleEndian
        data.append(Data(bytes: &argc, count: 4))
        data.append(Data("/bin/agy\0\0\0".utf8))
        data.append(Data("agy\0--flag\0SECRET_ENV=1\0".utf8))

        #expect(AntigravityProcess.arguments(fromProcArgs2: data) == ["agy", "--flag"])
    }
}

struct AntigravityProbeTests {
    private static let endpoint = AntigravityEndpoint(
        pid: 42,
        kind: .app,
        scheme: "https",
        port: 56140,
        csrfToken: "tok")
    private static let userStatus = #"{"userStatus": {"email": "me@example.com", "userTier": {"name": "Ultra"}}}"#

    private final class Counter: @unchecked Sendable {
        var discoveries = 0
    }

    @Test
    func `nothing running is not running and makes no request`() async {
        let transport = StubTransport([])
        let probe = AntigravityProbe(transport: transport, discover: { [] }, isAlive: { _ in true })

        let result = await probe.fetch(now: Date())

        #expect(result == .failure(.notRunning))
        #expect(await transport.requestCount == 0)
    }

    @Test
    func `a fetch reads the summary, then the identity once per process`() async throws {
        let transport = StubTransport([
            StubTransport.respond(200, body: AntigravityParserTests.summary),
            StubTransport.respond(200, body: Self.userStatus),
            StubTransport.respond(200, body: AntigravityParserTests.summary),
        ])
        let counter = Counter()
        let probe = AntigravityProbe(
            transport: transport,
            discover: {
                counter.discoveries += 1
                return [Self.endpoint]
            },
            isAlive: { _ in true })

        let first = try await probe.fetch(now: Date()).get()
        let second = try await probe.fetch(now: Date()).get()

        #expect(first.accountEmail == "me@example.com")
        #expect(first.plan == "Ultra")
        #expect(first.accountIdentities.isEmpty)
        #expect(second.windows.count == 4)
        #expect(counter.discoveries == 1)
        let requests = await transport.requests
        #expect(requests.map { $0.url?.path } == [
            AntigravityProbe.quotaSummaryPath,
            AntigravityProbe.userStatusPath,
            AntigravityProbe.quotaSummaryPath,
        ])
        #expect(requests.allSatisfy { $0.url?.host == "127.0.0.1" })
        #expect(requests[0].value(forHTTPHeaderField: "X-Codeium-Csrf-Token") == "tok")
        #expect(requests[0].value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
        #expect(requests[0].httpBody == Data(#"{"forceRefresh":true}"#.utf8))
    }

    @Test
    func `a dead cached process triggers a new scan`() async throws {
        let transport = StubTransport([
            StubTransport.respond(200, body: AntigravityParserTests.summary),
            StubTransport.respond(200, body: Self.userStatus),
            StubTransport.respond(200, body: AntigravityParserTests.summary),
        ])
        let counter = Counter()
        let probe = AntigravityProbe(
            transport: transport,
            discover: {
                counter.discoveries += 1
                return [Self.endpoint]
            },
            isAlive: { _ in false })

        _ = try await probe.fetch(now: Date()).get()
        _ = try await probe.fetch(now: Date()).get()

        #expect(counter.discoveries == 2)
    }

    @Test
    func `a refused connection moves to the next endpoint`() async throws {
        let other = AntigravityEndpoint(pid: 42, kind: .app, scheme: "http", port: 61000, csrfToken: "tok")
        let transport = StubTransport([
            .fail(.cannotConnectToHost),
            StubTransport.respond(200, body: AntigravityParserTests.summary),
            StubTransport.respond(200, body: Self.userStatus),
        ])
        let probe = AntigravityProbe(transport: transport, discover: { [Self.endpoint, other] }, isAlive: { _ in true })

        let result = try await probe.fetch(now: Date()).get()

        #expect(result.windows.count == 4)
        #expect(await transport.requests.map { $0.url?.port } == [56140, 61000, 61000])
    }

    @Test
    func `the CLI sends no CSRF header`() async {
        let cli = AntigravityEndpoint(pid: 9, kind: .cli, scheme: "https", port: 6000, csrfToken: "")
        let transport = StubTransport([StubTransport.respond(200, body: AntigravityParserTests.summary)])
        let probe = AntigravityProbe(transport: transport, discover: { [cli] }, isAlive: { _ in true })

        _ = await probe.fetch(now: Date())

        #expect(await transport.requests.first?.value(forHTTPHeaderField: "X-Codeium-Csrf-Token") == nil)
    }
}

struct AntigravityLaneTests {
    @Test
    func `the menu bar, alerts and iPhone bars use the lowest window per lane`() throws {
        let windows = try AntigravityParser.quotaWindows(from: Data(AntigravityParserTests.summary.utf8))
        var state = ProviderState(provider: .antigravity, windows: windows)
        state.lastFetched = Date()

        #expect(windows.representative(.session, for: .antigravity)?.label == "Gemini 5-hour")
        #expect(windows.representative(.weekly, for: .antigravity)?.label == "Claude/GPT weekly")
        #expect(MenuBarText.percent(for: state, now: Date()) == "12%")
        let snapshot = try #require(SyncSnapshot.make(for: state, now: Date()))
        #expect(snapshot.primary?.label == "Gemini 5-hour")
        #expect(snapshot.secondary?.label == "Claude/GPT weekly")
        #expect(snapshot.rateWindows.count == 4)
        #expect(snapshot.accountIdentities == nil)
    }

    @Test
    func `Claude keeps Weekly ahead of its Sonnet window`() {
        let windows = [
            QuotaWindow(label: "Session", lane: .session, usedPercent: 10, windowMinutes: 300, resetsAt: nil),
            QuotaWindow(label: "Weekly", lane: .weekly, usedPercent: 20, windowMinutes: 10080, resetsAt: nil),
            QuotaWindow(label: "Sonnet", lane: .weekly, usedPercent: 90, windowMinutes: 10080, resetsAt: nil),
        ]

        #expect(windows.representative(.weekly, for: .claude)?.label == "Weekly")
    }
}
