import Foundation

/// Fetches Codex's session and weekly limits with one `GET` (068 §2.1, §4.2).
///
/// Lite is read-only for credentials: it never refreshes the token, because the Codex CLI owns it. An expired
/// token returns `.tokenExpired` without a request, and the menu tells the user to run `codex` once.
public struct CodexProbe: Sendable {
    /// `chatgpt_base_url` from `config.toml` is out of scope (§4.2), so the URL is fixed.
    public static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    /// A rate-limited provider isn't called again for at least this long (§4.1 table, §4.2 step 4).
    public static let minimumRateLimitDelay: TimeInterval = 5 * 60

    private let transport: any HTTPTransport
    private let authReader: CodexAuthReader

    public init(transport: any HTTPTransport, authReader: CodexAuthReader = CodexAuthReader()) {
        self.transport = transport
        self.authReader = authReader
    }

    /// The `auth.json` this probe reads. The scheduler watches its directory, so a CLI-side refresh triggers a
    /// fetch (§5.1).
    public var authFileURL: URL {
        self.authReader.authFileURL
    }

    public func fetch(now: Date) async -> Result<ProbeResult, ProbeFailure> {
        switch self.authReader.read() {
        case let .success(auth):
            await self.fetch(auth: auth, now: now, mayReread: true)
        case let .failure(error):
            switch error {
            case .notFound, .noOAuthTokens: .failure(.signInRequired)
            case .unreadable: .failure(.tokenUnavailable)
            }
        }
    }

    /// The request the full app sends in `CodexOAuthUsageFetcher.fetchUsage`: the bearer token, the account ID
    /// when there is one, `Accept` and the `QuotaKit` user agent. The 15 s timeout matches the transport's (§3.2).
    public static func makeRequest(auth: CodexAuth) -> URLRequest {
        var request = URLRequest(url: Self.usageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("QuotaKit", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = auth.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return request
    }

    /// `mayReread` is true only for the first attempt, so a 401 re-reads `auth.json` at most once.
    private func fetch(auth: CodexAuth, now: Date, mayReread: Bool) async -> Result<ProbeResult, ProbeFailure> {
        guard !auth.isExpired(now: now) else { return .failure(.tokenExpired) }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await self.transport.send(Self.makeRequest(auth: auth))
        } catch {
            return .failure(.network(Self.message(for: error)))
        }

        switch response.statusCode {
        case 200...299:
            return CodexUsageParser.parse(data, auth: auth)
        case 401:
            // The CLI may have refreshed the token while the request was in flight. Retry only with a new one.
            guard mayReread,
                  case let .success(fresh) = self.authReader.read(),
                  fresh.accessToken != auth.accessToken
            else { return .failure(.signInRequired) }
            return await self.fetch(auth: fresh, now: now, mayReread: false)
        case 429:
            let retryAfter = Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: now)
            let floor = now.addingTimeInterval(Self.minimumRateLimitDelay)
            return .failure(.rateLimited(until: max(retryAfter ?? floor, floor)))
        default:
            return .failure(.server(statusCode: response.statusCode))
        }
    }

    /// `Retry-After` is either a number of seconds or an HTTP date.
    static func retryAfter(_ header: String?, now: Date) -> Date? {
        guard let value = header?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) {
            return seconds.isFinite && seconds >= 0 ? now.addingTimeInterval(seconds) : nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }

    private static func message(for error: Error) -> String {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return "Cancelled"
        }
        return error.localizedDescription
    }
}
