import Foundation

#if os(macOS)

// MARK: - Factory Cookie Importer

/// Imports Factory session cookies from Safari/Chrome/Firefox browsers
public enum FactoryCookieImporter {
    private static let sessionCookieNames: Set<String> = [
        "wos-session",
        "__Secure-next-auth.session-token",
        "next-auth.session-token",
        "__Host-authjs.csrf-token",
        "authjs.session-token",
    ]

    public struct SessionInfo: Sendable {
        public let cookies: [HTTPCookie]
        public let sourceLabel: String

        public init(cookies: [HTTPCookie], sourceLabel: String) {
            self.cookies = cookies
            self.sourceLabel = sourceLabel
        }

        public var cookieHeader: String {
            self.cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
    }

    /// Attempts to import Factory cookies from Safari first, then Chrome, then Firefox
    public static func importSession(logger: ((String) -> Void)? = nil) throws -> SessionInfo {
        let log: (String) -> Void = { msg in logger?("[factory-cookie] \(msg)") }

        // Try Safari first
        do {
            let safariRecords = try SafariCookieImporter.loadCookies(
                matchingDomains: ["factory.ai", "app.factory.ai", "auth.factory.ai"],
                logger: log)
            if !safariRecords.isEmpty {
                let httpCookies = SafariCookieImporter.makeHTTPCookies(safariRecords)
                if httpCookies.contains(where: { Self.sessionCookieNames.contains($0.name) }) {
                    log("Found \(httpCookies.count) Factory cookies in Safari")
                    return SessionInfo(cookies: httpCookies, sourceLabel: "Safari")
                } else {
                    log("Safari cookies found, but no Factory session cookie present")
                }
            }
        } catch {
            log("Safari cookie import failed: \(error.localizedDescription)")
        }

        // Try Chrome
        do {
            let chromeSources = try ChromeCookieImporter.loadCookiesFromAllProfiles(
                matchingDomains: ["factory.ai", "app.factory.ai", "auth.factory.ai"])
            for source in chromeSources where !source.records.isEmpty {
                let httpCookies = source.records.compactMap { record -> HTTPCookie? in
                    let domain = record.hostKey.hasPrefix(".") ? String(record.hostKey.dropFirst()) : record.hostKey
                    var props: [HTTPCookiePropertyKey: Any] = [
                        .domain: domain,
                        .path: record.path,
                        .name: record.name,
                        .value: record.value,
                        .secure: record.isSecure,
                    ]
                    if record.isHTTPOnly {
                        props[.init("HttpOnly")] = "TRUE"
                    }
                    if record.expiresUTC > 0 {
                        let unixTimestamp = Double(record.expiresUTC - 11_644_473_600_000_000) / 1_000_000
                        props[.expires] = Date(timeIntervalSince1970: unixTimestamp)
                    }
                    return HTTPCookie(properties: props)
                }
                if httpCookies.contains(where: { Self.sessionCookieNames.contains($0.name) }) {
                    log("Found \(httpCookies.count) Factory cookies in \(source.label)")
                    return SessionInfo(cookies: httpCookies, sourceLabel: source.label)
                } else {
                    log("Chrome source \(source.label) has no Factory session cookie")
                }
            }
        } catch {
            log("Chrome cookie import failed: \(error.localizedDescription)")
        }

        // Try Firefox
        do {
            let firefoxSources = try FirefoxCookieImporter.loadCookiesFromAllProfiles(
                matchingDomains: ["factory.ai", "app.factory.ai", "auth.factory.ai"])
            for source in firefoxSources where !source.records.isEmpty {
                let httpCookies = source.records.compactMap { record -> HTTPCookie? in
                    let domain = record.host.hasPrefix(".") ? String(record.host.dropFirst()) : record.host
                    var props: [HTTPCookiePropertyKey: Any] = [
                        .domain: domain,
                        .path: record.path,
                        .name: record.name,
                        .value: record.value,
                        .secure: record.isSecure,
                    ]
                    if record.isHTTPOnly {
                        props[.init("HttpOnly")] = "TRUE"
                    }
                    if let expires = record.expires {
                        props[.expires] = expires
                    }
                    return HTTPCookie(properties: props)
                }
                if httpCookies.contains(where: { Self.sessionCookieNames.contains($0.name) }) {
                    log("Found \(httpCookies.count) Factory cookies in \(source.label)")
                    return SessionInfo(cookies: httpCookies, sourceLabel: source.label)
                } else {
                    log("Firefox source \(source.label) has no Factory session cookie")
                }
            }
        } catch {
            log("Firefox cookie import failed: \(error.localizedDescription)")
        }

        throw FactoryStatusProbeError.noSessionCookie
    }

    /// Check if Factory session cookies are available
    public static func hasSession(logger: ((String) -> Void)? = nil) -> Bool {
        do {
            let session = try self.importSession(logger: logger)
            return !session.cookies.isEmpty
        } catch {
            return false
        }
    }
}

// MARK: - Factory API Models

public struct FactoryAuthResponse: Codable, Sendable {
    public let featureFlags: FactoryFeatureFlags?
    public let organization: FactoryOrganization?
}

public struct FactoryFeatureFlags: Codable, Sendable {
    public let flags: [String: Bool]?
    public let configs: [String: AnyCodable]?
}

public struct FactoryOrganization: Codable, Sendable {
    public let id: String?
    public let name: String?
    public let subscription: FactorySubscription?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case subscription
    }
}

public struct FactorySubscription: Codable, Sendable {
    public let factoryTier: String?
    public let orbSubscription: FactoryOrbSubscription?
}

public struct FactoryOrbSubscription: Codable, Sendable {
    public let plan: FactoryPlan?
    public let status: String?
}

public struct FactoryPlan: Codable, Sendable {
    public let name: String?
    public let id: String?
}

public struct FactoryUsageResponse: Codable, Sendable {
    public let usage: FactoryUsageData?
    public let source: String?
    public let userId: String?
}

public struct FactoryUsageData: Codable, Sendable {
    public let startDate: Int64?
    public let endDate: Int64?
    public let standard: FactoryTokenUsage?
    public let premium: FactoryTokenUsage?
}

public struct FactoryTokenUsage: Codable, Sendable {
    public let userTokens: Int64?
    public let orgTotalTokensUsed: Int64?
    public let totalAllowance: Int64?
    public let usedRatio: Double?
    public let orgOverageUsed: Int64?
    public let basicAllowance: Int64?
    public let orgOverageLimit: Int64?
}

/// Helper for encoding arbitrary JSON
public struct AnyCodable: Codable, Sendable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            return
        }
        _ = try? container.decode([String: AnyCodable].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

// MARK: - Factory Status Snapshot

public struct FactoryStatusSnapshot: Sendable {
    /// Standard token usage (user)
    public let standardUserTokens: Int64
    /// Standard token usage (org total)
    public let standardOrgTokens: Int64
    /// Standard token allowance
    public let standardAllowance: Int64
    /// Premium token usage (user)
    public let premiumUserTokens: Int64
    /// Premium token usage (org total)
    public let premiumOrgTokens: Int64
    /// Premium token allowance
    public let premiumAllowance: Int64
    /// Billing period start
    public let periodStart: Date?
    /// Billing period end
    public let periodEnd: Date?
    /// Plan name
    public let planName: String?
    /// Factory tier (enterprise, team, etc.)
    public let tier: String?
    /// Organization name
    public let organizationName: String?
    /// User email
    public let accountEmail: String?
    /// User ID
    public let userId: String?
    /// Raw JSON for debugging
    public let rawJSON: String?

    public init(
        standardUserTokens: Int64,
        standardOrgTokens: Int64,
        standardAllowance: Int64,
        premiumUserTokens: Int64,
        premiumOrgTokens: Int64,
        premiumAllowance: Int64,
        periodStart: Date?,
        periodEnd: Date?,
        planName: String?,
        tier: String?,
        organizationName: String?,
        accountEmail: String?,
        userId: String?,
        rawJSON: String?)
    {
        self.standardUserTokens = standardUserTokens
        self.standardOrgTokens = standardOrgTokens
        self.standardAllowance = standardAllowance
        self.premiumUserTokens = premiumUserTokens
        self.premiumOrgTokens = premiumOrgTokens
        self.premiumAllowance = premiumAllowance
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.planName = planName
        self.tier = tier
        self.organizationName = organizationName
        self.accountEmail = accountEmail
        self.userId = userId
        self.rawJSON = rawJSON
    }

    /// Convert to UsageSnapshot for the common provider interface
    public func toUsageSnapshot() -> UsageSnapshot {
        // Primary: Standard tokens used (as percentage of allowance, capped reasonably)
        let standardPercent = self.calculateUsagePercent(
            used: self.standardUserTokens,
            allowance: self.standardAllowance)

        let primary = RateWindow(
            usedPercent: standardPercent,
            windowMinutes: nil,
            resetsAt: self.periodEnd,
            resetDescription: self.periodEnd.map { Self.formatResetDate($0) })

        // Secondary: Premium tokens used
        let premiumPercent = self.calculateUsagePercent(
            used: self.premiumUserTokens,
            allowance: self.premiumAllowance)

        let secondary = RateWindow(
            usedPercent: premiumPercent,
            windowMinutes: nil,
            resetsAt: self.periodEnd,
            resetDescription: self.periodEnd.map { Self.formatResetDate($0) })

        // Format login method as tier + plan
        let loginMethod: String? = {
            var parts: [String] = []
            if let tier = self.tier, !tier.isEmpty {
                parts.append("Factory \(tier.capitalized)")
            }
            if let plan = self.planName, !plan.isEmpty, !plan.lowercased().contains("factory") {
                parts.append(plan)
            }
            return parts.isEmpty ? nil : parts.joined(separator: " - ")
        }()

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            providerCost: nil,
            updatedAt: Date(),
            accountEmail: self.accountEmail,
            accountOrganization: self.organizationName,
            loginMethod: loginMethod)
    }

    private func calculateUsagePercent(used: Int64, allowance: Int64) -> Double {
        // Treat very large allowances (> 1 trillion) as unlimited
        let unlimitedThreshold: Int64 = 1_000_000_000_000
        if allowance > unlimitedThreshold {
            // For unlimited, show a token count-based pseudo-percentage (capped at 100%)
            // Use 100M tokens as a reference point for "100%"
            let referenceTokens: Double = 100_000_000
            return min(100, Double(used) / referenceTokens * 100)
        }
        guard allowance > 0 else { return 0 }
        return min(100, Double(used) / Double(allowance) * 100)
    }

    private static func formatResetDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d 'at' h:mma"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "Resets " + formatter.string(from: date)
    }
}

// MARK: - Factory Status Probe Error

public enum FactoryStatusProbeError: LocalizedError, Sendable {
    case notLoggedIn
    case networkError(String)
    case parseFailed(String)
    case noSessionCookie

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            "Not logged in to Factory. Please log in via the CodexBar menu."
        case let .networkError(msg):
            "Factory API error: \(msg)"
        case let .parseFailed(msg):
            "Could not parse Factory usage: \(msg)"
        case .noSessionCookie:
            "No Factory session found. Please log in to app.factory.ai in Safari, Chrome, or Firefox."
        }
    }
}

// MARK: - Factory Session Store

public actor FactorySessionStore {
    public static let shared = FactorySessionStore()

    private var sessionCookies: [HTTPCookie] = []
    private var bearerToken: String?
    private let fileURL: URL

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = appSupport.appendingPathComponent("CodexBar", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("factory-session.json")

        Task { await self.loadFromDisk() }
    }

    public func setCookies(_ cookies: [HTTPCookie]) {
        self.sessionCookies = cookies
        self.saveToDisk()
    }

    public func getCookies() -> [HTTPCookie] {
        self.sessionCookies
    }

    public func setBearerToken(_ token: String?) {
        self.bearerToken = token
    }

    public func getBearerToken() -> String? {
        self.bearerToken
    }

    public func clearSession() {
        self.sessionCookies = []
        self.bearerToken = nil
        try? FileManager.default.removeItem(at: self.fileURL)
    }

    public func hasValidSession() -> Bool {
        !self.sessionCookies.isEmpty || self.bearerToken != nil
    }

    private func saveToDisk() {
        let cookieData = self.sessionCookies.compactMap { cookie -> [String: Any]? in
            guard let props = cookie.properties else { return nil }
            var serializable: [String: Any] = [:]
            for (key, value) in props {
                let keyString = key.rawValue
                if let date = value as? Date {
                    serializable[keyString] = date.timeIntervalSince1970
                    serializable[keyString + "_isDate"] = true
                } else if let url = value as? URL {
                    serializable[keyString] = url.absoluteString
                    serializable[keyString + "_isURL"] = true
                } else if JSONSerialization.isValidJSONObject([value]) ||
                    value is String ||
                    value is Bool ||
                    value is NSNumber
                {
                    serializable[keyString] = value
                }
            }
            return serializable
        }
        guard !cookieData.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: cookieData, options: [.prettyPrinted])
        else {
            return
        }
        try? data.write(to: self.fileURL)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: self.fileURL),
              let cookieArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }

        self.sessionCookies = cookieArray.compactMap { props in
            var cookieProps: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in props {
                if key.hasSuffix("_isDate") || key.hasSuffix("_isURL") { continue }

                let propKey = HTTPCookiePropertyKey(key)

                if props[key + "_isDate"] as? Bool == true, let interval = value as? TimeInterval {
                    cookieProps[propKey] = Date(timeIntervalSince1970: interval)
                } else if props[key + "_isURL"] as? Bool == true, let urlString = value as? String {
                    cookieProps[propKey] = URL(string: urlString)
                } else {
                    cookieProps[propKey] = value
                }
            }
            return HTTPCookie(properties: cookieProps)
        }
    }
}

// MARK: - Factory Status Probe

public struct FactoryStatusProbe: Sendable {
    public let baseURL: URL
    public var timeout: TimeInterval = 15.0

    public init(baseURL: URL = URL(string: "https://app.factory.ai")!, timeout: TimeInterval = 15.0) {
        self.baseURL = baseURL
        self.timeout = timeout
    }

    /// Fetch Factory usage using browser cookies (Safari/Chrome/Firefox) with fallback to stored session
    public func fetch(logger: ((String) -> Void)? = nil) async throws -> FactoryStatusSnapshot {
        let log: (String) -> Void = { msg in logger?("[factory] \(msg)") }

        // Try importing cookies from Safari/Chrome/Firefox first
        do {
            let session = try FactoryCookieImporter.importSession(logger: log)
            log("Using cookies from \(session.sourceLabel)")
            return try await self.fetchWithCookieHeader(session.cookieHeader)
        } catch {
            log("Browser cookie import failed: \(error.localizedDescription)")
        }

        // Fall back to stored session cookies
        let storedCookies = await FactorySessionStore.shared.getCookies()
        if !storedCookies.isEmpty {
            log("Using stored session cookies")
            let cookieHeader = storedCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            do {
                return try await self.fetchWithCookieHeader(cookieHeader)
            } catch {
                if case FactoryStatusProbeError.notLoggedIn = error {
                    await FactorySessionStore.shared.clearSession()
                    log("Stored session invalid, cleared")
                } else {
                    log("Stored session failed: \(error.localizedDescription)")
                }
            }
        }

        throw FactoryStatusProbeError.noSessionCookie
    }

    private func fetchWithCookieHeader(_ cookieHeader: String) async throws -> FactoryStatusSnapshot {
        // First fetch auth info to get user ID and org info
        let authInfo = try await self.fetchAuthInfo(cookieHeader: cookieHeader)

        // Extract user ID from JWT in the auth response or use a default endpoint
        let userId = self.extractUserIdFromAuth(authInfo)

        // Fetch usage data
        let usageData = try await self.fetchUsage(cookieHeader: cookieHeader, userId: userId)

        return self.buildSnapshot(authInfo: authInfo, usageData: usageData, userId: userId)
    }

    private func fetchAuthInfo(cookieHeader: String) async throws -> FactoryAuthResponse {
        let url = self.baseURL.appendingPathComponent("/api/app/auth/me")
        var request = URLRequest(url: url)
        request.timeoutInterval = self.timeout
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("web-app", forHTTPHeaderField: "x-factory-client")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FactoryStatusProbeError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw FactoryStatusProbeError.notLoggedIn
        }

        guard httpResponse.statusCode == 200 else {
            throw FactoryStatusProbeError.networkError("HTTP \(httpResponse.statusCode)")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(FactoryAuthResponse.self, from: data)
        } catch {
            let rawJSON = String(data: data, encoding: .utf8) ?? "<binary>"
            throw FactoryStatusProbeError
                .parseFailed("Auth decode failed: \(error.localizedDescription). Raw: \(rawJSON.prefix(200))")
        }
    }

    private func fetchUsage(cookieHeader: String, userId: String?) async throws -> FactoryUsageResponse {
        let url = self.baseURL.appendingPathComponent("/api/organization/subscription/usage")
        var request = URLRequest(url: url)
        request.timeoutInterval = self.timeout
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("web-app", forHTTPHeaderField: "x-factory-client")

        // Build request body
        var body: [String: Any] = ["useCache": true]
        if let userId {
            body["userId"] = userId
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FactoryStatusProbeError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw FactoryStatusProbeError.notLoggedIn
        }

        guard httpResponse.statusCode == 200 else {
            throw FactoryStatusProbeError.networkError("HTTP \(httpResponse.statusCode)")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(FactoryUsageResponse.self, from: data)
        } catch {
            let rawJSON = String(data: data, encoding: .utf8) ?? "<binary>"
            throw FactoryStatusProbeError
                .parseFailed("Usage decode failed: \(error.localizedDescription). Raw: \(rawJSON.prefix(200))")
        }
    }

    private func extractUserIdFromAuth(_ auth: FactoryAuthResponse) -> String? {
        // The user ID might be in the organization or we might need to parse JWT
        // For now, return nil and let the API handle it
        nil
    }

    private func buildSnapshot(
        authInfo: FactoryAuthResponse,
        usageData: FactoryUsageResponse,
        userId: String?) -> FactoryStatusSnapshot
    {
        let usage = usageData.usage

        let periodStart: Date? = usage?.startDate.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        let periodEnd: Date? = usage?.endDate.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }

        return FactoryStatusSnapshot(
            standardUserTokens: usage?.standard?.userTokens ?? 0,
            standardOrgTokens: usage?.standard?.orgTotalTokensUsed ?? 0,
            standardAllowance: usage?.standard?.totalAllowance ?? 0,
            premiumUserTokens: usage?.premium?.userTokens ?? 0,
            premiumOrgTokens: usage?.premium?.orgTotalTokensUsed ?? 0,
            premiumAllowance: usage?.premium?.totalAllowance ?? 0,
            periodStart: periodStart,
            periodEnd: periodEnd,
            planName: authInfo.organization?.subscription?.orbSubscription?.plan?.name,
            tier: authInfo.organization?.subscription?.factoryTier,
            organizationName: authInfo.organization?.name,
            accountEmail: nil, // Email is in JWT, not in auth response body
            userId: userId ?? usageData.userId,
            rawJSON: nil)
    }
}

#else

// MARK: - Factory (Unsupported)

public enum FactoryStatusProbeError: LocalizedError, Sendable {
    case notSupported

    public var errorDescription: String? {
        "Factory is only supported on macOS."
    }
}

public struct FactoryStatusSnapshot: Sendable {
    public init() {}

    public func toUsageSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: 0, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            providerCost: nil,
            updatedAt: Date(),
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil)
    }
}

public struct FactoryStatusProbe: Sendable {
    public init(baseURL: URL = URL(string: "https://app.factory.ai")!, timeout: TimeInterval = 15.0) {
        _ = baseURL
        _ = timeout
    }

    public func fetch(logger: ((String) -> Void)? = nil) async throws -> FactoryStatusSnapshot {
        _ = logger
        throw FactoryStatusProbeError.notSupported
    }
}

#endif
