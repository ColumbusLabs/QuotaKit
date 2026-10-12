import Foundation

/// What a successful provider fetch produces (068 §4).
public struct ProbeResult: Sendable, Equatable {
    public var windows: [QuotaWindow]
    /// Plan name, synced as `loginMethod`.
    public var plan: String?
    public var accountEmail: String?
    /// Exactly the strings the full app's `AccountIdentityComputer` writes, so iOS merges cards (§4.1, §4.2).
    public var accountIdentities: [String]

    public init(
        windows: [QuotaWindow],
        plan: String? = nil,
        accountEmail: String? = nil,
        accountIdentities: [String] = [])
    {
        self.windows = windows
        self.plan = plan
        self.accountEmail = accountEmail
        self.accountIdentities = accountIdentities
    }
}

/// Why a fetch didn't produce data. The scheduler uses it for backoff, the menu for the footer.
public enum ProbeFailure: Error, Sendable, Equatable {
    /// The CLI's token has expired; Lite never refreshes it (§4.1, §4.2). No request was made.
    case tokenExpired
    /// The token couldn't be read at all, for example `/usr/bin/security` failed (§4.1 step 4).
    case tokenUnavailable
    /// The account must sign in to the CLI again: a 403 scope error, or a 401 that survived one re-read.
    case signInRequired
    /// HTTP 429. Don't call this provider again before `until` (at least 5 minutes out).
    case rateLimited(until: Date)
    /// HTTP 5xx or another unexpected status. Retried with exponential backoff.
    case server(statusCode: Int)
    /// The request didn't complete (offline, timeout, TLS). Retried with exponential backoff.
    case network(String)
    /// The response decoded to an unknown shape (§8). Not retried tightly.
    case unrecognizedResponse
    /// Antigravity isn't running (§4.3).
    case notRunning

    /// The menu status this failure shows as.
    public var status: ProviderStatus {
        switch self {
        case .tokenExpired: .tokenExpired
        case .tokenUnavailable: .tokenUnavailable
        case .signInRequired: .signInRequired
        case .unrecognizedResponse: .unrecognizedResponse
        case .notRunning: .notRunning
        case .rateLimited: .error("Rate limited")
        case let .server(statusCode): .error("Server error \(statusCode)")
        case let .network(message): .error(message)
        }
    }
}

/// The only HTTP seam. Probes take one so tests can use a stub and never touch the network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The real transport: one ephemeral session configured as in 068 §3.2.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionTransport.makeSession()) {
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.timeoutIntervalForRequest = 15
        // The scheduler retries, so don't wait for connectivity.
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
