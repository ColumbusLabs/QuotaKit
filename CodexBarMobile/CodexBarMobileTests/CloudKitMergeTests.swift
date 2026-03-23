import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Multi-device Merge Tests")
struct CloudKitMergeTests {
    private let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let newerDate = Date(timeIntervalSince1970: 1_700_100_000)

    private func makeProvider(
        id: String,
        name: String,
        email: String? = nil,
        lastUpdated: Date,
        usedPercent: Double = 50.0
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: SyncRateWindow(
                usedPercent: usedPercent,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: email,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated)
    }

    private func makeSnapshot(
        deviceName: String,
        deviceID: String,
        providers: [ProviderUsageSnapshot],
        timestamp: Date? = nil
    ) -> SyncedUsageSnapshot {
        SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: timestamp ?? providers.map(\.lastUpdated).max() ?? Date(),
            deviceName: deviceName,
            deviceID: deviceID)
    }

    // MARK: - Single device (degenerate case)

    @Test("Single device returns its data unchanged")
    func singleDevice() throws {
        let provider = makeProvider(id: "claude", name: "Claude", email: "a@b.com", lastUpdated: olderDate)
        let snapshot = makeSnapshot(deviceName: "MacBook Air", deviceID: "uuid-1", providers: [provider])

        let merged = try #require(CloudSyncReader.mergeSnapshots([snapshot]))
        #expect(merged.providers.count == 1)
        #expect(merged.providers[0].providerID == "claude")
        #expect(merged.providers[0].accountEmail == "a@b.com")
        #expect(merged.deviceName == "MacBook Air")
    }

    // MARK: - Same provider, same account → take newest

    @Test("Same provider + same account deduplicates to most recent")
    func sameProviderSameAccount() throws {
        let oldProvider = makeProvider(
            id: "claude", name: "Claude", email: "user@a.com",
            lastUpdated: olderDate, usedPercent: 30.0)
        let newProvider = makeProvider(
            id: "claude", name: "Claude", email: "user@a.com",
            lastUpdated: newerDate, usedPercent: 80.0)

        let macA = makeSnapshot(deviceName: "MacBook Air", deviceID: "uuid-a", providers: [oldProvider])
        let macB = makeSnapshot(deviceName: "Mac Mini", deviceID: "uuid-b", providers: [newProvider])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 1)
        #expect(merged.providers[0].primary?.usedPercent == 80.0) // Newer data wins
    }

    // MARK: - Same provider, different accounts → keep both

    @Test("Same provider + different accounts are preserved as separate entries")
    func sameProviderDifferentAccounts() throws {
        let accountA = makeProvider(
            id: "claude", name: "Claude", email: "personal@a.com", lastUpdated: olderDate)
        let accountB = makeProvider(
            id: "claude", name: "Claude", email: "work@b.com", lastUpdated: newerDate)

        let macA = makeSnapshot(deviceName: "MacBook Air", deviceID: "uuid-a", providers: [accountA])
        let macB = makeSnapshot(deviceName: "Mac Mini", deviceID: "uuid-b", providers: [accountB])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 2)

        let emails = Set(merged.providers.compactMap(\.accountEmail))
        #expect(emails == ["personal@a.com", "work@b.com"])
    }

    // MARK: - Different providers from different devices

    @Test("Different providers from different Macs are combined")
    func differentProviders() throws {
        let claude = makeProvider(id: "claude", name: "Claude", lastUpdated: olderDate)
        let cursor = makeProvider(id: "cursor", name: "Cursor", lastUpdated: olderDate)
        let codex = makeProvider(id: "codex", name: "Codex", lastUpdated: newerDate)

        let macA = makeSnapshot(deviceName: "MacBook Air", deviceID: "uuid-a", providers: [claude, cursor])
        let macB = makeSnapshot(deviceName: "Mac Mini", deviceID: "uuid-b", providers: [codex])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 3)

        let ids = Set(merged.providers.map(\.providerID))
        #expect(ids == ["claude", "cursor", "codex"])
    }

    // MARK: - Combined device name

    @Test("Merged snapshot combines device names")
    func combinedDeviceName() throws {
        let macA = makeSnapshot(
            deviceName: "MacBook Air", deviceID: "uuid-a",
            providers: [makeProvider(id: "claude", name: "Claude", lastUpdated: olderDate)])
        let macB = makeSnapshot(
            deviceName: "Mac Mini", deviceID: "uuid-b",
            providers: [makeProvider(id: "codex", name: "Codex", lastUpdated: newerDate)])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.deviceName.contains("MacBook Air"))
        #expect(merged.deviceName.contains("Mac Mini"))
    }

    // MARK: - Empty input

    @Test("Empty snapshot list returns nil")
    func emptyInput() {
        let result = CloudSyncReader.mergeSnapshots([])
        #expect(result == nil)
    }

    // MARK: - Provider with nil email vs non-nil email

    @Test("Provider with nil email is treated as separate from one with email")
    func nilVsNonNilEmail() throws {
        let noEmail = makeProvider(id: "claude", name: "Claude", email: nil, lastUpdated: olderDate)
        let withEmail = makeProvider(id: "claude", name: "Claude", email: "a@b.com", lastUpdated: newerDate)

        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [noEmail])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [withEmail])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 2) // Different keys: "claude|" vs "claude|a@b.com"
    }

    // MARK: - Providers sorted by name

    @Test("Merged providers are sorted alphabetically by name")
    func sortedByName() throws {
        let zProvider = makeProvider(id: "z-tool", name: "Z Tool", lastUpdated: olderDate)
        let aProvider = makeProvider(id: "a-tool", name: "A Tool", lastUpdated: newerDate)

        let snapshot = makeSnapshot(
            deviceName: "Mac", deviceID: "uuid-1",
            providers: [zProvider, aProvider])

        let merged = try #require(CloudSyncReader.mergeSnapshots([snapshot]))
        #expect(merged.providers[0].providerName == "A Tool")
        #expect(merged.providers[1].providerName == "Z Tool")
    }

    // MARK: - Uses latest sync timestamp

    @Test("Merged snapshot uses the most recent syncTimestamp across devices")
    func latestTimestamp() throws {
        let macA = makeSnapshot(
            deviceName: "Mac A", deviceID: "uuid-a",
            providers: [makeProvider(id: "claude", name: "Claude", lastUpdated: olderDate)],
            timestamp: olderDate)
        let macB = makeSnapshot(
            deviceName: "Mac B", deviceID: "uuid-b",
            providers: [makeProvider(id: "codex", name: "Codex", lastUpdated: newerDate)],
            timestamp: newerDate)

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.syncTimestamp == newerDate)
    }

    // MARK: - Cost aggregation for local-cost providers

    private func makeProviderWithCost(
        id: String,
        name: String,
        email: String? = nil,
        lastUpdated: Date,
        sessionCost: Double,
        daily: [SyncDailyPoint]
    ) -> ProviderUsageSnapshot {
        let totalCost = daily.reduce(0) { $0 + $1.costUSD }
        let totalTokens = daily.reduce(0) { $0 + $1.totalTokens }
        return ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: email,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated,
            costSummary: SyncCostSummary(
                sessionCostUSD: sessionCost,
                sessionTokens: nil,
                last30DaysCostUSD: totalCost,
                last30DaysTokens: totalTokens,
                daily: daily))
    }

    @Test("Claude cost data is summed across devices (local-cost provider)")
    func claudeCostSummed() throws {
        let dailyA = [
            SyncDailyPoint(dayKey: "2024-01-15", costUSD: 1.50, totalTokens: 10000),
            SyncDailyPoint(dayKey: "2024-01-16", costUSD: 2.00, totalTokens: 15000),
        ]
        let dailyB = [
            SyncDailyPoint(dayKey: "2024-01-15", costUSD: 0.80, totalTokens: 5000),
            SyncDailyPoint(dayKey: "2024-01-17", costUSD: 3.00, totalTokens: 20000),
        ]

        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            makeProviderWithCost(id: "claude", name: "Claude", email: "user@a.com",
                                 lastUpdated: olderDate, sessionCost: 0.50, daily: dailyA),
        ])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            makeProviderWithCost(id: "claude", name: "Claude", email: "user@a.com",
                                 lastUpdated: newerDate, sessionCost: 0.30, daily: dailyB),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 1)

        let cost = try #require(merged.providers[0].costSummary)

        // Session costs should be summed
        #expect(cost.sessionCostUSD == 0.80) // 0.50 + 0.30

        // Daily points: Jan 15 summed, Jan 16 from A only, Jan 17 from B only
        #expect(cost.daily.count == 3)

        let jan15 = try #require(cost.daily.first { $0.dayKey == "2024-01-15" })
        #expect(jan15.costUSD == 2.30) // 1.50 + 0.80
        #expect(jan15.totalTokens == 15000) // 10000 + 5000

        let jan16 = try #require(cost.daily.first { $0.dayKey == "2024-01-16" })
        #expect(jan16.costUSD == 2.00) // Only from Mac A

        let jan17 = try #require(cost.daily.first { $0.dayKey == "2024-01-17" })
        #expect(jan17.costUSD == 3.00) // Only from Mac B

        // 30-day total recalculated from merged daily
        #expect(cost.last30DaysCostUSD == 7.30) // 2.30 + 2.00 + 3.00
    }

    @Test("Account-level provider cost is NOT summed (takes newest)")
    func accountCostDeduped() throws {
        let daily = [SyncDailyPoint(dayKey: "2024-01-15", costUSD: 5.00, totalTokens: 50000)]

        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            makeProviderWithCost(id: "augment", name: "Augment", email: "user@a.com",
                                 lastUpdated: olderDate, sessionCost: 1.00, daily: daily),
        ])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            makeProviderWithCost(id: "augment", name: "Augment", email: "user@a.com",
                                 lastUpdated: newerDate, sessionCost: 2.00, daily: daily),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let cost = try #require(merged.providers[0].costSummary)

        // Should NOT be summed — account-level data, take newest
        #expect(cost.sessionCostUSD == 2.00) // From Mac B (newer), not 3.00
        #expect(cost.last30DaysCostUSD == 5.00) // Not doubled
    }

    @Test("Model breakdowns are merged by label with summed costs")
    func modelBreakdownsMerged() throws {
        let dailyA = [SyncDailyPoint(
            dayKey: "2024-01-15", costUSD: 2.00, totalTokens: 10000,
            modelBreakdowns: [
                SyncCostBreakdown(label: "claude-4-sonnet", costUSD: 1.50),
                SyncCostBreakdown(label: "claude-4-opus", costUSD: 0.50),
            ])]
        let dailyB = [SyncDailyPoint(
            dayKey: "2024-01-15", costUSD: 1.00, totalTokens: 5000,
            modelBreakdowns: [
                SyncCostBreakdown(label: "claude-4-sonnet", costUSD: 0.80),
                SyncCostBreakdown(label: "claude-4-haiku", costUSD: 0.20),
            ])]

        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            makeProviderWithCost(id: "claude", name: "Claude", lastUpdated: olderDate,
                                 sessionCost: 0, daily: dailyA),
        ])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            makeProviderWithCost(id: "claude", name: "Claude", lastUpdated: newerDate,
                                 sessionCost: 0, daily: dailyB),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let jan15 = try #require(merged.providers[0].costSummary?.daily.first)

        #expect(jan15.modelBreakdowns.count == 3)

        let sonnet = try #require(jan15.modelBreakdowns.first { $0.label == "claude-4-sonnet" })
        #expect(sonnet.costUSD == 2.30) // 1.50 + 0.80

        let opus = try #require(jan15.modelBreakdowns.first { $0.label == "claude-4-opus" })
        #expect(opus.costUSD == 0.50) // Only from Mac A

        let haiku = try #require(jan15.modelBreakdowns.first { $0.label == "claude-4-haiku" })
        #expect(haiku.costUSD == 0.20) // Only from Mac B
    }

    @Test("Provider without cost data is unaffected by merge")
    func noCostDataUnaffected() throws {
        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            makeProvider(id: "copilot", name: "Copilot", email: "user@a.com",
                         lastUpdated: olderDate, usedPercent: 40),
        ])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            makeProvider(id: "copilot", name: "Copilot", email: "user@a.com",
                         lastUpdated: newerDate, usedPercent: 60),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 1)
        #expect(merged.providers[0].primary?.usedPercent == 60) // Newer wins
        #expect(merged.providers[0].costSummary == nil) // No cost data
    }
}
