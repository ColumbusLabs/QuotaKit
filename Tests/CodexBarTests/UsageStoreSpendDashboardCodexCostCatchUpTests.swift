import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct UsageStoreSpendDashboardCodexCostCatchUpTests {
    @Test
    func `automatic sleep uses active scan duration instead of awaited latency`() async throws {
        let store = try Self.makeStore(suite: "active-duration")
        store.settings.backgroundWorkLowPowerModePreference = .off
        var sleeps: [TimeInterval] = []
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            .init(pending: true, progressKey: "pending")
        }
        store._test_spendDashboardCodexCostCatchUpActiveDuration = 2
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in
            try await Task.sleep(for: .milliseconds(20))
            return .init(pending: true, progressKey: "progressed")
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { delay in
            sleeps.append(delay)
            if sleeps.count == 2 { throw CancellationError() }
        }
        store.startSpendDashboardCodexCostCatchUpIfNeeded(
            accounts: [Self.account(id: "account", cacheIdentity: "cache-account")])
        let task = try #require(store.spendDashboardCodexCostCatchUpTask)
        await task.value
        #expect(sleeps == [1998, 1998])
    }

    @Test(arguments: [CodexCostCatchUpMode.automatic, .accelerated])
    func `app low power preference reaches successive catch-up passes`(mode: CodexCostCatchUpMode) async throws {
        let store = try Self.makeStore(suite: "app-low-power-worker")
        store.settings.backgroundWorkLowPowerModePreference = .on
        var sleeps: [TimeInterval] = []
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "pending")
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in
            CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "progressed")
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { delay in
            sleeps.append(delay)
            if sleeps.count == 2 { throw CancellationError() }
        }
        store.startSpendDashboardCodexCostCatchUpIfNeeded(
            accounts: [Self.account(id: "account", cacheIdentity: "cache-account")], mode: mode)
        let task = try #require(store.spendDashboardCodexCostCatchUpTask)
        await task.value
        #expect(sleeps.count == 2)
        if mode == .automatic {
            #expect(sleeps.allSatisfy { $0 >= 1800 })
        } else {
            #expect(sleeps == [0, 0])
        }
    }

    @Test
    func `invalidated pass retires its orphaned indexing activity`() async throws {
        let store = try Self.makeStore(suite: "invalidated-activity")
        let gate = SpendDashboardPendingLoads<CostUsageFetcher.CodexScanCatchUpStatus>()
        defer {
            store.cancelSpendDashboardCodexCostCatchUp()
            gate.close()
        }
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            Self.status(pending: true, key: "pending", processedBytes: 100)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in try await gate.load() }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in await Task.yield() }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }

        store.startSpendDashboardCodexCostCatchUpIfNeeded(
            accounts: [Self.account(id: "account", cacheIdentity: "cache-account")], mode: .accelerated)
        let task = try #require(store.spendDashboardCodexCostCatchUpTask)
        try await gate.waitForPendingCount(1)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.phase == .indexing)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.fractionCompleted == 1)
        let revision = store.settings.costUsageSettingsRevision
        store.settings.costUsageHistoryDays = store.settings.costUsageHistoryDays == 7 ? 30 : 7
        #expect(store.settings.costUsageSettingsRevision != revision)
        gate.resume(returning: Self.status(pending: false, key: "complete", processedBytes: 100))
        await task.value

        #expect(store.spendDashboardCodexCostCatchUpTask == nil)
        #expect(store.spendDashboardCodexCostCatchUpActivity == nil)
    }

    @Test
    func `combined low power and thermal pressure publishes thermal pause without scanning`() async throws {
        let store = try Self.makeStore(suite: "combined-thermal-pause")
        var advanceCount = 0
        var sleepDurations: [TimeInterval] = []
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            Self.status(pending: true, key: "pending", processedBytes: 25)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in
            advanceCount += 1
            return Self.status(pending: false, key: "complete", processedBytes: 100)
        }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.battery, true, .serious) }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { duration in
            sleepDurations.append(duration)
            throw CancellationError()
        }

        store.startSpendDashboardCodexCostCatchUpIfNeeded(
            accounts: [Self.account(id: "account", cacheIdentity: "cache-account")])
        let task = try #require(store.spendDashboardCodexCostCatchUpTask)
        await task.value

        #expect(store.spendDashboardCodexCostCatchUpActivity?.phase == .paused)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.pauseReason == .thermal)
        #expect(sleepDurations == [CodexCostCatchUpPolicy.constrainedRetryDelay])
        #expect(advanceCount == 0)
    }

    @Test
    func `dashboard catch-up advances every account cache and publishes a reload revision`() async throws {
        let store = try Self.makeStore(suite: "all-accounts")
        let accounts = [
            Self.account(id: "first", cacheIdentity: "cache-first"),
            Self.account(id: "second", cacheIdentity: "cache-second"),
        ]
        let baselineConfiguration = SpendDashboardSource.configuration(settings: store.settings, store: store)
        var completedCacheIdentities: Set<String> = []
        var statusAccounts: [String] = []
        var advancedAccounts: [String] = []
        var receivedHistoryDays: [Int] = []
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { account in
            statusAccounts.append(account.id)
            let complete = completedCacheIdentities.contains(account.cacheIdentity)
            return Self.status(
                pending: !complete,
                key: complete ? "complete-\(account.id)" : "pending-\(account.id)",
                processedBytes: complete ? 100 : 25)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { account, _, historyDays in
            advancedAccounts.append(account.id)
            receivedHistoryDays.append(historyDays)
            completedCacheIdentities.insert(account.cacheIdentity)
            return Self.status(
                pending: false,
                key: "complete-\(account.id)",
                processedBytes: 100)
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in
            await Task.yield()
        }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = {
            (.battery, true, .serious)
        }

        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .accelerated)
        await Self.waitUntil {
            store.spendDashboardCodexCostCatchUpTask == nil
        }

        let replacementConfiguration = SpendDashboardSource.configuration(settings: store.settings, store: store)
        #expect(statusAccounts == ["first", "second"])
        #expect(advancedAccounts == ["first", "second"])
        #expect(receivedHistoryDays == [30, 30])
        #expect(store.spendDashboardCodexCostCatchUpRevision == 1)
        #expect(baselineConfiguration.sourceRevisions != replacementConfiguration.sourceRevisions)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.phase == .complete)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.mode == .accelerated)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.fractionCompleted == 1)
        #expect(store.memoryPressureReliefTask != nil)
    }

    @Test(arguments: [1, 7, 29, 123, 248, 365])
    func `dashboard catch-up uses the configured history window`(historyDays: Int) async throws {
        let receivedHistoryDays = try await Self.receivedHistoryDays(
            configuredHistoryDays: historyDays,
            suite: "configured-\(historyDays)")

        #expect(receivedHistoryDays == historyDays)
    }

    @Test
    func `startup ambient dashboard load keeps the configured history after primary catch-up completes`() throws {
        let store = try Self.makeStore(suite: "startup-history-selector")
        store.settings.codexActiveSource = .liveSystem
        store.settings.costUsageHistoryDays = 30

        #expect(store.spendDashboardCodexHistoryDays == 30)

        store.codexCostCatchUpActivity = CodexCostCatchUpActivity(
            phase: .complete,
            mode: .automatic,
            processedBytes: 100,
            totalBytes: 100,
            completedFiles: 1,
            totalFiles: 1,
            pauseReason: nil,
            staleSnapshotUpdatedAt: nil)

        // #160: convergence must not widen routine work to the full scan window.
        #expect(store.spendDashboardCodexHistoryDays == 30)
    }

    @Test
    func `managed dashboard cache uses the configured history window`() throws {
        let store = try Self.makeStore(suite: "managed-history-selector")
        store.settings.codexActiveSource = .managedAccount(id: UUID())
        store.settings.costUsageHistoryDays = 30

        #expect(store.spendDashboardCodexHistoryDays == 30)
    }

    @Test
    func `expanding the configured history restarts the active catch-up scope`() throws {
        let store = try Self.makeStore(suite: "history-context")
        let accounts = [Self.account(id: "account", cacheIdentity: "cache-account")]
        store.settings.costUsageHistoryDays = 30
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            Self.status(pending: true, key: "pending", processedBytes: 25)
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in
            try await Task.sleep(for: .seconds(60))
        }

        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .accelerated)
        let originalToken = try #require(store.spendDashboardCodexCostCatchUpToken)

        // #160: 30-day work cannot satisfy a 123-day scope, so the worker must
        // restart under the expanded horizon rather than keep the old context.
        store.settings.costUsageHistoryDays = 123
        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: accounts)
        let replacementToken = try #require(store.spendDashboardCodexCostCatchUpToken)

        #expect(replacementToken != originalToken)
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    @Test
    func `a stalled account cache does not prevent a sibling cache from advancing`() async throws {
        let store = try Self.makeStore(suite: "stalled-sibling")
        let accounts = [
            Self.account(id: "stalled", cacheIdentity: "cache-stalled"),
            Self.account(id: "healthy", cacheIdentity: "cache-healthy"),
        ]
        var advancedAccounts: [String] = []
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { account in
            Self.status(
                pending: true,
                key: "pending-\(account.id)",
                processedBytes: 25)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { account, _, _ in
            advancedAccounts.append(account.id)
            if account.id == "stalled" {
                return Self.status(
                    pending: true,
                    key: "pending-stalled",
                    processedBytes: 25)
            }
            return Self.status(
                pending: false,
                key: "complete-healthy",
                processedBytes: 100)
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in
            await Task.yield()
        }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = {
            (.ac, false, .nominal)
        }

        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .accelerated)
        await Self.waitUntil {
            store.spendDashboardCodexCostCatchUpTask == nil
        }

        #expect(advancedAccounts == ["stalled", "healthy"])
        #expect(store.spendDashboardCodexCostCatchUpRevision == 1)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.phase == .paused)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.pauseReason == .noProgress)
    }

    @Test
    func `a no-progress pass does not publish a reload revision`() async throws {
        let store = try Self.makeStore(suite: "no-progress-revision")
        let accounts = [Self.account(id: "stalled", cacheIdentity: "cache-stalled")]
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            Self.status(pending: true, key: "unchanged", processedBytes: 25)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in
            Self.status(pending: true, key: "unchanged", processedBytes: 25)
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in
            await Task.yield()
        }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = {
            (.ac, false, .nominal)
        }

        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .accelerated)
        await Self.waitUntil {
            store.spendDashboardCodexCostCatchUpTask == nil
        }

        #expect(store.spendDashboardCodexCostCatchUpRevision == 0)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.phase == .paused)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.pauseReason == .noProgress)
    }

    @Test
    func `dashboard catch-up stalls a cache that revisits an earlier semantic state`() async throws {
        let store = try Self.makeStore(suite: "cyclic-progress")
        let accounts = [Self.account(id: "cyclic", cacheIdentity: "cache-cyclic")]
        let progressKeys = ["validation-1", "validation-2", "validation-0"]
        var advanceCount = 0
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            Self.status(pending: true, key: "validation-0", processedBytes: 25)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in
            advanceCount += 1
            return Self.status(
                pending: true,
                key: progressKeys[min(advanceCount - 1, progressKeys.count - 1)],
                processedBytes: 25)
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in
            await Task.yield()
        }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = {
            (.ac, false, .nominal)
        }

        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .accelerated)
        await Self.waitUntil {
            store.spendDashboardCodexCostCatchUpTask == nil
        }

        #expect(advanceCount == 3)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.phase == .paused)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.pauseReason == .noProgress)
    }

    @Test
    func `a same-mode dashboard reload does not queue a worker after the completing task`() async throws {
        let store = try Self.makeStore(suite: "same-mode-restart")
        let accounts = [Self.account(id: "account", cacheIdentity: "cache-account")]
        var statusLoadCount = 0
        var advanceCount = 0
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            statusLoadCount += 1
            return Self.status(
                pending: statusLoadCount == 2,
                key: "status-\(statusLoadCount)",
                processedBytes: statusLoadCount == 2 ? 25 : 100)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in
            advanceCount += 1
            return Self.status(pending: false, key: "complete", processedBytes: 100)
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in
            await Task.yield()
        }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = {
            (.ac, false, .nominal)
        }

        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts)
        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts)
        await Self.waitUntil {
            store.spendDashboardCodexCostCatchUpTask == nil && statusLoadCount == 1
        }

        #expect(statusLoadCount == 1)
        #expect(advanceCount == 0)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.phase == .complete)
    }

    @Test
    func `normal and dashboard requests share the primary cache worker`() async throws {
        let store = try Self.makeStore(suite: "primary-cache-worker")
        let account = Self.account(
            id: "live",
            cacheIdentity: "live-cache",
            source: .liveSystem)
        store.settings.codexActiveSource = .liveSystem
        var advanceCount = 0
        var receivedHistoryDays: Int?
        var completed = false
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
            Self.status(
                pending: !completed,
                key: completed ? "complete" : "pending",
                processedBytes: completed ? 100 : 25)
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, historyDays in
            advanceCount += 1
            receivedHistoryDays = historyDays
            completed = true
            return Self.status(pending: false, key: "complete", processedBytes: 100)
        }
        store._test_codexCostCatchUpSleepOverride = { _ in await Task.yield() }
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }

        store.startCodexCostCatchUpIfNeeded(mode: .automatic)
        store.synchronizeSpendDashboardCodexCostCatchUp(
            accounts: [account],
            preferredMode: .accelerated)
        await Self.waitUntil {
            store.codexCostCatchUpTask == nil
                && receivedHistoryDays == store.settings.costUsageHistoryDays
        }

        #expect(advanceCount == 1)
        #expect(store.spendDashboardCodexCostCatchUpTask == nil)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.phase == .complete)
        #expect(store.spendDashboardCodexCostCatchUpRevision == 1)
        store.cancelSpendDashboardCodexCostCatchUp()
        store.cancelCodexCostCatchUp()
    }

    @Test
    func `dashboard synchronization keeps an accelerated account queue accelerated`() throws {
        let store = try Self.makeStore(suite: "preserve-mode")
        let accounts = [Self.account(id: "account", cacheIdentity: "cache-account")]

        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .accelerated)
        let originalToken = store.spendDashboardCodexCostCatchUpToken
        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: accounts)

        #expect(originalToken != nil)
        #expect(store.spendDashboardCodexCostCatchUpToken == originalToken)
        #expect(store.spendDashboardCodexCostCatchUpMode == .accelerated)
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    @Test
    func `stopping an active pass clears a queued restart`() throws {
        let store = try Self.makeStore(suite: "stop-clears-restart")
        store.spendDashboardCodexCostCatchUpTask = Task {}
        store.spendDashboardCodexCostCatchUpPassIsRunning = true
        store.spendDashboardCodexCostCatchUpRestartRequested = true

        store.stopSpendDashboardCodexCostCatchUp()

        #expect(store.spendDashboardCodexCostCatchUpStopRequested)
        #expect(!store.spendDashboardCodexCostCatchUpRestartRequested)
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    @Test
    func `synchronization after an explicit stop does not restart the worker`() throws {
        let store = try Self.makeStore(suite: "stop-stays-durable")
        let accounts = [Self.account(id: "account", cacheIdentity: "cache-account")]
        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .accelerated)
        store.stopSpendDashboardCodexCostCatchUp()

        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: accounts)

        #expect(store.spendDashboardCodexCostCatchUpStopRequested)
        #expect(store.spendDashboardCodexCostCatchUpTask == nil)
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    @Test
    func `visible synchronization upgrades an automatic worker to accelerated`() throws {
        let store = try Self.makeStore(suite: "upgrade-automatic-on-visible")
        let accounts = [Self.account(id: "account", cacheIdentity: "cache-account")]
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = {
            (.ac, false, .nominal)
        }

        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .automatic)
        let originalToken = store.spendDashboardCodexCostCatchUpToken
        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: accounts, preferredMode: .accelerated)

        #expect(originalToken != nil)
        #expect(store.spendDashboardCodexCostCatchUpTask != nil)
        #expect(store.spendDashboardCodexCostCatchUpMode == .accelerated)
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    @Test
    func `visible synchronization does not bypass low power mode`() throws {
        let store = try Self.makeStore(suite: "visible-respects-low-power")
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = {
            (.battery, true, .nominal)
        }

        store.synchronizeSpendDashboardCodexCostCatchUp(
            accounts: [Self.account(id: "account", cacheIdentity: "cache-account")],
            preferredMode: .accelerated)

        #expect(store.spendDashboardCodexCostCatchUpMode == .automatic)
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    @Test
    func `visible synchronization does not bypass serious thermal pressure`() throws {
        let store = try Self.makeStore(suite: "visible-respects-thermal-pressure")
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = {
            (.ac, false, .serious)
        }

        store.synchronizeSpendDashboardCodexCostCatchUp(
            accounts: [Self.account(id: "account", cacheIdentity: "cache-account")],
            preferredMode: .accelerated)

        #expect(store.spendDashboardCodexCostCatchUpMode == .automatic)
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    @Test
    func `visible synchronization preserves an explicitly accelerated worker in low power mode`() throws {
        let store = try Self.makeStore(suite: "explicit-acceleration-in-low-power")
        let accounts = [Self.account(id: "account", cacheIdentity: "cache-account")]
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = {
            (.battery, true, .serious)
        }
        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .accelerated)

        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: accounts, preferredMode: .accelerated)

        #expect(store.spendDashboardCodexCostCatchUpMode == .accelerated)
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    @Test
    func `hidden synchronization downgrades an accelerated worker to automatic`() throws {
        let store = try Self.makeStore(suite: "downgrade-accelerated-on-hidden")
        let accounts = [Self.account(id: "account", cacheIdentity: "cache-account")]

        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .accelerated)
        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: accounts, preferredMode: .automatic)

        #expect(store.spendDashboardCodexCostCatchUpTask != nil)
        #expect(store.spendDashboardCodexCostCatchUpMode == .automatic)
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    @Test
    func `stopped synchronization still clears an invalid account scope`() throws {
        let store = try Self.makeStore(suite: "stopped-invalid-account-scope")
        let accounts = [Self.account(id: "account", cacheIdentity: "cache-account")]
        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .accelerated)
        store.stopSpendDashboardCodexCostCatchUp()

        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: [])

        #expect(store.spendDashboardCodexCostCatchUpTask == nil)
        #expect(!store.spendDashboardCodexCostCatchUpStopRequested)
    }

    @Test(arguments: [false, true])
    func `superseded pass completion cannot clear the replacement pass ownership`(
        cancelled: Bool) async throws
    {
        let store = try Self.makeStore(suite: "superseded-pass-\(cancelled)")
        let oldGate = SpendDashboardPendingLoads<CostUsageFetcher.CodexScanCatchUpStatus>()
        let replacementGate = SpendDashboardPendingLoads<CostUsageFetcher.CodexScanCatchUpStatus>()
        defer {
            store.cancelSpendDashboardCodexCostCatchUp()
            oldGate.close()
            replacementGate.close()
        }
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            Self.status(pending: true, key: "pending", processedBytes: 25)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { account, _, _ in
            if account.id == "old" {
                let result = try await oldGate.load()
                if cancelled {
                    throw CancellationError()
                }
                return result
            }
            return try await replacementGate.load()
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in await Task.yield() }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }

        store.startSpendDashboardCodexCostCatchUpIfNeeded(
            accounts: [Self.account(id: "old", cacheIdentity: "cache-old")], mode: .accelerated)
        let oldTask = try #require(store.spendDashboardCodexCostCatchUpTask)
        try await oldGate.waitForPendingCount(1)
        store.startSpendDashboardCodexCostCatchUpIfNeeded(
            accounts: [Self.account(id: "replacement", cacheIdentity: "cache-replacement")], mode: .accelerated)
        let replacementTask = try #require(store.spendDashboardCodexCostCatchUpTask)
        let replacementToken = try #require(store.spendDashboardCodexCostCatchUpToken)
        try await replacementGate.waitForPendingCount(1)
        #expect(store.spendDashboardCodexCostCatchUpPassIsRunning)

        oldGate.resume(returning: Self.status(pending: false, key: "old-complete", processedBytes: 100))
        await oldTask.value

        #expect(store.spendDashboardCodexCostCatchUpToken == replacementToken)
        #expect(store.spendDashboardCodexCostCatchUpPassIsRunning)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.phase == .indexing)
        store.stopSpendDashboardCodexCostCatchUp()
        #expect(store.spendDashboardCodexCostCatchUpTask != nil)
        #expect(store.spendDashboardCodexCostCatchUpToken == replacementToken)
        replacementGate.resume(returning: Self.status(pending: false, key: "complete", processedBytes: 100))
        await replacementTask.value
        #expect(store.spendDashboardCodexCostCatchUpTask == nil)
        #expect(!store.spendDashboardCodexCostCatchUpPassIsRunning)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.pauseReason == .user)
    }

    @Test
    func `an error completed before replacement cannot publish the obsolete revision`() async throws {
        let store = try Self.makeStore(suite: "superseded-error-revision")
        let oldGate = SpendDashboardPendingLoads<Result<CostUsageFetcher.CodexScanCatchUpStatus, any Error>>()
        let replacementGate = SpendDashboardPendingLoads<CostUsageFetcher.CodexScanCatchUpStatus>()
        defer {
            store.cancelSpendDashboardCodexCostCatchUp()
            oldGate.close()
            replacementGate.close()
        }
        var oldAdvanceCount = 0
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            Self.status(pending: true, key: "pending", processedBytes: 25)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { account, _, _ in
            guard account.id == "old" else { return try await replacementGate.load() }
            oldAdvanceCount += 1
            if oldAdvanceCount == 1 {
                return Self.status(pending: true, key: "progress", processedBytes: 50)
            }
            return try await oldGate.load().get()
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in await Task.yield() }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }

        store.startSpendDashboardCodexCostCatchUpIfNeeded(
            accounts: [Self.account(id: "old", cacheIdentity: "cache-old")], mode: .accelerated)
        let oldTask = try #require(store.spendDashboardCodexCostCatchUpTask)
        try await oldGate.waitForPendingCount(1)
        #expect(oldAdvanceCount == 2)
        // The executor can finish before cancellation while its MainActor continuation is still queued.
        oldGate.resume(returning: .failure(NSError(domain: "SyntheticCatchUp", code: 2)))
        store.startSpendDashboardCodexCostCatchUpIfNeeded(
            accounts: [Self.account(id: "replacement", cacheIdentity: "cache-replacement")], mode: .accelerated)
        // An error published before replacement is valid; only revisions after
        // replacement starts can belong to the obsolete worker.
        let revision = store.spendDashboardCodexCostCatchUpRevision
        let replacementTask = try #require(store.spendDashboardCodexCostCatchUpTask)
        let replacementToken = try #require(store.spendDashboardCodexCostCatchUpToken)
        await oldTask.value
        try await replacementGate.waitForPendingCount(1)

        #expect(store.spendDashboardCodexCostCatchUpRevision == revision)
        #expect(store.spendDashboardCodexCostCatchUpToken == replacementToken)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.pauseReason == nil)
        #expect(store.spendDashboardCodexCostCatchUpPassIsRunning)
        replacementGate.resume(returning: Self.status(pending: false, key: "complete", processedBytes: 100))
        await replacementTask.value
        #expect(store.spendDashboardCodexCostCatchUpRevision == revision + 1)
    }

    private static func makeStore(suite: String) throws -> UsageStore {
        let settings = testSettingsStore(
            suiteName: "UsageStoreSpendDashboardCodexCostCatchUpTests-\(suite)", userDefaults: InMemoryUserDefaults())
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

    private static func receivedHistoryDays(
        configuredHistoryDays: Int,
        suite: String) async throws -> Int
    {
        let store = try Self.makeStore(suite: suite)
        let account = Self.account(id: "account", cacheIdentity: "cache-account")
        store.settings.costUsageHistoryDays = configuredHistoryDays
        var completed = false
        var receivedHistoryDays: Int?
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            Self.status(
                pending: !completed,
                key: completed ? "complete" : "pending",
                processedBytes: completed ? 100 : 25)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, historyDays in
            receivedHistoryDays = historyDays
            completed = true
            return Self.status(pending: false, key: "complete", processedBytes: 100)
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in
            await Task.yield()
        }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = {
            (.battery, true, .serious)
        }

        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: [account], mode: .accelerated)
        await Self.waitUntil {
            store.spendDashboardCodexCostCatchUpTask == nil
        }

        return try #require(receivedHistoryDays)
    }

    private static func account(
        id: String,
        cacheIdentity: String,
        source: CodexActiveSource = .profileHome(path: "/synthetic/default"))
        -> CodexSpendScanRequest
    {
        CodexSpendScanRequest(
            id: id,
            displayName: "Codex · \(id)",
            source: source,
            homePath: "/synthetic/\(id)",
            authFingerprint: nil,
            authFileWasReadable: false,
            cacheIdentity: cacheIdentity)
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
        Issue.record("Timed out waiting for Spend Dashboard Codex cost catch-up")
    }
}

@MainActor
private final class SpendDashboardPendingLoads<Value: Sendable> {
    private var pending: [CheckedContinuation<Value, any Error>] = []

    func load() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            self.pending.append(continuation)
        }
    }

    func waitForPendingCount(_ expected: Int) async throws {
        for _ in 0..<1000 {
            if self.pending.count == expected { return }
            await Task.yield()
        }
        throw NSError(domain: "SpendDashboardPendingLoads", code: 1)
    }

    func resume(returning value: Value) {
        guard !self.pending.isEmpty else {
            Issue.record("No pending Spend Dashboard load to resume")
            return
        }
        self.pending.removeFirst().resume(returning: value)
    }

    func close() {
        for continuation in self.pending {
            continuation.resume(throwing: CancellationError())
        }
        self.pending.removeAll()
    }
}
