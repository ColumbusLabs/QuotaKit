import Foundation

public struct MiniMaxSettingsReader: Sendable {
    public static let cookieHeaderKeys = [
        "MINIMAX_COOKIE",
        "MINIMAX_COOKIE_HEADER",
    ]

    public static func cookieHeader(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        for key in self.cookieHeaderKeys {
            guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else {
                continue
            }
            if MiniMaxCookieHeader.normalized(from: raw) != nil {
                return raw
            }
        }
        return nil
    }
}

public enum MiniMaxSettingsError: LocalizedError, Sendable {
    case missingCookie

    public var errorDescription: String? {
        switch self {
        case .missingCookie:
            "MiniMax session not found. Sign in to platform.minimax.io in your browser and try again."
        }
    }
}
