import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OpenCodeUsageError: LocalizedError {
    case invalidCredentials
    case networkError(String)
    case apiError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "OpenCode session cookie is invalid or expired."
        case let .networkError(message):
            "OpenCode network error: \(message)"
        case let .apiError(message):
            "OpenCode API error: \(message)"
        case let .parseFailed(message):
            "OpenCode parse error: \(message)"
        }
    }
}

public struct OpenCodeUsageFetcher: Sendable {
    private static let log = CodexBarLog.logger("opencode-usage")
    private static let baseURL = URL(string: "https://opencode.ai")!
    private static let serverURL = URL(string: "https://opencode.ai/_server")!
    private static let workspacesServerID = "def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f"
    private static let subscriptionServerID = "7abeebee372f304e050aaaf92be863f4a86490e382f8c79db68fd94040d691b4"
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"

    public static func fetchUsage(
        cookieHeader: String,
        timeout: TimeInterval,
        now: Date = Date()) async throws -> OpenCodeUsageSnapshot
    {
        let workspaceID = try await self.fetchWorkspaceID(
            cookieHeader: cookieHeader,
            timeout: timeout)
        let subscriptionText = try await self.fetchSubscription(
            workspaceID: workspaceID,
            cookieHeader: cookieHeader,
            timeout: timeout)
        return try self.parseSubscription(text: subscriptionText, now: now)
    }

    private static func fetchWorkspaceID(
        cookieHeader: String,
        timeout: TimeInterval) async throws -> String
    {
        let text = try await self.fetchServerText(
            serverID: self.workspacesServerID,
            body: nil,
            cookieHeader: cookieHeader,
            timeout: timeout,
            referer: self.baseURL)
        if self.looksSignedOut(text: text) {
            throw OpenCodeUsageError.invalidCredentials
        }
        let ids = self.parseWorkspaceIDs(text: text)
        guard let first = ids.first else {
            throw OpenCodeUsageError.parseFailed("Missing workspace id.")
        }
        return first
    }

    private static func fetchSubscription(
        workspaceID: String,
        cookieHeader: String,
        timeout: TimeInterval) async throws -> String
    {
        let body = try JSONSerialization.data(withJSONObject: [workspaceID], options: [])
        let referer = URL(string: "https://opencode.ai/workspace/\(workspaceID)/billing") ?? self.baseURL
        let text = try await self.fetchServerText(
            serverID: self.subscriptionServerID,
            body: body,
            cookieHeader: cookieHeader,
            timeout: timeout,
            referer: referer)
        if self.looksSignedOut(text: text) {
            throw OpenCodeUsageError.invalidCredentials
        }
        return text
    }

    private static func fetchServerText(
        serverID: String,
        body: Data?,
        cookieHeader: String,
        timeout: TimeInterval,
        referer: URL) async throws -> String
    {
        var request = URLRequest(url: self.serverURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(serverID, forHTTPHeaderField: "X-Server-Id")
        request.setValue("codexbar", forHTTPHeaderField: "X-Server-Instance")
        request.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(self.baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("text/javascript, application/json;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeUsageError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            Self.log.error("OpenCode returned \(httpResponse.statusCode): \(bodyText)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw OpenCodeUsageError.invalidCredentials
            }
            throw OpenCodeUsageError.apiError("HTTP \(httpResponse.statusCode)")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw OpenCodeUsageError.parseFailed("Response was not UTF-8.")
        }
        return text
    }

    static func parseSubscription(text: String, now: Date) throws -> OpenCodeUsageSnapshot {
        if let snapshot = self.parseSubscriptionJSON(text: text, now: now) {
            return snapshot
        }

        guard let rollingPercent = self.extractDouble(
            pattern: #"rollingUsage[^}]*?usagePercent\s*:\s*([0-9]+(?:\.[0-9]+)?)"#,
            text: text),
            let rollingReset = self.extractInt(
                pattern: #"rollingUsage[^}]*?resetInSec\s*:\s*([0-9]+)"#,
                text: text),
            let weeklyPercent = self.extractDouble(
                pattern: #"weeklyUsage[^}]*?usagePercent\s*:\s*([0-9]+(?:\.[0-9]+)?)"#,
                text: text),
            let weeklyReset = self.extractInt(
                pattern: #"weeklyUsage[^}]*?resetInSec\s*:\s*([0-9]+)"#,
                text: text)
        else {
            throw OpenCodeUsageError.parseFailed("Missing usage fields.")
        }

        return OpenCodeUsageSnapshot(
            rollingUsagePercent: rollingPercent,
            weeklyUsagePercent: weeklyPercent,
            rollingResetInSec: rollingReset,
            weeklyResetInSec: weeklyReset,
            updatedAt: now)
    }

    private static func parseSubscriptionJSON(text: String, now: Date) -> OpenCodeUsageSnapshot? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = object as? [String: Any]
        else {
            return nil
        }

        guard let rolling = dict["rollingUsage"] as? [String: Any],
              let weekly = dict["weeklyUsage"] as? [String: Any]
        else {
            return nil
        }

        let rollingPercent = self.doubleValue(from: rolling["usagePercent"])
        let weeklyPercent = self.doubleValue(from: weekly["usagePercent"])
        let rollingReset = self.intValue(from: rolling["resetInSec"])
        let weeklyReset = self.intValue(from: weekly["resetInSec"])

        guard let rollingPercent, let weeklyPercent, let rollingReset, let weeklyReset else { return nil }

        return OpenCodeUsageSnapshot(
            rollingUsagePercent: rollingPercent,
            weeklyUsagePercent: weeklyPercent,
            rollingResetInSec: rollingReset,
            weeklyResetInSec: weeklyReset,
            updatedAt: now)
    }

    static func parseWorkspaceIDs(text: String) -> [String] {
        let pattern = #"id\s*:\s*\"(wrk_[^\"]+)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: nsrange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func extractDouble(pattern: String, text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsrange),
              let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Double(text[range])
    }

    private static func extractInt(pattern: String, text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsrange),
              let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Int(text[range])
    }

    private static func doubleValue(from value: Any?) -> Double? {
        switch value {
        case let number as Double:
            return number
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func intValue(from value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func looksSignedOut(text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("login") || lower.contains("sign in") || lower.contains("not found") {
            return true
        }
        if lower.contains("\"httpError\"") || lower.contains("httperror") {
            return true
        }
        return false
    }
}
