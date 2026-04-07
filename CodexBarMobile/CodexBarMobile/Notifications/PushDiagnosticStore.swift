import Foundation
import Observation

/// Visibility layer for the Mac→iOS push notification chain.
///
/// Every step of the chain (remote registration, CKSubscription creation,
/// silent push arrival, CloudKit fetch, transition detection, local notification
/// post) writes a snapshot into this store, so the user can see exactly where
/// things break without attaching a Mac + Xcode Console.
///
/// Lives in memory only; cleared on app restart so each session starts fresh.
@Observable
@MainActor
final class PushDiagnosticStore {
    static let shared = PushDiagnosticStore()

    // MARK: - Remote Notification Registration

    enum RegistrationState: Equatable {
        case pending
        case success(tokenPrefix: String)
        case failed(message: String)

        var label: String {
            switch self {
            case .pending: "Waiting for APNS registration…"
            case .success(let prefix): "Registered (token: \(prefix)…)"
            case .failed(let msg): "FAILED: \(msg)"
            }
        }
    }

    private(set) var registrationState: RegistrationState = .pending
    private(set) var registrationUpdatedAt: Date?

    // MARK: - CKSubscription

    enum SubscriptionState: Equatable {
        case pending
        case created
        case alreadyExists
        case failed(message: String)

        var label: String {
            switch self {
            case .pending: "Waiting for subscription setup…"
            case .created: "Created fresh"
            case .alreadyExists: "Already exists (serverRejectedRequest)"
            case .failed(let msg): "FAILED: \(msg)"
            }
        }
    }

    private(set) var subscriptionState: SubscriptionState = .pending
    private(set) var subscriptionUpdatedAt: Date?

    // MARK: - Silent Push Receipt

    private(set) var lastPushReceivedAt: Date?
    private(set) var lastPushUserInfoSummary: String?
    private(set) var totalPushCount: Int = 0

    // MARK: - CloudKit Fetch (from push handler)

    enum FetchState: Equatable {
        case none
        case success(deviceCount: Int)
        case empty
        case failed(message: String)

        var label: String {
            switch self {
            case .none: "—"
            case .success(let n): "✓ Fetched \(n) device snapshot(s)"
            case .empty: "(empty)"
            case .failed(let msg): "FAILED: \(msg)"
            }
        }
    }

    private(set) var lastFetchState: FetchState = .none
    private(set) var lastFetchAt: Date?

    // MARK: - Transition Detection

    private(set) var lastTransitionSummary: String = "—"
    private(set) var lastTransitionAt: Date?
    private(set) var totalTransitionCount: Int = 0

    // MARK: - Local Notification Post

    enum NotificationPostState: Equatable {
        case none
        case success(count: Int)
        case suppressed(reason: String)
        case failed(message: String)

        var label: String {
            switch self {
            case .none: "—"
            case .success(let n): "✓ Posted \(n) notification(s)"
            case .suppressed(let reason): "Suppressed: \(reason)"
            case .failed(let msg): "FAILED: \(msg)"
            }
        }
    }

    private(set) var lastNotificationState: NotificationPostState = .none
    private(set) var lastNotificationAt: Date?

    // MARK: - Authorization

    private(set) var notificationAuthorized: Bool?

    // MARK: - Event Log (rolling, most-recent-first)

    struct LogEntry: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String

        enum Level: String {
            case info, warning, error
        }
    }

    private(set) var log: [LogEntry] = []
    private let maxLogEntries = 100

    // MARK: - Writers (called from notification chain)

    func recordRegistrationSuccess(tokenPrefix: String) {
        self.registrationState = .success(tokenPrefix: tokenPrefix)
        self.registrationUpdatedAt = Date()
        self.append(.info, "Remote registration succeeded (\(tokenPrefix)…)")
    }

    func recordRegistrationFailure(_ error: Error) {
        self.registrationState = .failed(message: error.localizedDescription)
        self.registrationUpdatedAt = Date()
        self.append(.error, "Remote registration failed: \(error.localizedDescription)")
    }

    func recordSubscriptionCreated() {
        self.subscriptionState = .created
        self.subscriptionUpdatedAt = Date()
        self.append(.info, "CKSubscription created fresh")
    }

    func recordSubscriptionAlreadyExists() {
        self.subscriptionState = .alreadyExists
        self.subscriptionUpdatedAt = Date()
        self.append(.info, "CKSubscription already exists")
    }

    func recordSubscriptionFailure(_ error: Error) {
        self.subscriptionState = .failed(message: error.localizedDescription)
        self.subscriptionUpdatedAt = Date()
        self.append(.error, "CKSubscription setup failed: \(error.localizedDescription)")
    }

    func recordPushReceived(userInfoSummary: String) {
        self.lastPushReceivedAt = Date()
        self.lastPushUserInfoSummary = userInfoSummary
        self.totalPushCount += 1
        self.append(.info, "Silent push received (total: \(self.totalPushCount))")
    }

    func recordFetch(_ state: FetchState) {
        self.lastFetchState = state
        self.lastFetchAt = Date()
        switch state {
        case .success(let n):
            self.append(.info, "Fetch: \(n) device snapshot(s)")
        case .empty:
            self.append(.warning, "Fetch: empty")
        case .failed(let msg):
            self.append(.error, "Fetch failed: \(msg)")
        case .none:
            break
        }
    }

    func recordTransitions(_ summary: String, count: Int) {
        self.lastTransitionSummary = summary
        self.lastTransitionAt = Date()
        self.totalTransitionCount += count
        if count > 0 {
            self.append(.info, "Transitions detected: \(summary)")
        } else {
            self.append(.info, "No transitions")
        }
    }

    func recordNotificationPost(_ state: NotificationPostState) {
        self.lastNotificationState = state
        self.lastNotificationAt = Date()
        switch state {
        case .success(let n):
            self.append(.info, "Posted \(n) local notification(s)")
        case .suppressed(let reason):
            self.append(.warning, "Notification suppressed: \(reason)")
        case .failed(let msg):
            self.append(.error, "Notification post failed: \(msg)")
        case .none:
            break
        }
    }

    func recordAuthorizationStatus(_ authorized: Bool) {
        self.notificationAuthorized = authorized
        self.append(.info, "UN authorization: \(authorized ? "granted" : "denied")")
    }

    // MARK: - Log helpers

    private func append(_ level: LogEntry.Level, _ message: String) {
        self.log.insert(LogEntry(timestamp: Date(), level: level, message: message), at: 0)
        if self.log.count > self.maxLogEntries {
            self.log.removeLast(self.log.count - self.maxLogEntries)
        }
        // Mirror to stdout so Console.app still sees it.
        print("[CodexBar Push] \(level.rawValue.uppercased()): \(message)")
    }

    func clearLog() {
        self.log = []
    }
}
