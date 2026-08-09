import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct UserFacingLocalizationCoverageTests {
    @Test
    func `core user facing labels resolve to English`() {
        #expect(L("Settings") == "Settings")
        #expect(L("Account") == "Account")
        #expect(L("Plan") == "Plan")
        #expect(L("Refresh") == "Refresh")
    }

    @Test
    func `provider inventory exposes English display names for exactly four providers`() {
        let names = ProviderDescriptorRegistry.all.map { ($0.id.rawValue, $0.metadata.displayName) }

        #expect(names.map(\.0) == ["codex", "claude", "cursor", "grok"])
        #expect(names.map(\.1) == ["Codex", "Claude", "Cursor", "Grok"])
    }

    @Test
    func `spend dashboard accessibility copy remains English`() {
        let start = Date(timeIntervalSince1970: 1_783_036_800)
        let points = [
            SpendDashboardModel.DailyPoint(
                sourceID: "claude",
                provider: .claude,
                providerName: "Claude",
                day: start,
                cost: 2,
                stackStart: 0,
                stackEnd: 2),
            SpendDashboardModel.DailyPoint(
                sourceID: "codex",
                provider: .codex,
                providerName: "Codex",
                day: start,
                cost: 3,
                stackStart: 2,
                stackEnd: 5),
        ]

        let presentation = SpendDailyChartPresentation(dailyPoints: points, aggregateTotal: 5)

        #expect(presentation.content == .chart)
        #expect(presentation.accessibilityValue == "1 day of usage data across 2 services")
    }
}
