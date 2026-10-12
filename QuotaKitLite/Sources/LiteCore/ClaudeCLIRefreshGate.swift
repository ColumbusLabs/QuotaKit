import Foundation

/// When Lite may ask the Claude CLI to refresh its own expired login (068 §4.1, amended 2026-10-12).
///
/// Lite still never refreshes Claude's token itself: the refresh token rotates, and spending it would sign Claude
/// Code out. Instead, like the full app's delegated refresh, Lite starts `claude` briefly so Claude Code renews its
/// own credentials and saves them to its Keychain item, which Lite then re-reads. That costs a few seconds of a
/// subprocess, so it is rationed: at most one attempt per cooldown, whatever the outcome.
public struct ClaudeCLIRefreshGate: Sendable, Equatable {
    public static let cooldown: TimeInterval = 30 * 60

    public private(set) var lastAttempt: Date?

    public init(lastAttempt: Date? = nil) {
        self.lastAttempt = lastAttempt
    }

    /// Only for an expired token, and only once per cooldown.
    public func allowsAttempt(for failure: ProbeFailure, at now: Date) -> Bool {
        guard failure == .tokenExpired else { return false }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= Self.cooldown || now < lastAttempt
    }

    public mutating func recordAttempt(at now: Date) {
        self.lastAttempt = now
    }
}
