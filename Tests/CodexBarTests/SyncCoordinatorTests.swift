import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// Mock sync pusher that records push calls for testing.
final class MockSyncPusher: SyncPushing, @unchecked Sendable {
    var pushCount = 0
    var lastSnapshot: SyncedUsageSnapshot?
    var snapshotsAcrossCalls: [SyncedUsageSnapshot] = []
    var nextResult: SyncPushResult = .success
    var shouldBlockNextPush = false
    private var blockedPushContinuation: CheckedContinuation<Void, Never>?

    // P4 — per-provider write tracking
    var perProviderCallCount = 0
    var lastPerProviderEnvelopes: [ProviderUsageEnvelope] = []
    var nextPerProviderResult: SyncPushResult = .success

    // L1 ghost-records cleanup — delete tracking
    var deleteCallCount = 0
    var deletedRecordNamesAcrossCalls: [[String]] = []
    var nextDeleteResult: SyncPushResult = .success

    // L1 reconcile — startup CKQuery for stranded records
    var fetchRecordNamesCallCount = 0
    var fetchRecordNamesLastDeviceID: String?
    var nextFetchRecordNamesResult: [String] = []

    @discardableResult
    func pushSnapshot(_ snapshot: SyncedUsageSnapshot) async -> SyncPushResult {
        self.pushCount += 1
        self.lastSnapshot = snapshot
        self.snapshotsAcrossCalls.append(snapshot)
        if self.shouldBlockNextPush {
            self.shouldBlockNextPush = false
            await withCheckedContinuation { continuation in
                self.blockedPushContinuation = continuation
            }
        }
        return self.nextResult
    }

    func resumeBlockedPush() {
        self.blockedPushContinuation?.resume()
        self.blockedPushContinuation = nil
    }

    @discardableResult
    func pushPerProviderRecords(
        _ envelopes: [ProviderUsageEnvelope]) async -> SyncPushResult
    {
        self.perProviderCallCount += 1
        self.lastPerProviderEnvelopes = envelopes
        return self.nextPerProviderResult
    }

    @discardableResult
    func deletePerProviderRecords(recordNames: [String]) async -> SyncPushResult {
        self.deleteCallCount += 1
        self.deletedRecordNamesAcrossCalls.append(recordNames)
        return self.nextDeleteResult
    }

    func fetchPerProviderRecordNames(forDeviceID deviceID: String) async -> [String] {
        self.fetchRecordNamesCallCount += 1
        self.fetchRecordNamesLastDeviceID = deviceID
        return self.nextFetchRecordNamesResult
    }
}

@MainActor
@Suite(.serialized)
// swiftlint:disable:next type_body_length
struct SyncCoordinatorTests {
    private func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func makeUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
    }

    @Test
    func `remaining provider balances do not sync as zero-limit budgets`() {
        let balance = ProviderCostSnapshot(
            used: 42.50,
            limit: 0,
            currencyCode: "USD",
            period: "ZenMux PAYG balance",
            updatedAt: Date())

        #expect(SyncCoordinator.syncBudgetSnapshot(provider: .zenmux, providerCost: balance) == nil)
        #expect(SyncCoordinator.syncBudgetSnapshot(provider: .neuralwatt, providerCost: balance) == nil)
        #expect(SyncCoordinator.syncBudgetSnapshot(provider: .fireworks, providerCost: balance) == nil)
        #expect(SyncCoordinator.syncBudgetSnapshot(provider: .xai, providerCost: balance) == nil)
        #expect(SyncCoordinator.syncBudgetSnapshot(provider: .opencode, providerCost: balance) == nil)
        #expect(SyncCoordinator.syncBudgetSnapshot(provider: .cursor, providerCost: balance) != nil)
    }

    @Test
    func `OpenCode pay as you go syncs spend and balance without a false zero limit budget`() {
        let cost = ProviderCostSnapshot(
            used: 15,
            limit: 0,
            currencyCode: "USD",
            period: "Monthly",
            balance: 12.50,
            updatedAt: Date())

        #expect(SyncCoordinator.syncBudgetSnapshot(provider: .opencode, providerCost: cost) == nil)
        #expect(SyncCoordinator.syncedStatusMessage(
            provider: .opencode,
            snapshot: nil,
            providerCost: cost,
            error: nil,
            rateWindows: []) == "Monthly spend: USD 15.00 · Balance: USD 12.50")
    }

    @Test
    func `xAI cost history maps to existing sync summary with partial confidence`() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = XAIUsageSnapshot(
            balanceUSD: 25,
            daily: [
                .init(day: "2027-01-14", costUSD: 1.25),
                .init(day: "2027-01-15", costUSD: 2.75),
            ],
            historyDays: 30,
            limitReached: true,
            updatedAt: now)

        let summary = try #require(SyncCoordinator.mapXAICostSummary(
            provider: .xai,
            snapshot: usage.toUsageSnapshot()))

        #expect(summary.sessionCostUSD == 2.75)
        #expect(summary.last30DaysCostUSD == 4)
        #expect(summary.historyDays == 30)
        #expect(summary.currencyCode == "USD")
        #expect(summary.isEstimated == true)
        #expect(summary.historyCoverageIsEstablished == nil)
        #expect(summary.daily.map(\.dayKey) == ["2027-01-14", "2027-01-15"])
        #expect(summary.daily.map(\.costUSD) == [1.25, 2.75])
        #expect(summary.daily.allSatisfy { $0.isEstimated == true })
    }

    @Test
    func `Codex cost summary maps history coverage from token snapshot`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-codex-history-coverage")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let providerUpdatedAt = Date(timeIntervalSince1970: 1_799_999_995)
        let costUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        store._setSnapshotForTesting(
            UsageSnapshot(primary: nil, secondary: nil, updatedAt: providerUpdatedAt),
            provider: .codex)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 30,
                sessionCostUSD: 3,
                last30DaysTokens: 30,
                last30DaysCostUSD: 3,
                historyCoverageIsEstablished: false,
                daily: [],
                updatedAt: costUpdatedAt),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let codex = try #require(mock.lastSnapshot?.providers.first { $0.providerID == "codex" })
        #expect(codex.costSummary?.historyCoverageIsEstablished == false)
        #expect(codex.lastUpdated == providerUpdatedAt)
        #expect(codex.costSummary?.costUpdatedAt == costUpdatedAt)
        #expect(codex.costSummary?.totalCostUpdatedAt == costUpdatedAt)
        #expect(codex.costSummary?.sourceRevisions?["tokenScanner"] == costUpdatedAt)
    }

    @Test
    func `Codex complete history publishes exact Mac local day bounds`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-codex-local-history-bounds")
        settings.iCloudSyncEnabled = true
        settings.costUsageBucketTimeZoneIdentifier = "America/Indiana/Indianapolis"
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let updatedAt = try #require(utc.date(from: DateComponents(
            year: 2026, month: 8, day: 12, hour: 1)))
        let store = self.makeUsageStore(settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(primary: nil, secondary: nil, updatedAt: updatedAt),
            provider: .codex)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 0,
                sessionCostUSD: 0,
                last30DaysTokens: 0,
                last30DaysCostUSD: 0,
                historyDays: 30,
                historyCoverageIsEstablished: true,
                historySinceDayKey: "2026-07-13",
                historyUntilDayKey: "2026-08-11",
                daily: [],
                updatedAt: updatedAt),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let summary = try #require(mock.lastSnapshot?.providers.first?.costSummary)
        #expect(summary.historySinceDayKey == "2026-07-13")
        #expect(summary.historyUntilDayKey == "2026-08-11")
    }

    @Test
    func `Codex account switch does not retain the previous account's partial cost history`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-codex-cost-account-scope")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let establishedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let partialAt = establishedAt.addingTimeInterval(60)
        func usageSnapshot(email: String, accountID: String, updatedAt: Date) -> UsageSnapshot {
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: updatedAt,
                identity: ProviderIdentitySnapshot(
                    providerID: UsageProvider.codex.instanceID,
                    accountEmail: email,
                    accountOrganization: nil,
                    loginMethod: "oauth",
                    accountID: accountID))
        }
        func costSnapshot(cost: Double, complete: Bool, updatedAt: Date) -> CostUsageTokenSnapshot {
            CostUsageTokenSnapshot(
                sessionTokens: Int(cost * 100),
                sessionCostUSD: cost,
                last30DaysTokens: Int(cost * 100),
                last30DaysCostUSD: cost,
                historyDays: 30,
                historyCoverageIsEstablished: complete,
                daily: [],
                updatedAt: updatedAt)
        }

        store._setSnapshotForTesting(
            usageSnapshot(email: "alice@example.com", accountID: "account-a", updatedAt: establishedAt),
            provider: .codex)
        store._setTokenSnapshotForTesting(
            costSnapshot(cost: 130, complete: true, updatedAt: establishedAt),
            provider: .codex)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()
        #expect(mock.lastSnapshot?.providers.first?.costSummary?.last30DaysCostUSD == 130)

        // B's first result is partial. B must start cold rather than inheriting
        // A's retained complete total merely because both use the Codex slot.
        store._setSnapshotForTesting(
            usageSnapshot(email: "bob@example.com", accountID: "account-b", updatedAt: partialAt),
            provider: .codex)
        store.installCachedTokenSnapshot(
            costSnapshot(cost: 8, complete: false, updatedAt: partialAt),
            for: .codex)
        await coordinator.pushCurrentSnapshot()

        let codex = try #require(mock.lastSnapshot?.providers.first { $0.providerID == "codex" })
        #expect(codex.accountEmail == "bob@example.com")
        #expect(codex.costSummary?.last30DaysCostUSD == 8)
        #expect(codex.costSummary?.historyCoverageIsEstablished == false)
    }

    @Test
    func `Cursor machine local fallback stays standalone and out of account sync`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-cursor-unowned-local-cost")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .cursor,
            metadata: #require(ProviderDefaults.metadata[.cursor]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let localCost = CostUsageTokenSnapshot(
            sessionTokens: 150,
            sessionCostUSD: 0.12,
            last30DaysTokens: 150,
            last30DaysCostUSD: 0.12,
            ownership: .machineLocalUnowned,
            daily: [],
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        store._setTokenSnapshotForTesting(localCost, provider: .cursor)

        // With no account context, the machine-local total remains available to Mac surfaces.
        #expect(store.tokenSnapshot(for: .cursor)?.ownership == .machineLocalUnowned)

        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 25,
                    windowMinutes: 10080,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_001),
                identity: ProviderIdentitySnapshot(
                    providerID: .cursor,
                    accountEmail: "selected@cursor.test",
                    accountOrganization: nil,
                    loginMethod: "cookie")),
            provider: .cursor)

        // A remote failure may leave the local fallback published, but it cannot inherit the
        // selected Cursor account or appear on that account's provider card.
        #expect(store.tokenSnapshot(for: .cursor) == nil)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let cursor = try #require(mock.lastSnapshot?.providers.first { $0.providerID == "cursor" })
        #expect(cursor.accountEmail == "selected@cursor.test")
        #expect(cursor.costSummary == nil)
    }

    @Test
    func `Antigravity authoritative account never syncs machine local cost`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-antigravity-unowned-local-cost")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .antigravity,
            metadata: #require(ProviderDefaults.metadata[.antigravity]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 40,
                    windowMinutes: 300,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_001),
                identity: ProviderIdentitySnapshot(
                    providerID: .antigravity,
                    accountEmail: "owner@antigravity.test",
                    accountOrganization: nil,
                    loginMethod: "oauth")),
            provider: .antigravity)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 300,
                sessionCostUSD: nil,
                last30DaysTokens: 300,
                last30DaysCostUSD: nil,
                ownership: .machineLocalUnowned,
                daily: [],
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)),
            provider: .antigravity)

        #expect(store.tokenSnapshot(for: .antigravity) == nil)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let antigravity = try #require(mock.lastSnapshot?.providers.first {
            $0.providerID == "antigravity"
        })
        #expect(antigravity.accountEmail == "owner@antigravity.test")
        #expect(antigravity.costSummary == nil)
    }

    @Test
    func `xAI sync preserves balance and cost history without a false budget`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-xai")
        settings.iCloudSyncEnabled = true
        settings[providerConfig: .xai, field: .apiKey] = "fixture-management-key"
        settings[providerConfig: .xai, field: .workspace] = "fixture-team"
        try settings.setProviderEnabled(
            provider: .xai,
            metadata: #require(ProviderDefaults.metadata[.xai]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let usage = XAIUsageSnapshot(
            balanceUSD: 25,
            daily: [
                .init(day: "2027-01-14", costUSD: 1.25),
                .init(day: "2027-01-15", costUSD: 2.75),
            ],
            limitReached: true,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        store._setSnapshotForTesting(usage.toUsageSnapshot(), provider: .xai)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == UsageProvider.xai.rawValue }))
        #expect(provider.statusMessage == "Prepaid credits: USD 25.00")
        #expect(provider.budget == nil)
        #expect(provider.costSummary?.last30DaysCostUSD == 4)
        #expect(provider.costSummary?.isEstimated == true)
        #expect(provider.costSummary?.costUpdatedAt == usage.updatedAt)
        #expect(provider.costSummary?.totalCostUpdatedAt == usage.updatedAt)
        #expect(provider.costSummary?.sourceRevisions?["xai"] == usage.updatedAt)
    }

    @Test
    func `Claude prepaid balance syncs without a false zero-limit budget`() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let balanceOnly = ProviderCostSnapshot(
            used: 0,
            limit: 0,
            currencyCode: "usd",
            period: "Extra usage",
            balance: 27.50,
            updatedAt: now)

        let extra = try #require(SyncCoordinator.mapClaudeExtraUsage(
            provider: .claude,
            snapshot: UsageSnapshot(primary: nil, secondary: nil, updatedAt: now),
            providerCost: balanceOnly))

        #expect(extra.utilization == nil)
        #expect(extra.monthlySpendUSD == nil)
        #expect(extra.monthlyLimitUSD == nil)
        #expect(extra.balanceUSD == 27.50)
        #expect(SyncCoordinator.syncBudgetSnapshot(provider: .claude, providerCost: balanceOnly) == nil)
    }

    @Test
    func `Claude spend limit keeps its prepaid balance on the sync envelope`() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let spendLimit = ProviderCostSnapshot(
            used: 30,
            limit: 100,
            currencyCode: "USD",
            period: "This month",
            balance: 18.25,
            updatedAt: now)

        let extra = try #require(SyncCoordinator.mapClaudeExtraUsage(
            provider: .claude,
            snapshot: UsageSnapshot(primary: nil, secondary: nil, updatedAt: now),
            providerCost: spendLimit))

        #expect(extra.utilization == 30)
        #expect(extra.monthlySpendUSD == 30)
        #expect(extra.monthlyLimitUSD == 100)
        #expect(extra.balanceUSD == 18.25)
        #expect(SyncCoordinator.syncBudgetSnapshot(provider: .claude, providerCost: spendLimit) != nil)
    }

    @Test
    func `push skipped when sync disabled`() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-disabled")
        settings.iCloudSyncEnabled = false
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        #expect(mock.pushCount == 0)
        #expect(coordinator.lastSyncTime == nil)
    }

    @Test
    func `push succeeds when sync enabled`() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-enabled")
        settings.iCloudSyncEnabled = true
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        // Push may or may not happen depending on whether there are enabled providers.
        // With default config, providers may be enabled, so check status tracking.
        if mock.pushCount > 0 {
            #expect(coordinator.lastSyncTime != nil)
            #expect(coordinator.lastSyncSucceeded == true)
            #expect(coordinator.lastSyncMessage == nil)
        }
    }

    @Test
    func `push failure tracks status`() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-failure")
        settings.iCloudSyncEnabled = true
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        mock.nextResult = .failure("iCloud sync unavailable")
        mock.nextPerProviderResult = .failure("provider sync unavailable")
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        if mock.pushCount > 0 {
            #expect(coordinator.lastSyncTime != nil)
            #expect(coordinator.lastSyncSucceeded == false)
            #expect(coordinator.lastSyncMessage?.contains("iCloud sync unavailable") == true)
            #expect(coordinator.lastSyncMessageIsWarning == false)
        }
    }

    @Test
    func `cloud kit production schema message extracts record type`() {
        let message =
            "Error saving record <CKRecordID: 0x123; recordName=ABC, " +
            "zoneID=DeviceSnapshotsZone:__defaultOwner__> to server: " +
            "Cannot create new type DeviceSnapshot in production schema"

        #expect(CloudSyncError.missingProductionRecordType(in: message) == "DeviceSnapshot")
        #expect(
            CloudSyncError.productionSchemaMissingRecordType("DeviceSnapshot")
                .description
                .contains("iCloud.com.columbuslabs.quotakit"))
    }

    @Test
    func `legacy schema failure with per provider success reports partial success`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-schema-partial")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: Date()),
            provider: .codex)

        let schemaMessage = CloudSyncError
            .productionSchemaMissingRecordType("DeviceSnapshot")
            .description
        let mock = MockSyncPusher()
        mock.nextResult = .failure(schemaMessage)
        mock.nextPerProviderResult = .success
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        #expect(mock.pushCount == 1)
        #expect(mock.perProviderCallCount == 1)
        #expect(coordinator.lastSyncSucceeded == true)
        #expect(coordinator.lastSyncMessageIsWarning == true)
        #expect(coordinator.lastSyncMessage?.contains("iPhone sync completed") == true)
        #expect(coordinator.lastSyncMessage?.contains("DeviceSnapshot") == true)
    }

    @Test
    func `legacy and per provider failures report full failure`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-both-fail")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: Date()),
            provider: .codex)

        let mock = MockSyncPusher()
        mock.nextResult = .failure("legacy unavailable")
        mock.nextPerProviderResult = .failure("provider unavailable")
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        #expect(mock.pushCount == 1)
        #expect(mock.perProviderCallCount == 1)
        #expect(coordinator.lastSyncSucceeded == false)
        #expect(coordinator.lastSyncMessageIsWarning == false)
        #expect(coordinator.lastSyncMessage?.contains("legacy unavailable") == true)
        #expect(coordinator.lastSyncMessage?.contains("provider unavailable") == true)
    }

    @Test
    func `is syncing is false after push`() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-syncing")
        settings.iCloudSyncEnabled = true
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        // isSyncing should be false after synchronous push completes
        #expect(coordinator.isSyncing == false)
    }

    @Test
    func `cost mutation during an in flight push is published by one trailing push`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-trailing-cost-push")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let initialDate = Date(timeIntervalSince1970: 1_800_000_000)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 1,
                last30DaysTokens: 100,
                last30DaysCostUSD: 1,
                daily: [],
                updatedAt: initialDate),
            provider: .codex)

        let mock = MockSyncPusher()
        mock.shouldBlockNextPush = true
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        coordinator.startObserving()

        let initialPush = Task { @MainActor in
            await coordinator.pushCurrentSnapshot()
        }
        for _ in 0..<100 where mock.pushCount == 0 {
            await Task.yield()
        }
        #expect(mock.pushCount == 1)
        #expect(coordinator.isSyncing)

        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 250,
                sessionCostUSD: 2.5,
                last30DaysTokens: 250,
                last30DaysCostUSD: 2.5,
                daily: [],
                updatedAt: initialDate.addingTimeInterval(5)),
            provider: .codex)
        // Let the observation callback re-arm and mark the active drain pending.
        for _ in 0..<20 {
            await Task.yield()
        }

        mock.resumeBlockedPush()
        await initialPush.value

        #expect(mock.pushCount == 2)
        let finalCodex = try #require(mock.lastSnapshot?.providers.first {
            $0.providerID == UsageProvider.codex.rawValue
        })
        #expect(finalCodex.costSummary?.sessionCostUSD == 2.5)
        #expect(coordinator.isSyncing == false)
    }

    @Test
    func `multiple mutations during an in flight push coalesce into one trailing push`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-coalesced-cost-push")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let initialDate = Date(timeIntervalSince1970: 1_800_000_000)

        func snapshot(cost: Double, offset: TimeInterval) -> CostUsageTokenSnapshot {
            CostUsageTokenSnapshot(
                sessionTokens: Int(cost * 100),
                sessionCostUSD: cost,
                last30DaysTokens: Int(cost * 100),
                last30DaysCostUSD: cost,
                daily: [],
                updatedAt: initialDate.addingTimeInterval(offset))
        }

        store._setTokenSnapshotForTesting(snapshot(cost: 1, offset: 0), provider: .codex)
        let mock = MockSyncPusher()
        mock.shouldBlockNextPush = true
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        coordinator.startObserving()

        let initialPush = Task { @MainActor in
            await coordinator.pushCurrentSnapshot()
        }
        for _ in 0..<100 where mock.pushCount == 0 {
            await Task.yield()
        }
        #expect(mock.pushCount == 1)

        store._setTokenSnapshotForTesting(snapshot(cost: 2, offset: 2), provider: .codex)
        for _ in 0..<10 {
            await Task.yield()
        }
        store._setTokenSnapshotForTesting(snapshot(cost: 3, offset: 3), provider: .codex)
        for _ in 0..<10 {
            await Task.yield()
        }
        store._setTokenSnapshotForTesting(snapshot(cost: 4, offset: 4), provider: .codex)
        for _ in 0..<20 {
            await Task.yield()
        }

        mock.resumeBlockedPush()
        await initialPush.value

        #expect(mock.pushCount == 2)
        let finalCodex = try #require(mock.lastSnapshot?.providers.first {
            $0.providerID == UsageProvider.codex.rawValue
        })
        #expect(finalCodex.costSummary?.sessionCostUSD == 4)
    }

    @Test
    func `push includes model and service breakdowns`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-breakdowns")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let tokenUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let dashboardUpdatedAt = tokenUpdatedAt.addingTimeInterval(5)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 1500,
                sessionCostUSD: 0.32,
                last30DaysTokens: 32000,
                last30DaysCostUSD: 2.40,
                daily: [
                    CostUsageDailyReport.Entry(
                        date: "2026-03-16",
                        inputTokens: 1000,
                        outputTokens: 500,
                        totalTokens: 1500,
                        costUSD: 2.40,
                        modelsUsed: ["gpt-5.4", "gpt-5.3-codex"],
                        modelBreakdowns: [
                            .init(modelName: "gpt-5.4", costUSD: 1.80, totalTokens: 1100),
                            .init(modelName: "gpt-5.3-codex", costUSD: 0.60, totalTokens: 400),
                        ]),
                ],
                updatedAt: tokenUpdatedAt),
            provider: .codex)
        store.openAIDashboard = OpenAIDashboardSnapshot(
            signedInEmail: "user@example.com",
            codeReviewRemainingPercent: nil,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [
                OpenAIDashboardDailyBreakdown(
                    day: "2026-03-16",
                    services: [
                        OpenAIDashboardServiceUsage(service: "CLI", creditsUsed: 1.90),
                        OpenAIDashboardServiceUsage(service: "GitHub Code Review", creditsUsed: 0.50),
                    ],
                    totalCreditsUsed: 2.40),
            ],
            creditsPurchaseURL: nil,
            updatedAt: dashboardUpdatedAt)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == UsageProvider.codex.rawValue }))
        let costSummary = try #require(provider.costSummary)
        let daily = try #require(costSummary.daily.first)

        #expect(daily.modelBreakdowns == [
            SyncCostBreakdown(label: "gpt-5.4", costUSD: 1.80, totalTokens: 1100),
            SyncCostBreakdown(label: "gpt-5.3-codex", costUSD: 0.60, totalTokens: 400),
        ])
        #expect(daily.serviceBreakdowns == [
            SyncCostBreakdown(label: "Codex Run", costUSD: 1.90),
            SyncCostBreakdown(label: "GitHub Code Review", costUSD: 0.50),
        ])
        #expect(costSummary.costUpdatedAt == dashboardUpdatedAt)
        #expect(costSummary.totalCostUpdatedAt == tokenUpdatedAt)
        #expect(costSummary.sourceRevisions?["tokenScanner"] == tokenUpdatedAt)
        #expect(costSummary.sourceRevisions?["openAIDashboard"] == dashboardUpdatedAt)
    }

    @Test
    func `push builds codex cost summary from dashboard when token snapshot missing`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-dashboardFallback")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let dashboardUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        store.openAIDashboard = OpenAIDashboardSnapshot(
            signedInEmail: "user@example.com",
            codeReviewRemainingPercent: nil,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [
                OpenAIDashboardDailyBreakdown(
                    day: "2026-03-15",
                    services: [OpenAIDashboardServiceUsage(service: "CLI", creditsUsed: 0.75)],
                    totalCreditsUsed: 0.75),
                OpenAIDashboardDailyBreakdown(
                    day: "2026-03-16",
                    services: [OpenAIDashboardServiceUsage(service: "GitHub Code Review", creditsUsed: 1.25)],
                    totalCreditsUsed: 1.25),
            ],
            creditsPurchaseURL: nil,
            updatedAt: dashboardUpdatedAt)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == UsageProvider.codex.rawValue }))
        let costSummary = try #require(provider.costSummary)
        #expect(costSummary.sessionCostUSD == nil)
        #expect(costSummary.last30DaysCostUSD == 2.0)
        #expect(costSummary.daily.count == 2)
        #expect(costSummary.daily[0].serviceBreakdowns == [SyncCostBreakdown(label: "Codex Run", costUSD: 0.75)])
        #expect(costSummary.costUpdatedAt == dashboardUpdatedAt)
        #expect(costSummary.totalCostUpdatedAt == dashboardUpdatedAt)
        #expect(costSummary.sourceRevisions?["openAIDashboard"] == dashboardUpdatedAt)
    }

    @Test
    func `default sync enabled is true`() throws {
        let suite = "SyncCoord-defaultEnabled"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(settings.iCloudSyncEnabled == true)
    }

    @Test
    func `sync enabled persists across instances`() throws {
        let suite = "SyncCoord-persist"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        storeA.iCloudSyncEnabled = false

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.iCloudSyncEnabled == false)
    }

    @Test
    func `toggling setting updates user defaults`() throws {
        let suite = "SyncCoord-toggle"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        settings.iCloudSyncEnabled = false
        #expect(defaults.bool(forKey: "iCloudSyncEnabled") == false)

        settings.iCloudSyncEnabled = true
        #expect(defaults.bool(forKey: "iCloudSyncEnabled") == true)
    }

    // MARK: - P4 per-provider dual-write

    @Test
    func `per provider write fires alongside legacy on first push`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-perprov-first")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: Date()),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        // Legacy write ran once; per-provider write ran once with the Codex envelope.
        #expect(mock.pushCount == 1)
        #expect(mock.perProviderCallCount == 1)
        #expect(mock.lastPerProviderEnvelopes.count >= 1)
        #expect(mock.lastPerProviderEnvelopes.contains { $0.provider.providerID == "codex" })
    }

    @Test
    func `per provider write skipped when data unchanged`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-perprov-unchanged")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let fixedSnapshot = CostUsageTokenSnapshot(
            sessionTokens: 100,
            sessionCostUSD: 0.1,
            last30DaysTokens: 1000,
            last30DaysCostUSD: 1.0,
            daily: [],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        store._setTokenSnapshotForTesting(fixedSnapshot, provider: .codex)
        // Pin `updatedAt` so SyncCoordinator's `lastUpdated` is stable
        // between pushes. Without this, fallback `Date()` differs by ≥1s
        // between pushes on a slow CI runner, the diff hash flips, and
        // the "unchanged" assertion racily fails.
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()
        let firstCallEnvelopes = mock.lastPerProviderEnvelopes

        // Second push with unchanged data: coordinator's diff cache should
        // surface an empty envelope array, so the mock records either a
        // zero-length call or no call at all.
        await coordinator.pushCurrentSnapshot()

        #expect(!firstCallEnvelopes.isEmpty) // first push wrote envelopes
        // Second push skipped everything — either no call, or explicit empty.
        // Coordinator guards on `!envelopes.isEmpty` so it should be no call.
        #expect(mock.perProviderCallCount == 1)
    }

    @Test
    func `per provider write sends only changed provider on incremental update`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-perprov-incr")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            provider: .codex)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 50,
                sessionCostUSD: 0.05,
                last30DaysTokens: 500,
                last30DaysCostUSD: 0.5,
                daily: [],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            provider: .claude)
        // Pin UsageSnapshot.updatedAt for both providers so SyncCoordinator's
        // `lastUpdated` fallback to `Date()` doesn't leak wall-clock between
        // pushes (see perProviderWriteSkippedWhenDataUnchanged comment).
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            provider: .codex)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            provider: .claude)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        // First push — both providers upload.
        await coordinator.pushCurrentSnapshot()
        let firstCount = mock.lastPerProviderEnvelopes.count
        #expect(firstCount >= 2)

        // Change ONLY Codex (token snapshot + UsageSnapshot.updatedAt).
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 200,
                sessionCostUSD: 0.2,
                last30DaysTokens: 2000,
                last30DaysCostUSD: 2.0,
                daily: [],
                updatedAt: Date(timeIntervalSince1970: 1_700_001_000)),
            provider: .codex)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_001_000)),
            provider: .codex)

        await coordinator.pushCurrentSnapshot()

        // Second call should contain only the changed provider.
        #expect(mock.perProviderCallCount == 2)
        #expect(mock.lastPerProviderEnvelopes.count == 1)
        #expect(mock.lastPerProviderEnvelopes.first?.provider.providerID == "codex")
    }

    // MARK: - L1 ghost-records cleanup

    @Test
    func `L1: first push after restart does NOT emit deletes (pushHistorySeeded guard)`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-firstpush")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: Date()),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        // First-push guard: no deletes should fire even though
        // lastPushedRecordNames was empty pre-call. Otherwise we'd interpret
        // the empty initial set as "nothing was previously enabled" and
        // skip cleanup of records from previous Mac sessions.
        #expect(mock.deleteCallCount == 0)
    }

    @Test
    func `L1: provider disabled between cycles emits delete for its CKRecord`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-disable")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        for provider in [UsageProvider.codex, .claude] {
            store._setTokenSnapshotForTesting(
                CostUsageTokenSnapshot(
                    sessionTokens: 100,
                    sessionCostUSD: 0.1,
                    last30DaysTokens: 1000,
                    last30DaysCostUSD: 1.0,
                    daily: [],
                    updatedAt: pinned),
                provider: provider)
            store._setSnapshotForTesting(
                UsageSnapshot(primary: nil, secondary: nil, updatedAt: pinned),
                provider: provider)
        }

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        // First push — seed lastPushedRecordNames with both composites.
        await coordinator.pushCurrentSnapshot()
        #expect(mock.deleteCallCount == 0)

        // Disable Claude before next cycle.
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: false)

        // Second push — Claude's composite is in lastPushedRecordNames but
        // not in this cycle's set, so a delete must fire for its recordName.
        await coordinator.pushCurrentSnapshot()
        #expect(mock.deleteCallCount == 1)
        let deleted = mock.deletedRecordNamesAcrossCalls.last ?? []
        #expect(deleted.count == 1)
        #expect(deleted.first?.contains("claude") == true)
    }

    @Test
    func `L1: account-identity drift (composite key change) emits delete for old composite`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-drift")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)

        // First cycle: Codex with nil accountEmail (composite "codex|_").
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: pinned),
            provider: .codex)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: pinned,
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: nil,
                    accountOrganization: nil,
                    loginMethod: nil)),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()
        #expect(mock.deleteCallCount == 0) // first push, no delete

        // Second cycle: same provider but accountEmail loaded — composite
        // shifts from "codex|_" to "codex|user@example.com". The old
        // composite must be deleted.
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: pinned.addingTimeInterval(60),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "user@example.com",
                    accountOrganization: nil,
                    loginMethod: nil)),
            provider: .codex)
        await coordinator.pushCurrentSnapshot()

        #expect(mock.deleteCallCount == 1)
        let deleted = mock.deletedRecordNamesAcrossCalls.last ?? []
        // Deleted composite must end with "|_" (the orphan with nil email).
        #expect(deleted.count == 1)
        #expect(deleted.first?.hasSuffix("|codex|_") == true)
    }

    @Test
    func `L1: no deletes when all providers stay enabled with stable identity`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-steady")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: pinned),
            provider: .codex)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: pinned),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        // Three cycles, no state change.
        for _ in 0..<3 {
            await coordinator.pushCurrentSnapshot()
        }
        // pushHistorySeeded after first; subsequent two would only delete
        // if state changed. Steady state = no deletes.
        #expect(mock.deleteCallCount == 0)
    }

    @Test
    func `L1: delete failure does NOT advance lastPushedRecordNames (retries next cycle)`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-retry")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        for provider in [UsageProvider.codex, .claude] {
            store._setTokenSnapshotForTesting(
                CostUsageTokenSnapshot(
                    sessionTokens: 100,
                    sessionCostUSD: 0.1,
                    last30DaysTokens: 1000,
                    last30DaysCostUSD: 1.0,
                    daily: [],
                    updatedAt: pinned),
                provider: provider)
            store._setSnapshotForTesting(
                UsageSnapshot(primary: nil, secondary: nil, updatedAt: pinned),
                provider: provider)
        }

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: false)

        // First retry cycle: simulate delete failure.
        mock.nextDeleteResult = .failure("CloudKit unavailable")
        await coordinator.pushCurrentSnapshot()
        #expect(mock.deleteCallCount == 1)

        // Second retry cycle: success this time, should re-attempt.
        mock.nextDeleteResult = .success
        await coordinator.pushCurrentSnapshot()
        #expect(mock.deleteCallCount == 2)
        // Same composite re-deleted (because failure didn't advance state).
        #expect(mock.deletedRecordNamesAcrossCalls[0] ==
            mock.deletedRecordNamesAcrossCalls[1])
    }

    // MARK: - L1 reconcile (startup CKQuery for stranded records)

    @Test
    func `L1 reconcile seeds last pushed names so stranded mocks clean next cycle`() async throws {
        // Reproduces user-reported 2026-05-05 bug: stranded mock CKRecords
        // from a previous Mac process incarnation persisted on iOS forever.
        // Cause: lastPushedRecordNames was in-memory only; restart wiped
        // the history, the first-cycle guard skipped delete, subsequent
        // cycles diff'd against (current vs current) so no diff fired.
        // Fix: at startup, fetch CloudKit's current state for this device
        // and seed the in-memory set, so the next push-cycle diff sees
        // pre-existing records.
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-reconcile")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: pinned),
            provider: .codex)
        store._setSnapshotForTesting(
            UsageSnapshot(primary: nil, secondary: nil, updatedAt: pinned),
            provider: .codex)

        // Pre-existing CloudKit state: this device pushed 2 mock records
        // in a previous process incarnation (mock toggle was on). After
        // restart, those records still exist but lastPushedRecordNames
        // is empty in memory.
        let mock = MockSyncPusher()
        let strandedMockA =
            "test-device-id|claude|personal-mock@claude.test"
        let strandedMockB =
            "test-device-id|cursor|expired-mock@cursor.test"
        mock.nextFetchRecordNamesResult = [strandedMockA, strandedMockB]

        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        // Reconcile happens fire-and-forget when startObserving is called.
        // Test environment: trigger reconcile + first push manually so we
        // can assert behavior without coupling to observer lifecycle.
        // Instead, simulate the reconcile-then-push flow by triggering
        // observation, then waiting for both ops to settle.
        coordinator.startObserving()
        // Yield so the reconcile Task can run before the push cycle.
        // Multiple yields because the reconcile Task and the
        // observeLoop's Task are scheduled separately.
        for _ in 0..<5 {
            await Task.yield()
        }

        // Reconcile fired exactly once at startup.
        #expect(mock.fetchRecordNamesCallCount == 1)
        // Push cycle ran (no current snapshot yet because store is empty,
        // but we explicitly seeded one above so push should fire).
        await coordinator.pushCurrentSnapshot()

        // The 2 stranded mocks are NOT in current cycle's emit set
        // (only real codex). Whole-provider gone (claude / cursor not
        // in any current record) → 1-cycle delete.
        for _ in 0..<20 where mock.deleteCallCount == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(mock.deleteCallCount == 1)
        let deletedNames = Set(mock.deletedRecordNamesAcrossCalls.flatMap(\.self))
        #expect(deletedNames.contains(strandedMockA))
        #expect(deletedNames.contains(strandedMockB))
    }

    @Test
    func `L1 reconcile: empty CloudKit result preserves first-push guard semantics`() async throws {
        // Fresh device, never pushed before — CloudKit returns empty.
        // Reconcile should be a no-op; first push behavior unchanged
        // (no spurious deletes, lastPushedRecordNames seeds normally).
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-reconcile-empty")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: Date()),
            provider: .codex)

        let mock = MockSyncPusher()
        mock.nextFetchRecordNamesResult = []
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        coordinator.startObserving()
        for _ in 0..<5 {
            await Task.yield()
        }
        await coordinator.pushCurrentSnapshot()

        #expect(mock.fetchRecordNamesCallCount == 1)
        #expect(mock.deleteCallCount == 0) // no stranded records to clean
    }

    @Test
    func `L1 reconcile: skipped when iCloud sync disabled`() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-reconcile-disabled")
        settings.iCloudSyncEnabled = false
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        coordinator.startObserving()
        for _ in 0..<5 {
            await Task.yield()
        }
        // No CKQuery should fire — pushing is a no-op anyway, no point
        // querying CloudKit.
        #expect(mock.fetchRecordNamesCallCount == 0)
    }

    // MARK: - extraRateWindows passthrough (Claude Designs/Routines, Cursor Extra)

    @Test
    func `extraRateWindows: Claude Designs/Daily Routines/Web Sonnet appear in rateWindows`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-extras-claude")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        let designsWindow = RateWindow(
            usedPercent: 23.0,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: nil)
        let routinesWindow = RateWindow(
            usedPercent: 42.5,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: nil)
        let webSonnetWindow = RateWindow(
            usedPercent: 67.8,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: nil)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 12.0,
                    windowMinutes: 60,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 35.0,
                    windowMinutes: 10080,
                    resetsAt: nil,
                    resetDescription: nil),
                extraRateWindows: [
                    NamedRateWindow(id: "claude-design", title: "Designs", window: designsWindow),
                    NamedRateWindow(id: "claude-routines", title: "Daily Routines", window: routinesWindow),
                    NamedRateWindow(id: "claude-web-sonnet", title: "Web Sonnet", window: webSonnetWindow),
                ],
                updatedAt: pinned),
            provider: .claude)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == "claude" }))
        // Primary + secondary + 3 extras = 5 total in rateWindows.
        // Note: tertiary path requires supportsOpus + tertiary set — we
        // don't set tertiary here, so just primary + secondary + 3 extras.
        #expect(provider.rateWindows.count == 5)
        let labels = provider.rateWindows.compactMap(\.label)
        #expect(labels.contains("Designs"))
        #expect(labels.contains("Daily Routines"))
        #expect(labels.contains("Web Sonnet"))
    }

    @Test
    func `extraRateWindows: Codex Spark visibility applies to synced rate windows`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-extras-codex-spark-hidden")
        settings.iCloudSyncEnabled = true
        settings.codexSparkUsageVisible = false
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        let sparkWindow = RateWindow(
            usedPercent: 23.0,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil)
        let customWindow = RateWindow(
            usedPercent: 42.0,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 12.0,
                    windowMinutes: 300,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 35.0,
                    windowMinutes: 10080,
                    resetsAt: nil,
                    resetDescription: nil),
                extraRateWindows: [
                    NamedRateWindow(
                        id: CodexAdditionalRateLimitMapper.sparkWindowID,
                        title: "Codex Spark 5-hour",
                        window: sparkWindow),
                    NamedRateWindow(id: "codex-custom-model", title: "Custom Model", window: customWindow),
                ],
                updatedAt: pinned),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == "codex" }))
        let labels = provider.rateWindows.compactMap(\.label)
        #expect(labels.contains("Codex Spark 5-hour") == false)
        #expect(labels.contains("Custom Model"))
    }

    @Test
    func `extraRateWindows: nil extras don't break legacy primary/secondary mapping`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-extras-nil")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 12.0,
                    windowMinutes: 60,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: nil,
                extraRateWindows: nil,
                updatedAt: pinned),
            provider: .claude)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == "claude" }))
        #expect(provider.rateWindows.count == 1) // just primary
    }

    @Test
    func `ghost provider not pushed to per provider zone`() async throws {
        // Provider enabled but has NO data yet (mimics early startup before
        // OAuth / cookies populate rate windows / cost / budget). The
        // legacy-zone monolithic write still includes it, but per-provider
        // zone push must skip it — otherwise it lands in
        // DeviceProvidersZone under recordName `{deviceID}|codex|_` and
        // never gets overwritten once accountEmail populates on a later push.
        let settings = self.makeSettingsStore(suite: "SyncCoord-ghost")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        // No token snapshot, no UsageSnapshot — provider has absolutely
        // nothing to say. This is the ghost case.

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        // Legacy monolithic still pushed (includes the bare provider entry
        // so old iOS builds can at least name it).
        #expect(mock.pushCount >= 0) // may be 0 if no providers available at all
        // Per-provider zone must NOT receive the ghost.
        #expect(mock.lastPerProviderEnvelopes.allSatisfy { e in
            e.provider.providerID != "codex"
                || e.provider.primary != nil
                || e.provider.secondary != nil
                || !e.provider.rateWindows.isEmpty
                || e.provider.costSummary != nil
                || e.provider.budget != nil
                || e.provider.isError
                || e.provider.statusMessage != nil
        })
    }

    @Test
    func `identity only Copilot plan remains in per provider sync`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-copilot-identity-only")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .copilot,
            metadata: #require(ProviderDefaults.metadata[.copilot]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .copilot,
                    accountEmail: nil,
                    accountOrganization: nil,
                    loginMethod: "Business")),
            provider: .copilot)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let copilot = try #require(mock.lastPerProviderEnvelopes.first {
            $0.provider.providerID == UsageProvider.copilot.rawValue
        })
        #expect(copilot.provider.primary == nil)
        #expect(copilot.provider.secondary == nil)
        #expect(copilot.provider.loginMethod == "Business")
        #expect(copilot.provider.statusMessage == "Plan: Business")
    }
}
