import CodexBarSync
import Foundation
import Testing
@testable import LiteCore

struct AlertLogicTests {
    private static let email = "me@example.com"

    private static func windows(session: Double?, weekly: Double? = nil) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        if let session {
            windows.append(QuotaWindow(
                label: "Session",
                lane: .session,
                usedPercent: 100 - session,
                windowMinutes: 300,
                resetsAt: nil))
        }
        if let weekly {
            windows.append(QuotaWindow(
                label: "Weekly",
                lane: .weekly,
                usedPercent: 100 - weekly,
                windowMinutes: 10080,
                resetsAt: nil))
        }
        return windows
    }

    /// Runs fetches in order, given as remaining percents, and returns every event.
    private static func run(
        _ fetches: [(session: Double?, weekly: Double?)],
        thresholds: [Int] = [50, 20],
        email: String? = Self.email) -> [AlertEvent.Kind]
    {
        var memory: AlertMemory?
        var kinds: [AlertEvent.Kind] = []
        for fetch in fetches {
            let result = AlertLogic.evaluate(
                provider: .claude,
                windows: self.windows(session: fetch.session, weekly: fetch.weekly),
                accountEmail: email,
                thresholds: thresholds,
                memory: memory)
            kinds += result.events.map(\.kind)
            memory = result.memory
        }
        return kinds
    }

    @Test
    func `the first fetch only records the baseline`() {
        #expect(Self.run([(0, 10)]).isEmpty)
    }

    @Test
    func `the session reaching zero is depleted and coming back is restored`() {
        #expect(Self.run([(5, nil), (0, nil), (0, nil), (80, nil)]).filter { $0 == .depleted || $0 == .restored }
            == [.depleted, .restored])
    }

    @Test
    func `crossing a threshold warns once`() {
        let kinds = Self.run([(60, nil), (45, nil), (40, nil)])

        #expect(kinds == [.warning(lane: .session, threshold: 50, remaining: 45)])
    }

    @Test
    func `jumping past both thresholds warns for the lowest only`() {
        let kinds = Self.run([(nil, 70), (nil, 10), (nil, 5)])

        #expect(kinds == [.warning(lane: .weekly, threshold: 20, remaining: 10)])
    }

    @Test
    func `a window that climbs back above a threshold can warn again`() {
        let kinds = Self.run([(60, nil), (45, nil), (90, nil), (48, nil)])

        #expect(kinds == [
            .warning(lane: .session, threshold: 50, remaining: 45),
            .warning(lane: .session, threshold: 50, remaining: 48),
        ])
    }

    @Test
    func `depleted only sends no warnings`() {
        let kinds = Self.run([(60, nil), (10, nil), (0, nil)], thresholds: [])

        #expect(kinds == [.depleted])
    }

    @Test
    func `a different account starts a new baseline without alerting`() {
        let first = AlertLogic.evaluate(
            provider: .codex,
            windows: Self.windows(session: 80),
            accountEmail: "a@example.com",
            thresholds: [50, 20],
            memory: nil)
        let switched = AlertLogic.evaluate(
            provider: .codex,
            windows: Self.windows(session: 0),
            accountEmail: "b@example.com",
            thresholds: [50, 20],
            memory: first.memory)

        #expect(switched.events.isEmpty)
        #expect(switched.memory.accountEmail == "b@example.com")
    }

    @Test
    func `memory survives a restart so an old depletion does not re-alert`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlertTests-\(UUID().uuidString)")
            .appendingPathComponent("alerts.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = AlertMemoryStore(fileURL: url)
        let depleted = AlertLogic.evaluate(
            provider: .claude,
            windows: Self.windows(session: 0, weekly: 15),
            accountEmail: Self.email,
            thresholds: [50, 20],
            memory: AlertMemory(accountEmail: Self.email, sessionRemaining: 3, remaining: [.weekly: 15]))
        try store.save([.claude: depleted.memory])

        let afterRestart = AlertLogic.evaluate(
            provider: .claude,
            windows: Self.windows(session: 0, weekly: 15),
            accountEmail: Self.email,
            thresholds: [50, 20],
            memory: store.load()[.claude])

        #expect(afterRestart.events.isEmpty)
    }
}

struct AlertEventTests {
    @Test
    func `banners use the full app's English wording`() {
        let depleted = AlertEvent(provider: .claude, kind: .depleted, accountEmail: nil)
        let warning = AlertEvent(
            provider: .codex,
            kind: .warning(lane: .weekly, threshold: 20, remaining: 18.4),
            accountEmail: "me@example.com")

        #expect(depleted.banner.title == "Claude session depleted")
        #expect(depleted.banner.body == "0% left. Will notify when it's available again.")
        #expect(warning.banner.title == "Codex weekly quota low")
        #expect(warning.banner.body
            == "Account me@example.com. 18% left. Reached your 20% weekly warning threshold.")
    }

    @Test
    func `the deduplication scope is 8 bytes of SHA256 over the email discriminator`() {
        let event = AlertEvent(provider: .claude, kind: .depleted, accountEmail: " Me@Example.com ")

        #expect(event.deduplicationScope?.count == 16)
        #expect(event.deduplicationScope
            == AlertEvent(provider: .codex, kind: .restored, accountEmail: "me@example.com").deduplicationScope)
        #expect(AlertEvent(provider: .claude, kind: .depleted, accountEmail: nil).deduplicationScope == nil)
    }

    @Test
    func `the CloudKit state matches the zone names iOS subscribes to`() {
        #expect(QuotaProviderList.quotaZoneName(
            providerID: "claude",
            state: AlertEvent(provider: .claude, kind: .depleted, accountEmail: nil).state)
            == "Quota-claude-depletedZone")
        #expect(AlertEvent(
            provider: .codex,
            kind: .warning(lane: .session, threshold: 50, remaining: 40),
            accountEmail: nil).state == "warning")
    }
}

struct AlertDebouncerTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `transitions wait five minutes and warnings one minute`() {
        var debouncer = AlertDebouncer()
        let depleted = AlertEvent(provider: .claude, kind: .depleted, accountEmail: nil)
        let warning = AlertEvent(
            provider: .claude,
            kind: .warning(lane: .session, threshold: 50, remaining: 40),
            accountEmail: nil)
        debouncer.recordDelivery(of: depleted, at: Self.now)
        debouncer.recordDelivery(of: warning, at: Self.now)

        #expect(!debouncer.allows(depleted, at: Self.now.addingTimeInterval(299)))
        #expect(debouncer.allows(depleted, at: Self.now.addingTimeInterval(300)))
        #expect(!debouncer.allows(warning, at: Self.now.addingTimeInterval(59)))
        #expect(debouncer.allows(warning, at: Self.now.addingTimeInterval(60)))
    }

    @Test
    func `different thresholds are debounced separately`() {
        var debouncer = AlertDebouncer()
        let fifty = AlertEvent(
            provider: .claude,
            kind: .warning(lane: .session, threshold: 50, remaining: 40),
            accountEmail: nil)
        let twenty = AlertEvent(
            provider: .claude,
            kind: .warning(lane: .session, threshold: 20, remaining: 15),
            accountEmail: nil)
        debouncer.recordDelivery(of: fifty, at: Self.now)

        #expect(debouncer.allows(twenty, at: Self.now))
    }
}

struct AlertThresholdTests {
    @Test
    func `the iPhone markers follow the preset`() {
        #expect(AlertThresholds.standard.syncConfig == SyncQuotaWarningConfig(
            sessionThresholds: [50, 20],
            sessionEnabled: true,
            weeklyThresholds: [50, 20],
            weeklyEnabled: true))
        #expect(AlertThresholds.depletedOnly.syncConfig.sessionEnabled == false)
    }

    @Test
    func `a threshold change changes the published content`() {
        let state = SyncSnapshotTests.state()
        let now = SyncSnapshotTests.now

        #expect(SyncSnapshot.contentHash(for: state, now: now, quotaWarnings: AlertThresholds.standard.syncConfig)
            != SyncSnapshot.contentHash(for: state, now: now, quotaWarnings: AlertThresholds.late.syncConfig))
        #expect(SyncSnapshot.make(for: state, now: now, quotaWarnings: AlertThresholds.late.syncConfig)?
            .quotaWarnings?.resolvedSessionThresholds() == [25, 10])
    }

    @Test
    func `alert preferences default to Mac banners on, iPhone off, 50 and 20`() throws {
        let suite = "AlertThresholdTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = LitePreferences(defaults: defaults)

        #expect(preferences.macAlerts)
        #expect(!preferences.iPhoneAlerts)
        #expect(preferences.alertThresholds == .standard)
    }
}
