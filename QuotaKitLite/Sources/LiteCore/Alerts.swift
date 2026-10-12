import CodexBarSync
import CryptoKit
import Foundation

/// Warning thresholds, as remaining percents (068 §6.4). The presets are the Alerts ▸ choices.
public enum AlertThresholds: String, CaseIterable, Sendable {
    case standard
    case late
    case depletedOnly

    /// Highest first, like `QuotaWarningThresholds.sanitized`.
    public var values: [Int] {
        switch self {
        case .standard: [50, 20]
        case .late: [25, 10]
        case .depletedOnly: []
        }
    }

    public var displayName: String {
        switch self {
        case .standard: "50% / 20% Left"
        case .late: "25% / 10% Left"
        case .depletedOnly: "Depleted Only"
        }
    }

    /// What the iPhone draws as warning markers, so they sit where alerts fire (§6.4).
    public var syncConfig: SyncQuotaWarningConfig {
        let enabled = !self.values.isEmpty
        return SyncQuotaWarningConfig(
            sessionThresholds: enabled ? self.values : nil,
            sessionEnabled: enabled,
            weeklyThresholds: enabled ? self.values : nil,
            weeklyEnabled: enabled)
    }
}

/// One alert to deliver, to the iPhone and as a Mac banner.
public struct AlertEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The session window reached 0% left.
        case depleted
        /// The session window has quota again after being depleted.
        case restored
        /// A window fell to or below a warning threshold.
        case warning(lane: QuotaWindow.Lane, threshold: Int, remaining: Double)
    }

    public let provider: LiteProvider
    public let kind: Kind
    public let accountEmail: String?

    /// The CloudKit `state`, which is also part of the zone name.
    public var state: String {
        switch self.kind {
        case .depleted: "depleted"
        case .restored: "restored"
        case .warning: "warning"
        }
    }

    /// `QuotaTransitionWriter.deduplicationScope`: 8 bytes of SHA256 over the account discriminator, so the same
    /// account's alerts in one hour collapse into one record. Lite uses the full app's generic `email:` form.
    public var deduplicationScope: String? {
        guard let email = self.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !email.isEmpty
        else { return nil }
        return SHA256.hash(data: Data("email:\(email)".utf8)).prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// The Mac banner, in the full app's English wording (`en.lproj/Localizable.strings`).
    public var banner: (title: String, body: String) {
        let name = self.provider.displayName
        switch self.kind {
        case .depleted:
            return ("\(name) session depleted", "0% left. Will notify when it's available again.")
        case .restored:
            return ("\(name) session restored", "Session quota is available again.")
        case let .warning(lane, threshold, remaining):
            let window = lane.rawValue
            let left = "\(Int(min(100, max(0, remaining)).rounded()))%"
            let body = if let accountEmail {
                "Account \(accountEmail). \(left) left. Reached your \(threshold)% \(window) warning threshold."
            } else {
                "\(left) left. Reached your \(threshold)% \(window) warning threshold."
            }
            return ("\(name) \(window) quota low", body)
        }
    }
}

/// What alert evaluation remembers per provider, persisted so a restart doesn't re-fire (068 §6.4).
public struct AlertMemory: Codable, Sendable, Equatable {
    /// The account the memory belongs to. A different account starts over without alerting.
    public var accountEmail: String?
    /// The session window's remaining percent at the last fetch, for depleted and restored.
    public var sessionRemaining: Double?
    /// Remaining percent per lane at the last fetch, for threshold crossings.
    public var remaining: [QuotaWindow.Lane: Double]
    /// Thresholds already alerted per lane; cleared once the window climbs back above them.
    public var fired: [QuotaWindow.Lane: Set<Int>]

    public init(
        accountEmail: String? = nil,
        sessionRemaining: Double? = nil,
        remaining: [QuotaWindow.Lane: Double] = [:],
        fired: [QuotaWindow.Lane: Set<Int>] = [:])
    {
        self.accountEmail = accountEmail
        self.sessionRemaining = sessionRemaining
        self.remaining = remaining
        self.fired = fired
    }
}

/// The full app's `SessionQuotaNotificationLogic` and `QuotaWarningNotificationLogic`, on fetched data only.
public enum AlertLogic {
    /// `SessionQuotaNotificationLogic.depletedThreshold`.
    static let depletedThreshold = 0.0001

    /// Evaluates one successful fetch. Never call it with projected windows: alerts don't come from guesses.
    ///
    /// With no memory (the first fetch ever, or a new account) nothing fires; the thresholds already passed are
    /// only recorded, so turning Lite on below 20% doesn't alert about the past.
    public static func evaluate(
        provider: LiteProvider,
        windows: [QuotaWindow],
        accountEmail: String?,
        thresholds: [Int],
        memory: AlertMemory?) -> (events: [AlertEvent], memory: AlertMemory)
    {
        let previous = memory?.accountEmail == accountEmail ? memory : nil
        var next = AlertMemory(accountEmail: accountEmail)
        var events: [AlertEvent] = []
        let active = thresholds.filter { (1...99).contains($0) }

        let session = windows.representative(.session, for: provider)?.remainingPercent
        next.sessionRemaining = session
        if let session, let before = previous?.sessionRemaining {
            let wasDepleted = before <= self.depletedThreshold
            let isDepleted = session <= self.depletedThreshold
            if !wasDepleted, isDepleted {
                events.append(AlertEvent(provider: provider, kind: .depleted, accountEmail: accountEmail))
            } else if wasDepleted, !isDepleted {
                events.append(AlertEvent(provider: provider, kind: .restored, accountEmail: accountEmail))
            }
        }

        for lane in [QuotaWindow.Lane.session, .weekly] {
            guard let remaining = windows.representative(lane, for: provider)?.remainingPercent else { continue }
            next.remaining[lane] = remaining
            // `thresholdsToClear`: a window back above a threshold can alert on it again.
            var fired = (previous?.fired[lane] ?? []).filter { remaining <= Double($0) }
            let eligible = active.filter { remaining <= Double($0) && !fired.contains($0) }
            if let previous, !eligible.isEmpty {
                // `crossedThreshold`: the lowest threshold crossed since the last fetch.
                let before = previous.remaining[lane]
                let crossed = before.map { before in eligible.filter { before > Double($0) } } ?? eligible
                if let threshold = crossed.min() {
                    events.append(AlertEvent(
                        provider: provider,
                        kind: .warning(lane: lane, threshold: threshold, remaining: remaining),
                        accountEmail: accountEmail))
                    // `firedThresholdsAfterWarning`: this threshold and every higher one.
                    fired.formUnion(active.filter { $0 >= threshold })
                }
            } else if previous == nil {
                fired.formUnion(eligible)
            }
            next.fired[lane] = fired
        }
        return (events, next)
    }
}

/// Persists `AlertMemory` per provider as JSON next to `state.json`.
public struct AlertMemoryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        LiteStateStore.defaultFileURL().deletingLastPathComponent().appendingPathComponent("alerts.json")
    }

    public func load() -> [LiteProvider: AlertMemory] {
        guard let data = try? Data(contentsOf: self.fileURL),
              let memories = try? JSONDecoder().decode([LiteProvider: AlertMemory].self, from: data)
        else { return [:] }
        return memories
    }

    public func save(_ memories: [LiteProvider: AlertMemory]) throws {
        try FileManager.default.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try JSONEncoder().encode(memories).write(to: self.fileURL, options: .atomic)
    }
}

/// `QuotaTransitionWriter`'s debounce: 5 minutes per (provider, state, account) for depleted and restored, 60 s per
/// (provider, window, threshold, account) for warnings. A delivery is recorded only once it succeeded, so a failed
/// write doesn't start the window.
public struct AlertDebouncer: Sendable {
    public static let transitionInterval: TimeInterval = 5 * 60
    public static let warningInterval: TimeInterval = 60

    private var lastDelivery: [String: Date] = [:]

    public init() {}

    public func allows(_ event: AlertEvent, at now: Date) -> Bool {
        guard let last = self.lastDelivery[Self.key(for: event)] else { return true }
        return now.timeIntervalSince(last) >= Self.interval(for: event)
    }

    public mutating func recordDelivery(of event: AlertEvent, at now: Date) {
        self.lastDelivery[Self.key(for: event)] = now
    }

    static func key(for event: AlertEvent) -> String {
        let scope = event.deduplicationScope ?? "legacy"
        return switch event.kind {
        case .depleted, .restored:
            "\(event.provider.rawValue)|\(event.state)|\(scope)"
        case let .warning(lane, threshold, _):
            "\(event.provider.rawValue)|\(lane.rawValue)|\(threshold)|\(scope)"
        }
    }

    static func interval(for event: AlertEvent) -> TimeInterval {
        if case .warning = event.kind { return self.warningInterval }
        return self.transitionInterval
    }
}
