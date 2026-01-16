import CodexBarCore
import Foundation

enum TokenAccountInjection: Sendable {
    case cookieHeader
    case environment(key: String)
}

struct TokenAccountSupport: Sendable {
    let title: String
    let subtitle: String
    let placeholder: String
    let injection: TokenAccountInjection
    let requiresManualCookieSource: Bool
    let cookieName: String?
}

enum TokenAccountSupportCatalog {
    static func support(for provider: UsageProvider) -> TokenAccountSupport? {
        switch provider {
        case .claude:
            TokenAccountSupport(
                title: "Session tokens",
                subtitle: "Store multiple Claude session keys (sessionKey).",
                placeholder: "Paste sessionKey…",
                injection: .cookieHeader,
                requiresManualCookieSource: true,
                cookieName: "sessionKey")
        case .zai:
            TokenAccountSupport(
                title: "API tokens",
                subtitle: "Stored locally in token-accounts.json.",
                placeholder: "Paste token…",
                injection: .environment(key: ZaiSettingsReader.apiTokenKey),
                requiresManualCookieSource: false,
                cookieName: nil)
        case .cursor:
            TokenAccountSupport(
                title: "Session tokens",
                subtitle: "Store multiple Cursor Cookie headers.",
                placeholder: "Cookie: …",
                injection: .cookieHeader,
                requiresManualCookieSource: true,
                cookieName: nil)
        case .opencode:
            TokenAccountSupport(
                title: "Session tokens",
                subtitle: "Store multiple OpenCode Cookie headers.",
                placeholder: "Cookie: …",
                injection: .cookieHeader,
                requiresManualCookieSource: true,
                cookieName: nil)
        case .factory:
            TokenAccountSupport(
                title: "Session tokens",
                subtitle: "Store multiple Factory Cookie headers.",
                placeholder: "Cookie: …",
                injection: .cookieHeader,
                requiresManualCookieSource: true,
                cookieName: nil)
        case .minimax:
            TokenAccountSupport(
                title: "Session tokens",
                subtitle: "Store multiple MiniMax Cookie headers.",
                placeholder: "Cookie: …",
                injection: .cookieHeader,
                requiresManualCookieSource: true,
                cookieName: nil)
        case .augment:
            TokenAccountSupport(
                title: "Session tokens",
                subtitle: "Store multiple Augment Cookie headers.",
                placeholder: "Cookie: …",
                injection: .cookieHeader,
                requiresManualCookieSource: true,
                cookieName: nil)
        case .codex, .gemini, .antigravity, .copilot, .kiro, .vertexai:
            nil
        }
    }

    static func envOverride(for provider: UsageProvider, token: String) -> [String: String]? {
        guard let support = self.support(for: provider) else { return nil }
        switch support.injection {
        case let .environment(key):
            return [key: token]
        case .cookieHeader:
            return nil
        }
    }
}
