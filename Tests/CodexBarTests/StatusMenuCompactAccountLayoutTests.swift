import AppKit
import CodexBarCore
import Foundation
import XCTest
@testable import CodexBar

/// Coverage for the compact multi-account layout on the token-account and Codex
/// paths (the claude-swap path is covered by StatusMenuClaudeSwapCompactTests).
@MainActor
final class StatusMenuCompactAccountLayoutTests: XCTestCase {
    func test_compactConstraintDetailLocalizesLabelsWithoutChangingValues() {
        let row = AccountMenuLayoutPlanner.CompactRow(
            accountID: ProviderAccountIdentity(source: "test", opaqueID: "1"),
            label: "Account",
            headroomPercent: 43,
            severity: .warning,
            constraints: [
                .init(label: "Weekly", remainingPercent: 43),
                .init(label: "Monthly", remainingPercent: 12),
            ],
            hasError: false,
            canActivate: true,
            isBestCandidate: false)

        let localized = StatusItemController.localizedCompactConstraintDetail(row) { label in
            ["Weekly": "Week", "Monthly": "Month"][label] ?? label
        }

        XCTAssertEqual(localized, "Week 43% · Month 12%")
        XCTAssertEqual(row.headroomPercent, 43)
        XCTAssertEqual(row.severity, .warning)
    }

    private func snapshot(usedPercent: Double) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: usedPercent,
                windowMinutes: 300,
                resetsAt: Date().addingTimeInterval(3600),
                resetDescription: nil),
            secondary: nil,
            updatedAt: Date(),
            identity: nil)
    }

    func test_codexAccountProjectionMapsActiveHealthAndIdentity() {
        let accounts = (1...4).map { index in
            CodexVisibleAccount(
                id: "account-\(index)",
                email: "codex\(index)@example.com",
                // account-4: stored account without live auth → "Missing auth" health.
                storedAccountID: index == 4 ? UUID() : nil,
                selectionSource: .liveSystem,
                isActive: index == 2,
                isLive: index != 4,
                canReauthenticate: false,
                canRemove: false)
        }
        let snapshots = accounts.prefix(3).map { account in
            CodexAccountUsageSnapshot(
                account: account,
                snapshot: self.snapshot(usedPercent: 50),
                error: nil,
                sourceLabel: "test")
        }
        let display = CodexAccountMenuDisplay(
            accounts: accounts,
            snapshots: Array(snapshots),
            activeVisibleAccountID: "account-2",
            layout: .stacked)

        let projected = StatusItemController.projectedCodexAccounts(display: display)

        XCTAssertEqual(projected.map(\ProviderAccountUsageSnapshot.id.opaqueID), [
            "account-1", "account-2", "account-3", "account-4",
        ])
        XCTAssertEqual(projected.map(\ProviderAccountUsageSnapshot.isActive), [false, true, false, false])
        XCTAssertEqual(projected[0].id.source, "codex-account")
        XCTAssertEqual(projected[0].displayLabel, "codex1@example.com")
        // account-4 has no snapshot: unavailable health surfaces as an error row.
        XCTAssertNil(projected[3].snapshot)
        XCTAssertNotNil(projected[3].error)
        XCTAssertNil(projected[0].error)
    }
}
