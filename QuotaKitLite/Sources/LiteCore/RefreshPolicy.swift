import Foundation

/// The refresh due-time policy (068 §5): a pure value type that turns events, the environment and past
/// results into "which providers are due now" and "when to wake next".
///
/// It owns no timers, reads no clock (`now` is always passed in) and has no side effects, so the whole
/// trigger table in §5 is covered by unit tests. `RefreshScheduler` in the app target drives it with one timer.
///
/// Each provider has a handful of independent "wants a fetch at date X" sources (activity, menu open,
/// wake/launch settle, reset confirm, heartbeat or retry). Its due date is the earliest of them, pushed back to
/// the provider's `blockedUntil` when a 429 or a backoff forbids calling earlier.
public struct RefreshPolicy: Sendable, Equatable {
    // MARK: - Configuration

    /// Every interval from §5, in seconds. Tests use the defaults.
    public struct Timing: Sendable, Equatable {
        /// At most one activity-driven fetch per provider in this span.
        public var activityThrottle: TimeInterval = 90
        /// The activity throttle under Low Power Mode or a serious thermal state.
        public var constrainedActivityThrottle: TimeInterval = 5 * 60
        /// The idle heartbeat while the user is active on the Mac.
        public var heartbeat: TimeInterval = 30 * 60
        /// The heartbeat under Low Power Mode or a serious thermal state.
        public var constrainedHeartbeat: TimeInterval = 60 * 60
        /// Menu open refreshes data at least this old.
        public var menuStaleAfter: TimeInterval = 60
        /// Settle time after a wake or a network return, so Wi-Fi and DNS are up.
        public var wakeSettle: TimeInterval = 10
        /// Grace after the Antigravity app launches, so its language server is listening (§4.3).
        public var antigravityLaunchGrace: TimeInterval = 5
        /// How long after a window's reset time the confirming fetch is due.
        public var resetConfirmDelay: TimeInterval = 60
        /// Idle longer than this counts as "user inactive" and suspends the heartbeat.
        public var idleThreshold: TimeInterval = 30 * 60
        /// The first transient-failure retry delay; it doubles on each further failure.
        public var backoffBase: TimeInterval = 60

        public init() {}
    }

    /// What the Mac is doing right now. The app target sets these from system notifications.
    public struct Environment: Sendable, Equatable {
        public var isLowPowerMode = false
        /// Serious or critical thermal state.
        public var isThermallyConstrained = false
        public var isScreenLocked = false
        public var isDisplayAsleep = false
        /// Input idle for more than `Timing.idleThreshold`. Sampled only when deciding the heartbeat.
        public var isUserIdle = false
        public var isSystemAsleep = false
        /// The full QuotaKit app is running, so Lite stays quiet (§5.4).
        public var isPaused = false

        public init() {}

        /// Low Power Mode or thermal pressure: both slow the activity throttle and the heartbeat (§5).
        public var isConstrained: Bool {
            self.isLowPowerMode || self.isThermallyConstrained
        }

        /// Locked, display asleep or idle: nobody is looking, so the heartbeat is suspended (§5).
        public var isUserInactive: Bool {
            self.isScreenLocked || self.isDisplayAsleep || self.isUserIdle
        }

        /// Nothing may be fetched at all: paused for the full app (§5.4), or the system is asleep.
        var suspendsFetching: Bool {
            self.isPaused || self.isSystemAsleep
        }
    }

    /// Something that happened. System state changes go through `environment` instead.
    public enum Event: Sendable, Equatable {
        /// FSEvents saw writes for this provider (§5.1).
        case activity(LiteProvider)
        /// The status item menu opened.
        case menuOpened
        /// The system woke from sleep.
        case wake
        /// The network path became reachable again.
        case networkRestored
        /// The Antigravity app launched (§4.3).
        case antigravityLaunched
        /// Lite stopped being paused; fetch once.
        case resumed
    }

    /// What the policy remembers about one provider.
    public struct Schedule: Sendable, Equatable {
        public fileprivate(set) var lastAttempt: Date?
        public fileprivate(set) var lastSuccess: Date?
        public fileprivate(set) var lastActivity: Date?
        /// Consecutive transient (`.server`, `.network`) failures. Any other outcome resets it.
        public fileprivate(set) var consecutiveFailures = 0
        /// No fetch before this date: a 429 `until`, or the current backoff.
        public fileprivate(set) var blockedUntil: Date?
        /// When the next attempt is due after a failure; replaces the heartbeat date until the next attempt.
        public fileprivate(set) var retryAt: Date?
        /// The windows from the last success, for reset-boundary confirms.
        public fileprivate(set) var windows: [QuotaWindow] = []

        fileprivate var pendingActivityAt: Date?
        fileprivate var menuRequestedAt: Date?
        fileprivate var settleDueAt: Date?

        public init() {}
    }

    // MARK: - State

    public var timing: Timing
    public var environment = Environment()
    public var enabledProviders: Set<LiteProvider>
    public private(set) var schedules: [LiteProvider: Schedule] = [:]

    public init(enabledProviders: Set<LiteProvider> = Set(LiteProvider.allCases), timing: Timing = Timing()) {
        self.enabledProviders = enabledProviders
        self.timing = timing
    }

    /// The idle heartbeat in effect now.
    public var heartbeatInterval: TimeInterval {
        self.environment.isConstrained ? self.timing.constrainedHeartbeat : self.timing.heartbeat
    }

    /// The activity throttle in effect now.
    public var activityThrottle: TimeInterval {
        self.environment.isConstrained ? self.timing.constrainedActivityThrottle : self.timing.activityThrottle
    }

    // MARK: - Inputs

    /// Seeds a provider from persisted state at launch: the reset-boundary confirms and the menu-open age.
    /// It does not count as an attempt, so a first heartbeat fetch is still due.
    public mutating func restore(_ provider: LiteProvider, windows: [QuotaWindow], lastSuccess: Date?) {
        self.schedules[provider, default: Schedule()].windows = windows
        self.schedules[provider, default: Schedule()].lastSuccess = lastSuccess
    }

    /// Records an event. Events for disabled providers, and events while Lite is paused, are dropped;
    /// `.resumed` requests the one refresh that ends a pause.
    public mutating func handle(_ event: Event, at now: Date) {
        if case .resumed = event {
            for provider in self.enabledProviders {
                self.schedules[provider, default: Schedule()].settleDueAt = now
            }
            return
        }
        guard !self.environment.isPaused else { return }
        switch event {
        case let .activity(provider):
            guard self.enabledProviders.contains(provider) else { return }
            self.schedules[provider, default: Schedule()].lastActivity = now
            if self.schedules[provider, default: Schedule()].pendingActivityAt == nil {
                self.schedules[provider, default: Schedule()].pendingActivityAt = now
            }
        case .menuOpened:
            for provider in self.enabledProviders where self.isMenuStale(provider, at: now) {
                self.schedules[provider, default: Schedule()].menuRequestedAt = now
            }
        case .wake, .networkRestored:
            for provider in self.enabledProviders {
                self.requestSettle(provider, after: self.timing.wakeSettle, at: now)
            }
        case .antigravityLaunched:
            if self.enabledProviders.contains(.antigravity) {
                self.requestSettle(.antigravity, after: self.timing.antigravityLaunchGrace, at: now)
            }
        case .resumed:
            break
        }
    }

    /// The scheduler started a fetch. Clears every request the fetch covers; later ones stay pending.
    public mutating func recordAttempt(_ provider: LiteProvider, at now: Date) {
        var schedule = self.schedules[provider, default: Schedule()]
        schedule.lastAttempt = now
        schedule.retryAt = nil
        if let activity = schedule.pendingActivityAt, activity <= now { schedule.pendingActivityAt = nil }
        if let menu = schedule.menuRequestedAt, menu <= now { schedule.menuRequestedAt = nil }
        if let settle = schedule.settleDueAt, settle <= now { schedule.settleDueAt = nil }
        self.schedules[provider] = schedule
    }

    /// The fetch finished. Success resets backoff; failures set the next retry per the §5 rules.
    public mutating func recordResult(
        _ provider: LiteProvider,
        _ result: Result<ProbeResult, ProbeFailure>,
        at now: Date)
    {
        var schedule = self.schedules[provider, default: Schedule()]
        schedule.retryAt = nil
        schedule.blockedUntil = nil
        switch result {
        case let .success(probe):
            schedule.lastSuccess = now
            schedule.consecutiveFailures = 0
            schedule.windows = probe.windows
        case let .failure(failure):
            switch failure {
            case let .rateLimited(until):
                schedule.consecutiveFailures = 0
                schedule.blockedUntil = until
                schedule.retryAt = until
            case .server, .network:
                schedule.consecutiveFailures += 1
                let delay = self.backoffDelay(afterFailures: schedule.consecutiveFailures)
                schedule.blockedUntil = now.addingTimeInterval(delay)
                schedule.retryAt = schedule.blockedUntil
            case .unrecognizedResponse:
                // A format change won't fix itself in a minute: wait a whole heartbeat (§8).
                schedule.consecutiveFailures = 0
                schedule.blockedUntil = now.addingTimeInterval(self.heartbeatInterval)
                schedule.retryAt = schedule.blockedUntil
            case .tokenExpired, .tokenUnavailable, .signInRequired, .notRunning:
                // Retrying can't help until something changes: the next event or heartbeat decides.
                schedule.consecutiveFailures = 0
            }
        }
        self.schedules[provider] = schedule
    }

    // MARK: - Outputs

    /// When this provider should next be fetched, or nil if nothing is pending. A date at or before now means due.
    public func dueDate(for provider: LiteProvider) -> Date? {
        guard !self.environment.suspendsFetching, self.enabledProviders.contains(provider) else { return nil }
        let schedule = self.schedules[provider] ?? Schedule()
        var candidates: [Date] = []
        if let activity = schedule.pendingActivityAt {
            // At most one fetch per throttle span, however long the burst lasts.
            let earliest = schedule.lastAttempt.map { $0.addingTimeInterval(self.activityThrottle) } ?? activity
            candidates.append(max(activity, earliest))
        }
        if let menu = schedule.menuRequestedAt { candidates.append(menu) }
        if let settle = schedule.settleDueAt { candidates.append(settle) }
        if let confirm = self.resetConfirmDate(for: schedule) { candidates.append(confirm) }
        if !self.environment.isUserInactive {
            // The heartbeat, or the retry that replaces it after a failure. Suspended while nobody is looking.
            let heartbeat = schedule.lastAttempt.map { $0.addingTimeInterval(self.heartbeatInterval) } ?? .distantPast
            candidates.append(schedule.retryAt ?? heartbeat)
        }
        guard let earliest = candidates.min() else { return nil }
        guard let blocked = schedule.blockedUntil else { return earliest }
        return max(earliest, blocked)
    }

    /// Providers due at `now`, in `LiteProvider.allCases` order.
    public func dueProviders(at now: Date) -> [LiteProvider] {
        LiteProvider.allCases.filter { provider in
            self.dueDate(for: provider).map { $0 <= now } ?? false
        }
    }

    /// The earliest due date across providers, or nil if nothing is pending. `excluding` skips providers whose
    /// fetch is already in flight, so an overdue request can't make the timer spin.
    public func nextDueDate(excluding: Set<LiteProvider> = []) -> Date? {
        LiteProvider.allCases
            .filter { !excluding.contains($0) }
            .compactMap { self.dueDate(for: $0) }
            .min()
    }

    // MARK: - Internals

    private func isMenuStale(_ provider: LiteProvider, at now: Date) -> Bool {
        let schedule = self.schedules[provider] ?? Schedule()
        let staleAfter = self.timing.menuStaleAfter
        // A recent attempt, even a failed one, also counts: reopening the menu is not a retry button.
        let recent = [schedule.lastSuccess, schedule.lastAttempt].contains { date in
            date.map { now.timeIntervalSince($0) < staleAfter } ?? false
        }
        return !recent
    }

    private mutating func requestSettle(_ provider: LiteProvider, after delay: TimeInterval, at now: Date) {
        let due = now.addingTimeInterval(delay)
        let existing = self.schedules[provider, default: Schedule()].settleDueAt
        // Keep the earlier request: a second event must not push a pending settle back.
        self.schedules[provider, default: Schedule()].settleDueAt = existing.map { min($0, due) } ?? due
    }

    /// Transient failures back off 1, 2, 4, 8 minutes and so on, capped at the heartbeat (§5).
    private func backoffDelay(afterFailures failures: Int) -> TimeInterval {
        let exponent = Double(min(max(failures, 1) - 1, 20))
        return min(self.timing.backoffBase * pow(2, exponent), self.heartbeatInterval)
    }

    /// The first reset boundary `b` of any window with `b + delay` after the last attempt, plus the delay.
    /// Boundaries past the stored `resetsAt` follow `QuotaWindow.projected(at:)`, in whole window lengths.
    private func resetConfirmDate(for schedule: Schedule) -> Date? {
        let delay = self.timing.resetConfirmDelay
        return schedule.windows.compactMap { window -> Date? in
            guard let resetsAt = window.resetsAt else { return nil }
            guard let lastAttempt = schedule.lastAttempt, window.windowMinutes > 0 else {
                return resetsAt.addingTimeInterval(delay)
            }
            let length = TimeInterval(window.windowMinutes) * 60
            let missed = lastAttempt.timeIntervalSince(resetsAt.addingTimeInterval(delay)) / length
            let periods = missed < 0 ? 0 : missed.rounded(.down) + 1
            return resetsAt.addingTimeInterval(periods * length + delay)
        }.min()
    }
}
