import Foundation

/// Fetches Claude usage data directly from the claude.ai API using browser session cookies.
///
/// This approach mirrors what Claude Usage Tracker does, but automatically extracts the session key
/// from Chrome/Safari cookies instead of requiring manual setup.
///
/// API endpoints used:
/// - `GET https://claude.ai/api/organizations` → get org UUID
/// - `GET https://claude.ai/api/organizations/{org_id}/usage` → usage percentages + reset times
public enum ClaudeWebAPIFetcher {
    private static let baseURL = "https://claude.ai/api"

    public enum FetchError: LocalizedError, Sendable {
        case noSessionKeyFound
        case invalidSessionKey
        case networkError(Error)
        case invalidResponse
        case unauthorized
        case serverError(statusCode: Int)
        case noOrganization

        public var errorDescription: String? {
            switch self {
            case .noSessionKeyFound:
                "No Claude session key found in browser cookies."
            case .invalidSessionKey:
                "Invalid Claude session key format."
            case let .networkError(error):
                "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                "Invalid response from Claude API."
            case .unauthorized:
                "Unauthorized. Your Claude session may have expired."
            case let .serverError(code):
                "Claude API error: HTTP \(code)"
            case .noOrganization:
                "No Claude organization found for this account."
            }
        }
    }

    /// Claude usage data from the API
    public struct WebUsageData: Sendable {
        public let sessionPercentUsed: Double
        public let sessionResetsAt: Date?
        public let weeklyPercentUsed: Double?
        public let weeklyResetsAt: Date?
        public let opusPercentUsed: Double?
        public let extraUsageCost: ProviderCostSnapshot?

        public init(
            sessionPercentUsed: Double,
            sessionResetsAt: Date?,
            weeklyPercentUsed: Double?,
            weeklyResetsAt: Date?,
            opusPercentUsed: Double?,
            extraUsageCost: ProviderCostSnapshot?)
        {
            self.sessionPercentUsed = sessionPercentUsed
            self.sessionResetsAt = sessionResetsAt
            self.weeklyPercentUsed = weeklyPercentUsed
            self.weeklyResetsAt = weeklyResetsAt
            self.opusPercentUsed = opusPercentUsed
            self.extraUsageCost = extraUsageCost
        }
    }

    // MARK: - Public API

    /// Attempts to fetch Claude usage data using cookies extracted from browsers.
    /// Tries Safari first, then Chrome.
    public static func fetchUsage(logger: ((String) -> Void)? = nil) async throws -> WebUsageData {
        let log: (String) -> Void = { msg in logger?("[claude-web] \(msg)") }

        // Try to get session key from browsers
        let sessionKey = try extractSessionKey(logger: log)
        log("Found session key: \(sessionKey.prefix(20))...")

        // Fetch organization ID
        let orgId = try await fetchOrganizationId(sessionKey: sessionKey, logger: log)
        log("Organization ID: \(orgId)")

        var usage = try await fetchUsageData(orgId: orgId, sessionKey: sessionKey, logger: log)
        if usage.extraUsageCost == nil,
           let extra = await fetchExtraUsageCost(orgId: orgId, sessionKey: sessionKey, logger: log)
        {
            usage = WebUsageData(
                sessionPercentUsed: usage.sessionPercentUsed,
                sessionResetsAt: usage.sessionResetsAt,
                weeklyPercentUsed: usage.weeklyPercentUsed,
                weeklyResetsAt: usage.weeklyResetsAt,
                opusPercentUsed: usage.opusPercentUsed,
                extraUsageCost: extra)
        }
        return usage
    }

    /// Checks if we can find a Claude session key in browser cookies without making API calls.
    public static func hasSessionKey(logger: ((String) -> Void)? = nil) -> Bool {
        do {
            _ = try self.extractSessionKey(logger: logger)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Session Key Extraction

    private static func extractSessionKey(logger: ((String) -> Void)? = nil) throws -> String {
        let log: (String) -> Void = { msg in logger?(msg) }

        // Try Safari first (doesn't require Keychain access)
        do {
            let safariRecords = try SafariCookieImporter.loadCookies(
                matchingDomains: ["claude.ai"],
                logger: log)
            if let sessionKey = findSessionKey(in: safariRecords.map { record in
                (name: record.name, value: record.value)
            }) {
                log("Found sessionKey in Safari")
                return sessionKey
            }
        } catch {
            log("Safari cookie load failed: \(error.localizedDescription)")
        }

        // Try Chrome (may trigger Keychain prompt)
        do {
            let chromeSources = try ChromeCookieImporter.loadCookiesFromAllProfiles(
                matchingDomains: ["claude.ai"])
            for source in chromeSources {
                if let sessionKey = findSessionKey(in: source.records.map { record in
                    (name: record.name, value: record.value)
                }) {
                    log("Found sessionKey in \(source.label)")
                    return sessionKey
                }
            }
        } catch {
            log("Chrome cookie load failed: \(error.localizedDescription)")
        }

        throw FetchError.noSessionKeyFound
    }

    private static func findSessionKey(in cookies: [(name: String, value: String)]) -> String? {
        for cookie in cookies where cookie.name == "sessionKey" {
            let value = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
            // Validate it looks like a Claude session key
            if value.hasPrefix("sk-ant-") {
                return value
            }
        }
        return nil
    }

    // MARK: - API Calls

    private static func fetchOrganizationId(
        sessionKey: String,
        logger: ((String) -> Void)? = nil) async throws -> String
    {
        let url = URL(string: "\(baseURL)/organizations")!
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }

        logger?("Organizations API status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            // Parse organizations array - look for uuid field
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let firstOrg = json.first,
                  let uuid = firstOrg["uuid"] as? String
            else {
                throw FetchError.noOrganization
            }
            return uuid
        case 401, 403:
            throw FetchError.unauthorized
        default:
            throw FetchError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    private static func fetchUsageData(
        orgId: String,
        sessionKey: String,
        logger: ((String) -> Void)? = nil) async throws -> WebUsageData
    {
        let url = URL(string: "\(baseURL)/organizations/\(orgId)/usage")!
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }

        logger?("Usage API status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            return try self.parseUsageResponse(data)
        case 401, 403:
            throw FetchError.unauthorized
        default:
            throw FetchError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    private static func parseUsageResponse(_ data: Data) throws -> WebUsageData {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FetchError.invalidResponse
        }

        // Parse five_hour (session) usage
        var sessionPercent: Double?
        var sessionResets: Date?
        if let fiveHour = json["five_hour"] as? [String: Any] {
            if let utilization = fiveHour["utilization"] as? Int {
                sessionPercent = Double(utilization)
            }
            if let resetsAt = fiveHour["resets_at"] as? String {
                sessionResets = self.parseISO8601Date(resetsAt)
            }
        }
        guard let sessionPercent else {
            // If we can't parse session utilization, treat this as a failure so callers can fall back to the CLI.
            throw FetchError.invalidResponse
        }

        // Parse seven_day (weekly) usage
        var weeklyPercent: Double?
        var weeklyResets: Date?
        if let sevenDay = json["seven_day"] as? [String: Any] {
            if let utilization = sevenDay["utilization"] as? Int {
                weeklyPercent = Double(utilization)
            }
            if let resetsAt = sevenDay["resets_at"] as? String {
                weeklyResets = self.parseISO8601Date(resetsAt)
            }
        }

        // Parse seven_day_opus (Opus-specific weekly) usage
        var opusPercent: Double?
        if let sevenDayOpus = json["seven_day_opus"] as? [String: Any] {
            if let utilization = sevenDayOpus["utilization"] as? Int {
                opusPercent = Double(utilization)
            }
        }

        return WebUsageData(
            sessionPercentUsed: sessionPercent,
            sessionResetsAt: sessionResets,
            weeklyPercentUsed: weeklyPercent,
            weeklyResetsAt: weeklyResets,
            opusPercentUsed: opusPercent,
            extraUsageCost: nil)
    }

    // MARK: - Extra usage cost (Claude "Extra")

    private struct OverageSpendLimitResponse: Decodable {
        let monthlyCreditLimit: Double?
        let currency: String?
        let usedCredits: Double?
        let isEnabled: Bool?

        enum CodingKeys: String, CodingKey {
            case monthlyCreditLimit = "monthly_credit_limit"
            case currency
            case usedCredits = "used_credits"
            case isEnabled = "is_enabled"
        }
    }

    /// Best-effort fetch of Claude Extra spend/limit (does not fail the main usage fetch).
    private static func fetchExtraUsageCost(
        orgId: String,
        sessionKey: String,
        logger: ((String) -> Void)? = nil) async -> ProviderCostSnapshot?
    {
        let url = URL(string: "\(baseURL)/organizations/\(orgId)/overage_spend_limit")!
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            logger?("Overage API status: \(httpResponse.statusCode)")
            guard httpResponse.statusCode == 200 else { return nil }
            return Self.parseOverageSpendLimit(data)
        } catch {
            return nil
        }
    }

    private static func parseOverageSpendLimit(_ data: Data) -> ProviderCostSnapshot? {
        guard let decoded = try? JSONDecoder().decode(OverageSpendLimitResponse.self, from: data) else { return nil }
        guard decoded.isEnabled == true else { return nil }
        guard let used = decoded.usedCredits,
              let limit = decoded.monthlyCreditLimit,
              let currency = decoded.currency,
              !currency.isEmpty else { return nil }

        return ProviderCostSnapshot(
            used: used,
            limit: limit,
            currencyCode: currency,
            period: "Monthly",
            resetsAt: nil,
            updatedAt: Date())
    }

    #if DEBUG

    // MARK: - Test hooks (DEBUG-only)

    public static func _parseUsageResponseForTesting(_ data: Data) throws -> WebUsageData {
        try self.parseUsageResponse(data)
    }

    public static func _parseOverageSpendLimitForTesting(_ data: Data) -> ProviderCostSnapshot? {
        self.parseOverageSpendLimit(data)
    }
    #endif

    private static func parseISO8601Date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
