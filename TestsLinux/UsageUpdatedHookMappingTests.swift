import CodexBarCore
import Foundation
import Testing

struct UsageUpdatedHookMappingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func config(executable: String = "/usr/bin/true") -> HooksConfig {
        HooksConfig(enabled: true, events: [HookRule(event: .usageUpdated, executable: executable)])
    }

    private func makeSnapshot(planObservation: ProviderPlanObservation? = nil) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: self.now, resetDescription: nil),
            secondary: RateWindow(usedPercent: 40, windowMinutes: 10080, resetsAt: self.now, resetDescription: nil),
            updatedAt: self.now,
            planObservation: planObservation)
    }

    @Test
    func `shared mapping preserves genuine zero and omits synthetic windows`() throws {
        let event = HookEvent.usageUpdated(
            provider: "codex", snapshot: self.makeSnapshot(), account: nil, timestamp: self.now)
        #expect(event.usagePercent == 0)
        #expect(event.secondaryUsagePercent == 0.4)
        #expect(event.windowMinutes == 300)
        #expect(event.environmentVariables()["QUOTAKIT_WINDOW_MINUTES"] == "300")
        #expect(event.environmentVariables()["CODEXBAR_SECONDARY_USAGE_PERCENT"] == "0.4")

        let placeholder = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 0, windowMinutes: nil, resetsAt: nil,
                resetDescription: nil, isSyntheticPlaceholder: true),
            secondary: nil,
            updatedAt: self.now)
        let omitted = HookEvent.usageUpdated(
            provider: "codex", snapshot: placeholder, account: nil, timestamp: self.now)
        let payload = try #require(JSONSerialization.jsonObject(with: omitted.jsonPayload()) as? [String: Any])
        #expect(payload["usagePercent"] == nil)
        #expect(payload["windowMinutes"] == nil)
        #expect(omitted.environmentVariables()["QUOTAKIT_USAGE_PERCENT"] == nil)
    }

    @Test
    func `watch offers first and unchanged successful polls without exposing routing key`() throws {
        let detector = HookTransitionDetector()
        let config = HooksConfig(enabled: true, events: [
            HookRule(event: .usageUpdated, executable: "/usr/bin/true"),
        ])
        let observation = HookProviderObservation(
            provider: "codex", successfulUsage: self.makeSnapshot(),
            accountDiscriminator: "private-owner")
        for instant in [self.now, self.now.addingTimeInterval(60)] {
            let dispatches = detector.evaluate(observation: observation, config: config, now: instant)
            #expect(dispatches.count == 1)
            let dispatch = try #require(dispatches.first)
            #expect(dispatch.event.event == .usageUpdated)
            #expect(dispatch.accountDiscriminator == "private-owner")
            let payload = try String(decoding: dispatch.event.jsonPayload(), as: UTF8.self)
            #expect(!payload.contains("private-owner"))
            #expect(dispatch.event.environmentVariables()["QUOTAKIT_ACCOUNT"] == nil)
        }
    }

    @Test
    func `disabled hooks never dispatch a successful sample`() {
        let detector = HookTransitionDetector()
        let observation = HookProviderObservation(provider: "codex", successfulUsage: self.makeSnapshot())
        #expect(detector.evaluate(observation: observation, config: HooksConfig()).isEmpty)
    }

    @Test
    func `failed and status only observations cannot emit usage updates`() {
        let detector = HookTransitionDetector()
        let config = HooksConfig(enabled: true, events: [
            HookRule(event: .usageUpdated, executable: "/usr/bin/true"),
        ])
        let failure = HookProviderObservation(
            provider: "codex", refreshFailureStatus: "offline", successfulUsage: self.makeSnapshot())
        #expect(detector.evaluate(observation: failure, config: config).map(\.event.event) == [.refreshFailed])
        let statusOnly = HookProviderObservation(provider: "codex", status: .none)
        #expect(detector.evaluate(observation: statusOnly, config: config).isEmpty)
    }

    @Test
    func `private account throttle opens at exactly 600 seconds`() async {
        let event = HookEvent.usageUpdated(
            provider: "codex", snapshot: self.makeSnapshot(), account: nil, timestamp: self.now)
        let limiter = HookRateLimiter()
        #expect(await limiter.allow(event, accountDiscriminator: "A", now: self.now))
        #expect(await !limiter.allow(event, accountDiscriminator: "A", now: self.now.addingTimeInterval(599)))
        #expect(await limiter.allow(event, accountDiscriminator: "B", now: self.now.addingTimeInterval(599)))
        #expect(await limiter.allow(event, accountDiscriminator: "A", now: self.now.addingTimeInterval(600)))
        #expect(await HookRateLimiter().allow(event, accountDiscriminator: "A", now: self.now))
    }

    @Test
    func `dispatch reports attempts without counting unmatched or throttled candidates`() async {
        let event = HookEvent.usageUpdated(
            provider: "codex",
            snapshot: self.makeSnapshot(),
            account: nil,
            timestamp: self.now)
        let limiter = HookRateLimiter()
        let unmatched = await HookRunner.dispatch(
            event: event, config: HooksConfig(enabled: true), rateLimiter: limiter, baseEnvironment: [:])
        #expect(unmatched == .noMatchingRules)
        let first = await HookRunner.dispatch(
            event: event, config: self.config(), rateLimiter: limiter, baseEnvironment: [:])
        #expect(first == .attempted)
        let repeated = await HookRunner.dispatch(
            event: event, config: self.config(), rateLimiter: limiter, baseEnvironment: [:])
        #expect(repeated == .rateLimited)
    }

    @Test
    func `failed command attempts consume the throttle interval`() async {
        let event = HookEvent.usageUpdated(
            provider: "codex",
            snapshot: self.makeSnapshot(),
            account: nil,
            timestamp: self.now)
        let limiter = HookRateLimiter()
        let config = self.config(executable: "/nonexistent/codexbar-hook-fixture")
        let first = await HookRunner.dispatch(
            event: event, config: config, rateLimiter: limiter, baseEnvironment: [:])
        let repeated = await HookRunner.dispatch(
            event: event, config: config, rateLimiter: limiter, baseEnvironment: [:])
        #expect(first == .attempted)
        #expect(repeated == .rateLimited)
    }

    @Test
    func `shared mapping surfaces sampled raw plan provenance`() throws {
        let observedAt = self.now.addingTimeInterval(-30)
        let plan = try #require(ProviderPlanObservation(
            rawPlan: "pro",
            source: .usageResponse,
            observedAt: observedAt))
        let event = HookEvent.usageUpdated(
            provider: "codex",
            snapshot: self.makeSnapshot(planObservation: plan),
            account: nil,
            timestamp: self.now)

        #expect(event.plan == "pro")
        #expect(event.planSource == .usageResponse)
        #expect(event.planObservedAt == observedAt)

        let environment = event.environmentVariables()
        #expect(environment["CODEXBAR_PLAN"] == "pro")
        #expect(environment["QUOTAKIT_PLAN"] == "pro")
        #expect(environment["CODEXBAR_PLAN_SOURCE"] == "usage_response")
        #expect(environment["CODEXBAR_PLAN_OBSERVED_AT"] == "2027-01-15T07:59:30Z")

        let payload = try #require(JSONSerialization.jsonObject(with: event.jsonPayload()) as? [String: Any])
        #expect(payload["plan"] as? String == "pro")
        #expect(payload["planSource"] as? String == "usage_response")
        #expect(payload["planObservedAt"] as? String == "2027-01-15T07:59:30Z")
    }

    @Test
    func `shared mapping omits plan fields without an observation`() throws {
        let event = HookEvent.usageUpdated(
            provider: "codex",
            snapshot: self.makeSnapshot(),
            account: nil,
            timestamp: self.now)

        #expect(event.plan == nil)
        #expect(event.planSource == nil)
        #expect(event.planObservedAt == nil)

        let environment = event.environmentVariables()
        #expect(environment["CODEXBAR_PLAN"] == nil)
        #expect(environment["CODEXBAR_PLAN_SOURCE"] == nil)
        #expect(environment["CODEXBAR_PLAN_OBSERVED_AT"] == nil)

        let payload = try #require(JSONSerialization.jsonObject(with: event.jsonPayload()) as? [String: Any])
        #expect(payload["plan"] == nil)
        #expect(payload["planSource"] == nil)
        #expect(payload["planObservedAt"] == nil)
    }

    @Test
    func `display label identity is not promoted to plan provenance`() {
        let snapshot = self.makeSnapshot().withIdentity(ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "Pro 20x"))
        let event = HookEvent.usageUpdated(
            provider: "codex",
            snapshot: snapshot,
            account: nil,
            timestamp: self.now)

        #expect(event.plan == nil)
        #expect(event.environmentVariables()["CODEXBAR_PLAN"] == nil)
    }

    @Test
    func `plan metadata does not change the sampled account throttle key`() async throws {
        let firstPlan = try #require(ProviderPlanObservation(
            rawPlan: "pro",
            source: .usageResponse,
            observedAt: self.now))
        let secondPlan = try #require(ProviderPlanObservation(
            rawPlan: "team",
            source: .patWhoami,
            observedAt: self.now))
        let first = HookEvent.usageUpdated(
            provider: "codex",
            snapshot: self.makeSnapshot(planObservation: firstPlan),
            account: nil,
            timestamp: self.now)
        let second = HookEvent.usageUpdated(
            provider: "codex",
            snapshot: self.makeSnapshot(planObservation: secondPlan),
            account: nil,
            timestamp: self.now.addingTimeInterval(120))
        let limiter = HookRateLimiter()

        #expect(await limiter.allow(first, accountDiscriminator: "owner", now: self.now))
        #expect(await !limiter.allow(
            second,
            accountDiscriminator: "owner",
            now: self.now.addingTimeInterval(120)))
    }

    @Test
    func `watch polling carries plan provenance into usage updates`() throws {
        let plan = try #require(ProviderPlanObservation(
            rawPlan: "pro",
            source: .oauthClaims,
            observedAt: self.now))
        let snapshot = self.makeSnapshot(planObservation: plan)
        let observation = HookProviderObservation(
            provider: "codex",
            successfulUsage: snapshot,
            accountDiscriminator: "private-owner")
        let detector = HookTransitionDetector()

        let dispatches = detector.evaluate(observation: observation, config: self.config(), now: self.now)
        let dispatch = try #require(dispatches.first)

        #expect(dispatch.event == HookEvent.usageUpdated(
            provider: "codex",
            snapshot: snapshot,
            account: nil,
            timestamp: self.now))
        #expect(dispatch.event.plan == "pro")
        #expect(dispatch.event.planSource == .oauthClaims)
    }

    @Test
    func `old hook payloads decode without plan provenance`() throws {
        let json = #"{"event":"usage_updated","provider":"codex","usagePercent":0.2,"#
            + #""timestamp":"2026-09-08T12:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(HookEvent.self, from: Data(json.utf8))

        #expect(event.plan == nil)
        #expect(event.planSource == nil)
        #expect(event.planObservedAt == nil)
        #expect(event.environmentVariables()["CODEXBAR_PLAN"] == nil)
    }
}
