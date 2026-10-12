import CodexBarSync
import Foundation
import Testing
@testable import LiteCore

struct SyncSnapshotTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let deviceID = "LITE-DEVICE"

    static func state(
        _ provider: LiteProvider = .claude,
        sessionUsed: Double = 40,
        weeklyUsed: Double = 60,
        email: String? = "me@example.com",
        status: ProviderStatus = .ok,
        fetched: Date? = Self.now.addingTimeInterval(-60)) -> ProviderState
    {
        var state = ProviderState(provider: provider, windows: [
            QuotaWindow(
                label: "Session",
                lane: .session,
                usedPercent: sessionUsed,
                windowMinutes: 300,
                resetsAt: Self.now.addingTimeInterval(2 * 3600)),
            QuotaWindow(
                label: "Weekly",
                lane: .weekly,
                usedPercent: weeklyUsed,
                windowMinutes: 10080,
                resetsAt: Self.now.addingTimeInterval(3 * 86400)),
        ])
        state.plan = "max"
        state.accountEmail = email
        state.accountIdentities = email.map { ["\(provider.rawValue):email:\($0)"] } ?? []
        state.lastFetched = fetched
        state.status = status
        return state
    }

    @Test
    func `windows map to primary, secondary and rate windows with lane identities`() throws {
        let snapshot = try #require(SyncSnapshot.make(for: Self.state(), now: Self.now))

        #expect(snapshot.providerID == "claude")
        #expect(snapshot.providerName == "Claude")
        #expect(snapshot.rateWindows.map(\.label) == ["Session", "Weekly"])
        #expect(snapshot.rateWindows.map(\.identity) == [.session, .weekly])
        #expect(snapshot.primary == snapshot.rateWindows[0])
        #expect(snapshot.secondary == snapshot.rateWindows[1])
        #expect(snapshot.loginMethod == "max")
        #expect(snapshot.accountEmail == "me@example.com")
        #expect(snapshot.accountIdentities == ["claude:email:me@example.com"])
        #expect(snapshot.lastUpdated == Self.now.addingTimeInterval(-60))
        #expect(!snapshot.isError)
        #expect(snapshot.statusMessage == nil)
    }

    @Test
    func `pace carries the same text as the menu`() throws {
        let state = Self.state()
        let snapshot = try #require(SyncSnapshot.make(for: state, now: Self.now))
        let weekly = try #require(snapshot.rateWindows.last?.pace)
        let detail = try #require(PaceText.detail(for: state.windows[1], provider: .claude, now: Self.now))

        #expect(weekly.leftLabel == detail.leftLabel)
        #expect(weekly.rightLabel == detail.rightLabel)
        #expect(weekly.stage == detail.pace.stage)
    }

    @Test
    func `extension fields stay nil`() throws {
        let snapshot = try #require(SyncSnapshot.make(for: Self.state(), now: Self.now))

        #expect(snapshot.costSummary == nil)
        #expect(snapshot.budget == nil)
        #expect(snapshot.utilizationHistory == nil)
        #expect(snapshot.codexResetCredits == nil)
        #expect(snapshot.quotaWarnings == nil)
    }

    @Test
    func `an error status is published as the card text`() throws {
        let snapshot = try #require(SyncSnapshot.make(for: Self.state(status: .tokenExpired), now: Self.now))

        #expect(snapshot.isError)
        #expect(snapshot.statusMessage == "Token expired — run claude once")
    }

    @Test
    func `a provider with no windows and no error is a ghost and is not published`() {
        let state = ProviderState(provider: .codex)

        #expect(SyncSnapshot.make(for: state, now: Self.now) == nil)
    }

    @Test
    func `the envelope round trips through the iPhone decoder`() throws {
        let snapshot = try #require(SyncSnapshot.make(for: Self.state(), now: Self.now))
        let envelope = ProviderUsageEnvelope(
            deviceID: Self.deviceID,
            deviceName: "Mac",
            appVersion: "Lite 0.1.0",
            mobileVersion: nil,
            syncTimestamp: Self.now,
            notificationPushEnabled: nil,
            provider: snapshot)

        let data = try CloudSyncConstants.makeJSONEncoder().encode(envelope)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(ProviderUsageEnvelope.self, from: data)

        #expect(decoded == envelope)
    }

    @Test
    func `record names follow the CloudSyncManager wire contract`() {
        #expect(SyncSnapshot.recordName(deviceID: "D", provider: .codex, accountEmail: "a@b.c")
            == CloudSyncManager.perProviderRecordName(deviceID: "D", providerID: "codex", accountEmail: "a@b.c"))
        #expect(SyncSnapshot.recordName(deviceID: "D", provider: .claude, accountEmail: nil)
            == CloudSyncManager.perProviderRecordName(deviceID: "D", providerID: "claude", accountEmail: nil))
    }

    @Test
    func `the content hash ignores the fetch time but not the usage`() {
        let first = SyncSnapshot.contentHash(for: Self.state(fetched: Self.now.addingTimeInterval(-600)), now: Self.now)
        let refetched = SyncSnapshot.contentHash(for: Self.state(fetched: Self.now), now: Self.now)
        let moreUsage = SyncSnapshot.contentHash(for: Self.state(sessionUsed: 41, fetched: Self.now), now: Self.now)

        #expect(first != nil)
        #expect(first == refetched)
        #expect(first != moreUsage)
    }
}

struct SyncLedgerTests {
    private typealias Fixture = SyncSnapshotTests
    private static let now = Fixture.now
    private static let deviceID = Fixture.deviceID

    private static func written(_ states: [ProviderState], at date: Date) -> SyncLedger {
        var ledger = SyncLedger()
        let plan = ledger.plan(states: states, enabled: Set(states.map(\.provider)), deviceID: Self.deviceID, now: date)
        ledger.recordWrites(plan.writes, at: date)
        return ledger
    }

    @Test
    func `a new provider is written`() {
        let plan = SyncLedger().plan(
            states: [Fixture.state()],
            enabled: [.claude],
            deviceID: Self.deviceID,
            now: Self.now)

        #expect(plan.writes.map(\.recordName) == ["LITE-DEVICE|claude|me@example.com"])
        #expect(plan.deletes.isEmpty)
    }

    @Test
    func `nothing is written when nothing changed`() {
        let ledger = Self.written([Fixture.state()], at: Self.now)

        let plan = ledger.plan(
            states: [Fixture.state(fetched: Self.now.addingTimeInterval(30))],
            enabled: [.claude],
            deviceID: Self.deviceID,
            now: Self.now)

        #expect(plan.isEmpty)
    }

    @Test
    func `changed usage is written`() {
        let ledger = Self.written([Fixture.state()], at: Self.now)

        let plan = ledger.plan(
            states: [Fixture.state(sessionUsed: 55)],
            enabled: [.claude],
            deviceID: Self.deviceID,
            now: Self.now)

        #expect(plan.writes.count == 1)
    }

    @Test
    func `an unchanged record is rewritten after the 30 minute heartbeat`() {
        let ledger = Self.written([Fixture.state()], at: Self.now)
        let later = Self.now.addingTimeInterval(SyncLedger.heartbeat)

        // Same content at the later time: the pace text depends on `now`, so build the state for that time too.
        let plan = ledger.plan(states: [Fixture.state()], enabled: [.claude], deviceID: Self.deviceID, now: later)

        #expect(plan.writes.map(\.recordName) == ["LITE-DEVICE|claude|me@example.com"])
    }

    @Test
    func `a disabled provider's record is deleted`() {
        let ledger = Self.written([Fixture.state(), Fixture.state(.codex)], at: Self.now)

        let plan = ledger.plan(
            states: [Fixture.state(), Fixture.state(.codex)],
            enabled: [.claude],
            deviceID: Self.deviceID,
            now: Self.now)

        #expect(plan.writes.isEmpty)
        #expect(plan.deletes == ["LITE-DEVICE|codex|me@example.com"])
    }

    @Test
    func `an account change writes the new record and deletes the old one`() {
        let ledger = Self.written([Fixture.state()], at: Self.now)

        let plan = ledger.plan(
            states: [Fixture.state(email: "other@example.com")],
            enabled: [.claude],
            deviceID: Self.deviceID,
            now: Self.now)

        #expect(plan.writes.map(\.recordName) == ["LITE-DEVICE|claude|other@example.com"])
        #expect(plan.deletes == ["LITE-DEVICE|claude|me@example.com"])
    }

    @Test
    func `an enabled provider with nothing to publish keeps its record`() {
        let ledger = Self.written([Fixture.state()], at: Self.now)

        let plan = ledger.plan(
            states: [ProviderState(provider: .claude)],
            enabled: [.claude],
            deviceID: Self.deviceID,
            now: Self.now)

        #expect(plan.isEmpty)
    }

    @Test
    func `the ledger survives a save and load`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncLedgerTests-\(UUID().uuidString)")
            .appendingPathComponent("sync.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SyncLedgerStore(fileURL: url)
        let ledger = Self.written([Fixture.state()], at: Self.now)

        try store.save(ledger)

        #expect(store.load() == ledger)
    }
}
