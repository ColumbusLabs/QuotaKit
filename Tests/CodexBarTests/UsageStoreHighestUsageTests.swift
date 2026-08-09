import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct UsageStoreHighestUsageTests {
    @Test
    func `selects highest usage among enabled providers`() {
        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: "UsageStoreHighestUsageTests-selects"))
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false

        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }
        if let claudeMeta = registry.metadata[.claude] {
            settings.setProviderEnabled(provider: .claude, metadata: claudeMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)

        let codexSnapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 25, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        let claudeSnapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 60, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())

        store._setSnapshotForTesting(codexSnapshot, provider: .codex)
        store._setSnapshotForTesting(claudeSnapshot, provider: .claude)

        let highest = store.providerWithHighestUsage()
        #expect(highest?.provider == .claude)
        #expect(highest?.usedPercent == 60)

        let overviewHighest = store.providerWithHighestUsage(candidateProviders: [.codex])
        #expect(overviewHighest?.provider == .codex)
        #expect(overviewHighest?.usedPercent == 25)
        #expect(store.providerWithHighestUsage(candidateProviders: []) == nil)
    }

    @Test
    func `skips fully used providers`() {
        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: "UsageStoreHighestUsageTests-skips"))
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false

        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }
        if let claudeMeta = registry.metadata[.claude] {
            settings.setProviderEnabled(provider: .claude, metadata: claudeMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)

        let codexSnapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        let claudeSnapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 80, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())

        store._setSnapshotForTesting(codexSnapshot, provider: .codex)
        store._setSnapshotForTesting(claudeSnapshot, provider: .claude)

        let highest = store.providerWithHighestUsage()
        #expect(highest?.provider == .claude)
        #expect(highest?.usedPercent == 80)
    }

    @Test
    func `automatic metric uses api lane when it is most constrained for cursor`() {
        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: "UsageStoreHighestUsageTests-cursor-api"))
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.setMenuBarMetricPreference(.automatic, for: .cursor)

        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }
        if let cursorMeta = registry.metadata[.cursor] {
            settings.setProviderEnabled(provider: .cursor, metadata: cursorMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)

        let codexSnapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 50, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        let cursorSnapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 95, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            updatedAt: Date())

        store._setSnapshotForTesting(codexSnapshot, provider: .codex)
        store._setSnapshotForTesting(cursorSnapshot, provider: .cursor)

        let highest = store.providerWithHighestUsage()
        #expect(highest?.provider == .cursor)
        #expect(highest?.usedPercent == 95)
    }

    @Test
    func `automatic metric excludes cursor when all opus lanes are exhausted`() {
        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: "UsageStoreHighestUsageTests-cursor-all-100"))
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.setMenuBarMetricPreference(.automatic, for: .cursor)

        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }
        if let cursorMeta = registry.metadata[.cursor] {
            settings.setProviderEnabled(provider: .cursor, metadata: cursorMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)

        let codexSnapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 80, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        let cursorSnapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            tertiary: RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            updatedAt: Date())

        store._setSnapshotForTesting(codexSnapshot, provider: .codex)
        store._setSnapshotForTesting(cursorSnapshot, provider: .cursor)

        let highest = store.providerWithHighestUsage()
        #expect(highest?.provider == .codex)
        #expect(highest?.usedPercent == 80)
    }

    @Test
    func `cursor highest usage uses migrated tertiary api preference as secondary`() throws {
        let suite = "UsageStoreHighestUsageTests-cursor-migrated-api"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(
            [UsageProvider.cursor.rawValue: MenuBarMetricPreference.tertiary.rawValue],
            forKey: "menuBarMetricPreferences")
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite))
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false

        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }
        if let cursorMeta = registry.metadata[.cursor] {
            settings.setProviderEnabled(provider: .cursor, metadata: cursorMeta, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)

        let codexSnapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 40, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        let cursorSnapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 60, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            updatedAt: Date())

        store._setSnapshotForTesting(codexSnapshot, provider: .codex)
        store._setSnapshotForTesting(cursorSnapshot, provider: .cursor)

        let highest = store.providerWithHighestUsage()
        #expect(highest?.provider == .cursor)
        #expect(highest?.usedPercent == 60)
    }
}
