import CodexBarSync
import Foundation
import XCTest

@testable import CodexBarMobile

final class ProviderAccessGateTests: XCTestCase {

    func testFreeRealDataWithNoGroupsShowsNone() {
        let result = ProviderAccessGate.resolve(
            groups: [],
            isDemoMode: false,
            isProUnlocked: false,
            selectedProviderID: nil)

        XCTAssertTrue(result.visibleGroups.isEmpty)
        XCTAssertEqual(result.lockedCount, 0)
        XCTAssertNil(result.effectiveSelectedProviderID)
        XCTAssertFalse(result.isLimited)
    }

    func testFreeRealDataWithOneGroupShowsThatGroup() {
        let groups = [Self.group(id: "codex")]

        let result = ProviderAccessGate.resolve(
            groups: groups,
            isDemoMode: false,
            isProUnlocked: false,
            selectedProviderID: nil)

        XCTAssertEqual(result.visibleGroups.map(\.providerID), ["codex"])
        XCTAssertEqual(result.lockedCount, 0)
        XCTAssertFalse(result.isLimited)
    }

    func testFreeRealDataWithSelectedProviderShowsOneAndLocksRest() {
        let groups = [
            Self.group(id: "codex"),
            Self.group(id: "claude"),
            Self.group(id: "cursor"),
        ]

        let result = ProviderAccessGate.resolve(
            groups: groups,
            isDemoMode: false,
            isProUnlocked: false,
            selectedProviderID: "claude")

        XCTAssertEqual(result.visibleGroups.map(\.providerID), ["claude"])
        XCTAssertEqual(result.lockedCount, 2)
        XCTAssertEqual(result.effectiveSelectedProviderID, "claude")
        XCTAssertTrue(result.isLimited)
    }

    func testFreeRealDataWithStaleSelectionFallsBackToFirstGroup() {
        let groups = [
            Self.group(id: "codex"),
            Self.group(id: "claude"),
        ]

        let result = ProviderAccessGate.resolve(
            groups: groups,
            isDemoMode: false,
            isProUnlocked: false,
            selectedProviderID: "missing")

        XCTAssertEqual(result.visibleGroups.map(\.providerID), ["codex"])
        XCTAssertEqual(result.lockedCount, 1)
        XCTAssertEqual(result.effectiveSelectedProviderID, "codex")
        XCTAssertTrue(result.isLimited)
    }

    func testProRealDataShowsAllGroups() {
        let groups = [
            Self.group(id: "codex"),
            Self.group(id: "claude"),
            Self.group(id: "cursor"),
        ]

        let result = ProviderAccessGate.resolve(
            groups: groups,
            isDemoMode: false,
            isProUnlocked: true,
            selectedProviderID: "claude")

        XCTAssertEqual(result.visibleGroups.map(\.providerID), ["codex", "claude", "cursor"])
        XCTAssertEqual(result.lockedCount, 0)
        XCTAssertFalse(result.isLimited)
    }

    func testDemoModeShowsAllGroupsEvenWhenProIsLocked() {
        let groups = [
            Self.group(id: "codex"),
            Self.group(id: "claude"),
            Self.group(id: "cursor"),
        ]

        let result = ProviderAccessGate.resolve(
            groups: groups,
            isDemoMode: true,
            isProUnlocked: false,
            selectedProviderID: "claude")

        XCTAssertEqual(result.visibleGroups.map(\.providerID), ["codex", "claude", "cursor"])
        XCTAssertEqual(result.lockedCount, 0)
        XCTAssertFalse(result.isLimited)
    }

    func testMultiAccountProviderCountsAsOneFreeProviderGroup() {
        let groups = [
            Self.group(id: "codex", accounts: 2),
            Self.group(id: "claude"),
        ]

        let result = ProviderAccessGate.resolve(
            groups: groups,
            isDemoMode: false,
            isProUnlocked: false,
            selectedProviderID: "codex")

        XCTAssertEqual(result.visibleGroups.map(\.providerID), ["codex"])
        XCTAssertEqual(result.visibleGroups.first?.accounts.count, 2)
        XCTAssertEqual(result.lockedCount, 1)
        XCTAssertTrue(result.isLimited)
    }

    private static func group(id: String, accounts: Int = 1) -> ProviderAccountGroup {
        ProviderAccountGroup(
            providerID: id,
            providerName: id.capitalized,
            accounts: (0..<accounts).map { index in
                ProviderUsageSnapshot(
                    providerID: id,
                    providerName: id.capitalized,
                    primary: nil,
                    secondary: nil,
                    accountEmail: accounts > 1 ? "account\(index)@example.com" : nil,
                    loginMethod: nil,
                    statusMessage: nil,
                    isError: false,
                    lastUpdated: Date(timeIntervalSince1970: 1_800_000_000 + TimeInterval(index)))
            })
    }
}
