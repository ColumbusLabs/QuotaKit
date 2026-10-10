import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct CodexCostCatchUpRecoveryTests {
    @Test(arguments: [false, true], ["complete", "repeat", "progress", "cycle"])
    func `workers restore a full budget once and keep the terminal stall guard`(
        dashboard: Bool,
        scenario: String) async throws
    {
        let store = try UsageStoreSpendDashboardCodexCostCatchUpTests.makeStore(suite: "recovery-workers")
        defer {
            store.cancelCodexCostCatchUp()
            store.cancelSpendDashboardCodexCostCatchUp()
        }
        store.settings.backgroundWorkLowPowerModePreference = .off
        let accounts = [UsageStoreSpendDashboardCodexCostCatchUpTests.account(
            id: "fixture",
            cacheIdentity: "fixture")]
        let stillStalled = scenario != "complete"
        var keys = switch scenario {
        case "progress": ["advanced", "advanced", "further", "further"]
        case "cycle": ["advanced", "initial"]
        default: ["advanced", "advanced", stillStalled ? "advanced" : "complete"]
        }
        // The primary worker retains QuotaKit's three bounded same-key retries for
        // concurrently appended session tails; the dashboard stops at its first terminal stall.
        if !dashboard, scenario == "repeat" || scenario == "progress" {
            let lastKey = try #require(keys.last)
            keys += Array(repeating: lastKey, count: 2)
        }
        var advances = 0
        var budgets: [TimeInterval] = []
        var sleeps: [TimeInterval] = []
        let initial = CostUsageFetcher.CodexScanCatchUpStatus(
            pending: true,
            progressKey: "initial")
        let advance: @MainActor () -> CostUsageFetcher.CodexScanCatchUpStatus = {
            advances += 1
            return .init(
                pending: advances < keys.count || stillStalled,
                progressKey: keys[min(advances - 1, keys.count - 1)],
                yieldedBeforeFileAttempt: advances != 1)
        }
        store._test_codexCostCatchUpBudgetObserver = { budgets.append($0) }
        if dashboard {
            store._test_spendDashboardCodexCostCatchUpActiveDuration = 1.999
            store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in initial }
            store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in advance() }
            store._test_spendDashboardCodexCostCatchUpSleepOverride = { sleeps.append($0) }
            store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
            store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts)
            await store.spendDashboardCodexCostCatchUpTask?.value
        } else {
            store._test_codexCostCatchUpActiveDuration = 1.999
            store._test_codexCostCatchUpStatusOverride = { _ in
                advances >= 3 && !stillStalled ? .init(
                    pending: false,
                    progressKey: "complete") : initial
            }
            store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in advance() }
            store._test_codexCostCatchUpSleepOverride = { sleeps.append($0) }
            store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
            store._test_tokenUsageSnapshotLoaderOverride = { _, _, now, _, _ in
                guard advances >= 3, !stillStalled else { throw CostUsageError.cachedSnapshotUnavailable }
                return CostUsageTokenSnapshot(
                    sessionTokens: 0,
                    sessionCostUSD: nil,
                    last30DaysTokens: 0,
                    last30DaysCostUSD: nil,
                    historyCoverageIsEstablished: true,
                    daily: [],
                    updatedAt: now)
            }
            store.startCodexCostCatchUpIfNeeded()
            await store.codexCostCatchUpTask?.value
        }
        #expect(advances == keys.count)
        #expect(budgets.count == keys.count)
        #expect(budgets.first == 2)
        #expect(abs((budgets.dropFirst().first ?? 0) - 0.001) < 0.000001)
        if scenario == "cycle" {
            #expect(sleeps.allSatisfy { $0 == 0 })
        } else {
            #expect(budgets.dropFirst(2).first == 2)
            #expect(sleeps.contains { abs($0 - 3.998 * 999) < 0.000001 })
        }
        let activity = dashboard ? store.spendDashboardCodexCostCatchUpActivity : store.codexCostCatchUpActivity
        #expect(activity?.phase == (stillStalled ? .paused : .complete))
        #expect(activity?.pauseReason == (stillStalled ? .noProgress : nil))
    }

    @Test(arguments: [false, true])
    func `a user stop during recovery cooldown prevents the extra pass`(dashboard: Bool) async throws {
        let store = try UsageStoreSpendDashboardCodexCostCatchUpTests.makeStore(suite: "recovery-stop")
        defer {
            store.cancelCodexCostCatchUp()
            store.cancelSpendDashboardCodexCostCatchUp()
        }
        store.settings.backgroundWorkLowPowerModePreference = .off
        let accounts = [UsageStoreSpendDashboardCodexCostCatchUpTests.account(
            id: "fixture",
            cacheIdentity: "fixture")]
        var advances = 0
        let status = CostUsageFetcher.CodexScanCatchUpStatus(
            pending: true,
            progressKey: "same",
            yieldedBeforeFileAttempt: true)
        if dashboard {
            store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in status }
            store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in advances += 1; return status }
            store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
            store._test_spendDashboardCodexCostCatchUpSleepOverride = { delay in
                if delay > 0 { store.stopSpendDashboardCodexCostCatchUp() }
            }
            store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts)
            await store.spendDashboardCodexCostCatchUpTask?.value
        } else {
            store._test_codexCostCatchUpStatusOverride = { _ in status }
            store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in advances += 1; return status }
            store._test_cachedCodexTokenSnapshotLoaderOverride = { _, _, _ in nil }
            store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
            store._test_codexCostCatchUpSleepOverride = { delay in
                if delay > 0 { store.stopCodexCostCatchUp() }
            }
            store.startCodexCostCatchUpIfNeeded()
            await store.codexCostCatchUpTask?.value
        }
        #expect(advances == 1)
        #expect((dashboard ? store.spendDashboardCodexCostCatchUpActivity : store.codexCostCatchUpActivity)?
            .pauseReason == .user)
    }

    @Test
    func `an ambient refresh completes a sleeping automatic catch-up without another pass`() async throws {
        let store = try UsageStoreSpendDashboardCodexCostCatchUpTests.makeStore(suite: "primary-sleep-completion")
        defer { store.cancelCodexCostCatchUp() }
        store.settings.backgroundWorkLowPowerModePreference = .off
        store._test_codexCostCatchUpActiveDuration = 2
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        var statusReads = 0
        var advances = 0
        store._test_codexCostCatchUpStatusOverride = { _ in
            statusReads += 1
            if statusReads == 1 { return .init(pending: true, progressKey: "initial") }
            return .init(pending: false, progressKey: "complete", completionIsConfirmed: true)
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            advances += 1
            return .init(pending: true, progressKey: "advanced")
        }
        store._test_codexCostCatchUpSleepOverride = { delay in
            guard delay > 0 else { return }
            try await Task.sleep(for: .seconds(60))
        }

        store.startCodexCostCatchUpIfNeeded()
        let worker = try #require(store.codexCostCatchUpTask)
        for _ in 0..<1000 where !store.codexCostCatchUpIsWaiting {
            await Task.yield()
        }
        #expect(store.codexCostCatchUpIsWaiting)

        store.startCodexCostCatchUpIfNeeded(afterRefreshing: .codex)
        let check = try #require(store.codexCostCatchUpCompletionCheckTask)
        await check.value
        await worker.value

        #expect(advances == 1)
        #expect(store.codexCostCatchUpActivity?.phase == .complete)
        #expect(store.codexCostCatchUpActivity?.pauseReason == nil)
        #expect(store.codexCostCatchUpTask == nil)
        #expect(store.codexCostCatchUpToken == nil)
    }

    @Test
    func `a refresh during an ambient completion read forces a second status read`() async throws {
        let store = try UsageStoreSpendDashboardCodexCostCatchUpTests.makeStore(suite: "primary-completion-revision")
        let reads = CatchUpCompletionReadGate<Void>()
        defer { store.cancelCodexCostCatchUp(); reads.close() }
        store.settings.backgroundWorkLowPowerModePreference = .off
        store._test_codexCostCatchUpActiveDuration = 2
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        let pending = CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "pending")
        let completed = CostUsageFetcher.CodexScanCatchUpStatus(
            pending: false,
            progressKey: "complete",
            completionIsConfirmed: true)
        var statusReads = 0
        var gateNextRead = false
        var advances = 0
        store._test_codexCostCatchUpStatusOverride = { _ in
            statusReads += 1
            if statusReads == 1 { return pending }
            if gateNextRead {
                gateNextRead = false
                try? await reads.load()
                return completed
            }
            return pending
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            advances += 1
            return pending
        }
        store._test_codexCostCatchUpSleepOverride = { delay in
            guard delay > 0 else { return }
            try await Task.sleep(for: .seconds(60))
        }

        store.startCodexCostCatchUpIfNeeded()
        let worker = try #require(store.codexCostCatchUpTask)
        let workerToken = store.codexCostCatchUpToken
        for _ in 0..<1000 where !store.codexCostCatchUpIsWaiting {
            await Task.yield()
        }
        #expect(store.codexCostCatchUpIsWaiting)

        gateNextRead = true
        store.startCodexCostCatchUpIfNeeded(afterRefreshing: .codex)
        let check = try #require(store.codexCostCatchUpCompletionCheckTask)
        try await reads.waitForPendingCount(1)
        store.startCodexCostCatchUpIfNeeded(afterRefreshing: .codex)
        reads.resume(returning: ())
        await check.value

        #expect(statusReads == 3)
        #expect(advances == 1)
        #expect(store.codexCostCatchUpActivity?.phase == .indexing)
        #expect(store.codexCostCatchUpTask != nil)
        #expect(store.codexCostCatchUpToken == workerToken)
        store.cancelCodexCostCatchUp()
        await worker.value
    }

    @Test
    func `a confirmed completion clears a stalled ambient catch-up without a worker token`() async throws {
        let store = try UsageStoreSpendDashboardCodexCostCatchUpTests.makeStore(suite: "primary-stall-completion")
        defer { store.cancelCodexCostCatchUp() }
        let pending = CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "stalled")
        store._test_codexCostCatchUpStatusOverride = { _ in pending }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in pending }
        store._test_codexCostCatchUpSleepOverride = { _ in }
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        store.startCodexCostCatchUpIfNeeded(mode: .accelerated)
        await store.codexCostCatchUpTask?.value
        #expect(store.codexCostCatchUpActivity?.pauseReason == .noProgress)
        #expect(store.codexCostCatchUpToken == nil)

        store._test_codexCostCatchUpStatusOverride = { _ in .init(
            pending: false,
            progressKey: "complete",
            completionIsConfirmed: true) }
        store.startCodexCostCatchUpIfNeeded(afterRefreshing: .codex)
        await store.codexCostCatchUpCompletionCheckTask?.value

        #expect(store.codexCostCatchUpActivity?.phase == .complete)
        #expect(store.codexCostCatchUpActivity?.pauseReason == nil)
        #expect(store.codexCostCatchUpTask == nil)
        #expect(store.codexCostCatchUpToken == nil)
    }

    @Test
    func `an account refresh completes a sleeping automatic dashboard catch-up`() async throws {
        let store = try UsageStoreSpendDashboardCodexCostCatchUpTests.makeStore(suite: "dashboard-sleep-completion")
        defer { store.cancelSpendDashboardCodexCostCatchUp() }
        store.settings.backgroundWorkLowPowerModePreference = .off
        store._test_spendDashboardCodexCostCatchUpActiveDuration = 2
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        let accounts = [UsageStoreSpendDashboardCodexCostCatchUpTests.account(
            id: "fixture",
            cacheIdentity: "fixture")]
        var statusReads = 0
        var advances = 0
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            statusReads += 1
            if statusReads == 1 { return .init(pending: true, progressKey: "initial") }
            return .init(pending: false, progressKey: "complete", completionIsConfirmed: true)
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in
            advances += 1
            return .init(pending: true, progressKey: "advanced")
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { delay in
            guard delay > 0 else { return }
            try await Task.sleep(for: .seconds(60))
        }

        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts)
        let worker = try #require(store.spendDashboardCodexCostCatchUpTask)
        for _ in 0..<1000 where store.spendDashboardCodexCostCatchUpWaitingContext == nil {
            await Task.yield()
        }
        #expect(store.spendDashboardCodexCostCatchUpWaitingContext != nil)

        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: accounts)
        let check = try #require(store.spendDashboardCodexCostCatchUpCompletionProbeTask)
        await check.value
        await worker.value

        #expect(advances == 1)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.phase == .complete)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.pauseReason == nil)
        #expect(store.spendDashboardCodexCostCatchUpTask == nil)
        #expect(store.spendDashboardCodexCostCatchUpToken == nil)
    }

    @Test
    func `a refresh during dashboard completion reading rechecks newly appended tail work`() async throws {
        let store = try UsageStoreSpendDashboardCodexCostCatchUpTests.makeStore(suite: "dashboard-completion-revision")
        let reads = CatchUpCompletionReadGate<Void>()
        defer { store.cancelSpendDashboardCodexCostCatchUp(); reads.close() }
        let accounts = [UsageStoreSpendDashboardCodexCostCatchUpTests.account(
            id: "fixture",
            cacheIdentity: "fixture")]
        let pending = CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "pending")
        let completed = CostUsageFetcher.CodexScanCatchUpStatus(
            pending: false,
            progressKey: "complete",
            completionIsConfirmed: true)
        var gateNextRead = false
        var statusReads = 0
        var advances = 0
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            statusReads += 1
            if gateNextRead {
                gateNextRead = false
                try? await reads.load()
                return completed
            }
            return pending
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in
            advances += 1
            return pending
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .accelerated)
        await store.spendDashboardCodexCostCatchUpTask?.value
        #expect(store.spendDashboardCodexCostCatchUpActivity?.pauseReason == .noProgress)

        gateNextRead = true
        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: accounts)
        let check = try #require(store.spendDashboardCodexCostCatchUpCompletionProbeTask)
        try await reads.waitForPendingCount(1)
        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: accounts)
        reads.resume(returning: ())
        await check.value

        #expect(statusReads == 3)
        #expect(advances == 1)
        #expect(store.spendDashboardCodexCostCatchUpActivity?.pauseReason == .noProgress)
        #expect(store.spendDashboardCodexCostCatchUpTask == nil)
    }

    @Test(arguments: ["unconfirmed", "pending", "scope-mismatch", "unavailable", "new-account", "settings"])
    func `unproven or changed-scope results preserve the paused dashboard`(kind: String) async throws {
        let store = try UsageStoreSpendDashboardCodexCostCatchUpTests.makeStore(suite: "completion-guards")
        defer { store.cancelSpendDashboardCodexCostCatchUp() }
        let accounts = [UsageStoreSpendDashboardCodexCostCatchUpTests.account(
            id: "fixture",
            cacheIdentity: "fixture")]
        var advances = 0
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in .init(
            pending: true,
            progressKey: "same") }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in
            advances += 1
            return .init(
                pending: true,
                progressKey: "same")
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        store.startSpendDashboardCodexCostCatchUpIfNeeded(
            accounts: accounts,
            mode: .accelerated)
        await store.spendDashboardCodexCostCatchUpTask?.value
        let activity = store.spendDashboardCodexCostCatchUpActivity
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            .init(
                pending: kind == "pending",
                progressKey: kind,

                completionIsConfirmed: !["unconfirmed", "scope-mismatch", "unavailable"].contains(kind))
        }
        if kind == "settings" { store.settings.costUsageHistoryDays = 365 }
        let current = kind == "new-account"
            ? [UsageStoreSpendDashboardCodexCostCatchUpTests.account(
                id: "other",
                cacheIdentity: "other")] : accounts
        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: current)
        await store.spendDashboardCodexCostCatchUpTask?.value
        #expect(store.spendDashboardCodexCostCatchUpActivity == activity)
        #expect(advances == 1)
        #expect(store.spendDashboardCodexCostCatchUpTask == nil)
    }

    @Test
    func `previously complete accounts do not need a new scan to clear another account stall`() async throws {
        let store = try UsageStoreSpendDashboardCodexCostCatchUpTests.makeStore(suite: "completion-multiple")
        defer { store.cancelSpendDashboardCodexCostCatchUp() }
        let accounts = ["one", "two"].map {
            UsageStoreSpendDashboardCodexCostCatchUpTests.account(
                id: $0,
                cacheIdentity: $0)
        }
        var advances = 0
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { account in
            .init(
                pending: account.id == "two",
                progressKey: account.id,

                completionIsConfirmed: account.id == "one")
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in
            advances += 1
            return .init(
                pending: true,
                progressKey: "two")
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        store.startSpendDashboardCodexCostCatchUpIfNeeded(
            accounts: accounts,
            mode: .accelerated)
        await store.spendDashboardCodexCostCatchUpTask?.value
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { account in
            .init(
                pending: false,
                progressKey: account.id,

                completionIsConfirmed: true)
        }
        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: accounts)
        await store.spendDashboardCodexCostCatchUpCompletionProbeTask?.value
        #expect(store.spendDashboardCodexCostCatchUpActivity?.phase == .complete)
        #expect(advances == 1)
    }

    @Test(arguments: ["accounts", "settings", "stop", "refresh", "cancel"])
    func `a changed owner cannot be overwritten by a completion read`(action: String) async throws {
        let store = try UsageStoreSpendDashboardCodexCostCatchUpTests.makeStore(suite: "completion-race")
        defer { store.cancelSpendDashboardCodexCostCatchUp() }
        let accounts = [UsageStoreSpendDashboardCodexCostCatchUpTests.account(
            id: "fixture",
            cacheIdentity: "fixture")]
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in .init(
            pending: true,
            progressKey: "same") }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in .init(
            pending: true,
            progressKey: "same") }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        store.startSpendDashboardCodexCostCatchUpIfNeeded(
            accounts: accounts,
            mode: .accelerated)
        await store.spendDashboardCodexCostCatchUpTask?.value
        var continuation: CheckedContinuation<Void, Never>?
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            await withCheckedContinuation { continuation = $0 }
            return .init(
                pending: false,
                progressKey: "complete",

                completionIsConfirmed: true)
        }
        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: accounts)
        let task = try #require(store.spendDashboardCodexCostCatchUpCompletionProbeTask)
        for _ in 0..<1000 {
            if continuation != nil { break }
            await Task.yield()
        }
        let read = try #require(continuation)
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            .init(pending: true, progressKey: "same")
        }
        switch action {
        case "accounts":
            store.synchronizeSpendDashboardCodexCostCatchUp(accounts: [
                UsageStoreSpendDashboardCodexCostCatchUpTests.account(id: "other", cacheIdentity: "other"),
            ])
        case "settings": store.settings.costUsageHistoryDays = 365
        case "stop": store.stopSpendDashboardCodexCostCatchUp()
        case "refresh":
            let previousToken = store.spendDashboardCodexCostCatchUpToken
            store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts)
            #expect(store.spendDashboardCodexCostCatchUpToken != previousToken)
        default: store.cancelSpendDashboardCodexCostCatchUp()
        }
        read.resume()
        await task.value
        await store.spendDashboardCodexCostCatchUpTask?.value
        let reason = store.spendDashboardCodexCostCatchUpActivity?.pauseReason
        #expect(reason == (action == "cancel" ? nil : action == "stop" ? .user : .noProgress))
        #expect(store.spendDashboardCodexCostCatchUpTask == nil)
    }
}

@MainActor
private final class CatchUpCompletionReadGate<Value: Sendable> {
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
        throw NSError(domain: "CatchUpCompletionReadGate", code: 1)
    }

    func resume(returning value: Value) {
        guard !self.pending.isEmpty else {
            Issue.record("No catch-up completion read is pending")
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
