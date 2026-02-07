import Foundation

public enum ClaudeOAuthDelegatedRefreshCoordinator {
    public enum Outcome: Sendable, Equatable {
        case skippedByCooldown
        case cliUnavailable
        case attemptedSucceeded
        case attemptedFailed(String)
    }

    private static let log = CodexBarLog.logger(LogCategories.claudeUsage)
    private static let cooldownDefaultsKey = "claudeOAuthDelegatedRefreshLastAttemptAtV1"
    private static let cooldownIntervalDefaultsKey = "claudeOAuthDelegatedRefreshCooldownIntervalSecondsV1"
    private static let defaultCooldownInterval: TimeInterval = 60 * 5
    private static let shortCooldownInterval: TimeInterval = 20

    private static let stateLock = NSLock()
    private nonisolated(unsafe) static var hasLoadedState = false
    private nonisolated(unsafe) static var lastAttemptAt: Date?
    private nonisolated(unsafe) static var lastCooldownInterval: TimeInterval?

    public static func attempt(now: Date = Date(), timeout: TimeInterval = 8) async -> Outcome {
        if Task.isCancelled {
            return .attemptedFailed("Cancelled.")
        }

        guard self.isClaudeCLIAvailable() else {
            self.log.info("Claude OAuth delegated refresh skipped: claude CLI unavailable")
            return .cliUnavailable
        }

        guard !self.isInCooldown(now: now) else {
            self.log.debug("Claude OAuth delegated refresh skipped by cooldown")
            return .skippedByCooldown
        }

        // Reserve a short cooldown immediately so concurrent callers don't race past isInCooldown() and start
        // multiple touches/poll loops.
        self.recordAttempt(now: now, cooldown: self.shortCooldownInterval)

        let fingerprintBefore = self.currentClaudeKeychainFingerprint()
        var touchError: Error?

        do {
            try await self.touchOAuthAuthPath(timeout: timeout)
        } catch {
            touchError = error
        }

        // "Touch succeeded" must mean we actually observed the Claude keychain entry change.
        // Otherwise we end up in a long cooldown with still-expired credentials.
        let changed = await self.waitForClaudeKeychainChange(
            from: fingerprintBefore,
            timeout: min(max(timeout, 3), 12))
        if changed {
            self.recordAttempt(now: now, cooldown: self.defaultCooldownInterval)
            self.log.info("Claude OAuth delegated refresh touch succeeded")
            return .attemptedSucceeded
        }

        self.recordAttempt(now: now, cooldown: self.shortCooldownInterval)
        if let touchError {
            let message = touchError.localizedDescription
            self.log.warning(
                "Claude OAuth delegated refresh touch failed",
                metadata: ["error": message])
            return .attemptedFailed(message)
        }

        self.log.warning("Claude OAuth delegated refresh touch did not update Claude keychain")
        return .attemptedFailed("Claude keychain did not update after Claude CLI touch.")
    }

    public static func isInCooldown(now: Date = Date()) -> Bool {
        guard let lastAttemptAt = self.lastAttemptDate() else { return false }
        return now.timeIntervalSince(lastAttemptAt) < self.cooldownInterval
    }

    public static func cooldownRemainingSeconds(now: Date = Date()) -> Int? {
        guard let lastAttemptAt = self.lastAttemptDate() else { return nil }
        let remaining = self.cooldownInterval - now.timeIntervalSince(lastAttemptAt)
        guard remaining > 0 else { return nil }
        return Int(remaining.rounded(.up))
    }

    public static func isClaudeCLIAvailable() -> Bool {
        #if DEBUG
        if let override = self.cliAvailableOverride {
            return override
        }
        #endif
        return ClaudeStatusProbe.isClaudeBinaryAvailable()
    }

    private static func touchOAuthAuthPath(timeout: TimeInterval) async throws {
        #if DEBUG
        if let override = self.touchAuthPathOverride {
            try await override(timeout)
            return
        }
        #endif
        try await ClaudeStatusProbe.touchOAuthAuthPath(timeout: timeout)
    }

    private static func waitForClaudeKeychainChange(
        from fingerprintBefore: ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint?,
        timeout: TimeInterval) async -> Bool
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            do {
                try Task.checkCancellation()
            } catch {
                return false
            }

            let current = self.currentClaudeKeychainFingerprint()
            if current != fingerprintBefore {
                return true
            }
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch is CancellationError {
                return false
            } catch {
                // Ignore other errors and keep polling until the deadline.
            }
        }
        return false
    }

    private static func currentClaudeKeychainFingerprint() -> ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint? {
        #if DEBUG
        if let override = self.keychainFingerprintOverride {
            return override()
        }
        #endif
        return ClaudeOAuthCredentialsStore.currentClaudeKeychainFingerprintWithoutPromptForAuthGate()
    }

    private static func lastAttemptDate() -> Date? {
        self.stateLock.lock()
        defer { self.stateLock.unlock() }
        self.loadStateIfNeededLocked()
        return self.lastAttemptAt
    }

    private static var cooldownInterval: TimeInterval {
        self.stateLock.lock()
        defer { self.stateLock.unlock() }
        self.loadStateIfNeededLocked()
        return self.lastCooldownInterval ?? self.defaultCooldownInterval
    }

    private static func recordAttempt(now: Date, cooldown: TimeInterval) {
        self.stateLock.lock()
        defer { self.stateLock.unlock() }
        self.loadStateIfNeededLocked()
        self.lastAttemptAt = now
        self.lastCooldownInterval = cooldown
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: self.cooldownDefaultsKey)
        UserDefaults.standard.set(cooldown, forKey: self.cooldownIntervalDefaultsKey)
    }

    private static func loadStateIfNeededLocked() {
        guard !self.hasLoadedState else { return }
        self.hasLoadedState = true
        guard let raw = UserDefaults.standard.object(forKey: self.cooldownDefaultsKey) as? Double else {
            self.lastAttemptAt = nil
            self.lastCooldownInterval = nil
            return
        }
        self.lastAttemptAt = Date(timeIntervalSince1970: raw)
        if let interval = UserDefaults.standard.object(forKey: self.cooldownIntervalDefaultsKey) as? Double {
            self.lastCooldownInterval = interval
        } else {
            self.lastCooldownInterval = nil
        }
    }

    #if DEBUG
    private nonisolated(unsafe) static var cliAvailableOverride: Bool?
    private nonisolated(unsafe) static var touchAuthPathOverride: (@Sendable (TimeInterval) async throws -> Void)?
    private nonisolated(unsafe) static var keychainFingerprintOverride: (() -> ClaudeOAuthCredentialsStore
        .ClaudeKeychainFingerprint?)?

    static func setCLIAvailableOverrideForTesting(_ override: Bool?) {
        self.cliAvailableOverride = override
    }

    static func setTouchAuthPathOverrideForTesting(_ override: (@Sendable (TimeInterval) async throws -> Void)?) {
        self.touchAuthPathOverride = override
    }

    static func setKeychainFingerprintOverrideForTesting(
        _ override: (() -> ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint?)?)
    {
        self.keychainFingerprintOverride = override
    }

    static func resetForTesting() {
        self.stateLock.lock()
        self.hasLoadedState = true
        self.lastAttemptAt = nil
        self.lastCooldownInterval = nil
        self.stateLock.unlock()
        UserDefaults.standard.removeObject(forKey: self.cooldownDefaultsKey)
        UserDefaults.standard.removeObject(forKey: self.cooldownIntervalDefaultsKey)
        self.cliAvailableOverride = nil
        self.touchAuthPathOverride = nil
        self.keychainFingerprintOverride = nil
    }
    #endif
}
