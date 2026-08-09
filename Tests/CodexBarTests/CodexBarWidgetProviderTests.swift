import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWidget

struct CodexBarWidgetProviderTests {
    @Test
    func `widget provider choice is the four provider product`() {
        #expect(ProviderChoice(provider: .codex) == .codex)
        #expect(ProviderChoice(provider: .claude) == .claude)
        #expect(ProviderChoice(provider: .cursor) == .cursor)
        #expect(ProviderChoice(provider: .grok) == .grok)
        #expect(ProviderChoice.codex.provider == .codex)
        #expect(ProviderChoice.claude.provider == .claude)
        #expect(ProviderChoice.cursor.provider == .cursor)
        #expect(ProviderChoice.grok.provider == .grok)
    }

    @Test
    func `widget switcher keeps all enabled supported providers`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = UsageProvider.allCases.map { provider in
            WidgetSnapshot.ProviderEntry(
                provider: provider,
                updatedAt: now,
                primary: nil,
                secondary: nil,
                tertiary: nil,
                creditsRemaining: nil,
                codeReviewRemainingPercent: nil,
                tokenUsage: nil,
                dailyUsage: [])
        }
        let snapshot = WidgetSnapshot(
            entries: entries,
            enabledProviders: UsageProvider.allCases.map(\.instanceID),
            generatedAt: now)

        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(from: snapshot) == UsageProvider.allCases)
    }

    @Test
    func `widget switcher ignores retired provider ids and falls back to codex`() throws {
        let retired = try #require(ProviderInstanceID(rawValue: "gemini"))
        let snapshot = WidgetSnapshot(entries: [], enabledProviders: [retired], generatedAt: Date())

        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(from: snapshot) == [.codex])
    }

    @Test
    func `widget configuration intents default to codex and credits`() {
        #expect(ProviderSelectionIntent().provider == .codex)
        #expect(CompactMetricSelectionIntent().provider == .codex)
        #expect(CompactMetricSelectionIntent().metric == .credits)
        #expect(BurnDownSelectionIntent().provider == .codex)
        #expect(BurnDownSelectionIntent().window == .session)
        #expect(BurnProviderSelectionIntent().provider == .codex)
    }

    @Test
    func `generic widget rows preserve order and obey limits`() {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .grok,
            updatedAt: Date(),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            usageRows: [
                .init(id: "one", title: "One", percentLeft: 90),
                .init(id: "two", title: "Two", percentLeft: 80),
                .init(id: "three", title: "Three", percentLeft: 70),
            ],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        #expect(WidgetUsageRow.rows(for: entry, limit: 2).map(\.id) == ["one", "two"])
        #expect(WidgetUsageRow.rows(for: entry).map(\.id) == ["one", "two", "three"])
    }

    @Test
    func `small widget falls back to local cost when quota rows are unavailable`() {
        let tokenUsage = WidgetSnapshot.TokenUsageSummary(
            sessionCostUSD: 1.25,
            sessionTokens: 4200,
            last30DaysCostUSD: 12.50,
            last30DaysTokens: 42000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .claude,
            updatedAt: Date(),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            usageRows: [],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: tokenUsage,
            dailyUsage: [])

        #expect(WidgetUsageRow.compactTokenUsage(for: entry)?.sessionTokens == 4200)
    }

    @Test
    func `codex weekly exhaustion caps the paired session row`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let weeklyReset = now.addingTimeInterval(3600)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: now,
            primary: RateWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 100,
                windowMinutes: 10080,
                resetsAt: weeklyReset,
                resetDescription: nil),
            tertiary: nil,
            usageRows: [
                .init(id: "session", title: "Session", percentLeft: 80),
                .init(id: "weekly", title: "Weekly", percentLeft: 0),
            ],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        #expect(WidgetUsageRow.rows(for: entry, now: now).map(\.percentLeft) == [0, 0])
        #expect(WidgetUsageRow.rows(for: entry, now: weeklyReset).map(\.percentLeft) == [80, 0])
    }

    @Test
    func `burn down uses an exact provider entry`() {
        let snapshot = Self.burnSnapshot(provider: .claude, primaryUsed: 20, secondaryUsed: 30)

        #expect(BurnDownState(snapshot: snapshot, provider: .codex, selection: .session) == nil)
        #expect(BurnDownState(snapshot: snapshot, provider: .claude, selection: .session) != nil)
    }

    @Test
    func `codex weekly cap blocks the burn down session until reset`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let weeklyReset = now.addingTimeInterval(3600)
        let state = try #require(BurnDownState(
            snapshot: Self.burnSnapshot(
                provider: .codex,
                primaryUsed: 80,
                secondaryUsed: 100,
                primaryReset: now.addingTimeInterval(1800),
                secondaryReset: weeklyReset),
            provider: .codex,
            selection: .session,
            now: now))

        #expect(state.primaryWindow?.remainingPercent == 0)
        #expect(state.blankPrimaryChart)
        #expect(state.selectedResetOverride == weeklyReset)
    }

    @Test
    func `widget formatting retains compact tokens costs and history mode`() {
        #expect(WidgetFormat.tokenCount(9_400_000) == "9.4M tokens")
        #expect(WidgetUsageDisplay.percent(fromRemaining: 48, showUsed: true) == 52)
        #expect(UsageHistoryChartMode.isCostMode([
            .init(dayKey: "2026-07-01", totalTokens: 100, costUSD: 1.2),
        ]))
        #expect(!UsageHistoryChartMode.isCostMode([
            .init(dayKey: "2026-07-01", totalTokens: 100, costUSD: nil),
        ]))
    }

    private static func burnSnapshot(
        provider: UsageProvider,
        primaryUsed: Double?,
        secondaryUsed: Double?,
        primaryReset: Date? = nil,
        secondaryReset: Date? = nil) -> WidgetSnapshot
    {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: provider,
            updatedAt: updatedAt,
            primary: primaryUsed.map {
                RateWindow(
                    usedPercent: $0,
                    windowMinutes: 5 * 60,
                    resetsAt: primaryReset,
                    resetDescription: nil)
            },
            secondary: secondaryUsed.map {
                RateWindow(
                    usedPercent: $0,
                    windowMinutes: 7 * 24 * 60,
                    resetsAt: secondaryReset,
                    resetDescription: nil)
            },
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        return WidgetSnapshot(entries: [entry], generatedAt: updatedAt)
    }
}
