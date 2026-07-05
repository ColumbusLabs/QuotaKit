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
    func `Empty provider list is a stable key`() {
        let a = SnapshotIdentityKey.make(providerIDs: [], lastUpdated: self.t1)
        let b = SnapshotIdentityKey.make(providerIDs: [], lastUpdated: self.t1)
        #expect(a == b)
        #expect(a.providerIDs.isEmpty)
    }
}
