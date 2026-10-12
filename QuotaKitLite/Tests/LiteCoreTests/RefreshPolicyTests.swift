import Foundation
import LiteCore
import Testing

/// The trigger table of 068 §5 as a policy table. Every test passes its own times; nothing reads a clock.
struct RefreshPolicyTests {
    private static let t0 = Date(timeIntervalSince1970: 2_000_000)
    private static let minute: TimeInterval = 60

    private static let emptySuccess = Result<ProbeResult, ProbeFailure>.success(ProbeResult(windows: []))

    private static func at(_ seconds: TimeInterval) -> Date {
        self.t0.addingTimeInterval(seconds)
    }

    private static func policy(_ providers: Set<LiteProvider> = [.claude]) -> RefreshPolicy {
        RefreshPolicy(enabledProviders: providers)
    }

    /// An attempt at `seconds` that finishes at once with `result`.
    private static func fetch(
        _ policy: inout RefreshPolicy,
        _ provider: LiteProvider = .claude,
        at seconds: TimeInterval,
        _ result: Result<ProbeResult, ProbeFailure> = Self.emptySuccess)
    {
        policy.recordAttempt(provider, at: self.at(seconds))
        policy.recordResult(provider, result, at: self.at(seconds))
    }

    enum Inactivity: CaseIterable {
        case locked, displayAsleep, idle

        func set(_ value: Bool, in environment: inout RefreshPolicy.Environment) {
            switch self {
            case .locked: environment.isScreenLocked = value
            case .displayAsleep: environment.isDisplayAsleep = value
            case .idle: environment.isUserIdle = value
            }
        }
    }

    enum Constraint: CaseIterable {
        case lowPower, thermal

        func set(_ value: Bool, in environment: inout RefreshPolicy.Environment) {
            switch self {
            case .lowPower: environment.isLowPowerMode = value
            case .thermal: environment.isThermallyConstrained = value
            }
        }
    }

    private static func window(resetsInSeconds: TimeInterval, minutes: Int = 300) -> QuotaWindow {
        QuotaWindow(
            label: "Session",
            lane: .session,
            usedPercent: 40,
            windowMinutes: minutes,
            resetsAt: self.at(resetsInSeconds))
    }

    // MARK: - Activity

    @Test
    func `a provider never fetched is due immediately`() {
        let policy = Self.policy()

        #expect(policy.dueProviders(at: Self.t0) == [.claude])
    }

    @Test
    func `activity right after a fetch waits for the 90 second throttle`() {
        var policy = Self.policy()
        Self.fetch(&policy, at: 0)

        policy.handle(.activity(.claude), at: Self.at(10))

        #expect(policy.dueDate(for: .claude) == Self.at(90))
        #expect(policy.dueProviders(at: Self.at(89)).isEmpty)
        #expect(policy.dueProviders(at: Self.at(90)) == [.claude])
    }

    @Test
    func `activity after the throttle span refreshes right away`() {
        var policy = Self.policy()
        Self.fetch(&policy, at: 0)

        policy.handle(.activity(.claude), at: Self.at(200))

        #expect(policy.dueDate(for: .claude) == Self.at(200))
    }

    @Test
    func `an activity burst gives at most one fetch per 90 seconds`() {
        var policy = Self.policy()
        Self.fetch(&policy, at: 0)
        var attempts: [TimeInterval] = []

        // Ten minutes of writes every 15 seconds, polled every 5 seconds the way a timer would fire.
        for second in stride(from: 5.0, through: 600, by: 5) {
            if second.truncatingRemainder(dividingBy: 15) == 0 {
                policy.handle(.activity(.claude), at: Self.at(second))
            }
            if policy.dueProviders(at: Self.at(second)).contains(.claude) {
                Self.fetch(&policy, at: second)
                attempts.append(second)
            }
        }

        // Fetches at 90, 180, 270 and so on: never closer than 90 seconds, and the burst still gets refreshed.
        #expect(attempts == [90, 180, 270, 360, 450, 540])
        for (earlier, later) in zip(attempts, attempts.dropFirst()) {
            #expect(later - earlier >= 90)
        }
    }

    @Test
    func `activity during a fetch stays pending until the throttle ends`() {
        var policy = Self.policy()
        policy.recordAttempt(.claude, at: Self.at(0))
        policy.handle(.activity(.claude), at: Self.at(20))
        policy.recordResult(.claude, Self.emptySuccess, at: Self.at(30))

        #expect(policy.dueDate(for: .claude) == Self.at(90))
    }

    @Test
    func `a fetch clears the activity it covers`() {
        var policy = Self.policy()
        Self.fetch(&policy, at: 0)
        policy.handle(.activity(.claude), at: Self.at(100))
        Self.fetch(&policy, at: 100)

        #expect(policy.dueDate(for: .claude) == Self.at(100 + 30 * Self.minute))
    }

    @Test
    func `activity for one provider leaves the others alone`() {
        var policy = Self.policy([.claude, .codex])
        Self.fetch(&policy, .claude, at: 0)
        Self.fetch(&policy, .codex, at: 0)

        policy.handle(.activity(.codex), at: Self.at(200))

        #expect(policy.dueProviders(at: Self.at(200)) == [.codex])
    }

    // MARK: - Menu

    @Test
    func `menu open refreshes only data older than 60 seconds`() {
        var policy = Self.policy([.claude, .codex])
        Self.fetch(&policy, .claude, at: -30)
        Self.fetch(&policy, .codex, at: -120)

        policy.handle(.menuOpened, at: Self.t0)

        #expect(policy.dueProviders(at: Self.t0) == [.codex])
    }

    @Test
    func `menu open does not retry a provider that just failed`() {
        var policy = Self.policy()
        Self.fetch(&policy, at: -10, .failure(.tokenExpired))

        policy.handle(.menuOpened, at: Self.t0)

        #expect(policy.dueProviders(at: Self.t0).isEmpty)
    }

    @Test
    func `menu open refreshes data restored from disk`() {
        var policy = Self.policy()
        policy.restore(.claude, windows: [], lastSuccess: Self.at(-3600))

        policy.handle(.menuOpened, at: Self.t0)

        #expect(policy.dueProviders(at: Self.t0) == [.claude])
    }

    @Test
    func `refresh now fetches every enabled provider even with fresh data`() {
        var policy = Self.policy([.claude, .codex])
        Self.fetch(&policy, .claude, at: -5)
        Self.fetch(&policy, .codex, at: -5)

        policy.handle(.manualRefresh, at: Self.t0)

        #expect(policy.dueProviders(at: Self.t0) == [.claude, .codex])
    }

    @Test
    func `refresh now still waits out a rate limit`() {
        var policy = Self.policy()
        let until = Self.at(600)
        Self.fetch(&policy, at: 0, .failure(.rateLimited(until: until)))

        policy.handle(.manualRefresh, at: Self.at(60))

        #expect(policy.dueDate(for: .claude) == until)
    }

    // MARK: - Heartbeat

    @Test
    func `the refresh interval preference sets the heartbeat`() {
        var policy = Self.policy()
        policy.setHeartbeat(2 * Self.minute)
        Self.fetch(&policy, at: 0)

        #expect(policy.nextDueDate() == Self.at(2 * Self.minute))
    }

    @Test
    func `low power stretches a short refresh interval to 5 minutes`() {
        var policy = Self.policy()
        policy.setHeartbeat(2 * Self.minute)
        policy.environment.isLowPowerMode = true
        Self.fetch(&policy, at: 0)

        #expect(policy.nextDueDate() == Self.at(5 * Self.minute))
    }

    @Test
    func `heartbeat fires every 30 minutes while the user is active`() {
        var policy = Self.policy()
        Self.fetch(&policy, at: 0)
        #expect(policy.nextDueDate() == Self.at(30 * Self.minute))

        Self.fetch(&policy, at: 30 * Self.minute)
        #expect(policy.nextDueDate() == Self.at(60 * Self.minute))
    }

    @Test(arguments: Inactivity.allCases)
    func `heartbeat is suspended while the user is inactive and resumes after`(inactive: Inactivity) {
        var policy = Self.policy()
        Self.fetch(&policy, at: 0)

        inactive.set(true, in: &policy.environment)
        #expect(policy.dueProviders(at: Self.at(2 * 3600)).isEmpty)
        #expect(policy.nextDueDate() == nil)

        inactive.set(false, in: &policy.environment)
        #expect(policy.dueProviders(at: Self.at(2 * 3600)) == [.claude])
    }

    @Test
    func `activity still refreshes while the user is inactive`() {
        var policy = Self.policy()
        Self.fetch(&policy, at: 0)
        policy.environment.isScreenLocked = true

        policy.handle(.activity(.claude), at: Self.at(300))

        #expect(policy.dueDate(for: .claude) == Self.at(300))
    }

    // MARK: - Low Power and thermal

    @Test(arguments: Constraint.allCases)
    func `constrained systems throttle activity to 5 minutes and the heartbeat to 60`(constrained: Constraint) {
        var policy = Self.policy()
        constrained.set(true, in: &policy.environment)
        Self.fetch(&policy, at: 0)

        #expect(policy.nextDueDate() == Self.at(60 * Self.minute))

        policy.handle(.activity(.claude), at: Self.at(10))
        #expect(policy.dueDate(for: .claude) == Self.at(5 * Self.minute))
    }

    // MARK: - Failures

    @Test
    func `a 429 is respected until its date`() {
        var policy = Self.policy()
        let until = Self.at(10 * Self.minute)
        Self.fetch(&policy, at: 0, .failure(.rateLimited(until: until)))

        policy.handle(.activity(.claude), at: Self.at(100))
        policy.handle(.menuOpened, at: Self.at(300))
        policy.handle(.wake, at: Self.at(400))

        #expect(policy.dueProviders(at: Self.at(599)).isEmpty)
        #expect(policy.dueDate(for: .claude) == until)
        #expect(policy.dueProviders(at: until) == [.claude])
    }

    @Test(arguments: [
        ProbeFailure.server(statusCode: 503),
        ProbeFailure.network("offline"),
    ])
    func `transient failures back off 1, 2, 4, 8 minutes then cap at the heartbeat`(failure: ProbeFailure) throws {
        var policy = Self.policy()
        var time: TimeInterval = 0
        var delays: [TimeInterval] = []

        for _ in 0..<7 {
            Self.fetch(&policy, at: time, .failure(failure))
            let next = policy.nextDueDate()
            try delays.append(#require(next?.timeIntervalSince(Self.at(time))))
            time = try #require(next?.timeIntervalSince(Self.t0))
        }

        let minutes = delays.map { $0 / Self.minute }
        #expect(minutes == [1, 2, 4, 8, 16, 30, 30])
    }

    @Test
    func `activity does not cut a backoff short`() {
        var policy = Self.policy()
        Self.fetch(&policy, at: 0, .failure(.network("offline")))

        policy.handle(.activity(.claude), at: Self.at(5))

        #expect(policy.dueDate(for: .claude) == Self.at(60))
    }

    @Test
    func `a success resets the backoff`() {
        var policy = Self.policy()
        for step in 0..<3 {
            Self.fetch(&policy, at: TimeInterval(step) * 3600, .failure(.server(statusCode: 500)))
        }
        #expect(policy.schedules[.claude]?.consecutiveFailures == 3)

        Self.fetch(&policy, at: 3 * 3600)
        #expect(policy.schedules[.claude]?.consecutiveFailures == 0)
        #expect(policy.nextDueDate() == Self.at(3 * 3600 + 30 * Self.minute))

        Self.fetch(&policy, at: 4 * 3600, .failure(.server(statusCode: 500)))
        #expect(policy.nextDueDate() == Self.at(4 * 3600 + Self.minute))
    }

    @Test
    func `an unrecognized response does not retry tightly`() {
        var policy = Self.policy()
        Self.fetch(&policy, at: 0, .failure(.unrecognizedResponse))

        policy.handle(.activity(.claude), at: Self.at(10))
        policy.handle(.menuOpened, at: Self.at(120))

        #expect(policy.dueProviders(at: Self.at(29 * Self.minute)).isEmpty)
        #expect(policy.dueDate(for: .claude) == Self.at(30 * Self.minute))
    }

    @Test(arguments: [
        ProbeFailure.tokenExpired,
        ProbeFailure.tokenUnavailable,
        ProbeFailure.signInRequired,
        ProbeFailure.notRunning,
    ])
    func `failures that need a change wait for the next event or heartbeat`(failure: ProbeFailure) {
        var policy = Self.policy()
        Self.fetch(&policy, at: 0, .failure(failure))

        // No retry of its own: only the heartbeat is pending.
        #expect(policy.nextDueDate() == Self.at(30 * Self.minute))

        // An event brings it back sooner, which is the point of waiting for one.
        policy.handle(.activity(.claude), at: Self.at(200))
        #expect(policy.dueDate(for: .claude) == Self.at(200))
    }

    // MARK: - Reset boundaries

    @Test
    func `a confirm fetch is due 60 seconds after a window resets`() {
        var policy = Self.policy()
        let result = Result<ProbeResult, ProbeFailure>.success(
            ProbeResult(windows: [Self.window(resetsInSeconds: 1000)]))
        Self.fetch(&policy, at: 0, result)

        #expect(policy.nextDueDate() == Self.at(1060))
        #expect(policy.dueProviders(at: Self.at(1059)).isEmpty)
        #expect(policy.dueProviders(at: Self.at(1060)) == [.claude])
    }

    @Test
    func `the earliest window decides the confirm`() {
        var policy = Self.policy()
        let result = Result<ProbeResult, ProbeFailure>.success(ProbeResult(windows: [
            Self.window(resetsInSeconds: 900_000, minutes: 10080),
            Self.window(resetsInSeconds: 600),
        ]))
        Self.fetch(&policy, at: 0, result)

        #expect(policy.nextDueDate() == Self.at(660))
    }

    @Test
    func `a confirm that finds the old window does not repeat at the same boundary`() {
        var policy = Self.policy()
        let stale = Result<ProbeResult, ProbeFailure>.success(
            ProbeResult(windows: [Self.window(resetsInSeconds: 1000)]))
        Self.fetch(&policy, at: 0, stale)

        // The confirm fetch comes back with the same window, as if the server hasn't reset yet.
        Self.fetch(&policy, at: 1060, stale)

        // The next boundary is one window (5 hours) later; the 30 minute heartbeat comes first.
        #expect(policy.nextDueDate() == Self.at(1060 + 30 * Self.minute))
        policy.environment.isUserIdle = true
        #expect(policy.nextDueDate() == Self.at(1000 + 300 * Self.minute + 60))
    }

    @Test
    func `a stale window confirms at its next projected boundary`() {
        var policy = Self.policy()
        policy.restore(.claude, windows: [Self.window(resetsInSeconds: -3600)], lastSuccess: Self.at(-7200))
        policy.environment.isUserIdle = true

        // Never attempted: the reset an hour ago is still waiting for its confirm.
        #expect(policy.nextDueDate() == Self.at(-3600 + 60))

        // After an attempt that couldn't refresh it, the projection (§5.3) puts the next reset 4 hours out.
        Self.fetch(&policy, at: 60, .failure(.tokenExpired))
        #expect(policy.nextDueDate() == Self.at(-3600 + 300 * Self.minute + 60))
    }

    // MARK: - Wake, network, Antigravity

    @Test
    func `wake refreshes every provider after a 10 second settle`() {
        var policy = Self.policy([.claude, .codex])
        Self.fetch(&policy, .claude, at: 0)
        Self.fetch(&policy, .codex, at: 0)

        policy.handle(.wake, at: Self.at(100))

        #expect(policy.dueProviders(at: Self.at(109)).isEmpty)
        #expect(policy.dueProviders(at: Self.at(110)) == [.claude, .codex])
    }

    @Test
    func `network restored right after a wake does not push the settle back`() {
        var policy = Self.policy()
        Self.fetch(&policy, at: 0)

        policy.handle(.wake, at: Self.at(100))
        policy.handle(.networkRestored, at: Self.at(104))

        #expect(policy.dueDate(for: .claude) == Self.at(110))
    }

    @Test
    func `a settle already covered by a fetch is cleared, a later one is kept`() {
        var policy = Self.policy()
        Self.fetch(&policy, at: 0)
        policy.handle(.wake, at: Self.at(100))

        Self.fetch(&policy, at: 110)

        #expect(policy.dueDate(for: .claude) == Self.at(110 + 30 * Self.minute))
    }

    @Test
    func `an Antigravity launch fetches Antigravity after a 5 second grace`() {
        var policy = Self.policy([.claude, .antigravity])
        Self.fetch(&policy, .claude, at: 0)
        Self.fetch(&policy, .antigravity, at: 0, .failure(.notRunning))

        policy.handle(.antigravityLaunched, at: Self.at(100))

        #expect(policy.dueProviders(at: Self.at(104)).isEmpty)
        #expect(policy.dueProviders(at: Self.at(105)) == [.antigravity])
    }

    @Test
    func `an Antigravity launch is ignored when Antigravity is disabled`() {
        var policy = Self.policy([.claude])
        Self.fetch(&policy, at: 0)

        policy.handle(.antigravityLaunched, at: Self.at(100))

        #expect(policy.nextDueDate() == Self.at(30 * Self.minute))
    }

    // MARK: - Paused, asleep, disabled

    @Test
    func `paused means nothing is ever due`() {
        var policy = Self.policy([.claude, .codex, .antigravity])
        policy.environment.isPaused = true

        policy.handle(.activity(.claude), at: Self.t0)
        policy.handle(.menuOpened, at: Self.t0)
        policy.handle(.wake, at: Self.t0)

        #expect(policy.dueProviders(at: Self.at(24 * 3600)).isEmpty)
        #expect(policy.nextDueDate() == nil)
    }

    @Test
    func `ending a pause fetches once`() {
        var policy = Self.policy()
        Self.fetch(&policy, at: 0)
        policy.environment.isPaused = true
        policy.handle(.activity(.claude), at: Self.at(50))

        policy.environment.isPaused = false
        policy.handle(.resumed, at: Self.at(100))

        // The activity during the pause was dropped; only the resume request is pending.
        #expect(policy.dueDate(for: .claude) == Self.at(100))
        Self.fetch(&policy, at: 100)
        #expect(policy.dueDate(for: .claude) == Self.at(100 + 30 * Self.minute))
    }

    @Test
    func `nothing is due while the system sleeps`() {
        var policy = Self.policy()
        Self.fetch(&policy, at: 0)
        policy.environment.isSystemAsleep = true

        #expect(policy.dueProviders(at: Self.at(2 * 3600)).isEmpty)
        #expect(policy.nextDueDate() == nil)
    }

    @Test
    func `disabled providers are never due`() {
        var policy = Self.policy([.claude])

        policy.handle(.activity(.codex), at: Self.t0)
        policy.handle(.menuOpened, at: Self.t0)
        policy.handle(.wake, at: Self.t0)

        #expect(policy.dueDate(for: .codex) == nil)
        #expect(policy.dueDate(for: .antigravity) == nil)
        #expect(policy.dueProviders(at: Self.at(24 * 3600)) == [.claude])
    }

    @Test
    func `enabling a provider makes it due`() {
        var policy = Self.policy([.claude])
        Self.fetch(&policy, at: 0)

        policy.enabledProviders = [.claude, .codex]

        #expect(policy.dueProviders(at: Self.at(1)) == [.codex])
    }

    // MARK: - Next due date

    @Test
    func `nothing pending when every provider is disabled`() {
        let policy = Self.policy([])

        #expect(policy.nextDueDate() == nil)
    }

    @Test
    func `next due is the earliest across providers`() {
        var policy = Self.policy([.claude, .codex, .antigravity])
        Self.fetch(&policy, .claude, at: 0)
        Self.fetch(&policy, .codex, at: 600)
        Self.fetch(&policy, .antigravity, at: 300)

        #expect(policy.nextDueDate() == Self.at(30 * Self.minute))

        // Codex was fetched at 600, so activity at 650 waits for the throttle: 600 + 90.
        policy.handle(.activity(.codex), at: Self.at(650))
        #expect(policy.nextDueDate() == Self.at(690))
    }

    @Test
    func `next due skips providers that are already in flight`() {
        var policy = Self.policy([.claude, .codex])
        Self.fetch(&policy, .claude, at: 0)
        Self.fetch(&policy, .codex, at: 0)
        policy.handle(.menuOpened, at: Self.at(500))

        let next = policy.nextDueDate(excluding: [.claude, .codex])

        #expect(next == nil)
    }
}
