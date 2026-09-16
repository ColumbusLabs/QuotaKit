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

    // MARK: - Test A — shared primary worker receives visible 90 demand

    @Test
    func `shared primary worker receives visible 90 demand`() async throws {
        let store = try Self.makeStore(suite: "primary-shared-90")
        store.settings.codexActiveSource = .liveSystem
        store.settings.costUsageHistoryDays = 30
        let controller = try Self.sharedController(for: store, suite: "primary-shared-90")
        controller.selectDays(90)
        controller.activateHistoryDemandForVisibleDashboard()
        #expect(store.spendDashboardCodexHistoryDays == 90)

        let account = Self.liveAccount(id: "live", cacheIdentity: "live-cache")
        let primaryRecorder = SpendDashboardHorizonRecorder()
        let independentRecorder = SpendDashboardHorizonRecorder()
        var completed = false
        Self.installPrimaryCatchUpOverrides(
            store: store,
            recorder: primaryRecorder,
            completed: { completed },
            markCompleted: { completed = true })
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, historyDays in
            await independentRecorder.recordAdvance(historyDays)
            return Self.status(pending: false, key: "independent", processedBytes: 100)
        }

        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: [account])
        await Self.waitUntil { store.codexCostCatchUpTask == nil }
        // Allow the mirrored dashboard activity/revision to publish.
        await Self.waitUntil { store.spendDashboardCodexCostCatchUpUsesPrimaryWorker }

        #expect(await primaryRecorder.advanceHistoryDays == [90])
        #expect(await independentRecorder.advanceHistoryDays == [])
        #expect(store.spendDashboardCodexCostCatchUpTask == nil)
        #expect(store.spendDashboardCodexCostCatchUpUsesPrimaryWorker == true)
        #expect(store.codexCostCatchUpHistoryDays == 90)
        controller.deactivateHistoryDemand()
        store.cancelCodexCostCatchUp()
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Test B — shared primary worker receives visible All demand

    @Test
    func `shared primary worker receives visible All demand`() async throws {
        let store = try Self.makeStore(suite: "primary-shared-all")
        store.settings.codexActiveSource = .liveSystem
        store.settings.costUsageHistoryDays = 30
        let controller = try Self.sharedController(for: store, suite: "primary-shared-all")
        controller.selectDays(SpendDashboardSource.scanDays)
        controller.activateHistoryDemandForVisibleDashboard()
        #expect(store.spendDashboardCodexHistoryDays == SpendDashboardSource.scanDays)

        let account = Self.liveAccount(id: "live", cacheIdentity: "live-cache")
        let primaryRecorder = SpendDashboardHorizonRecorder()
        let independentRecorder = SpendDashboardHorizonRecorder()
        var completed = false
        Self.installPrimaryCatchUpOverrides(
            store: store,
            recorder: primaryRecorder,
            completed: { completed },
            markCompleted: { completed = true })
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, historyDays in
            await independentRecorder.recordAdvance(historyDays)
            return Self.status(pending: false, key: "independent", processedBytes: 100)
        }

        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: [account])
        await Self.waitUntil { store.codexCostCatchUpTask == nil }
        await Self.waitUntil { store.spendDashboardCodexCostCatchUpUsesPrimaryWorker }

        #expect(await primaryRecorder.advanceHistoryDays == [SpendDashboardSource.scanDays])
        #expect(await independentRecorder.advanceHistoryDays == [])
        #expect(store.spendDashboardCodexCostCatchUpTask == nil)
        #expect(store.spendDashboardCodexCostCatchUpUsesPrimaryWorker == true)
        #expect(store.codexCostCatchUpHistoryDays == SpendDashboardSource.scanDays)
        controller.deactivateHistoryDemand()
        store.cancelCodexCostCatchUp()
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Test F — generic primary refresh preserves visible All demand

    @Test
    func `generic Codex refresh preserves visible shared All demand`() async throws {
        let store = try Self.makeStore(suite: "primary-shared-all-generic-refresh")
        store.settings.codexActiveSource = .liveSystem
        store.settings.costUsageHistoryDays = 30
        let controller = try Self.sharedController(
            for: store,
            suite: "primary-shared-all-generic-refresh")
        controller.selectDays(SpendDashboardSource.scanDays)
        controller.activateHistoryDemandForVisibleDashboard()

        let account = Self.liveAccount(id: "live", cacheIdentity: "live-cache")
        let primaryRecorder = SpendDashboardHorizonRecorder()
        let independentRecorder = SpendDashboardHorizonRecorder()
        var completed = false
        Self.installPrimaryCatchUpOverrides(
            store: store,
            recorder: primaryRecorder,
            completed: { completed },
            markCompleted: { completed = true })
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, historyDays in
            await independentRecorder.recordAdvance(historyDays)
            return Self.status(pending: false, key: "independent", processedBytes: 100)
        }

        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: [account])
        await Self.waitUntil { store.codexCostCatchUpTask == nil }
        #expect(await primaryRecorder.advanceHistoryDays == [SpendDashboardSource.scanDays])
        #expect(store.codexCostCatchUpHistoryDays == SpendDashboardSource.scanDays)

        // A normal refresh carries no explicit dashboard horizon. The primary authority must
        // still include the currently visible shared All demand.
        completed = false
        store.startCodexCostCatchUpIfNeeded(afterRefreshing: .codex)
        await Self.waitUntil { store.codexCostCatchUpTask == nil }

        #expect(await primaryRecorder.advanceHistoryDays == [
            SpendDashboardSource.scanDays,
            SpendDashboardSource.scanDays,
        ])
        #expect(await independentRecorder.advanceHistoryDays == [])
        #expect(store.codexCostCatchUpHistoryDays == SpendDashboardSource.scanDays)
        #expect(store.spendDashboardCodexCostCatchUpUsesPrimaryWorker)
        controller.deactivateHistoryDemand()
        store.cancelCodexCostCatchUp()
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Test G — generic primary start preserves visible 90 demand

    @Test
    func `generic Codex start preserves visible shared 90 demand`() async throws {
        let store = try Self.makeStore(suite: "primary-shared-90-generic-start")
        store.settings.codexActiveSource = .liveSystem
        store.settings.costUsageHistoryDays = 30
        let controller = try Self.sharedController(
            for: store,
            suite: "primary-shared-90-generic-start")
        controller.selectDays(90)
        controller.activateHistoryDemandForVisibleDashboard()

        let account = Self.liveAccount(id: "live", cacheIdentity: "live-cache")
        let primaryRecorder = SpendDashboardHorizonRecorder()
        let independentRecorder = SpendDashboardHorizonRecorder()
        var completed = false
        Self.installPrimaryCatchUpOverrides(
            store: store,
            recorder: primaryRecorder,
            completed: { completed },
            markCompleted: { completed = true })
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, historyDays in
            await independentRecorder.recordAdvance(historyDays)
            return Self.status(pending: false, key: "independent", processedBytes: 100)
        }

        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: [account])
        await Self.waitUntil { store.codexCostCatchUpTask == nil }
        #expect(await primaryRecorder.advanceHistoryDays == [90])
        #expect(store.codexCostCatchUpHistoryDays == 90)

        // This is the no-argument path used by stale cached-token hydration.
        completed = false
        store.startCodexCostCatchUpIfNeeded()
        await Self.waitUntil { store.codexCostCatchUpTask == nil }

        #expect(await primaryRecorder.advanceHistoryDays == [90, 90])
        #expect(await independentRecorder.advanceHistoryDays == [])
        #expect(store.codexCostCatchUpHistoryDays == 90)
        controller.deactivateHistoryDemand()
        store.cancelCodexCostCatchUp()
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Test H — mode transitions preserve visible shared All demand

    @Test
    func `primary mode transitions preserve visible shared All demand`() async throws {
        let store = try Self.makeStore(suite: "primary-shared-all-mode-transition")
        store.settings.codexActiveSource = .liveSystem
        store.settings.costUsageHistoryDays = 30
        let controller = try Self.sharedController(
            for: store,
            suite: "primary-shared-all-mode-transition")
        controller.selectDays(SpendDashboardSource.scanDays)
        controller.activateHistoryDemandForVisibleDashboard()

        let account = Self.liveAccount(id: "live", cacheIdentity: "live-cache")
        let primaryRecorder = SpendDashboardHorizonRecorder()
        var completed = false
        Self.installPrimaryCatchUpOverrides(
            store: store,
            recorder: primaryRecorder,
            completed: { completed },
            markCompleted: { completed = true })

        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: [account])
        await Self.waitUntil { store.codexCostCatchUpTask == nil }

        completed = false
        store.startAcceleratedCodexCostCatchUp()
        await Self.waitUntil { store.codexCostCatchUpTask == nil }
        #expect(store.codexCostCatchUpMode == .accelerated)

        completed = false
        store.returnCodexCostCatchUpToBackground()
        await Self.waitUntil { store.codexCostCatchUpTask == nil }

        #expect(await primaryRecorder.advanceHistoryDays == [
            SpendDashboardSource.scanDays,
            SpendDashboardSource.scanDays,
            SpendDashboardSource.scanDays,
        ])
        #expect(store.codexCostCatchUpHistoryDays == SpendDashboardSource.scanDays)
        #expect(store.codexCostCatchUpMode == .automatic)
        controller.deactivateHistoryDemand()
        store.cancelCodexCostCatchUp()
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Test C — closing All withdraws shared primary demand

    @Test
    func `closing All withdraws shared primary demand`() async throws {
        let store = try Self.makeStore(suite: "primary-shared-close")
        store.settings.codexActiveSource = .liveSystem
        store.settings.costUsageHistoryDays = 30
        let controller = try Self.sharedController(for: store, suite: "primary-shared-close")
        controller.selectDays(SpendDashboardSource.scanDays)
        controller.activateHistoryDemandForVisibleDashboard()

        let account = Self.liveAccount(id: "live", cacheIdentity: "live-cache")
        let primaryRecorder = SpendDashboardHorizonRecorder()
        var completed = false
        Self.installPrimaryCatchUpOverrides(
            store: store,
            recorder: primaryRecorder,
            completed: { completed },
            markCompleted: { completed = true })

        // Visible All converges the shared primary cache at 365.
        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: [account])
        await Self.waitUntil { store.codexCostCatchUpTask == nil }
        #expect(await primaryRecorder.advanceHistoryDays == [SpendDashboardSource.scanDays])
        #expect(store.codexCostCatchUpHistoryDays == SpendDashboardSource.scanDays)

        // Simulate SpendDashboardPane.onDisappear: demand clears, controller
        // re-scopes to routine, then routine catch-up synchronizes.
        controller.deactivateHistoryDemand()
        let routineConfiguration = SpendDashboardSource.configuration(settings: store.settings, store: store)
        #expect(routineConfiguration.codexHistoryDays == 30)
        controller.update(configuration: routineConfiguration)
        completed = false
        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: [account])
        await Self.waitUntil { store.codexCostCatchUpTask == nil }

        // The withdrawn 365 demand must not persist: the next primary pass
        // uses the routine 30-day horizon.
        #expect(await primaryRecorder.advanceHistoryDays == [SpendDashboardSource.scanDays, 30])
        #expect(store.codexCostCatchUpHistoryDays == 30)
        #expect(store.spendDashboardCodexCostCatchUpTask == nil)
        store.cancelCodexCostCatchUp()
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Test D — close re-scopes an in-flight 365 dashboard load

    @Test
    func `close re-scopes an in-flight 365 dashboard load`() async throws {
        let store = try Self.makeStore(suite: "close-inflight")
        store.settings.codexActiveSource = .liveSystem
        store.settings.costUsageHistoryDays = 30
        let loader = SpendDashboardHorizonLoaderGate()
        let controller = try Self.sharedGatedController(for: store, suite: "close-inflight", loader: loader)
        controller.selectDays(SpendDashboardSource.scanDays)
        controller.activateHistoryDemandForVisibleDashboard()

        // Visible All: desired scope is 365.
        let visibleConfiguration = SpendDashboardSource.configuration(settings: store.settings, store: store)
        #expect(visibleConfiguration.codexHistoryDays == SpendDashboardSource.scanDays)
        controller.update(configuration: visibleConfiguration)
        await Self.waitForLoaderPendingCount(1, gate: loader)
        #expect(await loader.historyDays == [SpendDashboardSource.scanDays])

        // Simulate the actual pane close lifecycle: deactivate, capture the
        // new routine configuration, feed it into the controller.
        controller.deactivateHistoryDemand()
        let routineConfiguration = SpendDashboardSource.configuration(settings: store.settings, store: store)
        #expect(routineConfiguration.codexHistoryDays == 30)
        controller.update(configuration: routineConfiguration)
        await Self.waitForLoaderPendingCount(2, gate: loader)
        #expect(await loader.historyDays == [SpendDashboardSource.scanDays, 30])

        // Release the stale 365 completion: hard-scope semantics must reject
        // it as the current desired state.
        await loader.resume(
            at: 0,
            result: SpendDashboardLoadResult(inputs: [Self.input(cost: 5)], failedSourceIDs: []))
        await Self.waitForLoaderPendingCount(1, gate: loader)
        #expect(controller.model.groups.isEmpty)
        #expect(controller.isRefreshing)
        #expect(controller.configuration == routineConfiguration)

        await loader.resume(
            at: 0,
            result: SpendDashboardLoadResult(inputs: [Self.input(cost: 9)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing }
        #expect(controller.model.groups.first?.totalCost == 9)
        #expect(controller.configuration == routineConfiguration)
        #expect(controller.configuration?.codexHistoryDays == 30)
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    // MARK: - Test E — close before the broad builder starts never loads 365

    @Test
    func `close before the broad builder starts never loads 365`() async throws {
        let store = try Self.makeStore(suite: "close-gated-builder")
        store.settings.codexActiveSource = .liveSystem
        store.settings.costUsageHistoryDays = 30
        let buildGate = SpendDashboardHorizonBuildGate()
        let loader = SpendDashboardHorizonLoaderGate()
        let controller = try Self.sharedGatedController(
            for: store,
            suite: "close-gated-builder",
            loader: loader,
            buildGate: buildGate)
        controller.selectDays(SpendDashboardSource.scanDays)
        controller.activateHistoryDemandForVisibleDashboard()

        let visibleConfiguration = SpendDashboardSource.configuration(settings: store.settings, store: store)
        #expect(visibleConfiguration.codexHistoryDays == SpendDashboardSource.scanDays)
        controller.update(configuration: visibleConfiguration)
        await Self.waitForBuildGate(buildGate)

        // Dashboard closes while the 365 request builder is still gated.
        controller.deactivateHistoryDemand()
        let routineConfiguration = SpendDashboardSource.configuration(settings: store.settings, store: store)
        #expect(routineConfiguration.codexHistoryDays == 30)
        controller.update(configuration: routineConfiguration)
        await buildGate.resume()
        await Self.waitForLoaderPendingCount(1, gate: loader)

        // The stale 365 request must never reach the expensive loader.
        #expect(await loader.historyDays == [30])

        await loader.resume(
            at: 0,
            result: SpendDashboardLoadResult(inputs: [Self.input(cost: 9)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing }
        #expect(controller.model.groups.first?.totalCost == 9)
        #expect(controller.configuration == routineConfiguration)
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    @Test
    func `stopping the controller clears ephemeral history demand`() throws {
        let store = try Self.makeStore(suite: "stop-clears-demand")
        let controller = try Self.sharedController(for: store, suite: "stop-clears-demand")
        controller.selectDays(SpendDashboardSource.scanDays)
        controller.activateHistoryDemandForVisibleDashboard()
        #expect(controller.isHistoryDemandActive)
        #expect(controller.activeRequestedHistoryDays == SpendDashboardSource.scanDays)

        controller.stop()

        #expect(!controller.isHistoryDemandActive)
        #expect(controller.activeRequestedHistoryDays == nil)
        #expect(controller.selectedDays == SpendDashboardSource.scanDays)
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

    /// Ambient live-system account sharing the primary Codex cache. Unlike
    /// `.profileHome`, this exercises the shared-primary worker rather than
    /// the independent dashboard worker.
    private static func liveAccount(
        id: String,
        cacheIdentity: String) -> CodexSpendScanRequest
    {
        CodexSpendScanRequest(
            id: id,
            displayName: "Codex · \(id)",
            source: .liveSystem,
            homePath: "/synthetic/\(id)",
            authFingerprint: nil,
            authFileWasReadable: false,
            cacheIdentity: cacheIdentity)
    }

    private static func installPrimaryCatchUpOverrides(
        store: UsageStore,
        recorder: SpendDashboardHorizonRecorder,
        completed: @escaping @MainActor () -> Bool,
        markCompleted: @escaping @MainActor () -> Void)
    {
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, now, _, _ in
            CostUsageTokenSnapshot(
                sessionTokens: 10,
                sessionCostUSD: 1,
                last30DaysTokens: 10,
                last30DaysCostUSD: 1,
                historyCoverageIsEstablished: true,
                daily: [CostUsageDailyReport.Entry(
                    date: "2026-07-30",
                    inputTokens: 4,
                    outputTokens: 6,
                    totalTokens: 10,
                    costUSD: 1,
                    modelsUsed: nil,
                    modelBreakdowns: nil)],
                updatedAt: now)
        }
        store._test_codexCostCatchUpStatusOverride = { _ in
            let done = completed()
            return Self.status(
                pending: !done,
                key: done ? "complete" : "pending",
                processedBytes: done ? 100 : 25)
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, historyDays in
            await recorder.recordAdvance(historyDays)
            markCompleted()
            return Self.status(pending: false, key: "complete", processedBytes: 100)
        }
        store._test_codexCostCatchUpSleepOverride = { _ in await Task.yield() }
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
    }

    private static func sharedGatedController(
        for store: UsageStore,
        suite: String,
        loader: SpendDashboardHorizonLoaderGate,
        buildGate: SpendDashboardHorizonBuildGate? = nil) throws -> SpendDashboardController
    {
        let defaults = try #require(UserDefaults(
            suiteName: "SpendDashboardCodexHistoryHorizonTests-gated-\(suite)-\(UUID().uuidString)"))
        defaults.removePersistentDomain(
            forName: "SpendDashboardCodexHistoryHorizonTests-gated-\(suite)")
        let controller = SpendDashboardController(
            userDefaults: defaults,
            requestBuilder: { mode in
                if let buildGate {
                    await buildGate.suspendOnce()
                }
                let configuration = SpendDashboardSource.configuration(
                    settings: store.settings,
                    store: store)
                return SpendDashboardLoadRequest(
                    configuration: configuration,
                    capturedInputs: [],
                    unavailableSourceIDs: [],
                    codexRequests: [],
                    codexHistoryDays: configuration.codexHistoryDays,
                    now: Date(timeIntervalSince1970: 1_784_179_200),
                    force: mode.forcesLoader)
            },
            loader: { request in await loader.load(request) })
        store.sharedSpendDashboardControllerStorage = controller
        return controller
    }

    private static func input(cost: Double) -> SpendDashboardModel.ProviderInput {
        let entry = CostUsageDailyReport.Entry(
            date: "2026-07-15",
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: 10,
            costUSD: cost,
            modelsUsed: nil,
            modelBreakdowns: nil)
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 10,
            last30DaysCostUSD: cost,
            daily: [entry],
            updatedAt: Date(timeIntervalSince1970: 1_784_179_200))
        return SpendDashboardModel.ProviderInput(
            provider: .codex,
            displayName: UsageProvider.codex.rawValue,
            snapshot: snapshot)
    }

    private static func waitForLoaderPendingCount(
        _ count: Int,
        gate: SpendDashboardHorizonLoaderGate) async
    {
        for _ in 0..<1000 {
            if await gate.pendingCount == count {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for \(count) pending horizon loads")
    }

    private static func waitForBuildGate(_ gate: SpendDashboardHorizonBuildGate) async {
        for _ in 0..<1000 {
            if await gate.isSuspended {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for horizon build gate")
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

private actor SpendDashboardHorizonLoaderGate {
    private var continuations: [CheckedContinuation<SpendDashboardLoadResult, Never>] = []
    private(set) var configurations: [SpendDashboardConfiguration] = []
    private(set) var historyDays: [Int] = []

    var pendingCount: Int {
        self.continuations.count
    }

    func load(_ request: SpendDashboardLoadRequest) async -> SpendDashboardLoadResult {
        self.configurations.append(request.configuration)
        self.historyDays.append(request.codexHistoryDays)
        return await withCheckedContinuation { continuation in
            self.continuations.append(continuation)
        }
    }

    func resume(at index: Int, result: SpendDashboardLoadResult) {
        self.continuations.remove(at: index).resume(returning: result)
    }
}

private actor SpendDashboardHorizonBuildGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didGate = false

    var isSuspended: Bool {
        self.continuation != nil
    }

    func suspend() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    /// Gates only the first builder invocation. Later builder calls (e.g. the
    /// routine 30-day rebuild after close) proceed immediately so the stale
    /// 365 request can be proven dead without deadlocking the follow-up.
    func suspendOnce() async {
        if self.didGate {
            return
        }
        self.didGate = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        self.continuation?.resume()
        self.continuation = nil
    }
}
