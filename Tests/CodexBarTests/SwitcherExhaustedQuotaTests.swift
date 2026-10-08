import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct SwitcherExhaustedQuotaTests {
    @Test(arguments: [false, true])
    func `automatic switcher shows the most constrained healthy allowance`(_ showUsed: Bool) {
        let cases: [(Double, Double?, Double, Int)] = [
            (20, 40, 90, 43200), (20, nil, 90, 43200), (90, 40, 30, 300), (20, 90, 30, 10080),
        ]
        for (rolling, weekly, monthly, minutes) in cases {
            let snapshot = Self.snapshot(rolling: rolling, weekly: weekly, monthly: monthly)
            let percent = StatusItemController.switcherWeeklyMetricPercent(
                for: .opencodego,
                snapshot: snapshot,
                showUsed: showUsed)
            #expect(percent == (showUsed ? 90 : 10))
            let metric = MenuBarMetricWindowResolver.rateWindow(
                preference: .automatic,
                provider: .opencodego,
                snapshot: snapshot,
                supportsAverage: false)
            #expect(metric?.usedPercent == 90)
            #expect(metric?.windowMinutes == minutes)
        }
    }

    @Test
    func `automatic switcher preserves weekly progress when weekly is most constrained`() {
        let percent = StatusItemController.switcherWeeklyMetricPercent(
            for: .opencodego,
            snapshot: Self.snapshot(monthly: 30),
            showUsed: false)
        #expect(percent == 60)
    }

    @Test(arguments: [
        (100.0, 40.0, 30.0, 300),
        (20.0, 100.0, 30.0, 10080),
        (20.0, 40.0, 100.0, 43200),
    ])
    func `automatic switcher selects the exhausted opencode go quota lane`(
        rolling: Double, weekly: Double, monthly: Double, minutes: Int)
    {
        let snapshot = Self.snapshot(rolling: rolling, weekly: weekly, monthly: monthly)
        let metric = MenuBarMetricWindowResolver.rateWindow(
            preference: .automatic,
            provider: .opencodego,
            snapshot: snapshot,
            supportsAverage: false)
        #expect(metric?.usedPercent == 100)
        #expect(metric?.windowMinutes == minutes)
        #expect(StatusItemController.switcherWeeklyMetricPercent(
            for: .opencodego,
            snapshot: snapshot,
            showUsed: false) == 0)
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

    private static func snapshot(
        rolling: Double = 20,
        weekly: Double? = 40,
        monthly: Double) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: RateWindow(usedPercent: rolling, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: weekly.map {
                RateWindow(usedPercent: $0, windowMinutes: 10080, resetsAt: nil, resetDescription: nil)
            },
            tertiary: RateWindow(usedPercent: monthly, windowMinutes: 43200, resetsAt: nil, resetDescription: nil),
            updatedAt: Date(timeIntervalSince1970: 1_788_480_000))
    }
}
