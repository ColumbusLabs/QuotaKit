import CodexBarSync
import Foundation

/// Requests and response parsing for Claude's OAuth usage and profile endpoints, matching the full app's
/// `ClaudeOAuthUsageFetcher.swift` on the wire (068 §2.1, §4.1).
public enum ClaudeUsageAPI {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage?cedar_ember=1")!
    static let ordinaryUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    static let betaHeader = "oauth-2025-04-20"

    /// The full app's User-Agent when it doesn't detect the Claude CLI version: `claudeCodeUserAgent` with
    /// `fallbackClaudeCodeVersion` "2.1.0" (`ClaudeOAuthUsageFetcher.swift`, pinned by the full app's test
    /// `oauth usage fallback user agent skips version detector`).
    ///
    /// Lite never runs `claude --version` to detect the real version: that would be a subprocess on every refresh
    /// and launches the Claude CLI, which Lite never does (§2.3). The full app sends this exact string whenever
    /// detection is off or fails, so the endpoint already accepts it.
    public static let userAgent = "claude-cli/2.1.0 (external, cli)"
    /// The full app's retry User-Agent, derived from `userAgent` by swapping `claude-cli/` for `claude-code/` and
    /// dropping ` (external, cli)`.
    public static let fallbackUserAgent = "claude-code/2.1.0"

    /// The first request: `?cedar_ember=1` with the primary User-Agent. `includeInventory: false` is the one
    /// retry: no query and the fallback User-Agent, with the same token and other headers.
    static func usageRequest(accessToken: String, includeInventory: Bool = true) -> URLRequest {
        var request = URLRequest(url: includeInventory ? self.usageURL : self.ordinaryUsageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(
            includeInventory ? self.userAgent : self.fallbackUserAgent,
            forHTTPHeaderField: "User-Agent")
        return request
    }

    /// `ClaudeOAuthUsageFetcher.fetchProfile`: only Authorization, Accept and Content-Type, 15 s timeout.
    static func profileRequest(accessToken: String) -> URLRequest {
        var request = URLRequest(url: self.profileURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// A 403 that mentions `user:profile` is a scope error: not retried, and the account must sign in again.
    static func isScopeError(statusCode: Int, body: Data) -> Bool {
        statusCode == 403 && self.mentionsProfileScope(body)
    }

    /// `ClaudeOAuthUsageFetcher.swift:104-113`: retry once without `cedar_ember` on a 400, or on a 403 whose body
    /// doesn't mention `user:profile`.
    static func shouldRetryWithoutInventory(statusCode: Int, body: Data) -> Bool {
        statusCode == 400 || (statusCode == 403 && !self.mentionsProfileScope(body))
    }

    private static func mentionsProfileScope(_ body: Data) -> Bool {
        String(data: body, encoding: .utf8)?.contains("user:profile") ?? false
    }

    /// `Retry-After` as delta seconds or an HTTP date, as `ClaudeOAuthUsageFetcher.retryAfterDate` parses it.
    static func retryAfter(from response: HTTPURLResponse, now: Date) -> Date? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }
        if let seconds = TimeInterval(raw), seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter.date(from: raw)
    }

    // MARK: - Usage response

    /// The windows Lite shows (068 §4.1): `five_hour` → Session, `seven_day` → Weekly, and
    /// `seven_day_sonnet ?? seven_day_opus` → a weekly window labelled "Sonnet" or "Opus".
    ///
    /// Decoding matches the full app's `OAuthUsageResponse`: each window is decoded on its own and a missing, null
    /// or malformed one is skipped; a window without `utilization` is dropped (`mapOAuthUsage`'s `makeWindow`); and
    /// the model window picks Sonnet whenever `seven_day_sonnet` decodes, even without `utilization`, like
    /// `usage.sevenDaySonnet ?? usage.sevenDayOpus`. `extra_usage`, `limits`, `cedar_ember` and every other field
    /// are ignored.
    ///
    /// Returns nil when the body isn't a JSON object.
    public static func parseUsage(_ data: Data) -> [QuotaWindow]? {
        guard let response = try? JSONDecoder().decode(UsageResponse.self, from: data) else { return nil }
        var windows: [QuotaWindow] = []
        if let session = self.window(response.fiveHour, label: "Session", lane: .session, minutes: 300) {
            windows.append(session)
        }
        if let weekly = self.window(response.sevenDay, label: "Weekly", lane: .weekly, minutes: 10080) {
            windows.append(weekly)
        }
        let model = response.sevenDaySonnet.map { (window: $0, label: "Sonnet") }
            ?? response.sevenDayOpus.map { (window: $0, label: "Opus") }
        if let model, let window = self.window(model.window, label: model.label, lane: .weekly, minutes: 10080) {
            windows.append(window)
        }
        return windows
    }

    private static func window(
        _ window: UsageWindow?,
        label: String,
        lane: QuotaWindow.Lane,
        minutes: Int) -> QuotaWindow?
    {
        guard let window, let utilization = window.utilization else { return nil }
        return QuotaWindow(
            label: label,
            lane: lane,
            usedPercent: utilization,
            windowMinutes: minutes,
            resetsAt: self.parseISO8601Date(window.resetsAt))
    }

    /// `ClaudeOAuthUsageFetcher.parseISO8601Date`: with fractional seconds first, then without.
    static func parseISO8601Date(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private struct UsageWindow: Decodable {
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    private struct UsageResponse: Decodable {
        let fiveHour: UsageWindow?
        let sevenDay: UsageWindow?
        let sevenDaySonnet: UsageWindow?
        let sevenDayOpus: UsageWindow?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDaySonnet = "seven_day_sonnet"
            case sevenDayOpus = "seven_day_opus"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.fiveHour = try? container.decodeIfPresent(UsageWindow.self, forKey: .fiveHour)
            self.sevenDay = try? container.decodeIfPresent(UsageWindow.self, forKey: .sevenDay)
            self.sevenDaySonnet = try? container.decodeIfPresent(UsageWindow.self, forKey: .sevenDaySonnet)
            self.sevenDayOpus = try? container.decodeIfPresent(UsageWindow.self, forKey: .sevenDayOpus)
        }
    }

    // MARK: - Profile response

    /// The account behind a token, from `GET /api/oauth/profile`.
    struct Profile: Equatable {
        var accountUUID: String?
        var email: String?
    }

    /// Mirrors the full app's `OAuthProfileResponse`: `account.uuid`, else top-level `accountUuid`/`account_uuid`;
    /// `account.{emailAddress, email_address, email}`, else the same keys at the top level. Values are trimmed and
    /// blank ones ignored. Returns nil when the body isn't a JSON object.
    static func parseProfile(_ data: Data) -> Profile? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let account = object["account"] as? [String: Any]
        let emailKeys = ["emailAddress", "email_address", "email"]
        return Profile(
            accountUUID: account.flatMap { self.string(in: $0, keys: ["uuid"]) }
                ?? self.string(in: object, keys: ["accountUuid", "account_uuid"]),
            email: account.flatMap { self.string(in: $0, keys: emailKeys) }
                ?? self.string(in: object, keys: emailKeys))
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key] as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// `claude:email:<normalized>`, in the format `AccountIdentityComputer.claude` writes (068 §4.1). Lite emits no
    /// `claude:account:` string: the full app fills that from the organization name on its CLI and web paths, never
    /// from the profile's account UUID, so a UUID would never match anything iOS could merge with.
    public static func accountIdentities(email: String?) -> [String] {
        AccountIdentityNormalize.normalize(email).map { ["claude:email:\($0)"] } ?? []
    }
}
