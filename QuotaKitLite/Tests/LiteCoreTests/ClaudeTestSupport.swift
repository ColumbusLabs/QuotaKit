import Foundation
import LiteCore

/// Stubs for the Claude probe's seams. None of them touch the Keychain, `/usr/bin/security` or the network.
enum ClaudeFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let future = Self.now.addingTimeInterval(3600)
    static let past = Self.now.addingTimeInterval(-60)

    /// Claude Code's credentials JSON, shaped like the fixture in the full app's
    /// `Tests/CodexBarTests/ClaudeOAuthTests.swift` (`parses O auth credentials`).
    static func credentialsJSON(
        token: String,
        expiresAt: Date? = Self.future,
        subscriptionType: String? = "max",
        rateLimitTier: String? = "default_claude_max_20x") -> Data
    {
        var oauth: [String: Any] = [
            "accessToken": token,
            "refreshToken": "never-stored-refresh-token",
            "scopes": ["user:inference", "user:profile"],
        ]
        if let expiresAt { oauth["expiresAt"] = expiresAt.timeIntervalSince1970 * 1000 }
        if let subscriptionType { oauth["subscriptionType"] = subscriptionType }
        if let rateLimitTier { oauth["rateLimitTier"] = rateLimitTier }
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])
    }

    /// From the full app's `ClaudeOAuthTests.swift` (`maps O auth usage to snapshot`), with a `seven_day_sonnet`
    /// reset added.
    static let usageJSON = """
    {
      "five_hour": { "utilization": 12.5, "resets_at": "2025-12-25T12:00:00.000Z" },
      "seven_day": { "utilization": 30, "resets_at": "2025-12-31T00:00:00.000Z" },
      "seven_day_sonnet": { "utilization": 5, "resets_at": "2025-12-31T00:00:00.000Z" }
    }
    """

    /// From the full app's `ClaudeOAuthTests.swift` (`O auth profile request decodes nested account identity`).
    static let profileJSON = """
    {
      "account": {
        "uuid": "account-123",
        "email": "user@example.com"
      },
      "organization": {
        "uuid": "org-123"
      }
    }
    """
}

/// A response the stub transport returns, or a transport error.
enum ClaudeStubResponse {
    case http(status: Int, body: String, headers: [String: String] = [:])
    case error(URLError.Code)
}

/// Records every request and answers from a handler.
final class ClaudeStubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let handler: @Sendable (URLRequest) -> ClaudeStubResponse

    init(handler: @escaping @Sendable (URLRequest) -> ClaudeStubResponse) {
        self.handler = handler
    }

    /// Usage requests answer with `usage`, profile requests with the profile fixture.
    convenience init(usage: ClaudeStubResponse = .http(status: 200, body: ClaudeFixtures.usageJSON)) {
        self.init { request in
            request.url?.path == "/api/oauth/profile"
                ? .http(status: 200, body: ClaudeFixtures.profileJSON)
                : usage
        }
    }

    var requests: [URLRequest] {
        self.lock.withLock { self.recorded }
    }

    var usageRequests: [URLRequest] {
        self.requests.filter { $0.url?.path == "/api/oauth/usage" }
    }

    var profileRequests: [URLRequest] {
        self.requests.filter { $0.url?.path == "/api/oauth/profile" }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.lock.withLock { self.recorded.append(request) }
        switch self.handler(request) {
        case let .error(code):
            throw URLError(code)
        case let .http(status, body, headers):
            let url = request.url ?? ClaudeUsageAPIURLs.usage
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers)
            else { throw URLError(.badServerResponse) }
            return (Data(body.utf8), response)
        }
    }
}

enum ClaudeUsageAPIURLs {
    static let usage = URL(string: "https://api.anthropic.com/api/oauth/usage")!
}

/// A credentials file that counts reads.
final class StubCredentialsFile: ClaudeCredentialsFileReading, @unchecked Sendable {
    private let lock = NSLock()
    private var contents: Data?
    private var count = 0

    init(_ contents: Data? = nil) {
        self.contents = contents
    }

    var reads: Int {
        self.lock.withLock { self.count }
    }

    func readCredentialsFile() -> Data? {
        self.lock.withLock {
            self.count += 1
            return self.contents
        }
    }
}

/// Keychain metadata whose state tests can change between calls.
final class StubKeychainMetadata: ClaudeKeychainMetadataReading, @unchecked Sendable {
    private let lock = NSLock()
    private var current: ClaudeKeychainItemState
    private var count = 0

    init(_ state: ClaudeKeychainItemState) {
        self.current = state
    }

    var state: ClaudeKeychainItemState {
        get { self.lock.withLock { self.current } }
        set { self.lock.withLock { self.current = newValue } }
    }

    var reads: Int {
        self.lock.withLock { self.count }
    }

    func claudeCredentialsItemState() -> ClaudeKeychainItemState {
        self.lock.withLock {
            self.count += 1
            return self.current
        }
    }
}

/// A `security` reader that returns queued results, then repeats the last one, and counts runs.
final class StubKeychainSecret: ClaudeKeychainSecretReading, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<Data, ClaudeSecretReadFailure>]
    private var count = 0

    init(_ results: [Result<Data, ClaudeSecretReadFailure>]) {
        self.results = results
    }

    convenience init(token: String, expiresAt: Date? = ClaudeFixtures.future) {
        self.init([.success(ClaudeFixtures.credentialsJSON(token: token, expiresAt: expiresAt))])
    }

    var reads: Int {
        self.lock.withLock { self.count }
    }

    func readClaudeCredentialsSecret() async -> Result<Data, ClaudeSecretReadFailure> {
        self.lock.withLock {
            self.count += 1
            if self.results.count > 1 {
                return self.results.removeFirst()
            }
            return self.results.first ?? .failure(.failed)
        }
    }
}

/// An in-memory stand-in for Lite's Keychain cache item.
final class StubTokenCache: ClaudeTokenCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    private var loadCount = 0
    private var clearCount = 0

    init(_ stored: Data? = nil) {
        self.stored = stored
    }

    var data: Data? {
        self.lock.withLock { self.stored }
    }

    var loads: Int {
        self.lock.withLock { self.loadCount }
    }

    var clears: Int {
        self.lock.withLock { self.clearCount }
    }

    func loadCachedToken() -> Data? {
        self.lock.withLock {
            self.loadCount += 1
            return self.stored
        }
    }

    func saveCachedToken(_ data: Data) {
        self.lock.withLock { self.stored = data }
    }

    func clearCachedToken() {
        self.lock.withLock {
            self.clearCount += 1
            self.stored = nil
        }
    }
}

/// The seams for one resolver or probe, kept so tests can inspect the counts.
struct ClaudeSeams {
    var file = StubCredentialsFile()
    var metadata = StubKeychainMetadata(.found(modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)))
    var secret = StubKeychainSecret(token: "keychain-token")
    var cache = StubTokenCache()

    func makeResolver() -> ClaudeCredentialResolver {
        ClaudeCredentialResolver(
            credentialsFile: self.file,
            keychainMetadata: self.metadata,
            keychainSecret: self.secret,
            tokenCache: self.cache)
    }

    func makeProbe(transport: ClaudeStubTransport) -> ClaudeProbe {
        ClaudeProbe(transport: transport, resolver: self.makeResolver())
    }
}
