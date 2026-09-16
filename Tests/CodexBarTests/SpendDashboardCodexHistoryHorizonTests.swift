import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

/// Deterministic regression coverage for
/// `ColumbusLabs/QuotaKit#160`: routine/background spend collection must not
/// silently expand Codex history scans to 365 days.
///
/// The horizon policy (`SpendDashboardSource.requiredCodexHistoryDays`) keeps
/// routine work bounded at the configured window. Only the dashboard's All
/// range (or an explicitly configured 365-day window) selects the full scan
/// window. Every test observes horizons through the existing loader/catch-up
/// seams; no test depends on timing sleeps.
@MainActor
@Suite(.serialized)
struct SpendDashboardCodexHistoryHorizonTests {
    // MARK: - Policy units

    @Test
    func `routine horizons stay bounded without an extended consumer`() {
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: 30,
            dashboardRequestedDays: nil) == 30)
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: 30,
            dashboardRequestedDays: 7) == 30)
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: 30,
            dashboardRequestedDays: 30) == 30)
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: 90,
            dashboardRequestedDays: 30) == 90)
    }

    @Test
    func `explicit extended demand selects the full scan window`() {
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: 30,
            dashboardRequestedDays: SpendDashboardSource.scanDays) == SpendDashboardSource.scanDays)
    }

    @Test
    func `explicitly configured full window stays full without dashboard demand`() {
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: SpendDashboardSource.scanDays,
            dashboardRequestedDays: nil) == SpendDashboardSource.scanDays)
    }

    // MARK: - Test A — routine bounded collection does not widen to 365

    @Test
    func `routine dashboard load captures and scans the configured horizon`() async throws {
        let store = try Self.makeStore(suite: "routine-bounded")
        store.settings.costUsageHistoryDays = 30

        let configuration = SpendDashboardSource.configuration(settings: store.settings, store: store)
        #expect(configuration.codexHistoryDays == 30)

        let request = await SpendDashboardSource.makeRequest(
            settings: store.settings,
            store: store,
            mode: .refreshMissing,
            now: Date(timeIntervalSince1970: 1_784_179_200))
        #expect(request.codexHistoryDays == 30)
        #expect(request.codexHistoryDays == request.configuration.codexHistoryDays)

        let recorder = SpendDashboardHorizonRecorder()
        let loadRequest = SpendDashboardLoadRequest(
            configuration: configuration,
            capturedInputs: [],
            unavailableSourceIDs: [],
            codexRequests: [Self.account(id: "routine", cacheIdentity: "routine-cache")],
            codexHistoryDays: request.codexHistoryDays,
            now: Date(timeIntervalSince1970: 1_784_179_200),
            force: false)
        _ = await SpendDashboardSource.load(
            loadRequest,
            codexSnapshotLoader: { context in
                await recorder.recordSnapshot(context.historyDays)
                return Self.snapshot(now: context.now)
            },
            codexActivityLoader: { _ in nil })

        // The scanning loader observes exactly one bounded horizon: no hidden
        // second request escalates to the full year.
        #expect(await recorder.snapshotHistoryDays == [30])
    }

    // MARK: - Test B — explicit All consumer may request 365

    @Test
    func `selecting the All range captures and scans the full horizon`() async throws {
        let store = try Self.makeStore(suite: "all-range")
        store.settings.costUsageHistoryDays = 30
        let controller = try Self.sharedController(for: store, suite: "all-range")

        #expect(store.spendDashboardExtendedCodexHistoryRequired == false)
        #expect(SpendDashboardSource.configuration(settings: store.settings, store: store).codexHistoryDays == 30)

        controller.selectDays(SpendDashboardSource.scanDays)

        // The 365-day request is intentional and attributable to the All range.
        #expect(store.spendDashboardExtendedCodexHistoryRequired == true)
        let configuration = SpendDashboardSource.configuration(settings: store.settings, store: store)
        #expect(configuration.codexHistoryDays == SpendDashboardSource.scanDays)

        let request = await SpendDashboardSource.makeRequest(
            settings: store.settings,
            store: store,
            mode: .refreshMissing,
            now: Date(timeIntervalSince1970: 1_784_179_200))
        #expect(request.codexHistoryDays == SpendDashboardSource.scanDays)

        let recorder = SpendDashboardHorizonRecorder()
        let loadRequest = SpendDashboardLoadRequest(
            configuration: configuration,
            capturedInputs: [],
            unavailableSourceIDs: [],
            codexRequests: [Self.account(id: "all", cacheIdentity: "all-cache")],
            codexHistoryDays: request.codexHistoryDays,
            now: Date(timeIntervalSince1970: 1_784_179_200),
            force: false)
        _ = await SpendDashboardSource.load(
            loadRequest,
            codexSnapshotLoader: { context in
                await recorder.recordSnapshot(context.historyDays)
                return Self.snapshot(now: context.now)
            },
            codexActivityLoader: { _ in nil })
        #expect(await recorder.snapshotHistoryDays == [SpendDashboardSource.scanDays])
    }

    // MARK: - Test C — broader established history satisfies narrower consumption

    @Test
    func `established broader cache satisfies a narrower requirement without rescanning`() async throws {
        let store = try Self.makeStore(suite: "superset-reuse")
        store.settings.costUsageHistoryDays = 30
        let controller = try Self.sharedController(for: store, suite: "superset-reuse")
        let accounts = [Self.account(id: "account", cacheIdentity: "cache-account")]
        let advanceRecorder = SpendDashboardHorizonRecorder()
        // An established cache reports no pending work regardless of horizon.
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            Self.status(pending: false, key: "complete", processedBytes: 100)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, historyDays in
            await advanceRecorder.recordAdvance(historyDays)
            return Self.status(pending: false, key: "complete", processedBytes: 100)
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in await Task.yield() }

        controller.selectDays(SpendDashboardSource.scanDays)
        #expect(SpendDashboardSource.configuration(settings: store.settings, store: store).codexHistoryDays == 365)
        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .automatic)
        await Self.waitUntil { store.spendDashboardCodexCostCatchUpTask == nil }

        controller.selectDays(30)
        #expect(SpendDashboardSource.configuration(settings: store.settings, store: store).codexHistoryDays == 30)
        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .automatic)
        await Self.waitUntil { store.spendDashboardCodexCostCatchUpTask == nil }

        // Neither the broader nor the narrower run needed a scan pass: the
        // established history already covered both scopes.
        #expect(await advanceRecorder.advanceHistoryDays == [])
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Test D — narrower history cannot satisfy a broader explicit request

    @Test
    func `explicit broader request schedules new work after narrower history`() async throws {
        let store = try Self.makeStore(suite: "narrow-to-broad")
        store.settings.costUsageHistoryDays = 30
        let controller = try Self.sharedController(for: store, suite: "narrow-to-broad")
        let accounts = [Self.account(id: "account", cacheIdentity: "cache-account")]
        var completedCacheIdentities: Set<String> = []
        let advanceRecorder = SpendDashboardHorizonRecorder()
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { account in
            let complete = completedCacheIdentities.contains(account.cacheIdentity)
            return Self.status(
                pending: !complete,
                key: complete ? "complete" : "pending",
                processedBytes: complete ? 100 : 25)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { account, _, historyDays in
            await advanceRecorder.recordAdvance(historyDays)
            completedCacheIdentities.insert(account.cacheIdentity)
            return Self.status(pending: false, key: "complete", processedBytes: 100)
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in await Task.yield() }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }

        // Establish the narrower history first.
        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .automatic)
        await Self.waitUntil { store.spendDashboardCodexCostCatchUpTask == nil }
        #expect(await advanceRecorder.advanceHistoryDays == [30])

        // The explicit broader request must schedule additional work under the
        // proper hard scope instead of treating the 30-day data as complete.
        completedCacheIdentities.removeAll()
        controller.selectDays(SpendDashboardSource.scanDays)
        let configuration = SpendDashboardSource.configuration(settings: store.settings, store: store)
        #expect(configuration.codexHistoryDays == SpendDashboardSource.scanDays)
        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .automatic)
        await Self.waitUntil { store.spendDashboardCodexCostCatchUpTask == nil }

        #expect(await advanceRecorder.advanceHistoryDays == [30, SpendDashboardSource.scanDays])
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Test E — background/dashboard-not-visible scenario

    @Test
    func `background synchronization without a visible dashboard stays bounded`() async throws {
        // No shared controller selection exists here: this is the launch-time
        // background path (`applySharedSpendDashboardConfiguration` effects:
        // synchronize + makeRequest) with the spend system active but the
        // dashboard never opened to its All range.
        let store = try Self.makeStore(suite: "background-bounded")
        store.settings.costUsageHistoryDays = 30
        let accounts = [Self.account(id: "account", cacheIdentity: "cache-account")]
        var completedCacheIdentities: Set<String> = []
        let advanceRecorder = SpendDashboardHorizonRecorder()
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { account in
            let complete = completedCacheIdentities.contains(account.cacheIdentity)
            return Self.status(
                pending: !complete,
                key: complete ? "complete" : "pending",
                processedBytes: complete ? 100 : 25)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { account, _, historyDays in
            await advanceRecorder.recordAdvance(historyDays)
            completedCacheIdentities.insert(account.cacheIdentity)
            return Self.status(pending: false, key: "complete", processedBytes: 100)
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in await Task.yield() }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }

        let request = await SpendDashboardSource.makeRequest(
            settings: store.settings,
            store: store,
            mode: .refreshMissing,
            now: Date(timeIntervalSince1970: 1_784_179_200))
        #expect(request.codexHistoryDays == 30)

        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: accounts)
        await Self.waitUntil { store.spendDashboardCodexCostCatchUpTask == nil }

        // Routine background work observes exactly one bounded horizon.
        #expect(await advanceRecorder.advanceHistoryDays == [30])
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Helpers

    private static func makeStore(suite: String) throws -> UsageStore {
        let settings = testSettingsStore(
            suiteName: "SpendDashboardCodexHistoryHorizonTests-\(suite)")
        settings.costUsageEnabled = true
        let metadata = try #require(ProviderRegistry.shared.metadata[.codex])
        settings.setProviderEnabled(provider: .codex, metadata: metadata, enabled: true)
        return UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
    }

    private static func sharedController(for store: UsageStore, suite: String) throws -> SpendDashboardController {
        let defaults = try #require(UserDefaults(
            suiteName: "SpendDashboardCodexHistoryHorizonTests-controller-\(suite)-\(UUID().uuidString)"))
        defaults.removePersistentDomain(
            forName: "SpendDashboardCodexHistoryHorizonTests-controller-\(suite)")
        let controller = SpendDashboardController(
            userDefaults: defaults,
            requestBuilder: { _ in
                SpendDashboardLoadRequest(
                    configuration: SpendDashboardConfiguration(
                        costUsageEnabled: false,
                        providerIDs: [],
                        codexAccountIdentities: []),
                    capturedInputs: [],
                    unavailableSourceIDs: [],
                    codexRequests: [],
                    now: Date(timeIntervalSince1970: 1_784_179_200),
                    force: false)
            })
        store.sharedSpendDashboardControllerStorage = controller
        return controller
    }

    private static func account(
        id: String,
        cacheIdentity: String) -> CodexSpendScanRequest
    {
        CodexSpendScanRequest(
            id: id,
            displayName: "Codex · \(id)",
            source: .profileHome(path: "/synthetic/\(id)"),
            homePath: "/synthetic/\(id)",
            authFingerprint: nil,
            authFileWasReadable: false,
            cacheIdentity: cacheIdentity)
    }

    nonisolated static func snapshot(now: Date) -> CostUsageTokenSnapshot {
        CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 0,
            last30DaysCostUSD: 0,
            daily: [],
            updatedAt: now)
    }

    private static func status(
        pending: Bool,
        key: String,
        processedBytes: Int64) -> CostUsageFetcher.CodexScanCatchUpStatus
    {
        CostUsageFetcher.CodexScanCatchUpStatus(
            pending: pending,
            progressKey: key,
            processedBytes: processedBytes,
            totalBytes: 100,
            completedFiles: pending ? 0 : 1,
            totalFiles: 1)
    }

    private static func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1000 {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        Issue.record("Timed out waiting for Spend Dashboard Codex history horizon")
    }
}

private actor SpendDashboardHorizonRecorder {
    private(set) var snapshotHistoryDays: [Int] = []
    private(set) var advanceHistoryDays: [Int] = []

    func recordSnapshot(_ historyDays: Int) {
        self.snapshotHistoryDays.append(historyDays)
    }

    func recordAdvance(_ historyDays: Int) {
        self.advanceHistoryDays.append(historyDays)
    }
}
