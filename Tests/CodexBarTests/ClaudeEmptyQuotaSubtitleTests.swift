import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

/// Settings subtitles resolve availability from the successful snapshot after fetch state is cleared.
struct ClaudeEmptyQuotaSubtitleTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    @Test
    func `quota-less Claude snapshot shows limits unavailable in provider subtitles`() throws {
        let (settings, store) = try Self.makeStore()
        store._setSnapshotForTesting(
            UsageSnapshot(primary: nil, secondary: nil, updatedAt: Self.now),
            provider: .claude)
        let pane = ProvidersPane(settings: settings, store: store)

        #expect(pane._test_providerSubtitle(.claude).contains("Limits not available"))
        #expect(pane._test_providerSidebarSubtitle(.claude).hasSuffix("\nLimits not available"))
    }

    @MainActor
    @Test
    func `spend-only Claude snapshot keeps the updated timestamp subtitle`() throws {
        let (settings, store) = try Self.makeStore()
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                providerCost: ProviderCostSnapshot(
                    used: 9.95,
                    limit: 150,
                    currencyCode: "USD",
                    period: "Monthly cap",
                    updatedAt: Self.now),
                updatedAt: Self.now),
            provider: .claude)
        let pane = ProvidersPane(settings: settings, store: store)

        #expect(!pane._test_providerSubtitle(.claude).contains("Limits not available"))
        #expect(!pane._test_providerSidebarSubtitle(.claude).contains("Limits not available"))
    }

    @MainActor
    @Test
    func `measured Claude window keeps the updated timestamp subtitle`() throws {
        let (settings, store) = try Self.makeStore()
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 12,
                    windowMinutes: 5 * 60,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: nil,
                updatedAt: Self.now),
            provider: .claude)
        let pane = ProvidersPane(settings: settings, store: store)

        #expect(!pane._test_providerSubtitle(.claude).contains("Limits not available"))
        #expect(!pane._test_providerSidebarSubtitle(.claude).contains("Limits not available"))
    }

    @MainActor
    private static func makeStore() throws -> (SettingsStore, UsageStore) {
        let settings = testSettingsStore(suiteName: "ClaudeEmptyQuotaSubtitleTests-\(UUID().uuidString)")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.claudeUsageDataSource = .web
        settings.claudeOAuthKeychainPromptMode = .never
        settings.providerDetectionCompleted = true

        let metadata = ProviderRegistry.shared.metadata
        for provider in UsageProvider.allCases {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(metadata[provider]),
                enabled: provider == .claude)
        }

        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        return (settings, store)
    }
}
