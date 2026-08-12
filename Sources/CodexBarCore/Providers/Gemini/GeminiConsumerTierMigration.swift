import Foundation

/// Shared copy for Google's June 2026 Gemini CLI consumer-tier shutdown.
public enum GeminiConsumerTierMigration {
    public static let deprecationError = """
    Google no longer supports Gemini CLI OAuth for individual, AI Pro, or Ultra accounts. \
    Enable QuotaKit's Antigravity provider, sign in to Antigravity or run `agy`, then refresh.
    """

    public static let oauthRecoveryError = """
    Could not refresh Gemini OAuth credentials. Reinstall or update Gemini CLI. Advanced \
    users launching QuotaKit from a configured environment can set GEMINI_OAUTH_CLIENT_ID \
    and GEMINI_OAUTH_CLIENT_SECRET. Consumer Google AI Pro/Ultra accounts blocked by the \
    June 2026 Gemini CLI shutdown should use QuotaKit's Antigravity provider instead. \
    Workspace and education accounts should keep using Gemini.
    """
}
