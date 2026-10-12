import Foundation
import LiteCore

/// Shared helpers for the Codex probe tests. Everything here is synthetic: no real credentials, no network.
enum CodexTestSupport {
    /// An unsigned JWT with the given JSON payload (base64url, no padding), shaped like `header.payload.signature`.
    static func jwt(_ payloadJSON: String) -> String {
        let encoded = Data(payloadJSON.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "fixture.\(encoded).signature"
    }

    /// A far-future `exp` (2100-01-01), so tokens built with it never expire inside a test.
    static let farFutureExp = 4_102_444_800

    /// The instant the probe tests treat as "now": 2026-10-11 12:00:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_791_720_000)

    static func accessToken(exp: Int = farFutureExp, extraClaims: String = "") -> String {
        self.jwt(#"{"exp":\#(exp)\#(extraClaims)}"#)
    }

    /// A ChatGPT-login `auth.json` body. Pass nil to omit `account_id` or `id_token`.
    static func authJSON(
        accessToken: String,
        accountID: String? = "account-123",
        idToken: String? = nil,
        lastRefresh: String? = "2026-10-10T12:00:00Z") -> String
    {
        var tokens = [#""access_token": "\#(accessToken)""#, #""refresh_token": "fixture-refresh""#]
        if let idToken {
            tokens.append(#""id_token": "\#(idToken)""#)
        }
        if let accountID {
            tokens.append(#""account_id": "\#(accountID)""#)
        }
        var fields = [#""OPENAI_API_KEY": null"#, #""tokens": { \#(tokens.joined(separator: ", ")) }"#]
        if let lastRefresh {
            fields.append(#""last_refresh": "\#(lastRefresh)""#)
        }
        return "{ \(fields.joined(separator: ", ")) }"
    }

    /// A temporary home directory. `defaultCodexHome` is `~/.codex` under it.
    struct Home {
        let root: URL

        init() throws {
            self.root = FileManager.default.temporaryDirectory
                .appendingPathComponent("CodexProbeTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        }

        var defaultCodexHome: URL {
            self.root.appendingPathComponent(".codex", isDirectory: true)
        }

        func reader(codexHome: URL? = nil) -> CodexAuthReader {
            var environment: [String: String] = [:]
            if let codexHome {
                environment["CODEX_HOME"] = codexHome.path
            }
            return CodexAuthReader(environment: environment, homeDirectory: self.root)
        }

        /// Writes `auth.json` into `directory` (default `~/.codex`), creating it.
        func writeAuth(_ json: String, in directory: URL? = nil) throws {
            let directory = directory ?? self.defaultCodexHome
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: directory.appendingPathComponent("auth.json"), options: .atomic)
        }

        func remove() {
            try? FileManager.default.removeItem(at: self.root)
        }
    }

    static func response(status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: CodexProbe.usageURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}

/// A transport that plays back scripted responses and records every request, so tests can count calls and check
/// headers. It never touches the network. `beforeSend` runs on each call with the 1-based call number, for
/// example to rewrite `auth.json` between a 401 and the retry.
actor StubTransport: HTTPTransport {
    enum Step: Sendable {
        case respond(status: Int, headers: [String: String], body: String)
        case fail(URLError.Code)
    }

    private var steps: [Step]
    private let beforeSend: @Sendable (Int) -> Void
    private(set) var requests: [URLRequest] = []

    init(_ steps: [Step], beforeSend: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.steps = steps
        self.beforeSend = beforeSend
    }

    static func respond(_ status: Int, headers: [String: String] = [:], body: String = "") -> Step {
        .respond(status: status, headers: headers, body: body)
    }

    var requestCount: Int {
        self.requests.count
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.requests.append(request)
        self.beforeSend(self.requests.count)
        guard !self.steps.isEmpty else { throw URLError(.cannotConnectToHost) }
        switch self.steps.removeFirst() {
        case let .respond(status, headers, body):
            return (Data(body.utf8), CodexTestSupport.response(status: status, headers: headers))
        case let .fail(code):
            throw URLError(code)
        }
    }
}
