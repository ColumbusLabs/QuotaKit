import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("SnapshotIdentityKey Tests (Contract C3)")
struct SnapshotIdentityKeyTests {
    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_700_000_060)

    @Test
    func `Same providers + same lastUpdated yield equal keys`() {
        let a = SnapshotIdentityKey.make(
            providerIDs: ["claude", "codex"],
            lastUpdated: self.t1)
        let b = SnapshotIdentityKey.make(
            providerIDs: ["codex", "claude"], // order-insensitive after sort
            lastUpdated: self.t1)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test
    func `Different provider sets yield different keys`() {
        let a = SnapshotIdentityKey.make(
            providerIDs: ["claude"],
            lastUpdated: self.t1)
        let b = SnapshotIdentityKey.make(
            providerIDs: ["claude", "codex"],
            lastUpdated: self.t1)
        #expect(a != b)
    }

    @Test
    func `Same providers + different lastUpdated yield different keys`() {
        let a = SnapshotIdentityKey.make(
            providerIDs: ["claude", "codex"],
            lastUpdated: self.t1)
        let b = SnapshotIdentityKey.make(
            providerIDs: ["claude", "codex"],
            lastUpdated: self.t2)
        #expect(a != b)
    }

    @Test
    func `Same quota freshness + different cost freshness yield different keys`() {
        let a = SnapshotIdentityKey.make(
            providerIDs: ["codex"],
            lastUpdated: self.t1,
            costUpdatedAt: self.t1)
        let b = SnapshotIdentityKey.make(
            providerIDs: ["codex"],
            lastUpdated: self.t1,
            costUpdatedAt: self.t2)
        #expect(a != b)
    }

    @Test
    func `Missing cost freshness remains compatible with legacy key`() {
        let legacy = SnapshotIdentityKey.make(
            providerIDs: ["codex"], lastUpdated: self.t1)
        let explicitNil = SnapshotIdentityKey.make(
            providerIDs: ["codex"], lastUpdated: self.t1, costUpdatedAt: nil)
        #expect(legacy == explicitNil)
    }

    @Test
    func `A non-max provider cost revision changes the aggregate key`() {
        let unchangedMaximum = self.t2
        let olderCodexRevision = self.t1
        let newerCodexRevision = self.t1.addingTimeInterval(30)
        let a = SnapshotIdentityKey.make(
            providerIDs: ["claude", "codex"],
            lastUpdated: self.t2,
            costUpdatedAt: unchangedMaximum,
            costRevisions: [
                "claude@\(unchangedMaximum.timeIntervalSince1970)",
                "codex@\(olderCodexRevision.timeIntervalSince1970)",
            ])
        let b = SnapshotIdentityKey.make(
            providerIDs: ["claude", "codex"],
            lastUpdated: self.t2,
            costUpdatedAt: unchangedMaximum,
            costRevisions: [
                "claude@\(unchangedMaximum.timeIntervalSince1970)",
                "codex@\(newerCodexRevision.timeIntervalSince1970)",
            ])

        #expect(a.costUpdatedAt == b.costUpdatedAt)
        #expect(a != b)
    }

    @Test
    func `A total revision changes the key when payload revision is unchanged`() {
        let payloadRevision = self.t2
        let a = SnapshotIdentityKey.make(
            providerIDs: ["codex"],
            lastUpdated: self.t1,
            costUpdatedAt: payloadRevision,
            costRevisions: ["codex@\(payloadRevision.timeIntervalSince1970):\(self.t1.timeIntervalSince1970)"])
        let b = SnapshotIdentityKey.make(
            providerIDs: ["codex"],
            lastUpdated: self.t1,
            costUpdatedAt: payloadRevision,
            costRevisions: ["codex@\(payloadRevision.timeIntervalSince1970):\(self.t2.timeIntervalSince1970)"])

        #expect(a.costUpdatedAt == b.costUpdatedAt)
        #expect(a != b)
    }

    @Test
    func `An intermediate device revision remains visible after merged scalar collapse`() {
        let oldest = self.t1
        let middle = self.t1.addingTimeInterval(30)
        let newest = self.t2
        func device(id: String, revision: Date) -> SyncedUsageSnapshot {
            SyncedUsageSnapshot(
                providers: [ProviderUsageSnapshot(
                    providerID: "codex",
                    providerName: "Codex",
                    primary: nil,
                    secondary: nil,
                    accountEmail: "same@example.com",
                    loginMethod: nil,
                    statusMessage: nil,
                    isError: false,
                    lastUpdated: self.t1,
                    costSummary: SyncCostSummary(
                        sessionCostUSD: 1,
                        sessionTokens: 1,
                        last30DaysCostUSD: 1,
                        last30DaysTokens: 1,
                        daily: [],
                        costUpdatedAt: revision,
                        totalCostUpdatedAt: revision))],
                syncTimestamp: revision,
                deviceName: id,
                deviceID: id)
        }
        let before = SnapshotIdentityKey.costRevisionComponents(from: [
            device(id: "oldest", revision: oldest),
            device(id: "middle", revision: middle),
            device(id: "newest", revision: newest),
        ])
        let after = SnapshotIdentityKey.costRevisionComponents(from: [
            device(id: "oldest", revision: oldest),
            device(id: "middle", revision: middle.addingTimeInterval(10)),
            device(id: "newest", revision: newest),
        ])

        // Aggregate min/max revisions remain oldest/newest in both states;
        // the raw contributor vector must still change.
        #expect(before != after)
    }

    @Test
    func `A subordinate dashboard revision changes identity under a newer scanner maximum`() {
        let providerUpdatedAt = self.t1
        let scannerRevision = self.t2
        func snapshot(dashboardRevision: Date) -> SyncedUsageSnapshot {
            SyncedUsageSnapshot(
                providers: [ProviderUsageSnapshot(
                    providerID: "codex",
                    providerName: "Codex",
                    primary: nil,
                    secondary: nil,
                    accountEmail: nil,
                    loginMethod: nil,
                    statusMessage: nil,
                    isError: false,
                    lastUpdated: providerUpdatedAt,
                    costSummary: SyncCostSummary(
                        sessionCostUSD: 1,
                        sessionTokens: 1,
                        last30DaysCostUSD: 1,
                        last30DaysTokens: 1,
                        daily: [],
                        costUpdatedAt: scannerRevision,
                        totalCostUpdatedAt: scannerRevision,
                        sourceRevisions: [
                            "tokenScanner": scannerRevision,
                            "openAIDashboard": dashboardRevision,
                        ]))],
                syncTimestamp: providerUpdatedAt,
                deviceName: "Mac",
                deviceID: "mac")
        }

        let before = SnapshotIdentityKey.costRevisionComponents(from: [
            snapshot(dashboardRevision: self.t1),
        ])
        let after = SnapshotIdentityKey.costRevisionComponents(from: [
            snapshot(dashboardRevision: self.t1.addingTimeInterval(30)),
        ])

        #expect(before != after)
    }

    @Test
    func `Removing a dashboard source changes identity under an unchanged scanner revision`() {
        let scannerRevision = self.t2
        func snapshot(includeDashboard: Bool) -> SyncedUsageSnapshot {
            SyncedUsageSnapshot(
                providers: [ProviderUsageSnapshot(
                    providerID: "codex",
                    providerName: "Codex",
                    primary: nil,
                    secondary: nil,
                    accountEmail: nil,
                    loginMethod: nil,
                    statusMessage: nil,
                    isError: false,
                    lastUpdated: self.t1,
                    costSummary: SyncCostSummary(
                        sessionCostUSD: 1,
                        sessionTokens: 1,
                        last30DaysCostUSD: 1,
                        last30DaysTokens: 1,
                        daily: [],
                        costUpdatedAt: scannerRevision,
                        totalCostUpdatedAt: scannerRevision,
                        sourceRevisions: includeDashboard
                            ? [
                                "tokenScanner": scannerRevision,
                                "openAIDashboard": self.t1,
                            ]
                            : ["tokenScanner": scannerRevision]))],
                syncTimestamp: self.t1,
                deviceName: "Mac",
                deviceID: "mac")
        }

        let before = SnapshotIdentityKey.costRevisionComponents(from: [
            snapshot(includeDashboard: true),
        ])
        let after = SnapshotIdentityKey.costRevisionComponents(from: [
            snapshot(includeDashboard: false),
        ])

        #expect(before != after)
    }

    @Test
    func `Empty provider list is a stable key`() {
        let a = SnapshotIdentityKey.make(providerIDs: [], lastUpdated: self.t1)
        let b = SnapshotIdentityKey.make(providerIDs: [], lastUpdated: self.t1)
        #expect(a == b)
        #expect(a.providerIDs.isEmpty)
    }
}
