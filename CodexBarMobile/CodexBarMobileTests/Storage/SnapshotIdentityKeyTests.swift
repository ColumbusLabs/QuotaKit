import Foundation
import Testing
@testable import CodexBarMobile

@Suite("SnapshotIdentityKey Tests (Contract C3)")
struct SnapshotIdentityKeyTests {
    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_700_000_060)

    @Test("Same providers + same lastUpdated yield equal keys")
    func equalKeys() {
        let a = SnapshotIdentityKey.make(
            providerIDs: ["claude", "codex"],
            lastUpdated: self.t1)
        let b = SnapshotIdentityKey.make(
            providerIDs: ["codex", "claude"], // order-insensitive after sort
            lastUpdated: self.t1)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Different provider sets yield different keys")
    func differentProvidersDifferentKeys() {
        let a = SnapshotIdentityKey.make(
            providerIDs: ["claude"],
            lastUpdated: self.t1)
        let b = SnapshotIdentityKey.make(
            providerIDs: ["claude", "codex"],
            lastUpdated: self.t1)
        #expect(a != b)
    }

    @Test("Same providers + different lastUpdated yield different keys")
    func differentTimestampDifferentKeys() {
        let a = SnapshotIdentityKey.make(
            providerIDs: ["claude", "codex"],
            lastUpdated: self.t1)
        let b = SnapshotIdentityKey.make(
            providerIDs: ["claude", "codex"],
            lastUpdated: self.t2)
        #expect(a != b)
    }

    @Test("Empty provider list is a stable key")
    func emptyProviderList() {
        let a = SnapshotIdentityKey.make(providerIDs: [], lastUpdated: self.t1)
        let b = SnapshotIdentityKey.make(providerIDs: [], lastUpdated: self.t1)
        #expect(a == b)
        #expect(a.providerIDs.isEmpty)
    }
}
