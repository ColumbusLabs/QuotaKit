import Foundation

/// PII-safe rendering of an email address for OSLog / NSE diagnostic
/// log fields. The CodexBar `hidePersonalInfo` privacy toggle gates
/// PII at SOURCE (the writer never sets `accountEmail` when the
/// toggle is on), but Apple's defensive convention is to *also*
/// redact identity strings at the log layer so a misrouted log
/// statement or a future hidePersonalInfo regression doesn't leak.
///
/// Format: `<first-char>***@<domain>` — e.g. `admin@example.com`
/// becomes `a***@example.com`. Long enough to identify the account
/// in support tickets, opaque enough to not constitute a PII leak.
/// Empty or non-email inputs pass through unchanged so log
/// statements stay debuggable on garbage data.
///
/// Used by `CloudSyncManager.writeQuotaTransition` /
/// `writeQuotaWarningTransition` log metadata and by
/// `CodexBarMobilePushExtension.NotificationService` NSE invocation
/// log entries. iOS 1.8.0 build 136 / Mac fork build 65.4.
public enum EmailRedaction {
    /// Returns a PII-safe rendering. `nil` → `"<nil>"`, empty → `"<empty>"`,
    /// non-email (no `@`) → returned verbatim, an email → `"x***@domain"`.
    public static func redact(_ email: String?) -> String {
        guard let email else { return "<nil>" }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "<empty>" }
        guard let atIndex = trimmed.firstIndex(of: "@") else {
            // Non-email string — return verbatim. Mac never writes
            // a non-email to `accountEmail`, but logs may carry other
            // identity strings that aren't worth redacting.
            return trimmed
        }
        let local = trimmed[..<atIndex]
        let domain = trimmed[atIndex...]
        guard let firstChar = local.first else {
            return "***\(domain)"
        }
        return "\(firstChar)***\(domain)"
    }
}
