import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct ProvidersPaneCoverageTests {
    @Test
    func `provider pane harness exercises exactly the supported providers`() {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests")
        ProvidersPaneTestHarness.exercise(settings: settings, store: Self.makeUsageStore(settings: settings))
    }

    @Test
    func `retained token account descriptors preserve Claude and Cursor fields`() throws {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-token-fields")
        let pane = ProvidersPane(settings: settings, store: Self.makeUsageStore(settings: settings))

        let claude = try #require(pane._test_tokenAccountDescriptor(for: .claude))
        let cursor = try #require(pane._test_tokenAccountDescriptor(for: .cursor))
        #expect(claude.showsOrganizationField)
        #expect(!claude.showsTeamModeControls)
        #expect(!cursor.showsOrganizationField)
        #expect(!cursor.showsTeamModeControls)
        #expect(pane._test_tokenAccountDescriptor(for: .codex) == nil)
        #expect(pane._test_tokenAccountDescriptor(for: .grok) == nil)
    }

    @Test
    func `provider search filters supported names and raw ids`() {
        let providers = UsageProvider.allCases
        let names = ProviderDefaults.metadata.mapValues(\.displayName)

        #expect(ProvidersPane.filteredProviders(providers, query: "  ", displayName: { names[$0] ?? $0.rawValue }) ==
            providers)
        #expect(ProvidersPane.filteredProviders(providers, query: "CLA", displayName: { names[$0] ?? $0.rawValue }) ==
            [.claude])
        #expect(ProvidersPane.filteredProviders(providers, query: "grok", displayName: { _ in "AI" }) == [.grok])
    }

    @Test
    func `provider reordering is inert while alphabetical sorting is enabled`() {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-sorted-reorder")
        let pane = ProvidersPane(settings: settings, store: Self.makeUsageStore(settings: settings))
        let original = settings.orderedProviders()

        settings.providersSortedAlphabetically = true
        pane._test_moveProviders(fromOffsets: IndexSet(integer: 0), toOffset: original.count)
        #expect(settings.orderedProviders() == original)

        settings.providersSortedAlphabetically = false
        pane._test_moveProviders(fromOffsets: IndexSet(integer: 0), toOffset: original.count)
        #expect(settings.orderedProviders().last == original.first)
    }

    @Test
    func `Claude preview follows daily routines visibility`() {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-claude-routines")
        let store = Self.makeUsageStore(settings: settings)
        let now = Date()
        store._setSnapshotForTesting(UsageSnapshot(
            primary: RateWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 30, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            extraRateWindows: [NamedRateWindow(
                id: "claude-routines",
                title: "Daily Routines",
                window: RateWindow(
                    usedPercent: 40,
                    windowMinutes: 10080,
                    resetsAt: now.addingTimeInterval(7200),
                    resetDescription: nil))],
            updatedAt: now), provider: .claude)
        let pane = ProvidersPane(settings: settings, store: store)

        #expect(pane._test_menuCardModel(for: .claude).metrics.contains { $0.id == "claude-routines" })
        settings.claudeDailyRoutinesUsageVisible = false
        #expect(!pane._test_menuCardModel(for: .claude).metrics.contains { $0.id == "claude-routines" })
    }

    @Test
    func `Codex preview follows Spark visibility`() {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-codex-spark")
        let store = Self.makeUsageStore(settings: settings)
        let now = Date()
        store._setSnapshotForTesting(UsageSnapshot(
            primary: RateWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 30, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            extraRateWindows: [NamedRateWindow(
                id: CodexAdditionalRateLimitMapper.sparkWindowID,
                title: "Codex Spark 5-hour",
                window: RateWindow(
                    usedPercent: 40,
                    windowMinutes: 300,
                    resetsAt: now.addingTimeInterval(1800),
                    resetDescription: nil))],
            updatedAt: now), provider: .codex)
        let pane = ProvidersPane(settings: settings, store: store)

        #expect(pane._test_menuCardModel(for: .codex).metrics.contains {
            $0.id == CodexAdditionalRateLimitMapper.sparkWindowID
        })
        settings.codexSparkUsageVisible = false
        #expect(!pane._test_menuCardModel(for: .codex).metrics.contains {
            $0.id == CodexAdditionalRateLimitMapper.sparkWindowID
        })
    }

    @Test
    func `provider detail keeps generic plan and metric presentations`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let row = ProviderDetailView<EmptyView>.planRow(provider: .codex, planText: "Pro")
            #expect(row?.label == "Plan")
            #expect(row?.value == "Pro")
        }
        let unavailable = UsageMenuCardView.Model.Metric(
            id: "unavailable",
            title: "Quota",
            percent: 0,
            percentStyle: .left,
            statusText: "Unavailable",
            resetText: nil,
            detailText: nil,
            detailLeftText: nil,
            detailRightText: nil,
            pacePercent: nil,
            paceOnTop: false)
        #expect(ProviderDetailView<EmptyView>.metricInlinePresentation(unavailable) == .status("Unavailable"))
    }

    private static func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(userDefaults: defaults, configStore: testConfigStore(suiteName: suite))
    }

    private static func makeUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
    }
}
