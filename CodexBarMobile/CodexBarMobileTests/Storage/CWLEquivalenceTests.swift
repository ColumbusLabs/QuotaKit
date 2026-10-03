import CodexBarSync
import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

/// T7 (research doc 024 Round 5 / P4a) — the CWL ledger path and the existing
/// blob path must produce numerically equivalent `CostDashboardInsights` for
/// the same input. Builds a snapshot, runs the blob `init(snapshot:)`, then
/// feeds the same data through the writer → `aggregate` → `fromLedger` and
/// compares totals / per-provider cost / daily series / model+service mix.
///
/// The fixture pins `last30DaysCostUSD = nil` so the blob path also reduces
/// from `daily[]` (matching how the ledger sums daily rows), and uses a
/// 365-day aggregate window so every fixture day is in range regardless of
/// timezone edges.
@Suite("CWL Equivalence — ledger path == blob path (T7)")
@MainActor
struct CWLEquivalenceTests {
    private static let tolerance = 0.001

    private func makeTempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CodexBarTests-CWLEquiv-\(UUID().uuidString)",
                isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Store.sqlite")
    }

    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Recent dayKey, `daysAgo` before now (UTC). Within any reasonable window.
    private func dayKey(daysAgo: Int) -> String {
        let d = Date().addingTimeInterval(-TimeInterval(daysAgo * 86400))
        return Self.utcFormatter.string(from: d)
    }

    private func provider(
        id: String,
        name: String,
        modelLabel: String,
        dailyCosts: [(daysAgo: Int, cost: Double, tokens: Int)],
        lastUpdated: Date) -> ProviderUsageSnapshot
    {
        let daily = dailyCosts.map { entry in
            SyncDailyPoint(
                dayKey: self.dayKey(daysAgo: entry.daysAgo),
                costUSD: entry.cost,
                totalTokens: entry.tokens,
                modelBreakdowns: [
                    SyncCostBreakdown(
                        label: modelLabel,
                        costUSD: entry.cost,
                        totalTokens: entry.tokens),
                ],
                serviceBreakdowns: [],
                isEstimated: false)
        }
        return ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "Pro",
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: nil, // force blob to reduce from daily[]
                last30DaysTokens: nil,
                daily: daily,
                isEstimated: false))
    }

    @Test
    func `Ledger insights numerically match blob insights for the same data`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let codex = self.provider(
            id: "codex", name: "Codex", modelLabel: "gpt-5",
            dailyCosts: [(0, 1.0, 100), (1, 2.0, 200), (2, 3.0, 300)],
            lastUpdated: now)
        let claude = self.provider(
            id: "claude", name: "Claude", modelLabel: "claude-opus-4-7",
            dailyCosts: [(0, 0.5, 50), (1, 1.5, 150)],
            lastUpdated: now)
        let snapshot = SyncedUsageSnapshot(
            providers: [codex, claude],
            syncTimestamp: now,
            deviceName: "Test Mac",
            deviceID: "test-device")

        // Blob path.
        let blob = CostDashboardInsights(snapshot: snapshot)

        // Ledger path: write → aggregate → fromLedger.
        for provider in snapshot.providers {
            try CostLedgerService.upsertFromSnapshot(
                provider, deviceID: "test-device", in: context)
        }
        try context.save()
        let aggregation = try CostLedgerService.aggregate(windowDays: 365, in: context)
        let ledger = CostDashboardInsights.fromLedger(
            aggregation: aggregation, snapshot: snapshot)

        // --- Totals ---
        #expect(abs(blob.total30DayCost - ledger.total30DayCost) < Self.tolerance)
        #expect(blob.total30DayTokens == ledger.total30DayTokens)
        #expect(blob.activeDayCount == ledger.activeDayCount)

        // --- Provider rows (per provider thirtyDayCost / tokens) ---
        #expect(blob.providerRows.count == ledger.providerRows.count)
        let blobByProvider = Dictionary(
            grouping: blob.providerRows, by: { $0.provider.providerID })
        let ledgerByProvider = Dictionary(
            grouping: ledger.providerRows, by: { $0.provider.providerID })
        for (id, blobRows) in blobByProvider {
            let blobCost = blobRows.reduce(0) { $0 + $1.thirtyDayCost }
            let ledgerCost = (ledgerByProvider[id] ?? []).reduce(0) { $0 + $1.thirtyDayCost }
            #expect(abs(blobCost - ledgerCost) < Self.tolerance, "provider \(id) cost mismatch")
        }

        // --- Daily series (dayKey → costUSD) ---
        let blobDaily = Dictionary(
            uniqueKeysWithValues: blob.dailyPoints.map { ($0.dayKey, $0.costUSD) })
        let ledgerDaily = Dictionary(
            uniqueKeysWithValues: ledger.dailyPoints.map { ($0.dayKey, $0.costUSD) })
        #expect(blobDaily.keys.sorted() == ledgerDaily.keys.sorted())
        for (day, cost) in blobDaily {
            #expect(abs(cost - (ledgerDaily[day] ?? -1)) < Self.tolerance, "day \(day) cost mismatch")
        }

        // --- Model mix (label → amount) ---
        let blobModels = Dictionary(
            uniqueKeysWithValues: blob.modelRows.map { ($0.label, $0.amountUSD) })
        let ledgerModels = Dictionary(
            uniqueKeysWithValues: ledger.modelRows.map { ($0.label, $0.amountUSD) })
        #expect(blobModels.keys.sorted() == ledgerModels.keys.sorted())
        for (label, amount) in blobModels {
            #expect(abs(amount - (ledgerModels[label] ?? -1)) < Self.tolerance, "model \(label) mismatch")
        }

        let blobModelTokens = Dictionary(
            uniqueKeysWithValues: blob.modelRows.map { ($0.label, $0.totalTokens) })
        let ledgerModelTokens = Dictionary(
            uniqueKeysWithValues: ledger.modelRows.map { ($0.label, $0.totalTokens) })
        #expect(blobModelTokens == ledgerModelTokens)
    }

    @Test
    func `CWL ON: Overview window follows the selected window, not max provider historyDays`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let codex = self.provider(
            id: "codex", name: "Codex", modelLabel: "gpt-5",
            dailyCosts: [(0, 1.0, 100), (1, 2.0, 200)],
            lastUpdated: now)
        let snapshot = SyncedUsageSnapshot(
            providers: [codex], syncTimestamp: now,
            deviceName: "Test Mac", deviceID: "test-device")
        try CostLedgerService.upsertFromSnapshot(codex, deviceID: "test-device", in: context)
        try context.save()

        // Each selected CWL window must drive the Overview "N Days" headline.
        for window in [7, 30, 90, 365] {
            let agg = try CostLedgerService.aggregate(windowDays: window, in: context)
            let insights = CostDashboardInsights.fromLedger(aggregation: agg, snapshot: snapshot)
            #expect(insights.cwlWindowDays == window)
            #expect(insights.historyDays == window, "CWL window \(window) must drive the headline")
        }

        // Blob path carries no override → headline falls back to provider historyDays.
        #expect(CostDashboardInsights(snapshot: snapshot).cwlWindowDays == nil)
    }

    @Test
    func `CWL includes fresh session-only today data before a ledger row exists`() {
        let now = Date()
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "API",
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 12.34,
                sessionTokens: 4321,
                last30DaysCostUSD: 12.34,
                last30DaysTokens: 4321,
                daily: [],
                costUpdatedAt: now,
                totalCostUpdatedAt: now))
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Test Mac",
            deviceID: "test-device")
        let emptyLedger = CostLedgerAggregation(
            windowDays: 30,
            totalCostUSD: 0,
            totalTokens: 0,
            activeDayCount: 0,
            providerRollups: [:],
            dailyPoints: [],
            modelMix: [],
            serviceMix: [])

        let insights = CostDashboardInsights.fromLedger(
            aggregation: emptyLedger,
            snapshot: snapshot)

        #expect(insights.providerRows.count == 1)
        #expect(insights.providerRows[0].today.source == .session)
        #expect(insights.totalTodayCost == 12.34)
        #expect(insights.todayReportingProviderCount == 1)
        #expect(insights.hasDisplayData)
    }

    @Test
    func `Blob and ledger Today freshness follow the verified day timestamp`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))
        let now = Date()
        let verifiedAt = now.addingTimeInterval(-2 * 60 * 60)
        let dayKey = CostDashboardInsights.todayDayKey(now: now)
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "API",
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 4,
                sessionTokens: 400,
                last30DaysCostUSD: 4,
                last30DaysTokens: 400,
                daily: [SyncDailyPoint(
                    dayKey: dayKey,
                    costUSD: 4,
                    totalTokens: 400,
                    dayEvidence: SyncDayEvidence(
                        sourceKind: "codexLocalLedger",
                        scopeID: "scope-a",
                        lineageID: "store-a",
                        revision: 2,
                        verifiedAt: verifiedAt))],
                costUpdatedAt: now,
                totalCostUpdatedAt: now))
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Test Mac",
            deviceID: "proof-device")
        let blobInsights = CostDashboardInsights(snapshot: snapshot)

        try CostLedgerService.upsertFromSnapshot(provider, deviceID: "proof-device", in: context)
        let aggregation = try CostLedgerService.aggregate(
            windowDays: 365,
            in: context,
            asOf: now)
        let ledgerInsights = CostDashboardInsights.fromLedger(
            aggregation: aggregation,
            snapshot: snapshot)

        #expect(blobInsights.providerRows.first?.today.updatedAt == verifiedAt)
        #expect(ledgerInsights.providerRows.first?.today.updatedAt == verifiedAt)
        #expect(blobInsights.providerRows.first?.today.isStale == true)
        #expect(ledgerInsights.providerRows.first?.today.isStale == true)
    }

    @Test
    func `Equivalence holds with multi-account providers (two Codex accounts)`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let now = Date(timeIntervalSince1970: 1_700_000_000)

        func codexAccount(_ email: String, cost: Double) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil, secondary: nil,
                accountEmail: email,
                loginMethod: "Pro", statusMessage: nil, isError: false,
                lastUpdated: now,
                costSummary: SyncCostSummary(
                    sessionCostUSD: nil, sessionTokens: nil,
                    last30DaysCostUSD: nil, last30DaysTokens: nil,
                    daily: [SyncDailyPoint(
                        dayKey: self.dayKey(daysAgo: 0),
                        costUSD: cost, totalTokens: Int(cost * 100),
                        modelBreakdowns: [], serviceBreakdowns: [], isEstimated: false)],
                    isEstimated: false))
        }

        let snapshot = SyncedUsageSnapshot(
            providers: [
                codexAccount("alice@codex.test", cost: 1.0),
                codexAccount("bob@codex.test", cost: 2.0),
            ],
            syncTimestamp: now,
            deviceName: "Test Mac",
            deviceID: "test-device")

        let blob = CostDashboardInsights(snapshot: snapshot)
        for provider in snapshot.providers {
            try CostLedgerService.upsertFromSnapshot(
                provider, deviceID: "test-device", in: context)
        }
        try context.save()
        let aggregation = try CostLedgerService.aggregate(windowDays: 365, in: context)
        let ledger = CostDashboardInsights.fromLedger(
            aggregation: aggregation, snapshot: snapshot)

        // Both paths keep the two accounts as separate rows (the whole point
        // of the Round 4 account-aware key).
        #expect(blob.providerRows.count == 2)
        #expect(ledger.providerRows.count == 2)
        #expect(abs(blob.total30DayCost - ledger.total30DayCost) < Self.tolerance)
        #expect(abs(ledger.total30DayCost - 3.0) < Self.tolerance)
    }

    @Test
    func `Today stays delayed when a live local contributor has no current-day proof`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))
        let now = Date()
        let todayKey = CostDashboardInsights.todayDayKey(now: now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
            .addingTimeInterval(-24 * 60 * 60)
        let yesterdayKey = SyncCostSummary.iso8601DayKey(for: yesterday)
        let verifiedAt = now.addingTimeInterval(-10 * 60)

        func point(dayKey: String, cost: Double, revision: Int64, device: String) -> SyncDailyPoint {
            SyncDailyPoint(
                dayKey: dayKey,
                costUSD: cost,
                totalTokens: Int(cost * 1000),
                dayEvidence: SyncDayEvidence(
                    sourceKind: "codexLocalLedger",
                    scopeID: "scope-a",
                    lineageID: "store-\(device)",
                    revision: revision,
                    verifiedAt: verifiedAt))
        }
        func deviceSnapshot(deviceID: String, days: [SyncDailyPoint]) -> SyncedUsageSnapshot {
            let dailyTotal = days.reduce(0) { $0 + $1.costUSD }
            let provider = ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: "Pro",
                statusMessage: nil,
                isError: false,
                lastUpdated: now,
                costSummary: SyncCostSummary(
                    sessionCostUSD: nil,
                    sessionTokens: nil,
                    last30DaysCostUSD: dailyTotal,
                    last30DaysTokens: days.reduce(0) { $0 + $1.totalTokens },
                    daily: days,
                    costUpdatedAt: now,
                    totalCostUpdatedAt: now,
                    sourceRevisions: ["codex-local-ledger": now]))
            return SyncedUsageSnapshot(
                providers: [provider],
                syncTimestamp: now,
                deviceName: deviceID,
                deviceID: deviceID)
        }

        let firstDevice = deviceSnapshot(
            deviceID: "dev-A",
            days: [point(dayKey: todayKey, cost: 1.25, revision: 10, device: "A")])
        let secondDevice = deviceSnapshot(
            deviceID: "dev-B",
            days: [point(dayKey: yesterdayKey, cost: 2.50, revision: 20, device: "B")])
        let merged = try #require(CloudSyncReader.mergeSnapshots([firstDevice, secondDevice]))
        let mergedCost = try #require(merged.providers.first?.costSummary)
        let blob = CostDashboardInsights(snapshot: merged)
        let blobToday = try #require(blob.providerRows.first?.today)
        let providerDetailToday = mergedCost.todayTotals(
            now: now,
            providerLastUpdated: merged.providers.first?.lastUpdated)
        #expect(mergedCost.daily.first(where: { $0.dayKey == todayKey })?.dayEvidence == nil)
        #expect(blobToday.costUSD == 1.25)
        #expect(blobToday.updatedAt == nil)
        #expect(blobToday.isStale)
        #expect(providerDetailToday.costUSD == blobToday.costUSD)
        #expect(providerDetailToday.updatedAt == nil)
        #expect(providerDetailToday.isStale)

        for device in [firstDevice, secondDevice] {
            let deviceID = try #require(device.deviceID)
            for provider in device.providers {
                try CostLedgerService.upsertFromSnapshot(provider, deviceID: deviceID, in: context)
            }
        }
        let expectedContributors = CostLedgerService.expectedLocalContributorDeviceIDsByProviderKey(
            from: [firstDevice, secondDevice])
        let aggregation = try CostLedgerService.aggregate(
            windowDays: 7,
            expectedLocalContributorDeviceIDsByProviderKey: expectedContributors,
            in: context,
            asOf: now)
        let ledger = CostDashboardInsights.fromLedger(aggregation: aggregation, snapshot: merged)
        let ledgerToday = try #require(ledger.providerRows.first?.today)
        #expect(ledgerToday.costUSD == blobToday.costUSD)
        #expect(ledgerToday.updatedAt == nil)
        #expect(ledgerToday.isStale)
        #expect(aggregation.providerRollups["codex|_"]?.incompleteDayEvidenceDayKeys.contains(todayKey) == true)

        let changedProofDevice = deviceSnapshot(
            deviceID: "dev-A",
            days: [point(dayKey: todayKey, cost: 1.25, revision: 11, device: "A")])
        let changedMerge = try #require(CloudSyncReader.mergeSnapshots([changedProofDevice, secondDevice]))
        let changedCost = try #require(changedMerge.providers.first?.costSummary)
        #expect(
            mergedCost.mobileRevisionKey(providerLastUpdated: now)
                != changedCost.mobileRevisionKey(providerLastUpdated: now),
            "The merged cache identity must retain each device's accepted day revision.")
    }

    @Test
    func `All-legacy multi-Mac Today retains summary freshness fallback`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))
        let now = Date()
        let todayKey = CostDashboardInsights.todayDayKey(now: now)

        func deviceSnapshot(deviceID: String, cost: Double) -> SyncedUsageSnapshot {
            let provider = ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: "Pro",
                statusMessage: nil,
                isError: false,
                lastUpdated: now,
                costSummary: SyncCostSummary(
                    sessionCostUSD: nil,
                    sessionTokens: nil,
                    last30DaysCostUSD: cost,
                    last30DaysTokens: 100,
                    daily: [SyncDailyPoint(
                        dayKey: todayKey,
                        costUSD: cost,
                        totalTokens: 100)],
                    costUpdatedAt: now,
                    totalCostUpdatedAt: now))
            return SyncedUsageSnapshot(
                providers: [provider],
                syncTimestamp: now,
                deviceName: deviceID,
                deviceID: deviceID)
        }

        let firstDevice = deviceSnapshot(deviceID: "dev-A", cost: 1.25)
        let secondDevice = deviceSnapshot(deviceID: "dev-B", cost: 2.50)
        let merged = try #require(CloudSyncReader.mergeSnapshots([firstDevice, secondDevice]))
        let mergedCost = try #require(merged.providers.first?.costSummary)
        let blob = CostDashboardInsights(snapshot: merged)
        let blobToday = try #require(blob.providerRows.first?.today)
        #expect(blobToday.costUSD == 3.75)
        #expect(blobToday.updatedAt == now)
        #expect(!blobToday.isStale)

        for device in [firstDevice, secondDevice] {
            for provider in device.providers {
                try CostLedgerService.upsertFromSnapshot(provider, deviceID: #require(device.deviceID), in: context)
            }
        }
        let expectedContributors = CostLedgerService.expectedLocalContributorDeviceIDsByProviderKey(
            from: [firstDevice, secondDevice])
        let aggregation = try CostLedgerService.aggregate(
            windowDays: 7,
            expectedLocalContributorDeviceIDsByProviderKey: expectedContributors,
            in: context,
            asOf: now)
        let ledger = CostDashboardInsights.fromLedger(aggregation: aggregation, snapshot: merged)
        let ledgerToday = try #require(ledger.providerRows.first?.today)
        #expect(ledgerToday.costUSD == blobToday.costUSD)
        #expect(ledgerToday.updatedAt == now)
        #expect(!ledgerToday.isStale)
        #expect(aggregation.providerRollups["codex|_"]?.incompleteDayEvidenceDayKeys.isEmpty == true)

        let detailToday = mergedCost.todayTotals(
            now: now,
            providerLastUpdated: merged.providers.first?.lastUpdated)
        #expect(detailToday.updatedAt == now)
        #expect(!detailToday.isStale)
    }
}
