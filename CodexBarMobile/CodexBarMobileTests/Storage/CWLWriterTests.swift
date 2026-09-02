import CodexBarSync
import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

/// Round 2 / P2 of research doc 024. Exercises the writer half of the Cost
/// Window Ledger:
///
/// - **T2**: `upsertDayPoint` dedupes by composite key
///   `(deviceID, providerID, dayKey)` — same key written twice yields one row.
/// - **T3**: Dedup rule = newer `lastUpdated` wins; older or equal is skipped
///   (we already have at-least-as-fresh data for that day).
/// - Gate test: `CostLedgerService.isEnabled(userDefaults:)` reads the flag
///   correctly. The flag's wiring into `SwiftDataBridge.upsertProvider` is
///   covered by inspection — pollution of the shared `UserDefaults.standard`
///   in an integration test is deferred to P4 (where the UI exists to flip
///   the flag end-to-end).
/// - `upsertFromSnapshot` wrapper:iterates `daily[]` and writes one row per day.
@Suite("CWL Writer — upsert dedupe + lastUpdated dedup rule (T2 + T3)")
@MainActor
struct CWLWriterTests {
    private func makeTempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CodexBarTests-CWLWriter-\(UUID().uuidString)",
                isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Store.sqlite")
    }

    // MARK: - T2

    @Test
    func `T2: same (deviceID, providerID, dayKey) written twice → 1 row`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 1.0, totalTokens: 100, isEstimated: false,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)

        // Second write with a strictly newer lastUpdated and different costs.
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 2.5, totalTokens: 250, isEstimated: true,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t.addingTimeInterval(60), in: context)

        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 1, "Same composite key must dedupe to one row")
        let row = try #require(rows.first)
        #expect(row.compositeKey == "dev-A|codex|_|2026-05-28")
        #expect(row.costUSD == 2.5)
        #expect(row.totalTokens == 250)
        #expect(row.isEstimated == true)
        #expect(row.lastUpdated == t.addingTimeInterval(60))
    }

    @Test
    func `T2: different (providerID, dayKey) under same device → separate rows`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 1.0, totalTokens: 100, isEstimated: false,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "claude", dayKey: "2026-05-28",
            costUSD: 1.0, totalTokens: 100, isEstimated: false,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-27",
            costUSD: 1.0, totalTokens: 100, isEstimated: false,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-B", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 1.0, totalTokens: 100, isEstimated: false,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 4, "4 distinct composite keys must yield 4 rows")
    }

    @Test
    func `T2 (multi-account): two accounts, same providerID + dayKey → separate rows (no collide)`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        // Two Codex accounts, same device, same day — must NOT collide.
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", accountEmail: "alice@codex.test",
            dayKey: "2026-05-28", costUSD: 1.0, totalTokens: 100, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [], lastUpdated: t, in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", accountEmail: "bob@codex.test",
            dayKey: "2026-05-28", costUSD: 2.0, totalTokens: 200, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [], lastUpdated: t, in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 2, "Two accounts of the same provider must stay distinct")
        let byEmail = Dictionary(grouping: rows, by: { $0.accountEmail ?? "_" })
        #expect(byEmail["alice@codex.test"]?.first?.costUSD == 1.0)
        #expect(byEmail["bob@codex.test"]?.first?.costUSD == 2.0)
    }

    // MARK: - T3

    @Test
    func `T3: incoming with strictly newer lastUpdated → overwrites`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 1.0, totalTokens: 100, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 9.9, totalTokens: 9999, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t.addingTimeInterval(3600), in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.costUSD == 9.9, "Newer write must overwrite older")
        #expect(row.totalTokens == 9999)
        #expect(row.lastUpdated == t.addingTimeInterval(3600))
    }

    @Test
    func `T3: incoming with older lastUpdated → skipped (existing kept)`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 5.0, totalTokens: 500, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 0.1, totalTokens: 10, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t.addingTimeInterval(-3600), in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.costUSD == 5.0, "Older write must be rejected")
        #expect(row.lastUpdated == t, "Existing lastUpdated must be preserved")
    }

    @Test
    func `T3: incoming with equal lastUpdated → skipped (existing kept, no churn)`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 5.0, totalTokens: 500, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 7.7, totalTokens: 777, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.costUSD == 5.0, "Equal lastUpdated must skip (redundant write)")
    }

    // MARK: - Gate (`isEnabled`)

    @Test
    func `Gate: isEnabled returns false when flag absent on a fresh UserDefaults`() throws {
        let suite = "CWLTestSuite-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(CostLedgerService.isEnabled(userDefaults: defaults) == false)
    }

    @Test
    func `Gate: isEnabled returns true when flag set`() throws {
        let suite = "CWLTestSuite-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: MobileSettingsKeys.cwlEnabled)
        #expect(CostLedgerService.isEnabled(userDefaults: defaults) == true)

        defaults.set(false, forKey: MobileSettingsKeys.cwlEnabled)
        #expect(CostLedgerService.isEnabled(userDefaults: defaults) == false)
    }

    // MARK: - `upsertFromSnapshot` wrapper

    @Test
    func `upsertFromSnapshot: iterates daily[] and writes one row per day`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: t,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: 6.0,
                last30DaysTokens: 600,
                daily: [
                    SyncDailyPoint(
                        dayKey: "2026-05-26", costUSD: 1.0, totalTokens: 100,
                        modelBreakdowns: [], serviceBreakdowns: [], isEstimated: false),
                    SyncDailyPoint(
                        dayKey: "2026-05-27", costUSD: 2.0, totalTokens: 200,
                        modelBreakdowns: [], serviceBreakdowns: [], isEstimated: false),
                    SyncDailyPoint(
                        dayKey: "2026-05-28", costUSD: 3.0, totalTokens: 300,
                        modelBreakdowns: [], serviceBreakdowns: [], isEstimated: false),
                ],
                isEstimated: false))

        try CostLedgerService.upsertFromSnapshot(
            snapshot, deviceID: "dev-A", in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 3)
        let byDay = Dictionary(grouping: rows, by: \.dayKey)
        #expect(byDay["2026-05-26"]?.first?.costUSD == 1.0)
        #expect(byDay["2026-05-27"]?.first?.costUSD == 2.0)
        #expect(byDay["2026-05-28"]?.first?.costUSD == 3.0)
        // All days inherit the parent provider's lastUpdated.
        for row in rows {
            #expect(row.lastUpdated == t)
        }
    }

    @Test
    func `upsertFromSnapshot: newer cost freshness overwrites equal provider freshness`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let providerUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let costUpdatedAt = providerUpdatedAt.addingTimeInterval(60)
        let makeSnapshot: (Double, Date) -> ProviderUsageSnapshot = { cost, freshness in
            ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil, secondary: nil,
                accountEmail: nil, loginMethod: nil, statusMessage: nil,
                isError: false,
                lastUpdated: providerUpdatedAt,
                costSummary: SyncCostSummary(
                    sessionCostUSD: nil,
                    sessionTokens: nil,
                    last30DaysCostUSD: cost,
                    last30DaysTokens: 100,
                    daily: [SyncDailyPoint(
                        dayKey: "2026-05-28",
                        costUSD: cost,
                        totalTokens: 100)],
                    costUpdatedAt: freshness))
        }

        try CostLedgerService.upsertFromSnapshot(
            makeSnapshot(1, providerUpdatedAt), deviceID: "dev-A", in: context)
        try CostLedgerService.upsertFromSnapshot(
            makeSnapshot(2, costUpdatedAt), deviceID: "dev-A", in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.costUSD == 2)
        #expect(row.lastUpdated == costUpdatedAt)
    }

    @Test
    func `upsertFromSnapshot: newer total freshness is not hidden by unchanged payload revision`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))

        let providerUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let dashboardRevision = providerUpdatedAt.addingTimeInterval(120)
        let oldTotalRevision = providerUpdatedAt.addingTimeInterval(10)
        let newTotalRevision = providerUpdatedAt.addingTimeInterval(20)
        func snapshot(cost: Double, totalRevision: Date) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: providerUpdatedAt,
                costSummary: SyncCostSummary(
                    sessionCostUSD: cost,
                    sessionTokens: 100,
                    last30DaysCostUSD: cost,
                    last30DaysTokens: 100,
                    daily: [SyncDailyPoint(
                        dayKey: "2026-05-28",
                        costUSD: cost,
                        totalTokens: 100)],
                    costUpdatedAt: dashboardRevision,
                    totalCostUpdatedAt: totalRevision))
        }

        try CostLedgerService.upsertFromSnapshot(
            snapshot(cost: 1, totalRevision: oldTotalRevision),
            deviceID: "dev-A",
            in: context)
        try CostLedgerService.upsertFromSnapshot(
            snapshot(cost: 2, totalRevision: newTotalRevision),
            deviceID: "dev-A",
            in: context)
        try context.save()

        let row = try #require(context.fetch(FetchDescriptor<DailyCostPoint>()).first)
        #expect(row.costUSD == 2)
        #expect(row.lastUpdated == dashboardRevision)
        #expect(row.totalUpdatedAt == newTotalRevision)
    }

    @Test
    func `upsertFromSnapshot: newer dashboard source is not hidden by newer scanner maximum`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))

        let providerUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let scannerRevision = providerUpdatedAt.addingTimeInterval(120)
        let oldDashboardRevision = providerUpdatedAt.addingTimeInterval(10)
        let newDashboardRevision = providerUpdatedAt.addingTimeInterval(20)
        func snapshot(serviceCost: Double, dashboardRevision: Date) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: providerUpdatedAt,
                costSummary: SyncCostSummary(
                    sessionCostUSD: 5,
                    sessionTokens: 100,
                    last30DaysCostUSD: 5,
                    last30DaysTokens: 100,
                    daily: [SyncDailyPoint(
                        dayKey: "2026-05-28",
                        costUSD: 5,
                        totalTokens: 100,
                        serviceBreakdowns: [SyncCostBreakdown(
                            label: "Codex Run",
                            costUSD: serviceCost)])],
                    costUpdatedAt: scannerRevision,
                    totalCostUpdatedAt: scannerRevision,
                    sourceRevisions: [
                        "tokenScanner": scannerRevision,
                        "openAIDashboard": dashboardRevision,
                    ]))
        }

        try CostLedgerService.upsertFromSnapshot(
            snapshot(serviceCost: 1, dashboardRevision: oldDashboardRevision),
            deviceID: "dev-A",
            in: context)
        try CostLedgerService.upsertFromSnapshot(
            snapshot(serviceCost: 2, dashboardRevision: newDashboardRevision),
            deviceID: "dev-A",
            in: context)
        try context.save()

        let row = try #require(context.fetch(FetchDescriptor<DailyCostPoint>()).first)
        let data = try #require(row.serviceBreakdownsData)
        let breakdowns = try CloudSyncConstants.makeJSONDecoder().decode(
            [SyncCostBreakdown].self,
            from: data)
        #expect(breakdowns.first?.costUSD == 2)
        #expect(row.lastUpdated == scannerRevision)
        #expect(row.totalUpdatedAt == scannerRevision)
        #expect(row.sourceRevisionKey?.contains(
            "openAIDashboard:\(newDashboardRevision.timeIntervalSince1970)") == true)
    }

    @Test
    func `upsertFromSnapshot: removing dashboard source clears retained breakdowns`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))

        let providerUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let scannerRevision = providerUpdatedAt.addingTimeInterval(120)
        let dashboardRevision = providerUpdatedAt.addingTimeInterval(10)
        func snapshot(includeDashboard: Bool) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: providerUpdatedAt,
                costSummary: SyncCostSummary(
                    sessionCostUSD: 5,
                    sessionTokens: 100,
                    last30DaysCostUSD: 5,
                    last30DaysTokens: 100,
                    daily: [SyncDailyPoint(
                        dayKey: "2026-05-28",
                        costUSD: 5,
                        totalTokens: 100,
                        serviceBreakdowns: includeDashboard
                            ? [SyncCostBreakdown(label: "Codex Run", costUSD: 1)]
                            : [])],
                    costUpdatedAt: scannerRevision,
                    totalCostUpdatedAt: scannerRevision,
                    sourceRevisions: includeDashboard
                        ? [
                            "tokenScanner": scannerRevision,
                            "openAIDashboard": dashboardRevision,
                        ]
                        : ["tokenScanner": scannerRevision]))
        }

        try CostLedgerService.upsertFromSnapshot(
            snapshot(includeDashboard: true),
            deviceID: "dev-A",
            in: context)
        try CostLedgerService.upsertFromSnapshot(
            snapshot(includeDashboard: false),
            deviceID: "dev-A",
            in: context)
        try context.save()

        let row = try #require(context.fetch(FetchDescriptor<DailyCostPoint>()).first)
        #expect(row.serviceBreakdownsData == nil)
        #expect(row.sourceRevisionKey?.contains("openAIDashboard") == false)
    }

    @Test
    func `upsertFromSnapshot: partial history never overwrites established days`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))
        let establishedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let partialAt = establishedAt.addingTimeInterval(60)
        let secondPartialAt = partialAt.addingTimeInterval(60)

        func snapshot(
            cost: Double,
            days: [SyncDailyPoint],
            coverage: Bool,
            updatedAt: Date) -> ProviderUsageSnapshot
        {
            ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: updatedAt,
                costSummary: SyncCostSummary(
                    sessionCostUSD: cost,
                    sessionTokens: Int(cost * 100),
                    last30DaysCostUSD: cost,
                    last30DaysTokens: Int(cost * 100),
                    daily: days,
                    historyDays: 30,
                    historyCoverageIsEstablished: coverage,
                    costUpdatedAt: updatedAt,
                    totalCostUpdatedAt: updatedAt))
        }

        try CostLedgerService.upsertFromSnapshot(
            snapshot(
                cost: 130,
                days: [
                    SyncDailyPoint(dayKey: "2026-08-11", costUSD: 120, totalTokens: 12000),
                    SyncDailyPoint(dayKey: "2026-08-12", costUSD: 10, totalTokens: 1000),
                ],
                coverage: true,
                updatedAt: establishedAt),
            deviceID: "dev-A",
            in: context)
        try CostLedgerService.upsertFromSnapshot(
            snapshot(
                cost: 8,
                days: [SyncDailyPoint(
                    dayKey: "2026-08-12",
                    costUSD: 8,
                    totalTokens: 1400,
                    costIsKnown: false)],
                coverage: false,
                updatedAt: partialAt),
            deviceID: "dev-A",
            in: context)
        try CostLedgerService.upsertFromSnapshot(
            snapshot(
                cost: 3,
                days: [SyncDailyPoint(dayKey: "2026-08-12", costUSD: 3, totalTokens: 300)],
                coverage: false,
                updatedAt: secondPartialAt),
            deviceID: "dev-A",
            in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 2)
        let byDay = Dictionary(uniqueKeysWithValues: rows.map { ($0.dayKey, $0) })
        #expect(byDay["2026-08-11"]?.costUSD == 120)
        #expect(byDay["2026-08-12"]?.costUSD == 10)
        #expect(byDay["2026-08-12"]?.totalTokens == 1400)
        #expect(byDay["2026-08-12"]?.sourceRevisionKey?.contains("historyCoverage=established") == true)
        #expect(byDay["2026-08-12"]?.sourceRevisionKey?.contains("costKnown=unknown") == true)
        #expect(byDay.values.reduce(0) { $0 + $1.costUSD } == 130)
    }

    @Test
    func `upsertFromSnapshot: newer complete correction may reduce total`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))
        let establishedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let correctedAt = establishedAt.addingTimeInterval(60)

        func snapshot(cost: Double, updatedAt: Date) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: updatedAt,
                costSummary: SyncCostSummary(
                    sessionCostUSD: cost,
                    sessionTokens: Int(cost * 100),
                    last30DaysCostUSD: cost,
                    last30DaysTokens: Int(cost * 100),
                    daily: [SyncDailyPoint(
                        dayKey: "2026-08-12",
                        costUSD: cost,
                        totalTokens: Int(cost * 100))],
                    historyDays: 30,
                    historyCoverageIsEstablished: true,
                    costUpdatedAt: updatedAt,
                    totalCostUpdatedAt: updatedAt))
        }

        try CostLedgerService.upsertFromSnapshot(
            snapshot(cost: 130, updatedAt: establishedAt),
            deviceID: "dev-A",
            in: context)
        try CostLedgerService.upsertFromSnapshot(
            snapshot(cost: 8, updatedAt: correctedAt),
            deviceID: "dev-A",
            in: context)
        try context.save()

        let row = try #require(context.fetch(FetchDescriptor<DailyCostPoint>()).first)
        #expect(row.costUSD == 8)
        #expect(row.totalUpdatedAt == correctedAt)
    }

    @Test
    func `upsertFromSnapshot: newer complete history removes omitted days only inside its window`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let establishedAt = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 11, hour: 12)))
        let correctedAt = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 12, hour: 12)))

        func snapshot(
            days: [SyncDailyPoint],
            historyDays: Int,
            updatedAt: Date) -> ProviderUsageSnapshot
        {
            ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: updatedAt,
                costSummary: SyncCostSummary(
                    sessionCostUSD: days.reduce(0) { $0 + $1.costUSD },
                    sessionTokens: days.reduce(0) { $0 + $1.totalTokens },
                    last30DaysCostUSD: days.reduce(0) { $0 + $1.costUSD },
                    last30DaysTokens: days.reduce(0) { $0 + $1.totalTokens },
                    daily: days,
                    historyDays: historyDays,
                    historyCoverageIsEstablished: true,
                    costUpdatedAt: updatedAt,
                    totalCostUpdatedAt: updatedAt))
        }

        // The first complete 365-day snapshot establishes A and B, plus an
        // older row outside the later 30-day authoritative window.
        try CostLedgerService.upsertFromSnapshot(
            snapshot(
                days: [
                    SyncDailyPoint(dayKey: "2026-01-01", costUSD: 5, totalTokens: 500),
                    SyncDailyPoint(dayKey: "2026-08-11", costUSD: 120, totalTokens: 12000),
                    SyncDailyPoint(dayKey: "2026-08-12", costUSD: 10, totalTokens: 1000),
                ],
                historyDays: 365,
                updatedAt: establishedAt),
            deviceID: "dev-A",
            in: context)
        // A newer complete correction omits A and changes B. A is inside the
        // 30-day window and must be removed; the January row is outside it
        // and must remain available to a longer-window reader.
        try CostLedgerService.upsertFromSnapshot(
            snapshot(
                days: [SyncDailyPoint(dayKey: "2026-08-12", costUSD: 8, totalTokens: 800)],
                historyDays: 30,
                updatedAt: correctedAt),
            deviceID: "dev-A",
            in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        let byDay = Dictionary(uniqueKeysWithValues: rows.map { ($0.dayKey, $0) })
        #expect(rows.count == 2)
        #expect(byDay["2026-01-01"]?.costUSD == 5)
        #expect(byDay["2026-08-11"] == nil)
        #expect(byDay["2026-08-12"]?.costUSD == 8)
    }

    @Test
    func `upsertFromSnapshot: complete empty history uses Mac local authoritative day keys`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let establishedAt = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 11, hour: 0)))
        // 01:00 UTC is still August 11 in America/Indiana. A UTC-derived
        // 30-day cutoff would start on July 14 and fail to delete July 13.
        let correctedAt = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 12, hour: 1)))

        func snapshot(days: [SyncDailyPoint], updatedAt: Date) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: updatedAt,
                costSummary: SyncCostSummary(
                    sessionCostUSD: days.reduce(0) { $0 + $1.costUSD },
                    sessionTokens: days.reduce(0) { $0 + $1.totalTokens },
                    last30DaysCostUSD: days.reduce(0) { $0 + $1.costUSD },
                    last30DaysTokens: days.reduce(0) { $0 + $1.totalTokens },
                    daily: days,
                    historyDays: 30,
                    historyCoverageIsEstablished: true,
                    historySinceDayKey: "2026-07-13",
                    historyUntilDayKey: "2026-08-11",
                    costUpdatedAt: updatedAt,
                    totalCostUpdatedAt: updatedAt))
        }

        try CostLedgerService.upsertFromSnapshot(
            snapshot(
                days: [SyncDailyPoint(dayKey: "2026-07-13", costUSD: 130, totalTokens: 13000)],
                updatedAt: establishedAt),
            deviceID: "dev-A",
            in: context)
        try CostLedgerService.upsertFromSnapshot(
            snapshot(days: [], updatedAt: correctedAt),
            deviceID: "dev-A",
            in: context)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<DailyCostPoint>()).isEmpty)
    }

    @Test
    func `nil-email migration keeps established history over emailed partial row`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))
        let establishedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let partialAt = establishedAt.addingTimeInterval(60)

        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A",
            providerID: "codex",
            dayKey: "2026-08-12",
            costUSD: 130,
            totalTokens: 13000,
            isEstimated: nil,
            modelBreakdowns: [],
            serviceBreakdowns: [],
            lastUpdated: establishedAt,
            sourceRevisionKey: "historyCoverage=established",
            in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A",
            providerID: "codex",
            accountEmail: "user@example.com",
            dayKey: "2026-08-12",
            costUSD: 8,
            totalTokens: 800,
            isEstimated: nil,
            modelBreakdowns: [],
            serviceBreakdowns: [],
            lastUpdated: partialAt,
            sourceRevisionKey: "historyCoverage=partial",
            in: context)

        let snapshot = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "user@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: partialAt,
            costSummary: SyncCostSummary(
                sessionCostUSD: 8,
                sessionTokens: 800,
                last30DaysCostUSD: 8,
                last30DaysTokens: 800,
                daily: [SyncDailyPoint(
                    dayKey: "2026-08-12",
                    costUSD: 8,
                    totalTokens: 800)],
                historyDays: 30,
                historyCoverageIsEstablished: false,
                costUpdatedAt: partialAt,
                totalCostUpdatedAt: partialAt))
        try CostLedgerService.upsertFromSnapshot(snapshot, deviceID: "dev-A", in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.accountEmail == "user@example.com")
        #expect(row.costUSD == 130)
        #expect(row.totalTokens == 13000)
        #expect(row.sourceRevisionKey?.contains("historyCoverage=established") == true)
    }

    @Test
    func `upsertFromSnapshot: nil costSummary → no rows written`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let snapshot = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            costSummary: nil)

        try CostLedgerService.upsertFromSnapshot(
            snapshot, deviceID: "dev-A", in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.isEmpty)
    }
}
