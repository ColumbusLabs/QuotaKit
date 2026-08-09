import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarWidget

struct ProviderPresentationPolicyCharacterizationTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func `automatic exhaustion priority is pinned for supported providers`() {
        let expected: [UsageProvider: Bool] = [
            .codex: false,
            .claude: false,
            .cursor: false,
            .grok: true,
        ]
        for provider in UsageProvider.allCases {
            #expect(MenuBarMetricWindowResolver.automaticSelectionPrioritizesExhaustedWindow(for: provider) ==
                expected[provider])
        }
    }

    @Test
    func `Cursor tertiary lane keeps its explicit fallback order`() {
        let primary = RateWindow(
            usedPercent: 11,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: "primary")
        let secondary = RateWindow(
            usedPercent: 22,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: "secondary")
        let tertiary = RateWindow(
            usedPercent: 33,
            windowMinutes: 43200,
            resetsAt: nil,
            resetDescription: "tertiary")
        let snapshot = UsageSnapshot(primary: primary, secondary: secondary, tertiary: tertiary, updatedAt: self.now)

        let selected = MenuBarMetricWindowResolver.rateWindow(
            preference: .tertiary,
            provider: .cursor,
            snapshot: snapshot,
            supportsAverage: false,
            now: self.now)

        #expect(selected?.resetDescription == "tertiary")
    }

    @Test
    func `session pace eligibility remains scoped to supported provider semantics`() {
        let fixtures: [(UsageProvider, Int?, Bool)] = [
            (.codex, nil, true),
            (.codex, 10080, false),
            (.claude, nil, true),
            (.cursor, 300, false),
            (.grok, 300, false),
        ]
        for (provider, minutes, expected) in fixtures {
            let window = RateWindow(
                usedPercent: 50,
                windowMinutes: minutes,
                resetsAt: self.now.addingTimeInterval(3600),
                resetDescription: nil)
            #expect((UsagePaceText.sessionPace(provider: provider, window: window, now: self.now) != nil) == expected)
        }
    }

    @Test
    @MainActor
    func `decorated icon styles are limited to Codex and Claude`() throws {
        let decoratedStyles: Set<IconStyle> = [.codex, .claude]
        for style in IconStyle.allCases {
            let decorated = IconRenderer.makeIcon(
                primaryRemaining: 60,
                weeklyRemaining: 40,
                creditsRemaining: nil,
                stale: false,
                style: style,
                hideCritters: false)
            let plain = IconRenderer.makeIcon(
                primaryRemaining: 60,
                weeklyRemaining: 40,
                creditsRemaining: nil,
                stale: false,
                style: style,
                hideCritters: true)
            #expect(
                try (#require(decorated.tiffRepresentation) != #require(plain.tiffRepresentation)) ==
                    decoratedStyles.contains(style))
        }
    }

    @Test
    func `history series selection keeps Codex and Claude contracts`() {
        let session = RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        let weekly = RateWindow(usedPercent: 20, windowMinutes: 10080, resetsAt: nil, resetDescription: nil)
        let histories = [
            self.history(.session, minutes: 300),
            self.history(.weekly, minutes: 10080),
            self.history(.opus, minutes: 10080),
        ]

        let codex = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            histories: histories,
            provider: .codex,
            snapshot: UsageSnapshot(primary: session, secondary: weekly, updatedAt: self.now))
        let claude = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            histories: histories,
            provider: .claude,
            snapshot: UsageSnapshot(primary: session, secondary: weekly, tertiary: weekly, updatedAt: self.now))

        #expect(codex.visibleSeries == ["session:300", "weekly:10080"])
        #expect(claude.visibleSeries == ["session:300", "weekly:10080", "opus:10080"])
    }

    @Test
    func `widget burn down secondary cap remains Codex and Claude only`() throws {
        for provider in UsageProvider.allCases {
            let entry = WidgetSnapshot.ProviderEntry(
                provider: provider,
                updatedAt: self.now,
                primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: RateWindow(usedPercent: 20, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
                tertiary: nil,
                creditsRemaining: nil,
                codeReviewRemainingPercent: nil,
                tokenUsage: nil,
                dailyUsage: [])
            let state = try #require(BurnDownState(
                snapshot: WidgetSnapshot(
                    entries: [entry],
                    enabledProviders: [provider.instanceID],
                    generatedAt: self.now),
                provider: provider,
                selection: .session,
                now: self.now))
            #expect(state.secondaryGloballyCapsPrimary == [.codex, .claude].contains(provider))
        }
    }

    private func history(_ name: PlanUtilizationSeriesName, minutes: Int) -> PlanUtilizationSeriesHistory {
        PlanUtilizationSeriesHistory(
            name: name,
            windowMinutes: minutes,
            entries: [PlanUtilizationHistoryEntry(capturedAt: self.now, usedPercent: 10, resetsAt: nil)])
    }
}
