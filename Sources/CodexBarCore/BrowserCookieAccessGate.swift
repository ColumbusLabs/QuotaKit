import Foundation

#if os(macOS)
import os.lock
import SweetCookieKit

public enum BrowserCookieAccessGate {
    private struct State {
        var loaded = false
        var deniedUntilByBrowser: [String: Date] = [:]
    }

    private static let lock = OSAllocatedUnfairLock<State>(initialState: State())
    private static let defaultsKey = "browserCookieAccessDeniedUntil"
    private static let cooldownInterval: TimeInterval = 60 * 60 * 6
    private static let log = CodexBarLog.logger("browser-cookie-gate")

    public static func shouldAttempt(_ browser: Browser, now: Date = Date()) -> Bool {
        guard browser.usesKeychainForCookieDecryption else { return true }
        return self.lock.withLock { state in
            self.loadIfNeeded(&state)
            if let blockedUntil = state.deniedUntilByBrowser[browser.rawValue] {
                if blockedUntil > now {
                    return false
                }
                state.deniedUntilByBrowser.removeValue(forKey: browser.rawValue)
                self.persist(state)
            }
            return true
        }
    }

    public static func recordIfNeeded(_ error: Error, now: Date = Date()) {
        guard let error = error as? BrowserCookieError else { return }
        guard case .accessDenied = error else { return }
        self.recordDenied(for: error.browser, now: now)
    }

    public static func recordDenied(for browser: Browser, now: Date = Date()) {
        guard browser.usesKeychainForCookieDecryption else { return }
        let blockedUntil = now.addingTimeInterval(self.cooldownInterval)
        self.lock.withLock { state in
            self.loadIfNeeded(&state)
            state.deniedUntilByBrowser[browser.rawValue] = blockedUntil
            self.persist(state)
        }
        self.log
            .info(
                "Browser cookie access denied for \(browser.displayName); suppressing prompts until \(blockedUntil)")
    }

    private static func loadIfNeeded(_ state: inout State) {
        guard !state.loaded else { return }
        state.loaded = true
        guard let raw = UserDefaults.standard.dictionary(forKey: self.defaultsKey) as? [String: Double] else {
            return
        }
        state.deniedUntilByBrowser = raw.compactMapValues { Date(timeIntervalSince1970: $0) }
    }

    private static func persist(_ state: State) {
        let raw = state.deniedUntilByBrowser.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(raw, forKey: self.defaultsKey)
    }
}
#else
public enum BrowserCookieAccessGate {
    public static func shouldAttempt(_ browser: Browser, now: Date = Date()) -> Bool { true }
    public static func recordIfNeeded(_ error: Error, now: Date = Date()) {}
    public static func recordDenied(for browser: Browser, now: Date = Date()) {}
}
#endif
