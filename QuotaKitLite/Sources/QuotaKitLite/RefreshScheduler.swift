import Dispatch
import Foundation
import LiteCore

/// Drives `RefreshPolicy` with exactly one `DispatchSourceTimer` (068 §5.2).
///
/// The timer is re-armed to the policy's next due date after every event, fetch and environment change. It never
/// repeats and there is no countdown timer; with nothing pending it is disarmed, so an idle Lite sleeps entirely.
/// At most one fetch per provider is in flight, and an event that arrives meanwhile waits for the result.
@MainActor
final class RefreshScheduler {
    typealias Refresh = @Sendable (LiteProvider) async -> Result<ProbeResult, ProbeFailure>

    private var policy: RefreshPolicy
    private let refresh: Refresh
    private let now: @MainActor () -> Date
    private let idleSeconds: @MainActor () -> TimeInterval
    private let timer: DispatchSourceTimer
    private var inFlight: Set<LiteProvider> = []
    private var isRunning = false

    /// - Parameters:
    ///   - refresh: fetches one provider. Called on the main actor's behalf, never twice at once per provider.
    ///   - now: the clock; injectable for tests.
    ///   - idleSeconds: seconds since the last user input. Read only when deciding the heartbeat.
    init(
        enabledProviders: Set<LiteProvider> = Set(LiteProvider.allCases),
        refresh: @escaping Refresh,
        now: @escaping @MainActor () -> Date = { Date() },
        idleSeconds: @escaping @MainActor () -> TimeInterval = { SystemObservers.secondsSinceLastUserInput() })
    {
        self.policy = RefreshPolicy(enabledProviders: enabledProviders)
        self.refresh = refresh
        self.now = now
        self.idleSeconds = idleSeconds
        self.timer = DispatchSource.makeTimerSource(queue: .main)
        self.timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.evaluate()
            }
        }
        self.timer.schedule(wallDeadline: .distantFuture, repeating: .never)
        self.timer.resume()
    }

    isolated deinit {
        self.timer.setEventHandler {}
        self.timer.cancel()
    }

    // MARK: - Lifecycle

    /// Starts scheduling. The first evaluation fetches every enabled provider, because none has been attempted.
    func start() {
        guard !self.isRunning else { return }
        self.isRunning = true
        self.evaluate()
    }

    func stop() {
        self.isRunning = false
        self.timer.schedule(wallDeadline: .distantFuture, repeating: .never)
    }

    /// Seeds a provider from the persisted state, so menu-open staleness and reset confirms work from launch.
    func restore(_ provider: LiteProvider, windows: [QuotaWindow], lastSuccess: Date?) {
        self.policy.restore(provider, windows: windows, lastSuccess: lastSuccess)
    }

    // MARK: - Entry points

    /// The status item menu opened: refresh providers whose data is older than 60 s (§5).
    func menuOpened() {
        self.send(.menuOpened)
    }

    /// Refresh now from the menu.
    func refreshNow() {
        self.send(.manualRefresh)
    }

    /// The Antigravity app launched: fetch after the 5 s grace (§4.3). Process observation itself is S11.
    func antigravityLaunched() {
        self.send(.antigravityLaunched)
    }

    /// FSEvents saw activity for a provider (§5.1).
    func activity(_ provider: LiteProvider) {
        self.send(.activity(provider))
    }

    func networkRestored() {
        self.send(.networkRestored)
    }

    /// The full QuotaKit app is running (§5.4): nothing is fetched while paused, and ending the pause fetches once.
    func setPaused(_ paused: Bool) {
        guard self.policy.environment.isPaused != paused else { return }
        self.policy.environment.isPaused = paused
        if !paused {
            self.policy.handle(.resumed, at: self.now())
        }
        self.evaluate()
    }

    func setEnabledProviders(_ providers: Set<LiteProvider>) {
        guard self.policy.enabledProviders != providers else { return }
        self.policy.enabledProviders = providers
        self.evaluate()
    }

    /// Changes the system state the policy depends on, then re-arms. Used by `SystemObservers`.
    func updateEnvironment(_ change: (inout RefreshPolicy.Environment) -> Void) {
        var environment = self.policy.environment
        change(&environment)
        guard environment != self.policy.environment else { return }
        self.policy.environment = environment
        self.evaluate()
    }

    /// The system woke: clear the asleep flag, then fetch after the settle (§5).
    func systemDidWake() {
        self.policy.environment.isSystemAsleep = false
        self.send(.wake)
    }

    // MARK: - Engine

    private func send(_ event: RefreshPolicy.Event) {
        self.policy.handle(event, at: self.now())
        self.evaluate()
    }

    /// Starts every due fetch, then re-arms the timer. Called by the timer, by each entry point and by each result.
    private func evaluate() {
        guard self.isRunning else { return }
        let now = self.now()
        self.sampleIdle()
        for provider in self.policy.dueProviders(at: now) where !self.inFlight.contains(provider) {
            self.begin(provider, at: now)
        }
        self.rearm(at: now)
    }

    private func begin(_ provider: LiteProvider, at now: Date) {
        self.inFlight.insert(provider)
        self.policy.recordAttempt(provider, at: now)
        let refresh = self.refresh
        Task { [weak self] in
            let result = await refresh(provider)
            self?.finish(provider, result)
        }
    }

    private func finish(_ provider: LiteProvider, _ result: Result<ProbeResult, ProbeFailure>) {
        self.inFlight.remove(provider)
        self.policy.recordResult(provider, result, at: self.now())
        self.evaluate()
    }

    /// The idle check is only ever made here, when the heartbeat is being decided; no timer polls it.
    private func sampleIdle() {
        let idle = self.idleSeconds() >= self.policy.timing.idleThreshold
        if self.policy.environment.isUserIdle != idle {
            self.policy.environment.isUserIdle = idle
        }
    }

    /// Re-arms the single timer to the earliest pending due date, or disarms it.
    private func rearm(at now: Date) {
        // Providers in flight are skipped: their result re-arms the timer, and counting an overdue request
        // that can't start yet would make the timer fire in a loop.
        var next = self.policy.nextDueDate(excluding: self.inFlight)
        let environment = self.policy.environment
        if environment.isUserIdle, !environment.isUserInactiveForOtherReason {
            // Nothing else announces that the user came back from idle, so look again after one heartbeat.
            // That is one wakeup per heartbeat while idle, no network, and cheaper than skipping the heartbeat.
            let recheck = now.addingTimeInterval(self.policy.heartbeatInterval)
            next = next.map { min($0, recheck) } ?? recheck
        }
        guard let next else {
            self.timer.schedule(wallDeadline: .distantFuture, repeating: .never)
            return
        }
        // An overdue date still waits a second, so a due provider that can't start can never spin the timer.
        let interval = max(next.timeIntervalSince(now), 1)
        let leeway = max(interval * 0.1, 5)
        self.timer.schedule(
            wallDeadline: .wallTime(of: now.addingTimeInterval(interval)),
            repeating: .never,
            leeway: .milliseconds(Int(leeway * 1000)))
    }
}

extension RefreshPolicy.Environment {
    /// Locked or display asleep: unlock and screens-wake notifications will re-arm, so no recheck is needed.
    fileprivate var isUserInactiveForOtherReason: Bool {
        self.isScreenLocked || self.isDisplayAsleep
    }
}

extension DispatchWallTime {
    fileprivate static func wallTime(of date: Date) -> DispatchWallTime {
        let seconds = date.timeIntervalSince1970
        let whole = seconds.rounded(.down)
        let spec = timespec(tv_sec: Int(whole), tv_nsec: Int((seconds - whole) * 1_000_000_000))
        return DispatchWallTime(timespec: spec)
    }
}
