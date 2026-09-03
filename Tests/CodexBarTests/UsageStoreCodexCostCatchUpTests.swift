import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct UsageStoreCodexCostCatchUpTests {
    @Test
    func `incomplete refresh cannot replace an established same-scope snapshot`() throws {
        let store = try Self.makeStore(suite: "retains-established")
        store.publishTokenSnapshot(Self.tokenSnapshot(cost: 3, now: Date()), for: .codex)
        let establishedRevision = store.tokenSnapshotPublicationRevision(for: .codex)

        store.publishTokenSnapshot(
            Self.tokenSnapshot(
                cost: 9,
                now: Date().addingTimeInterval(1),
                historyCoverageIsEstablished: false),
            for: .codex)

        #expect(store.tokenSnapshot(for: .codex)?.last30DaysCostUSD == 3)
        #expect(store.tokenSnapshot(for: .codex)?.historyCoverageIsEstablished == true)
        #expect(store.tokenSnapshotPublicationRevision(for: .codex) == establishedRevision)

        store.publishTokenSnapshot(
            Self.tokenSnapshot(cost: 2, now: Date().addingTimeInterval(2)),
            for: .codex)

        // Completion is authoritative: it may correct an inflated partial estimate downward.
        #expect(store.tokenSnapshot(for: .codex)?.last30DaysCostUSD == 2)
        #expect(store.tokenSnapshotPublicationRevision(for: .codex) == establishedRevision + 1)
    }

    @Test
    func `incomplete refresh does not retain an established snapshot from another scope`() throws {
        let store = try Self.makeStore(suite: "scope-change")
        store.publishTokenSnapshot(Self.tokenSnapshot(cost: 3, now: Date()), for: .codex)

        store.settings.costUsageHistoryDays = 7
        store.publishTokenSnapshot(
            Self.tokenSnapshot(
                cost: 9,
                now: Date().addingTimeInterval(1),
                historyCoverageIsEstablished: false),
            for: .codex)

        #expect(store.tokenSnapshot(for: .codex)?.last30DaysCostUSD == 9)
        #expect(store.tokenSnapshot(for: .codex)?.historyCoverageIsEstablished == false)
    }

    @Test
    func `Codex transient failures retain the established snapshot for publication`() async throws {
        let store = try Self.makeStore(suite: "transient-failure-retention")
        var loadCount = 0
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, now, _, _ in
            loadCount += 1
            if loadCount == 1 {
                return Self.tokenSnapshot(cost: 130, now: now)
            }
            throw NSError(domain: "UsageStoreCodexCostCatchUpTests", code: 1)
        }
        store._test_codexCostCatchUpStatusOverride = { _ in
            CostUsageFetcher.CodexScanCatchUpStatus(pending: false, progressKey: "complete")
        }

        await store.refreshTokenUsage(.codex, force: true)
        await Self.waitUntil { store.codexCostCatchUpTask == nil }
        #expect(store.tokenSnapshot(for: .codex)?.last30DaysCostUSD == 130)

        // The failure gate suppresses the first stale-data error and surfaces
        // the repeated failure. Neither attempt is allowed to clear Codex's
        // complete publication.
        await store.refreshTokenUsage(.codex, force: true)
        await store.refreshTokenUsage(.codex, force: true)

        #expect(loadCount == 3)
        #expect(store.tokenSnapshot(for: .codex)?.last30DaysCostUSD == 130)
        #expect(store.tokenSnapshot(for: .codex)?.historyCoverageIsEstablished == true)
        #expect(store.tokenError(for: .codex) != nil)
    }

    @Test
    func `verified current day overlays established history without adopting partial coverage`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let establishedAt = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 30,
            hour: 10)))
        let candidateAt = establishedAt.addingTimeInterval(60)
        let historical = CostUsageDailyReport.Entry(
            date: "2026-07-29",
            inputTokens: 2,
            outputTokens: 2,
            totalTokens: 4,
            costUSD: 4,
            modelsUsed: nil,
            modelBreakdowns: nil)
        let establishedToday = CostUsageDailyReport.Entry(
            date: "2026-07-30",
            inputTokens: 4,
            outputTokens: 6,
            totalTokens: 10,
            costUSD: 3,
            modelsUsed: nil,
            modelBreakdowns: nil)
        let established = CostUsageTokenSnapshot(
            sessionTokens: 10,
            sessionCostUSD: 3,
            last30DaysTokens: 14,
            last30DaysCostUSD: 7,
            historyCoverageIsEstablished: true,
            daily: [historical, establishedToday],
            updatedAt: establishedAt)
        let candidate = Self.tokenSnapshot(
            cost: 9,
            now: candidateAt,
            historyCoverageIsEstablished: false)

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar))

        #expect(overlaid.historyCoverageIsEstablished)
        #expect(overlaid.sessionCostUSD == 9)
        #expect(overlaid.last30DaysCostUSD == 13)
        #expect(overlaid.last30DaysTokens == 14)
        #expect(overlaid.daily.first { $0.date == "2026-07-29" }?.costUSD == 4)
        #expect(overlaid.daily.first { $0.date == "2026-07-30" }?.costUSD == 9)
        #expect(overlaid.updatedAt == candidateAt)

        let staleCandidate = Self.tokenSnapshot(
            cost: 12,
            now: establishedAt.addingTimeInterval(-1),
            historyCoverageIsEstablished: false)
        #expect(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            staleCandidate,
            onto: established,
            calendar: calendar) == nil)
    }

    @Test
    func `cold partial catch-up publishes only monotonic lower-bound progress`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let firstAt = Date(timeIntervalSince1970: 1_700_000_000)
        let current = Self.tokenSnapshot(
            cost: 8,
            now: firstAt,
            historyCoverageIsEstablished: false)
        let advanced = Self.tokenSnapshot(
            cost: 130,
            now: firstAt.addingTimeInterval(1),
            historyCoverageIsEstablished: false)
        let regressed = Self.tokenSnapshot(
            cost: 3,
            now: firstAt.addingTimeInterval(2),
            historyCoverageIsEstablished: false)

        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            advanced,
            over: current,
            calendar: calendar)?.last30DaysCostUSD == 130)
        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            regressed,
            over: advanced,
            calendar: calendar) == nil)
    }

    @Test
    func `cold partial catch-up accepts a new-day session reset`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let beforeMidnight = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 1,
            hour: 23,
            minute: 59)))
        let current = Self.tokenSnapshot(
            cost: 130,
            now: beforeMidnight,
            historyCoverageIsEstablished: false)
        let afterMidnight = CostUsageTokenSnapshot(
            sessionTokens: 1,
            sessionCostUSD: 1,
            last30DaysTokens: 20,
            last30DaysCostUSD: 131,
            historyCoverageIsEstablished: false,
            daily: current.daily + [CostUsageDailyReport.Entry(
                date: "2026-09-02",
                inputTokens: 1,
                outputTokens: 0,
                totalTokens: 1,
                costUSD: 1,
                modelsUsed: nil,
                modelBreakdowns: nil)],
            updatedAt: beforeMidnight.addingTimeInterval(120))

        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            afterMidnight,
            over: current,
            calendar: calendar)?.sessionCostUSD == 1)
    }

    @Test
    func `bounded catch-up publishes a changed current day before final history completes`() async throws {
        let store = try Self.makeStore(suite: "publishes-final")
        var snapshotLoadCount = 0
        var statusLoadCount = 0
        var advanceCount = 0
        var sleepDurations: [TimeInterval] = []
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, now, _, _ in
            snapshotLoadCount += 1
            return Self.tokenSnapshot(cost: Double(snapshotLoadCount), now: now)
        }
        store._test_codexCostCatchUpStatusOverride = { _ in
            statusLoadCount += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: statusLoadCount == 1,
                progressKey: "status-\(statusLoadCount)")
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            advanceCount += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: advanceCount < 2,
                progressKey: "advance-\(advanceCount)")
        }
        store._test_codexCostCatchUpSleepOverride = { duration in
            sleepDurations.append(duration)
            await Task.yield()
        }
        store._test_codexCostCatchUpResourceStateOverride = {
            (.ac, false, .nominal)
        }

        await store.refreshTokenUsage(.codex, force: true)
        await Self.waitUntil {
            store.codexCostCatchUpTask == nil && snapshotLoadCount == 3
        }

        #expect(advanceCount == 2)
        #expect(statusLoadCount == 2)
        #expect(snapshotLoadCount == 3)
        #expect(sleepDurations.first == 8)
        #expect(store.tokenSnapshot(for: .codex)?.last30DaysCostUSD == 3)
        #expect(store.tokenSnapshotPublicationRevision(for: .codex) == 3)
        #expect(store.tokenError(for: .codex) == nil)
        #expect(store.memoryPressureReliefTask != nil)
    }

    @Test
    func `catch-up stops after one bounded pass that makes no progress`() async throws {
        let store = try Self.makeStore(suite: "no-progress")
        var snapshotLoadCount = 0
        var advanceCount = 0
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, now, _, _ in
            snapshotLoadCount += 1
            return Self.tokenSnapshot(cost: 1, now: now)
        }
        store._test_codexCostCatchUpStatusOverride = { _ in
            CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "unchanged")
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            advanceCount += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "unchanged")
        }
        store._test_codexCostCatchUpSleepOverride = { _ in
            await Task.yield()
        }
        store._test_codexCostCatchUpResourceStateOverride = {
            (.ac, false, .nominal)
        }

        await store.refreshTokenUsage(.codex, force: true)
        await Self.waitUntil {
            store.codexCostCatchUpTask == nil && advanceCount == 1
        }

        #expect(advanceCount == 1)
        #expect(snapshotLoadCount == 2)
        #expect(store.tokenSnapshot(for: .codex)?.last30DaysCostUSD == 1)
        #expect(store.tokenSnapshotPublicationRevision(for: .codex) == 1)
        #expect(store.codexCostCatchUpActivity?.phase == .paused)
        #expect(store.codexCostCatchUpActivity?.pauseReason == .noProgress)
    }

    @Test
    func `pending tail cannot overwrite a newer foreground publication`() async throws {
        let store = try Self.makeStore(suite: "foreground-race")
        var snapshotLoadCount = 0
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, now, _, _ in
            snapshotLoadCount += 1
            if snapshotLoadCount == 2 {
                store.publishTokenSnapshot(Self.tokenSnapshot(cost: 99, now: now), for: .codex)
            }
            return Self.tokenSnapshot(cost: Double(snapshotLoadCount), now: now)
        }
        store._test_codexCostCatchUpStatusOverride = { _ in
            CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "unchanged")
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "unchanged")
        }
        store._test_codexCostCatchUpSleepOverride = { _ in await Task.yield() }
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }

        await store.refreshTokenUsage(.codex, force: true)
        await Self.waitUntil { store.codexCostCatchUpTask == nil }

        #expect(snapshotLoadCount == 2)
        #expect(store.tokenSnapshot(for: .codex)?.last30DaysCostUSD == 99)
        #expect(store.tokenSnapshotPublicationRevision(for: .codex) == 2)
    }

    @Test
    func `catch-up stops when bounded progress revisits an earlier semantic state`() async throws {
        let store = try Self.makeStore(suite: "cyclic-progress")
        let progressKeys = ["validation-1", "validation-2", "validation-0"]
        var advanceCount = 0
        store._test_codexCostCatchUpStatusOverride = { _ in
            CostUsageFetcher.CodexScanCatchUpStatus(
                pending: true,
                progressKey: "validation-0")
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            advanceCount += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: true,
                progressKey: progressKeys[min(advanceCount - 1, progressKeys.count - 1)])
        }
        store._test_codexCostCatchUpSleepOverride = { _ in
            await Task.yield()
        }
        store._test_codexCostCatchUpResourceStateOverride = {
            (.ac, false, .nominal)
        }

        store.startCodexCostCatchUpIfNeeded(mode: .accelerated)
        await Self.waitUntil {
            store.codexCostCatchUpTask == nil
        }

        #expect(advanceCount == 3)
        #expect(store.codexCostCatchUpActivity?.phase == .paused)
        #expect(store.codexCostCatchUpActivity?.pauseReason == .noProgress)
    }

    @Test
    func `catch-up continues when existing complete file backlog advances`() async throws {
        let store = try Self.makeStore(suite: "existing-complete-backlog")
        let first = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1,
            size: 125,
            days: [:],
            parsedBytes: 125,
            codexScanFileId: "1:1",
            codexScanComplete: true)
        let second = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1,
            size: 125,
            days: [:],
            parsedBytes: 125,
            codexScanFileId: "2:2",
            codexScanComplete: true)
        let files = [
            "/sessions/first.jsonl": first,
            "/sessions/second.jsonl": second,
        ]
        var caches = [CostUsageCache(), CostUsageCache(), CostUsageCache()]
        caches[0].codexScanCompletedFiles = 0
        caches[1].codexScanCompletedFiles = 1
        caches[2].codexScanCompletedFiles = 2
        let keys = caches.map {
            CostUsageFetcher.codexScanProgressKey(cache: $0, scopedFiles: files)
        }
        var statusLoadCount = 0
        var advanceCount = 0
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, now, _, _ in
            Self.tokenSnapshot(cost: 1, now: now)
        }
        store._test_codexCostCatchUpStatusOverride = { _ in
            statusLoadCount += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: statusLoadCount == 1,
                progressKey: statusLoadCount == 1 ? keys[0] : keys[2])
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            advanceCount += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: advanceCount < 2,
                progressKey: keys[advanceCount])
        }
        store._test_codexCostCatchUpSleepOverride = { _ in
            await Task.yield()
        }
        store._test_codexCostCatchUpResourceStateOverride = {
            (.ac, false, .nominal)
        }

        store.startCodexCostCatchUpIfNeeded(mode: .accelerated)
        await Self.waitUntil {
            store.codexCostCatchUpTask == nil
        }

        #expect(Set(keys).count == 3)
        #expect(advanceCount == 2)
        #expect(store.codexCostCatchUpActivity?.phase == .complete)
    }

    @Test
    func `a same-mode refresh does not queue a worker after the completing task`() async throws {
        let store = try Self.makeStore(suite: "same-mode-restart")
        var statusLoadCount = 0
        var advanceCount = 0
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, now, _, _ in
            Self.tokenSnapshot(cost: 1, now: now)
        }
        store._test_codexCostCatchUpStatusOverride = { _ in
            statusLoadCount += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: statusLoadCount == 2,
                progressKey: "status-\(statusLoadCount)")
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            advanceCount += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: false,
                progressKey: "complete")
        }
        store._test_codexCostCatchUpSleepOverride = { _ in
            await Task.yield()
        }
        store._test_codexCostCatchUpResourceStateOverride = {
            (.ac, false, .nominal)
        }

        store.startCodexCostCatchUpIfNeeded()
        store.startCodexCostCatchUpIfNeeded()
        await Self.waitUntil {
            store.codexCostCatchUpTask == nil && statusLoadCount == 1
        }

        #expect(statusLoadCount == 1)
        #expect(advanceCount == 0)
        #expect(store.codexCostCatchUpActivity?.phase == .complete)
    }

    @Test
    func `an ordinary refresh does not restart an unchanged no-progress key`() async throws {
        let store = try Self.makeStore(suite: "no-progress-refresh")
        var advanceCount = 0
        store._test_codexCostCatchUpStatusOverride = { _ in
            CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "unchanged")
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            advanceCount += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: true,
                progressKey: "unchanged")
        }
        store._test_codexCostCatchUpSleepOverride = { _ in await Task.yield() }
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }

        store.startCodexCostCatchUpIfNeeded()
        await Self.waitUntil { store.codexCostCatchUpTask == nil }
        store.startCodexCostCatchUpIfNeeded()
        await Task.yield()

        #expect(advanceCount == 1)
        #expect(store.codexCostCatchUpTask == nil)
        #expect(store.codexCostCatchUpActivity?.pauseReason == .noProgress)
    }

    @Test
    func `an ordinary refresh resumes only after a stalled progress key changes`() async throws {
        let store = try Self.makeStore(suite: "no-progress-key-change")
        let progressKey = LockIsolated("A")
        let bStatusLoadCount = LockIsolated(0)
        let advanceCount = LockIsolated(0)
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, now, _, _ in
            Self.tokenSnapshot(cost: 1, now: now)
        }
        store._test_codexCostCatchUpStatusOverride = { _ in
            if progressKey.value == "B" {
                bStatusLoadCount.setValue(bStatusLoadCount.value + 1)
            }
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: progressKey.value == "A" || bStatusLoadCount.value < 3,
                progressKey: progressKey.value)
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            advanceCount.setValue(advanceCount.value + 1)
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: progressKey.value == "A",
                progressKey: progressKey.value)
        }
        store._test_codexCostCatchUpSleepOverride = { _ in await Task.yield() }
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }

        store.startCodexCostCatchUpIfNeeded()
        await Self.waitUntil { store.codexCostCatchUpTask == nil }
        #expect(advanceCount.value == 1)
        #expect(store.codexCostCatchUpPausedProgressKey == "A")

        // The status probe observes the same semantic state and must not rebuild the cache.
        store.startCodexCostCatchUpIfNeeded()
        await Self.waitUntil { store.codexCostCatchUpProgressProbeTask == nil }
        #expect(advanceCount.value == 1)
        #expect(store.codexCostCatchUpPausedProgressKey == "A")

        // A real source change releases the pause and allows the existing worker to converge.
        progressKey.setValue("B")
        store.startCodexCostCatchUpIfNeeded()
        await Self.waitUntil {
            store.codexCostCatchUpTask == nil && advanceCount.value == 2
        }

        #expect(advanceCount.value == 2)
        #expect(store.codexCostCatchUpPausedProgressKey == nil)
        #expect(store.codexCostCatchUpActivity?.phase == .complete)
    }

    @Test
    func `accelerated catch-up runs without an inter-pass delay and publishes progress`() async throws {
        let store = try Self.makeStore(suite: "accelerated")
        var statusLoadCount = 0
        var sleepDurations: [TimeInterval] = []
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, now, _, _ in
            Self.tokenSnapshot(cost: 1, now: now)
        }
        store._test_codexCostCatchUpStatusOverride = { _ in
            statusLoadCount += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: statusLoadCount == 1,
                progressKey: "status-\(statusLoadCount)",
                processedBytes: statusLoadCount == 1 ? 25 : 100,
                totalBytes: 100,
                completedFiles: statusLoadCount == 1 ? 0 : 1,
                totalFiles: 1)
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            CostUsageFetcher.CodexScanCatchUpStatus(
                pending: false,
                progressKey: "complete",
                processedBytes: 100,
                totalBytes: 100,
                completedFiles: 1,
                totalFiles: 1)
        }
        store._test_codexCostCatchUpSleepOverride = { duration in
            sleepDurations.append(duration)
            await Task.yield()
        }
        store._test_codexCostCatchUpResourceStateOverride = {
            (.battery, true, .serious)
        }

        store.startCodexCostCatchUpIfNeeded(mode: .accelerated)
        await Self.waitUntil {
            store.codexCostCatchUpTask == nil
        }

        #expect(sleepDurations.first == 0)
        #expect(store.codexCostCatchUpActivity?.phase == .complete)
        #expect(store.codexCostCatchUpActivity?.mode == .accelerated)
        #expect(store.codexCostCatchUpActivity?.fractionCompleted == 1)
    }

    @Test
    func `stop during an idle delay preserves progress without starting a pass`() async throws {
        let store = try Self.makeStore(suite: "stop-idle")
        var advanceCount = 0
        store._test_codexCostCatchUpStatusOverride = { _ in
            CostUsageFetcher.CodexScanCatchUpStatus(
                pending: true,
                progressKey: "partial",
                processedBytes: 50,
                totalBytes: 100)
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            advanceCount += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(pending: false, progressKey: "unexpected")
        }
        store._test_codexCostCatchUpSleepOverride = { _ in
            store.stopCodexCostCatchUp()
            await Task.yield()
        }
        store._test_codexCostCatchUpResourceStateOverride = {
            (.ac, false, .nominal)
        }

        store.startCodexCostCatchUpIfNeeded()
        await Self.waitUntil {
            store.codexCostCatchUpTask == nil
        }

        #expect(advanceCount == 0)
        #expect(store.codexCostCatchUpActivity?.phase == .paused)
        #expect(store.codexCostCatchUpActivity?.pauseReason == .user)
        #expect(store.codexCostCatchUpActivity?.fractionCompleted == 0.5)
    }

    @Test
    func `stopping an active pass clears a queued restart`() throws {
        let store = try Self.makeStore(suite: "stop-clears-restart")
        store.codexCostCatchUpTask = Task {}
        store.codexCostCatchUpPassIsRunning = true
        store.codexCostCatchUpRestartRequested = true

        store.stopCodexCostCatchUp()

        #expect(store.codexCostCatchUpStopRequested)
        #expect(!store.codexCostCatchUpRestartRequested)
        store.cancelCodexCostCatchUp()
    }

    private static func makeStore(suite: String) throws -> UsageStore {
        let settings = testSettingsStore(suiteName: "UsageStoreCodexCostCatchUpTests-\(suite)")
        settings.costUsageEnabled = true
        settings.costUsageHistoryDays = 30
        let metadata = try #require(ProviderRegistry.shared.metadata[.codex])
        settings.setProviderEnabled(provider: .codex, metadata: metadata, enabled: true)
        return UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
    }

    private static func tokenSnapshot(
        cost: Double,
        now: Date,
        historyCoverageIsEstablished: Bool = true) -> CostUsageTokenSnapshot
    {
        CostUsageTokenSnapshot(
            sessionTokens: 10,
            sessionCostUSD: cost,
            last30DaysTokens: 10,
            last30DaysCostUSD: cost,
            historyCoverageIsEstablished: historyCoverageIsEstablished,
            daily: [CostUsageDailyReport.Entry(
                date: "2026-07-30",
                inputTokens: 4,
                outputTokens: 6,
                totalTokens: 10,
                costUSD: cost,
                modelsUsed: nil,
                modelBreakdowns: nil)],
            updatedAt: now)
    }

    private static func waitUntil(
        _ condition: @escaping @MainActor () -> Bool) async
    {
        for _ in 0..<1000 {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        Issue.record("Timed out waiting for Codex cost catch-up task")
    }
}
