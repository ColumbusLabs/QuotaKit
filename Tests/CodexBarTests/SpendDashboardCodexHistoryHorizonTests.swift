import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

/// Deterministic regression coverage for
/// `ColumbusLabs/QuotaKit#160`: routine/background spend collection must not
/// silently expand Codex history scans to 365 days.
///
/// The horizon policy (`SpendDashboardSource.requiredCodexHistoryDays`) keeps
/// routine work bounded at the configured window. Only an ACTIVE visible
/// dashboard demand widens it via `max(routine, active)`: visible 90 with
/// configured 30 requires 90, visible All requires 365. Persisted
/// `SpendDashboardController.selectedDays` alone is presentation preference
/// and never widens background work. Every test observes horizons through the
/// existing loader/catch-up seams; worker completion uses a bounded 1ms
/// polling gate (no fixed wall-clock sleeps).
@MainActor
@Suite(.serialized)
struct SpendDashboardCodexHistoryHorizonTests {
    // MARK: - Policy units

    @Test
    func `routine horizons stay bounded without active demand`() {
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: 30,
            activeDashboardRequestedDays: nil) == 30)
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: 30,
            activeDashboardRequestedDays: 7) == 30)
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: 30,
            activeDashboardRequestedDays: 30) == 30)
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: 90,
            activeDashboardRequestedDays: 30) == 90)
    }

    @Test
    func `active 90 widens a configured 30 window`() {
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: 30,
            activeDashboardRequestedDays: 90) == 90)
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: 90,
            activeDashboardRequestedDays: 30) == 90)
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: 90,
            activeDashboardRequestedDays: 90) == 90)
    }

    @Test
    func `explicit active All demand selects the full scan window`() {
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: 30,
            activeDashboardRequestedDays: SpendDashboardSource.scanDays) == SpendDashboardSource.scanDays)
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: 90,
            activeDashboardRequestedDays: SpendDashboardSource.scanDays) == SpendDashboardSource.scanDays)
    }

    @Test
    func `explicitly configured full window stays full without dashboard demand`() {
        #expect(SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: SpendDashboardSource.scanDays,
            activeDashboardRequestedDays: nil) == SpendDashboardSource.scanDays)
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

    // MARK: - Test 1 — visible 90 expands a configured 30 window

    @Test
    func `visible 90 expands a configured 30 window`() async throws {
        let store = try Self.makeStore(suite: "visible-90")
        store.settings.costUsageHistoryDays = 30
        let controller = try Self.sharedController(for: store, suite: "visible-90")
        controller.selectDays(90)
        // Simulate SpendDashboardPane.onAppear: persisted 90 becomes active demand.
        controller.activateHistoryDemandForVisibleDashboard()

        let configuration = SpendDashboardSource.configuration(settings: store.settings, store: store)
        #expect(configuration.codexHistoryDays == 90)

        let request = await SpendDashboardSource.makeRequest(
            settings: store.settings,
            store: store,
            mode: .refreshMissing,
            now: Date(timeIntervalSince1970: 1_784_179_200))
        #expect(request.codexHistoryDays == 90)
        #expect(request.codexHistoryDays == request.configuration.codexHistoryDays)

        let recorder = SpendDashboardHorizonRecorder()
        let loadRequest = SpendDashboardLoadRequest(
            configuration: configuration,
            capturedInputs: [],
            unavailableSourceIDs: [],
            codexRequests: [Self.account(id: "visible-90", cacheIdentity: "visible-90-cache")],
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
        #expect(await recorder.snapshotHistoryDays == [90])
        controller.deactivateHistoryDemand()
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Test 2 — persisted All does NOT expand background launch while closed

    @Test
    func `persisted All does not expand background launch while dashboard is closed`() async throws {
        // Production sequence: user selected All, closed the dashboard, app
        // relaunched. The shared controller exists (materialized with persisted
        // 365) but the dashboard is NOT visible, so active demand stays nil.
        let store = try Self.makeStore(suite: "persisted-all-closed")
        store.settings.costUsageHistoryDays = 30
        let controller = try Self.sharedController(for: store, suite: "persisted-all-closed")
        controller.selectDays(SpendDashboardSource.scanDays)
        #expect(controller.selectedDays == SpendDashboardSource.scanDays)
        controller.deactivateHistoryDemand()

        #expect(store.spendDashboardExtendedCodexHistoryRequired == false)
        #expect(store.spendDashboardCodexHistoryDays == 30)
        let configuration = SpendDashboardSource.configuration(settings: store.settings, store: store)
        #expect(configuration.codexHistoryDays == 30)

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

        // Routine background work observes exactly the configured horizon even
        // though a materialized controller persists All.
        #expect(await advanceRecorder.advanceHistoryDays == [30])
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Test 3 — opening persisted All activates 365

    @Test
    func `opening persisted All activates the full horizon`() async throws {
        let store = try Self.makeStore(suite: "open-persisted-all")
        store.settings.costUsageHistoryDays = 30
        let controller = try Self.sharedController(for: store, suite: "open-persisted-all")
        controller.selectDays(SpendDashboardSource.scanDays)
        controller.deactivateHistoryDemand()
        #expect(SpendDashboardSource.configuration(settings: store.settings, store: store).codexHistoryDays == 30)

        // Simulate SpendDashboardPane.onAppear with persisted All.
        controller.activateHistoryDemandForVisibleDashboard()
        #expect(controller.activeRequestedHistoryDays == SpendDashboardSource.scanDays)
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
        controller.deactivateHistoryDemand()
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Test 4 — closing All returns to routine bound

    @Test
    func `closing All returns to the routine bound without rescanning`() async throws {
        let store = try Self.makeStore(suite: "close-all")
        store.settings.costUsageHistoryDays = 30
        let controller = try Self.sharedController(for: store, suite: "close-all")
        controller.selectDays(SpendDashboardSource.scanDays)
        // Visible All.
        controller.activateHistoryDemandForVisibleDashboard()
        #expect(SpendDashboardSource.configuration(settings: store.settings, store: store).codexHistoryDays == 365)

        // Simulate SpendDashboardPane.onDisappear: demand clears before routine sync.
        controller.deactivateHistoryDemand()
        #expect(controller.activeRequestedHistoryDays == nil)
        #expect(store.spendDashboardExtendedCodexHistoryRequired == false)
        #expect(store.spendDashboardCodexHistoryDays == 30)
        #expect(SpendDashboardSource.configuration(settings: store.settings, store: store).codexHistoryDays == 30)
        // Presentation preference survives closing: reopening restores All.
        #expect(controller.selectedDays == SpendDashboardSource.scanDays)

        // An established cache reports no pending work: closing must not cause
        // a 365 corpus rescan, only cheap manifest/status re-evaluation.
        let accounts = [Self.account(id: "account", cacheIdentity: "cache-account")]
        let advanceRecorder = SpendDashboardHorizonRecorder()
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            Self.status(pending: false, key: "complete", processedBytes: 100)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, historyDays in
            await advanceRecorder.recordAdvance(historyDays)
            return Self.status(pending: false, key: "complete", processedBytes: 100)
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in await Task.yield() }

        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: accounts)
        await Self.waitUntil { store.spendDashboardCodexCostCatchUpTask == nil }
        #expect(await advanceRecorder.advanceHistoryDays == [])
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Test 5 — visible 90 closes back to 30

    @Test
    func `visible 90 closes back to the routine bound`() async throws {
        let store = try Self.makeStore(suite: "visible-90-close")
        store.settings.costUsageHistoryDays = 30
        let controller = try Self.sharedController(for: store, suite: "visible-90-close")
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

        // Visible 90: active demand widens the worker to 90, never 365.
        controller.selectDays(90)
        controller.activateHistoryDemandForVisibleDashboard()
        #expect(SpendDashboardSource.configuration(settings: store.settings, store: store).codexHistoryDays == 90)
        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .automatic)
        await Self.waitUntil { store.spendDashboardCodexCostCatchUpTask == nil }
        #expect(await advanceRecorder.advanceHistoryDays == [90])

        // Close: demand clears before routine sync; next work uses 30.
        completedCacheIdentities.removeAll()
        controller.deactivateHistoryDemand()
        #expect(store.spendDashboardCodexHistoryDays == 30)
        #expect(SpendDashboardSource.configuration(settings: store.settings, store: store).codexHistoryDays == 30)
        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: accounts)
        await Self.waitUntil { store.spendDashboardCodexCostCatchUpTask == nil }

        #expect(await advanceRecorder.advanceHistoryDays == [90, 30])
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Test 6 — same-range cache directionality via the real scanner seam

    @Test
    func `scanner cache compatibility is directional across horizons`() throws {
        let calendar = Calendar(identifier: .gregorian)
        let until = Date(timeIntervalSince1970: 1_784_179_200)
        let narrowSince = try #require(calendar.date(byAdding: .day, value: -29, to: until))
        let midSince = try #require(calendar.date(byAdding: .day, value: -89, to: until))
        let wideSince = try #require(calendar.date(byAdding: .day, value: -364, to: until))
        let narrowRange = CostUsageScanner.CostUsageDayRange(since: narrowSince, until: until, calendar: calendar)
        let midRange = CostUsageScanner.CostUsageDayRange(since: midSince, until: until, calendar: calendar)
        let wideRange = CostUsageScanner.CostUsageDayRange(since: wideSince, until: until, calendar: calendar)

        var wideCache = CostUsageCache()
        wideCache.lastScanUnixMs = 1
        wideCache.scanSinceKey = wideRange.scanSinceKey
        wideCache.scanUntilKey = wideRange.scanUntilKey

        var midCache = CostUsageCache()
        midCache.lastScanUnixMs = 1
        midCache.scanSinceKey = midRange.scanSinceKey
        midCache.scanUntilKey = midRange.scanUntilKey

        var narrowCache = CostUsageCache()
        narrowCache.lastScanUnixMs = 1
        narrowCache.scanSinceKey = narrowRange.scanSinceKey
        narrowCache.scanUntilKey = narrowRange.scanUntilKey

        // Established broader history satisfies narrower consumption without rescanning.
        #expect(CostUsageScanner.requestedWindowExpandsCache(range: narrowRange, cache: wideCache) == false)
        #expect(CostUsageScanner.requestedWindowExpandsCache(range: narrowRange, cache: midCache) == false)
        // Narrower history cannot satisfy broader explicit requests.
        #expect(CostUsageScanner.requestedWindowExpandsCache(range: wideRange, cache: narrowCache) == true)
        #expect(CostUsageScanner.requestedWindowExpandsCache(range: midRange, cache: narrowCache) == true)
        #expect(CostUsageScanner.requestedWindowExpandsCache(range: wideRange, cache: midCache) == true)
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
