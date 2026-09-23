import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct SwitcherExhaustedQuotaTests {
    @Test
    func `automatic switcher honors exhausted quotas and keeps healthy weekly progress`() {
        let exhausted = Self.snapshot(monthly: 100)
        #expect(StatusItemController.switcherWeeklyMetricPercent(
            for: .opencodego,
            snapshot: exhausted,
            showUsed: false) == 0)
        #expect(StatusItemController.switcherWeeklyMetricPercent(
            for: .opencodego,
            snapshot: exhausted,
            showUsed: true) == 100)

        let healthy = Self.snapshot(monthly: 90)
        #expect(StatusItemController.switcherWeeklyMetricPercent(
            for: .opencodego,
            snapshot: healthy,
            showUsed: false) == 60)
        #expect(StatusItemController.switcherWeeklyMetricPercent(
            for: .opencodego,
            snapshot: healthy,
            showUsed: true) == 40)
    }

    @Test
    func `explicit and opted out metrics retain their weekly selection`() {
        let snapshot = Self.snapshot(monthly: 100)
        for preference in [MenuBarMetricPreference.primary, .secondary, .tertiary] {
            #expect(StatusItemController.switcherWeeklyMetricPercent(
                for: .opencodego,
                snapshot: snapshot,
                showUsed: false,
                preference: preference) == 60)
        }

        #expect(StatusItemController.switcherWeeklyMetricPercent(
            for: .codex,
            snapshot: snapshot,
            showUsed: false) == 60)
    }

    private static func snapshot(monthly: Double) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 40, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: RateWindow(usedPercent: monthly, windowMinutes: 43200, resetsAt: nil, resetDescription: nil),
            updatedAt: Date(timeIntervalSince1970: 1_788_480_000))
    }
}
