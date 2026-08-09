import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct UsageStoreWidgetSnapshotTests {
    @Test
    func `widget snapshot preserves raw Codex windows for timeline projection`() async throws {
        let store = try self.makeStore(suite: "UsageStoreWidgetSnapshotTests-codex")
        let now = Date()
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 1,
                    windowMinutes: 300,
                    resetsAt: now.addingTimeInterval(1800),
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 100,
                    windowMinutes: 10080,
                    resetsAt: now.addingTimeInterval(3600),
                    resetDescription: nil),
                updatedAt: now),
            provider: .codex)

        let snapshot = try #require(await self.persistedSnapshot(from: store, reason: "codex"))
        let entry = try #require(snapshot.entries.first { $0.provider == .codex })
        #expect(entry.usageRows?.map(\.id) == ["session", "weekly"])
        #expect(entry.usageRows?.compactMap(\.percentLeft) == [99, 0])
        #expect(entry.usageRows?.first?.window?.usedPercent == 1)
        #expect(entry.usageRows?.last?.window?.resetsAt == now.addingTimeInterval(3600))
    }

    @Test
    func `widget snapshot includes Claude scoped weekly rows`() async throws {
        let store = try self.makeStore(suite: "UsageStoreWidgetSnapshotTests-claude")
        let now = Date()
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: RateWindow(usedPercent: 40, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
                extraRateWindows: [
                    NamedRateWindow(
                        id: "claude-weekly-scoped-fable",
                        title: "Fable only",
                        window: RateWindow(
                            usedPercent: 68,
                            windowMinutes: 10080,
                            resetsAt: now.addingTimeInterval(3600),
                            resetDescription: nil)),
                    NamedRateWindow(
                        id: "claude-daily-routines",
                        title: "Daily Routines",
                        window: RateWindow(
                            usedPercent: 12,
                            windowMinutes: 1440,
                            resetsAt: nil,
                            resetDescription: nil)),
                ],
                updatedAt: now),
            provider: .claude)

        let snapshot = try #require(await self.persistedSnapshot(from: store, reason: "claude"))
        let entry = try #require(snapshot.entries.first { $0.provider == .claude })
        #expect(entry.usageRows?.map(\.id) == ["primary", "secondary", "claude-weekly-scoped-fable"])
        #expect(entry.usageRows?.map(\.title) == ["Session", "Weekly", "Fable only"])
        #expect(entry.usageRows?.compactMap(\.percentLeft) == [75, 60, 32])
    }

    @Test
    func `widget snapshot labels Cursor request quota as Requests`() async throws {
        let store = try self.makeStore(suite: "UsageStoreWidgetSnapshotTests-cursor")
        try store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 40, windowMinutes: 43200, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                details: [ProviderDetailSection(rows: [
                    ProviderDetailSection.Row(label: "Request quota", value: "200 / 500"),
                ])],
                updatedAt: Date()),
            provider: .cursor)

        let snapshot = try #require(await self.persistedSnapshot(from: store, reason: "cursor"))
        let entry = try #require(snapshot.entries.first { $0.provider == .cursor })
        #expect(entry.usageRows?.map(\.id) == ["primary"])
        #expect(entry.usageRows?.map(\.title) == ["Requests"])
    }

    @Test
    func `widget snapshot includes Grok with its billing cadence label`() async throws {
        let store = try self.makeStore(suite: "UsageStoreWidgetSnapshotTests-grok")
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 35,
                    windowMinutes: 7 * 24 * 60,
                    resetsAt: Date().addingTimeInterval(4 * 24 * 60 * 60),
                    resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .grok)

        let snapshot = try #require(await self.persistedSnapshot(from: store, reason: "grok"))
        let entry = try #require(snapshot.entries.first { $0.provider == .grok })
        #expect(entry.usageRows?.map(\.id) == ["primary"])
        #expect(entry.usageRows?.map(\.title) == ["Weekly"])
        #expect(entry.usageRows?.compactMap(\.percentLeft) == [65])
    }

    private func makeStore(suite: String) throws -> UsageStore {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite))
        settings.statusChecksEnabled = false
        return UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
    }

    private func persistedSnapshot(from store: UsageStore, reason: String) async -> WidgetSnapshot? {
        var snapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { snapshots.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }
        store.persistWidgetSnapshot(reason: reason)
        await store.widgetSnapshotPersistTask?.value
        return snapshots.last
    }
}
