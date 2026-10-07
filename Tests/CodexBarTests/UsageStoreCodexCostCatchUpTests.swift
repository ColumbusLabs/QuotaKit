import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct UsageStoreCodexCostCatchUpTests {
    @Test
    func `automatic sleep uses active scan duration instead of awaited latency`() async throws {
        let store = try Self.makeStore(suite: "active-duration")
        store.settings.backgroundWorkLowPowerModePreference = .off
        var sleeps: [TimeInterval] = []
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        store._test_codexCostCatchUpStatusOverride = { _ in
            .init(pending: true, progressKey: "pending")
        }
        store._test_codexCostCatchUpActiveDuration = 2
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            try await Task.sleep(for: .milliseconds(20))
            return .init(pending: true, progressKey: "progressed")
        }
        store._test_codexCostCatchUpSleepOverride = { delay in
            sleeps.append(delay)
            if sleeps.count == 2 { throw CancellationError() }
        }
        store.startCodexCostCatchUpIfNeeded()
        let task = try #require(store.codexCostCatchUpTask)
        await task.value
        #expect(sleeps == [0, 1998])
    }

    @Test(arguments: [0.1, 0.75])
    func `automatic discovery yields after its accumulated time or page budget`(duration: TimeInterval)
        async throws
    {
        let store = try Self.makeStore(suite: "bounded-discovery")
        store.settings.backgroundWorkLowPowerModePreference = .off
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        store._test_codexCostCatchUpStatusOverride = { _ in .init(pending: true, progressKey: "start") }
        store._test_cachedCodexTokenSnapshotLoaderOverride = { _, _, _ in nil }
        store._test_codexCostCatchUpActiveDuration = duration
        var advances = 0
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            advances += 1
            return .init(pending: true, progressKey: "page-\(advances)")
        }
        var delayed = false
        store._test_codexCostCatchUpSleepOverride = { delay in
            guard delay > 0 else { return }
            delayed = true
            #expect(advances == (duration == 0.1 ? 8 : 3))
            let accountedDuration = max(2, Double(advances) * duration)
            #expect(abs(delay - accountedDuration * 999) < 0.000001)
            throw CancellationError()
        }
        store.startCodexCostCatchUpIfNeeded()
        await store.codexCostCatchUpTask?.value
        #expect(delayed)
    }

    @Test(arguments: [false, true])
    func `accelerated work does not accumulate automatic sleep debt`(switchDuringYield: Bool) async throws {
        let store = try Self.makeStore(suite: "acceleration-debt-\(switchDuringYield)")
        store.settings.backgroundWorkLowPowerModePreference = .off
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        store._test_codexCostCatchUpStatusOverride = { _ in .init(pending: true, progressKey: "start") }
        store._test_cachedCodexTokenSnapshotLoaderOverride = { _, _, _ in nil }
        store._test_codexCostCatchUpActiveDuration = 2
        let expectedAdvances = switchDuringYield ? 4 : 3
        var advances = 0
        var switched = false
        var delayed = false
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            advances += 1
            guard advances <= expectedAdvances else { throw CancellationError() }
            if advances == 3, !switchDuringYield {
                #expect(store.codexCostCatchUpPassIsRunning)
                switched = true
                store.startCodexCostCatchUpIfNeeded(mode: .automatic)
            }
            return .init(pending: true, progressKey: "page-\(advances)")
        }
        store._test_codexCostCatchUpSleepOverride = { delay in
            if switchDuringYield, advances == 3, !switched {
                #expect(delay == 0)
                #expect(!store.codexCostCatchUpPassIsRunning)
                switched = true
                store.startCodexCostCatchUpIfNeeded(mode: .automatic)
                return
            }
            guard delay > 0 else { return }
            delayed = true
            #expect(delay == 1998)
            #expect(advances == expectedAdvances)
            throw CancellationError()
        }
        store.startCodexCostCatchUpIfNeeded(mode: .accelerated)
        let original = try #require(store.codexCostCatchUpTask)
        await original.value
        await store.codexCostCatchUpTask?.value
        #expect(advances == expectedAdvances)
        #expect(delayed)
        #expect(switched)
        #expect(store.codexCostCatchUpMode == .automatic)
    }

    @Test(arguments: [CodexCostCatchUpPowerSource.ac, .battery, .unknown])
    func `app low power mode preserves longer automatic catch-up delays`(source: CodexCostCatchUpPowerSource)
        throws
    {
        let store = try Self.makeStore(suite: "app-low-power-policy")
        let resources = (source, false, ProcessInfo.ThermalState.nominal)
        store.settings.backgroundWorkLowPowerModePreference = .on
        let decision = store.codexCostCatchUpDecision(
            mode: .automatic, previousActiveDuration: 0.1, resourceState: resources)
        // An initial automatic pass has no assumed sleep debt. The app preference still
        // imposes its 30-minute floor before the first scan.
        let expectedDelay = BackgroundWorkPowerPolicy.lowPowerMinimumInterval
        #expect(decision.action == .runAfter(expectedDelay))
        #expect(expectedDelay == 1800)
        #expect(store.codexCostCatchUpDecision(
            mode: .accelerated, previousActiveDuration: 0.1, resourceState: resources).action == .runAfter(0))
        store.settings.backgroundWorkLowPowerModePreference = .off
        #expect(store.codexCostCatchUpDecision(
            mode: .automatic, previousActiveDuration: 0.1, resourceState: resources)
            == CodexCostCatchUpPolicy().decision(for: .init(
                mode: .automatic,
                previousActiveDuration: 0.1,
                powerSource: source,
                lowPowerModeEnabled: false,
                thermalState: .nominal)))
        store.settings.backgroundWorkLowPowerModePreference = .on
        #expect(store.codexCostCatchUpDecision(
            mode: .automatic,
            previousActiveDuration: nil,
            resourceState: (.ac, false, .nominal)).action == .runAfter(1800))
        #expect(store.codexCostCatchUpDecision(
            mode: .automatic,
            previousActiveDuration: 0.1,
            resourceState: (source, true, .nominal)).action == .pause(60, .lowPower))
        #expect(store.codexCostCatchUpDecision(
            mode: .automatic,
            previousActiveDuration: 0.1,
            resourceState: (source, true, .serious)).action == .pause(60, .thermal))
    }

    @Test(arguments: [CodexCostCatchUpMode.automatic, .accelerated])
    func `app low power preference reaches successive catch-up passes`(mode: CodexCostCatchUpMode) async throws {
        let store = try Self.makeStore(suite: "app-low-power-worker")
        store.settings.backgroundWorkLowPowerModePreference = .on
        var sleeps: [TimeInterval] = []
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        store._test_codexCostCatchUpStatusOverride = { _ in
            CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "pending")
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "progressed")
        }
        store._test_codexCostCatchUpSleepOverride = { delay in
            sleeps.append(delay)
            if sleeps.count == 2 { throw CancellationError() }
        }
        store.startCodexCostCatchUpIfNeeded(mode: mode)
        let task = try #require(store.codexCostCatchUpTask)
        await task.value
        #expect(sleeps.count == 2)
        if mode == .automatic {
            #expect(sleeps.allSatisfy { $0 >= 1800 })
        } else {
            #expect(sleeps == [0, 0])
        }
    }

    @Test
    func `combined low power and thermal pressure publishes thermal pause without scanning`() async throws {
        let store = try Self.makeStore(suite: "combined-thermal-pause")
        var advanceCount = 0
        var sleepDurations: [TimeInterval] = []
        store._test_codexCostCatchUpStatusOverride = { _ in
            CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "pending")
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            advanceCount += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(pending: false, progressKey: "complete")
        }
        store._test_codexCostCatchUpResourceStateOverride = { (.battery, true, .serious) }
        store._test_codexCostCatchUpSleepOverride = { duration in
            sleepDurations.append(duration)
            throw CancellationError()
        }

        store.startCodexCostCatchUpIfNeeded()
        let task = try #require(store.codexCostCatchUpTask)
        await task.value

        #expect(store.codexCostCatchUpActivity?.phase == .paused)
        #expect(store.codexCostCatchUpActivity?.pauseReason == .thermal)
        #expect(sleepDurations == [CodexCostCatchUpPolicy.constrainedRetryDelay])
        #expect(advanceCount == 0)
    }

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
        #expect(sleepDurations.first == 0)
        #expect(store.tokenSnapshot(for: .codex)?.last30DaysCostUSD == 3)
        #expect(store.tokenSnapshotPublicationRevision(for: .codex) == 3)
        #expect(store.tokenError(for: .codex) == nil)
        #expect(store.memoryPressureReliefTask != nil)
    }

    @Test
    func `catch-up retries bounded no-progress passes before pausing`() async throws {
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
            store.codexCostCatchUpTask == nil && advanceCount == 3
        }

        #expect(advanceCount == 3)
        #expect(snapshotLoadCount == 4)
        #expect(store.tokenSnapshot(for: .codex)?.last30DaysCostUSD == 1)
        #expect(store.tokenSnapshotPublicationRevision(for: .codex) == 1)
        #expect(store.codexCostCatchUpActivity?.phase == .paused)
        #expect(store.codexCostCatchUpActivity?.pauseReason == .noProgress)
    }

    @Test
    func `catch-up recovers when a no-progress retry eventually advances`() async throws {
        let store = try Self.makeStore(suite: "no-progress-recovery")
        var statusLoadCount = 0
        var advanceCount = 0
        var sleepDurations: [TimeInterval] = []
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, now, _, _ in
            Self.tokenSnapshot(cost: 1, now: now)
        }
        store._test_codexCostCatchUpStatusOverride = { _ in
            statusLoadCount += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: statusLoadCount == 1,
                progressKey: statusLoadCount == 1 ? "stalled" : "advanced")
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            advanceCount += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: advanceCount == 1,
                progressKey: advanceCount == 1 ? "stalled" : "advanced")
        }
        store._test_codexCostCatchUpSleepOverride = { duration in
            sleepDurations.append(duration)
            await Task.yield()
        }
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }

        store.startCodexCostCatchUpIfNeeded(mode: .accelerated)
        await Self.waitUntil {
            store.codexCostCatchUpTask == nil
        }

        #expect(advanceCount == 2)
        #expect(sleepDurations == [0, 5])
        #expect(store.codexCostCatchUpPausedProgressKey == nil)
        #expect(store.codexCostCatchUpActivity?.phase == .complete)
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

        #expect(snapshotLoadCount == 4)
        #expect(store.tokenSnapshot(for: .codex)?.last30DaysCostUSD == 99)
        #expect(store.tokenSnapshotPublicationRevision(for: .codex) == 2)
    }

    @Test(arguments: [false, true])
    func `terminal pauses coalesce same scope refresh and allow explicit resume`(throwsError: Bool) async throws {
        let store = try Self.makeStore(suite: "terminal-queued-restart-\(throwsError)")
        defer { store.cancelCodexCostCatchUp() }
        store._test_cachedCodexTokenSnapshotLoaderOverride = { _, _, _ in nil }
        var statusLoadCount = 0
        var advanceCount = 0
        store._test_codexCostCatchUpStatusOverride = { _ in
            statusLoadCount += 1
            return .init(pending: true, progressKey: "unchanged")
        }
        store._test_codexCostCatchUpAdvanceOverride = { [weak store] _, _, _ in
            advanceCount += 1
            if advanceCount == 1 {
                store?.startCodexCostCatchUpIfNeeded(afterRefreshing: .codex)
                #expect(store?.codexCostCatchUpRestartRequested == false)
            }
            if throwsError {
                throw NSError(domain: "SyntheticCatchUp", code: 1)
            }
            return .init(pending: true, progressKey: "unchanged")
        }
        store._test_codexCostCatchUpSleepOverride = { _ in await Task.yield() }
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }

        store.startCodexCostCatchUpIfNeeded()
        await Self.waitUntil { store.codexCostCatchUpTask == nil }

        #expect(statusLoadCount == 1)
        #expect(advanceCount == (throwsError ? 1 : 3))
        #expect(store.codexCostCatchUpActivity?.phase == .paused)
        #expect(!store.codexCostCatchUpRestartRequested)

        store.startAcceleratedCodexCostCatchUp()
        await Self.waitUntil { store.codexCostCatchUpTask == nil }
        #expect(statusLoadCount == 2)
        #expect(advanceCount == (throwsError ? 2 : 6))
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

        #expect(advanceCount == 3)
        #expect(store.codexCostCatchUpTask == nil)
        #expect(store.codexCostCatchUpActivity?.pauseReason == .noProgress)
    }

    @Test
    func `a terminal stall requires explicit resume after the progress key changes`() async throws {
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
        #expect(advanceCount.value == 3)
        #expect(store.codexCostCatchUpPausedProgressKey == "A")

        // The status probe observes the same semantic state and must not rebuild the cache.
        store.startCodexCostCatchUpIfNeeded()
        await Self.waitUntil { store.codexCostCatchUpProgressProbeTask == nil }
        #expect(advanceCount.value == 3)
        #expect(store.codexCostCatchUpPausedProgressKey == "A")

        // A source change cannot silently restart a terminally stalled scan.
        progressKey.setValue("B")
        store.startCodexCostCatchUpIfNeeded()
        await Task.yield()
        #expect(advanceCount.value == 3)
        #expect(store.codexCostCatchUpPausedProgressKey == "A")
        #expect(store.codexCostCatchUpActivity?.requiresExplicitResume == true)

        // An explicit resume releases the pause and lets the worker converge.
        store.startCodexCostCatchUpIfNeeded(resumePaused: true)
        await Self.waitUntil {
            store.codexCostCatchUpTask == nil && advanceCount.value == 4
        }

        #expect(advanceCount.value == 4)
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
        let settings = testSettingsStore(
            suiteName: "UsageStoreCodexCostCatchUpTests-\(suite)", userDefaults: InMemoryUserDefaults())
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
