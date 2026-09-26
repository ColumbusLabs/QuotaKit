import CodexBarCore
import Foundation
import Testing

struct UsageUpdatedHookMappingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var snapshot: UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: self.now, resetDescription: nil),
            secondary: RateWindow(usedPercent: 40, windowMinutes: 10080, resetsAt: self.now, resetDescription: nil),
            updatedAt: self.now)
    }

    @Test
    func `shared mapping preserves genuine zero and omits synthetic windows`() throws {
        let event = HookEvent.usageUpdated(
            provider: "codex", snapshot: self.snapshot, account: nil, timestamp: self.now)
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
            provider: "codex", successfulUsage: self.snapshot,
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
        let observation = HookProviderObservation(provider: "codex", successfulUsage: self.snapshot)
        #expect(detector.evaluate(observation: observation, config: HooksConfig()).isEmpty)
    }

    @Test
    func `failed and status only observations cannot emit usage updates`() {
        let detector = HookTransitionDetector()
        let config = HooksConfig(enabled: true, events: [
            HookRule(event: .usageUpdated, executable: "/usr/bin/true"),
        ])
        let failure = HookProviderObservation(
            provider: "codex", refreshFailureStatus: "offline", successfulUsage: self.snapshot)
        #expect(detector.evaluate(observation: failure, config: config).map(\.event.event) == [.refreshFailed])
        let statusOnly = HookProviderObservation(provider: "codex", status: .none)
        #expect(detector.evaluate(observation: statusOnly, config: config).isEmpty)
    }

    @Test
    func `private account throttle opens at exactly 600 seconds`() async {
        let event = HookEvent.usageUpdated(
            provider: "codex", snapshot: self.snapshot, account: nil, timestamp: self.now)
        let limiter = HookRateLimiter()
        #expect(await limiter.allow(event, accountDiscriminator: "A", now: self.now))
        #expect(await !limiter.allow(event, accountDiscriminator: "A", now: self.now.addingTimeInterval(599)))
        #expect(await limiter.allow(event, accountDiscriminator: "B", now: self.now.addingTimeInterval(599)))
        #expect(await limiter.allow(event, accountDiscriminator: "A", now: self.now.addingTimeInterval(600)))
    }
}
