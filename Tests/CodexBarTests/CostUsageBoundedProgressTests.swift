import Foundation
import Testing
@testable import CodexBarCore

// Bounded progress fixtures share one corpus and environment helper vocabulary.
// swiftlint:disable file_length
@Suite(.serialized)
// swiftlint:disable:next type_body_length
struct CostUsageBoundedProgressTests {
    @Test
    func `bounded catch up completes before a fresh Codex home creates session roots`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let freshCodexHome = env.root.appendingPathComponent("fresh-codex-home", isDirectory: true)
        try FileManager.default.createDirectory(at: freshCodexHome, withIntermediateDirectories: true)

        var options = Self.boundedOptions(env: env)
        options.codexSessionsRoot = freshCodexHome.appendingPathComponent("sessions", isDirectory: true)
        #expect(CostUsageScanner.codexSessionsRoots(options: options).isEmpty)

        let converged = try Self.finishBoundedCatchUp(
            env: env,
            day: day,
            options: &options,
            startingAt: 0)
        #expect(converged.files.isEmpty)
        #expect(converged.codexActiveLookbackState == nil)
        #expect(converged.codexScanCatchUpPending == false)
    }

    @Test
    func `bounded catch up completes without an optional archived sessions directory`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        try FileManager.default.removeItem(at: env.codexArchivedSessionsRoot)
        try Self.writeSyntheticCorpus(env: env, day: day, fileCount: 1)
        let archivedRoot = env.codexArchivedSessionsRoot
        #expect(!FileManager.default.fileExists(atPath: archivedRoot.path))

        var options = Self.boundedOptions(env: env)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)
        #expect(roots.map(\.standardizedFileURL.path) == [env.codexSessionsRoot.standardizedFileURL.path])

        let converged = try Self.finishBoundedCatchUp(
            env: env,
            day: day,
            options: &options,
            startingAt: 0)
        #expect(converged.files.count == 1)
        #expect(converged.files.values.allSatisfy { $0.codexInventoryValidationGeneration != nil })
        #expect(converged.codexActiveLookbackState == nil)
        #expect(converged.codexScanCatchUpPending == false)
    }

    @Test
    func `alternating history windows retain completed discovery and pending work`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        var options = Self.boundedOptions(env: env)
        let wideSince = try #require(options.calendar.date(byAdding: .day, value: -364, to: day))
        let narrowSince = try #require(options.calendar.date(byAdding: .day, value: -89, to: day))
        try Self.writeSyntheticCorpus(env: env, day: day, fileCount: 2)
        options.maxCodexScanDurationPerRefresh = nil
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex, since: wideSince, until: day, now: day, options: options)

        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let paths = cache.files.keys.sorted()
        #expect(paths.count == 2)
        let pendingPath = try #require(paths.last)
        let completedPath = try #require(paths.first)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }.sorted()
        cache.files[pendingPath]?.codexScanComplete = false
        cache.codexScanCatchUpPending = true
        cache.codexScanInventoryPaths = nil
        cache.codexActiveLookbackState = try CostUsageCodexActiveLookbackState(
            scanSinceKey: #require(cache.scanSinceKey),
            rootPaths: roots,
            completedRootPaths: roots,
            pendingFilePaths: [pendingPath],
            completedCurrentWindowRootPaths: roots,
            completedCurrentWindowFlatRootPaths: roots,
            directoryCursorVersion: 3)
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache)

        for (index, since) in [narrowSince, wideSince, narrowSince].enumerated() {
            let clock = BoundedProgressCounter()
            let origin = ContinuousClock.now
            options.codexScanBudgetForTesting = CostUsageScanner.CodexScanBudget(
                maxFileBytes: 0,
                maxBytesPerRefresh: 0,
                maxDuration: 2,
                now: { origin.advanced(by: .seconds(clock.value == 0 ? 0 : 3)) })
            clock.increment()
            let recorder = CostUsageScanner.CodexScanWorkRecorder()
            options.codexScanWorkRecorderForTesting = recorder
            _ = CostUsageControlledClockScanner.loadDailyReport(
                provider: .codex,
                since: since,
                until: day,
                now: day.addingTimeInterval(Double(index + 1)),
                options: options)
            let saved = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
            #expect(saved.codexActiveLookbackState?.pendingFilePaths == [pendingPath])
            #expect(saved.files[completedPath]?.codexScanComplete == true)
            #expect(recorder.snapshot().codexCandidateSelectionVisits == 1)
            #expect(recorder.snapshot().codexFileScanAttempts == 0)
            #expect(recorder.snapshot().codexDiscoveryVisits == 0)
        }
        options.codexScanBudgetForTesting = nil
        options.maxCodexScanDurationPerRefresh = 60
        for (index, since) in [wideSince, narrowSince, wideSince].enumerated() {
            _ = CostUsageControlledClockScanner.loadDailyReport(
                provider: .codex,
                since: since,
                until: day,
                now: day.addingTimeInterval(Double(index + 10)),
                options: options)
        }
        let completed = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(completed.codexScanCatchUpPending == false)
        #expect(completed.codexActiveLookbackState == nil)
        #expect(completed.codexScanCompletedFiles == 2)
        #expect(completed.codexScanTotalFiles == 2)
    }

    @Test(arguments: [false, true])
    func `retained discovery finds older pending history and new day expansion`(newDay: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        var options = Self.boundedOptions(env: env)
        let wideSince = try #require(options.calendar.date(byAdding: .day, value: -364, to: day))
        let narrowSince = try #require(options.calendar.date(byAdding: .day, value: -89, to: day))
        let discoveredDay = try #require(options.calendar.date(byAdding: .day, value: newDay ? 2 : -200, to: day))
        try Self.writeSyntheticCorpus(env: env, day: day, fileCount: 1)
        options.maxCodexScanDurationPerRefresh = nil
        let baseline = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex, since: wideSince, until: day, now: day, options: options)
        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }.sorted()
        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: discoveredDay, calendar: options.calendar)
        cache.codexScanCatchUpPending = true
        cache.codexScanInventoryPaths = nil
        cache.codexActiveLookbackState = try CostUsageCodexActiveLookbackState(
            scanSinceKey: #require(cache.scanSinceKey),
            rootPaths: roots,
            completedRootPaths: roots,
            currentWindowNextDayKeyByRoot: Dictionary(uniqueKeysWithValues: roots.map { ($0, dayKey) }),
            completedCurrentWindowRootPaths: newDay ? roots : [],
            completedCurrentWindowFlatRootPaths: roots)
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache)
        let iso = env.isoString(for: discoveredDay)
        let lines = [
            #"{"type":"session_meta","timestamp":"\#(iso)","payload":{"session_id":"discovered-history"}}"#,
            #"{"type":"turn_context","timestamp":"\#(iso)","payload":{"model":"openai/gpt-5.2-codex"}}"#,
            #"{"type":"event_msg","timestamp":"\#(iso)","payload":{"type":"token_count","info":"#
                + #"{"total_token_usage":{"input_tokens":50,"output_tokens":5}}}}"#,
        ]
        let discoveredURL = try env.writeCodexSessionFile(
            day: discoveredDay, filename: "discovered-history.jsonl", contents: lines.joined(separator: "\n") + "\n")
        options.maxCodexScanDurationPerRefresh = 60
        let until = newDay ? discoveredDay : day
        for index in 1...3 {
            _ = CostUsageControlledClockScanner.loadDailyReport(
                provider: .codex,
                since: narrowSince,
                until: until,
                now: until.addingTimeInterval(Double(index)),
                options: options)
        }
        let completed = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let discoveredUsage = try #require(completed.files.first {
            $0.key.hasSuffix(discoveredURL.lastPathComponent)
        }?.value)
        #expect(discoveredUsage.days[dayKey]?.values.first == [50, 0, 5])
        #expect(completed.codexScanCatchUpPending == false)
        let report = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: narrowSince,
            until: until,
            now: until.addingTimeInterval(10),
            options: options)
        if !newDay {
            #expect(report.data == baseline.data)
        }
    }

    @Test
    func `bounded progress accumulates while retaining a wider scan window`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        var options = Self.boundedOptions(env: env)
        let priorDay = try #require(options.calendar.date(byAdding: .day, value: -1, to: day))
        options.maxCodexScanDurationPerRefresh = nil
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: priorDay,
            until: day,
            now: day,
            options: options)

        let corpusSize = 600
        try Self.writeSyntheticCorpus(env: env, day: day, fileCount: corpusSize)
        options.maxCodexScanDurationPerRefresh = 60
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)
        let firstCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(firstCache.files.count == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(firstCache.codexScanCompletedFiles == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(firstCache.codexScanTotalFiles == CostUsageScanner.codexCatchUpScanCandidateLimit)

        let secondRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = secondRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(2),
            options: options)
        let secondCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(secondRecorder.snapshot().codexProgressAccountingVisits == 0)
        #expect(secondCache.files.count == corpusSize)
        #expect(secondCache.codexScanCompletedFiles == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(secondCache.codexScanTotalFiles == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(secondCache.codexActiveLookbackState?.pendingFilePaths.isEmpty == true)
        #expect(secondCache.codexScanInventoryPaths == nil)
        #expect(secondCache.codexScanCatchUpPending == true)

        let finalCache = try Self.finishBoundedCatchUp(
            env: env,
            day: day,
            options: &options,
            startingAt: 3)
        #expect(finalCache.codexActiveLookbackState == nil)
        #expect(finalCache.codexScanCompletedFiles == corpusSize)
        #expect(finalCache.codexScanTotalFiles == corpusSize)
        #expect(finalCache.codexScanInventoryPaths == nil)
        #expect(finalCache.files.values.allSatisfy { $0.codexInventoryValidationGeneration != nil })
        #expect(finalCache.codexScanCatchUpPending == false)
    }

    @Test
    func `retained scan duration rolls forward instead of forming a lifetime union`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let firstDay = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let firstSince = try #require(Calendar.current.date(byAdding: .day, value: -2, to: firstDay))
        var options = Self.boundedOptions(env: env)
        options.maxCodexScanDurationPerRefresh = nil

        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: firstSince,
            until: firstDay,
            now: firstDay,
            options: options)
        let initial = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
        let initialSince = try #require(initial.scanSinceKey)
        let initialUntil = try #require(initial.scanUntilKey)

        let nextDay = try #require(options.calendar.date(byAdding: .day, value: 1, to: firstDay))
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: nextDay,
            until: nextDay,
            now: nextDay,
            options: options)
        let rolled = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
        let initialSinceDate = try #require(CostUsageScanner.parseDayKey(initialSince, calendar: options.calendar))
        let initialUntilDate = try #require(CostUsageScanner.parseDayKey(initialUntil, calendar: options.calendar))
        let expectedSinceDate = try #require(options.calendar.date(byAdding: .day, value: 1, to: initialSinceDate))
        let expectedUntilDate = try #require(options.calendar.date(byAdding: .day, value: 1, to: initialUntilDate))

        #expect(rolled.scanSinceKey == CostUsageScanner.CostUsageDayRange.dayKey(
            from: expectedSinceDate,
            calendar: options.calendar))
        #expect(rolled.scanUntilKey == CostUsageScanner.CostUsageDayRange.dayKey(
            from: expectedUntilDate,
            calendar: options.calendar))
    }

    @Test
    func `legacy lifetime retention metadata shrinks to the bounded maximum lookback`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        var options = Self.boundedOptions(env: env)
        options.maxCodexScanDurationPerRefresh = nil
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)

        var legacyCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        legacyCache.scanSinceKey = "2018-01-01"
        legacyCache.codexRetainedLookbackDays = nil
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: legacyCache)

        let nextDay = try #require(options.calendar.date(byAdding: .day, value: 1, to: day))
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: nextDay,
            until: nextDay,
            now: nextDay,
            options: options)
        let migrated = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
        let retainedSince = try #require(migrated.scanSinceKey.flatMap {
            CostUsageScanner.parseDayKey($0, calendar: options.calendar)
        })
        let retainedUntil = try #require(migrated.scanUntilKey.flatMap {
            CostUsageScanner.parseDayKey($0, calendar: options.calendar)
        })

        #expect(migrated.codexRetainedLookbackDays == 365)
        #expect(options.calendar.dateComponents([.day], from: retainedSince, to: retainedUntil).day == 364)
    }

    @Test
    func `exact validation retains historical snapshots and detects changed old files`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let historicalDay = try env.makeLocalNoon(year: 2020, month: 1, day: 2)
        let currentDay = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let historicalURLs = try Self.writeSyntheticCorpus(env: env, day: historicalDay, fileCount: 600)
        for url in historicalURLs {
            try FileManager.default.setAttributes([.modificationDate: historicalDay], ofItemAtPath: url.path)
        }
        try Self.writeSyntheticCorpus(env: env, day: currentDay, fileCount: 1)

        var options = Self.boundedOptions(env: env)
        options.maxCodexScanDurationPerRefresh = nil
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: historicalDay,
            until: currentDay,
            now: currentDay,
            options: options)
        #expect(CostUsageStoreAccess.read(cacheRoot: env.cacheRoot).files.count == 601)

        var prepared = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        prepared.codexActiveLookbackState = try Self.completedLookbackState(
            cache: prepared,
            options: options,
            pendingFilePaths: [])
        prepared.codexScanInventoryPaths = nil
        prepared.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: prepared)

        options.maxCodexScanDurationPerRefresh = 60
        // swiftlint:disable multiline_arguments
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex, since: currentDay, until: currentDay,
            now: currentDay.addingTimeInterval(1), options: options)
        // swiftlint:enable multiline_arguments
        var narrowed = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let changedPath = try #require(narrowed.files.keys.first { $0.contains("/2020/01/02/progress-0000") })
        let iso = env.isoString(for: currentDay)
        let appendedRow = [
            #"{"type":"event_msg","timestamp":"\#(iso)","payload":{"type":"token_count","info":"#,
            #"{"total_token_usage":{"input_tokens":250,"cached_input_tokens":80,"output_tokens":30},"#,
            #""model":"openai/gpt-5.2-codex"}}}"#,
        ].joined()
        let handle = try FileHandle(forWritingTo: historicalURLs[0])
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((appendedRow + "\n").utf8))
        try handle.close()
        try FileManager.default.setAttributes(
            [.modificationDate: currentDay.addingTimeInterval(2)],
            ofItemAtPath: historicalURLs[0].path)
        // Start a fresh exact proof after the append, regardless of an earlier page cursor.
        narrowed.codexActiveLookbackState = try Self.completedLookbackState(
            cache: narrowed, options: options, pendingFilePaths: [])
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: narrowed)

        // swiftlint:disable multiline_arguments
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex, since: currentDay, until: currentDay,
            now: currentDay.addingTimeInterval(2), options: options)
        // swiftlint:enable multiline_arguments
        let pending = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(pending.codexActiveLookbackState?.pendingFilePaths.contains(changedPath) == true)
        #expect(pending.codexScanCatchUpPending == true)

        let converged = try Self.finishBoundedCatchUp(
            env: env,
            day: currentDay,
            options: &options,
            startingAt: 3)

        // Completed proof resumes normal retention; keep the changed old file and current file.
        #expect(converged.files.count == 2)
        #expect(converged.files[changedPath]?.days.keys.contains("2026-05-10") == true)
        #expect(converged.days.keys.contains("2020-01-02") == false)
        #expect(converged.codexRetainedLookbackDays == 365)
        #expect(converged.codexActiveLookbackState == nil)
        #expect(converged.codexScanCatchUpPending == false)
        #expect(converged.codexScanInventoryPaths?.count == 2)
    }

    @Test
    func `pending exact proof defers row and byte pruning until validation completes`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let historicalDay = try env.makeLocalNoon(year: 2020, month: 1, day: 2)
        let currentDay = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        try Self.writeSyntheticCorpus(env: env, day: historicalDay, fileCount: 2)
        try Self.writeSyntheticCorpus(env: env, day: currentDay, fileCount: 1)
        var options = Self.boundedOptions(env: env)
        options.maxCodexScanDurationPerRefresh = nil
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: historicalDay,
            until: currentDay,
            now: currentDay,
            options: options)

        let store = CostUsageStore(cacheRoot: env.cacheRoot)
        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(cache.files.count == 3)
        cache.scanSinceKey = "2026-05-10"
        cache.scanUntilKey = "2026-05-10"
        cache.codexActiveLookbackState = try Self.completedLookbackState(
            cache: cache, options: options, pendingFilePaths: [])
        cache.codexScanInventoryPaths = nil
        cache.codexScanCatchUpPending = true
        let window = (sinceKey: "2026-05-10", untilKey: "2026-05-10")
        let pending = await store.saveCodexCache(
            cache,
            calendar: options.calendar,
            requestedScanWindow: window,
            rowBudget: 1,
            fileBudgetBytes: 1)
        #expect(pending.deletedRows == 0)
        #expect(CostUsageStoreAccess.read(cacheRoot: env.cacheRoot).files.count == 3)

        cache.codexActiveLookbackState = nil
        cache.codexScanCatchUpPending = false
        _ = await store.saveCodexCache(
            cache,
            calendar: options.calendar,
            requestedScanWindow: window,
            rowBudget: 1,
            fileBudgetBytes: 1)
        let retained = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(retained.files.count == 1)
        #expect(retained.files.keys.first?.contains("/2026/05/10/") == true)
    }

    @Test
    func `unavailable exact inventory directory preserves cached usage and remains incomplete`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        try Self.writeSyntheticCorpus(env: env, day: day, fileCount: 1)
        var options = Self.boundedOptions(env: env)
        options.maxCodexScanDurationPerRefresh = nil
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)

        var pendingCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        pendingCache.codexActiveLookbackState = try Self.completedLookbackState(
            cache: pendingCache,
            options: options,
            pendingFilePaths: [])
        pendingCache.codexScanInventoryPaths = nil
        pendingCache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: pendingCache)

        let dayDirectory = env.codexSessionsRoot
            .appendingPathComponent("2026/05/10", isDirectory: true)
            .standardizedFileURL.path
        CostUsageScanner.setUnavailableCodexDirectoriesForTesting([dayDirectory])
        defer { CostUsageScanner.setUnavailableCodexDirectoriesForTesting([]) }
        options.maxCodexScanDurationPerRefresh = 60
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)
        let unavailable = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)

        #expect(unavailable.files.count == 1)
        #expect(unavailable.days.keys.contains("2026-05-10"))
        #expect(unavailable.codexActiveLookbackState != nil)
        #expect(unavailable.codexScanCatchUpPending == true)
        #expect(unavailable.codexScanInventoryPaths == nil)

        CostUsageScanner.setUnavailableCodexDirectoriesForTesting([])
        let converged = try Self.finishBoundedCatchUp(
            env: env,
            day: day,
            options: &options,
            startingAt: 2)
        #expect(converged.files.count == 1)
        #expect(converged.codexActiveLookbackState == nil)
        #expect(converged.codexScanCatchUpPending == false)
    }

    @Test
    func `narrow bounded catch-up completes a retained-window pending file`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let priorDay = try #require(Calendar.current.date(byAdding: .day, value: -1, to: day))
        let retainedURL = try #require(Self.writeSyntheticCorpus(env: env, day: priorDay, fileCount: 1).first)

        var options = Self.boundedOptions(env: env)
        options.maxCodexScanDurationPerRefresh = nil
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: priorDay,
            until: day,
            now: day,
            options: options)

        let handle = try FileHandle(forWritingTo: retainedURL)
        try handle.seekToEnd()
        let iso = env.isoString(for: day)
        let appendedRow =
            #"{"type":"event_msg","timestamp":"\#(iso)","payload":{"type":"token_count","info":"#
                + #"{"total_token_usage":{"input_tokens":250,"cached_input_tokens":80,"output_tokens":30},"#
                + #""model":"openai/gpt-5.2-codex"}}}"#
        try handle.write(contentsOf: Data((appendedRow + "\n").utf8))
        try handle.close()

        var pendingCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let pendingPath = try #require(pendingCache.files.keys.first { $0.hasSuffix(retainedURL.lastPathComponent) })
        pendingCache.files[pendingPath]?.codexScanComplete = false
        pendingCache.codexActiveLookbackState = nil
        pendingCache.codexScanInventoryPaths = nil
        pendingCache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: pendingCache)

        options.maxCodexScanDurationPerRefresh = 60
        let boundedRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = boundedRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)
        let boundedCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let retainedPath = try #require(boundedCache.files.keys.first { $0.hasSuffix(retainedURL.lastPathComponent) })
        #expect(boundedRecorder.snapshot().codexCandidateSelectionVisits == 1)
        #expect(boundedRecorder.snapshot().codexFileScanAttempts == 1)
        #expect(boundedRecorder.snapshot().codexProgressAccountingVisits == 0)
        #expect(boundedCache.files[retainedPath]?.lastCountedTotals?.input == 250)
        #expect(boundedCache.codexActiveLookbackState?.pendingFilePaths.isEmpty == true)
        #expect(boundedCache.codexScanCatchUpPending == true)

        let exactRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = exactRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(2),
            options: options)
        let exactCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(exactRecorder.snapshot().codexCandidateSelectionVisits == 0)
        #expect(exactRecorder.snapshot().codexFileScanAttempts == 0)
        #expect(exactRecorder.snapshot().codexProgressAccountingVisits == 1)
        #expect(exactCache.codexActiveLookbackState == nil)
        #expect(exactCache.codexScanCatchUpPending == false)
    }

    @Test
    func `time limited catch-up keeps bounded progress until exact validation`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let corpusSize = 1500
        try Self.writeSyntheticCorpus(env: env, day: day, fileCount: corpusSize)

        var options = Self.boundedOptions(env: env)
        let saveCounter = BoundedProgressCounter()
        var hooks = CostUsageStoreTestHooks.current
        hooks.codexCatchUpReconciliationVisit = { saveCounter.increment() }
        let firstRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = firstRecorder
        CostUsageStoreTestHooks.$current.withValue(hooks) {
            _ = CostUsageControlledClockScanner.loadDailyReport(
                provider: .codex,
                since: day,
                until: day,
                now: day,
                options: options)
        }
        let firstMetrics = firstRecorder.snapshot()

        let loadCounter = BoundedProgressCounter()
        hooks.codexCatchUpReconciliationVisit = { loadCounter.increment() }
        let firstCache = CostUsageStoreTestHooks.$current.withValue(hooks) {
            CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        }
        #expect(saveCounter.value == 0)
        #expect(loadCounter.value == 0)
        #expect(firstMetrics.codexFileScanAttempts == 512)
        #expect(firstMetrics.codexCandidateSelectionVisits == 512)
        #expect(firstMetrics.activeLookbackCompletionCandidates == 512)
        #expect(firstMetrics.codexProgressAccountingVisits == 0)
        #expect(firstCache.files.count == 512)
        #expect(firstMetrics.codexDiscoveryVisits == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(firstCache.codexActiveLookbackState?.pendingFilePaths.isEmpty == true)
        #expect(firstCache.codexScanProcessedBytes == 0)
        #expect(firstCache.codexScanTotalBytes == 0)
        #expect(firstCache.codexScanCompletedFiles == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(firstCache.codexScanTotalFiles == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(firstCache.codexScanInventoryPaths == nil)
        #expect(firstCache.codexScanCatchUpPending == true)

        let secondRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = secondRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)
        let secondMetrics = secondRecorder.snapshot()
        let secondCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(secondMetrics.codexFileScanAttempts == 512)
        #expect(secondMetrics.codexCandidateSelectionVisits == 512)
        #expect(secondMetrics.activeLookbackCompletionCandidates == 512)
        #expect(secondMetrics.codexProgressAccountingVisits == 0)
        #expect(secondCache.files.count == 1024)
        #expect(secondMetrics.codexDiscoveryVisits == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(secondCache.codexActiveLookbackState?.pendingFilePaths.isEmpty == true)
        #expect(secondCache.codexScanProcessedBytes == 0)
        #expect(secondCache.codexScanTotalBytes == 0)
        #expect(secondCache.codexScanCompletedFiles == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(secondCache.codexScanTotalFiles == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(secondCache.codexScanInventoryPaths == nil)
        #expect(secondCache.codexScanCatchUpPending == true)

        let finalRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = finalRecorder
        options.maxCodexScanDurationPerRefresh = nil
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(2),
            options: options)
        let finalMetrics = finalRecorder.snapshot()
        let finalCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let exactTotalBytes = finalCache.files.values.reduce(Int64(0)) { $0 + max(0, $1.size) }
        #expect(finalMetrics.codexProgressAccountingVisits == corpusSize)
        #expect(finalCache.codexActiveLookbackState == nil)
        #expect(finalCache.codexScanCatchUpPending == false)
        #expect(finalCache.files.count == corpusSize)
        #expect(Set(finalCache.codexScanInventoryPaths ?? []) == Set(finalCache.files.keys))
        #expect(finalCache.codexScanProcessedBytes == exactTotalBytes)
        #expect(finalCache.codexScanTotalBytes == exactTotalBytes)
        #expect(finalCache.codexScanCompletedFiles == corpusSize)
        #expect(finalCache.codexScanTotalFiles == corpusSize)

        var deferredCompletionCache = finalCache
        deferredCompletionCache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: deferredCompletionCache)
        let restoredPendingCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(restoredPendingCache.codexScanCatchUpPending == true)
    }

    @Test
    func `bounded queue advances past a cached complete prefix`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let corpusSize = CostUsageScanner.codexCatchUpScanCandidateLimit + 1
        let fileURLs = try Self.writeSyntheticCorpus(env: env, day: day, fileCount: corpusSize)
        let oldModificationDate = day.addingTimeInterval(-24 * 60 * 60)
        for fileURL in fileURLs {
            try FileManager.default.setAttributes(
                [.modificationDate: oldModificationDate],
                ofItemAtPath: fileURL.path)
        }

        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"),
            maxCodexSessionFileBytes: 0,
            maxCodexScanBytesPerRefresh: 0)
        options.refreshMinIntervalSeconds = 0
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)

        var pendingCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let incompleteFilename = try #require(fileURLs.last?.lastPathComponent)
        let incompletePath = try #require(pendingCache.files.keys.first { $0.hasSuffix(incompleteFilename) })
        pendingCache.files[incompletePath]?.codexScanComplete = false
        pendingCache.codexActiveLookbackState = try Self.completedLookbackState(
            cache: pendingCache,
            options: options,
            pendingFilePaths: fileURLs.map(\.path.resolvingTemporaryPath))
        pendingCache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: pendingCache)

        options.maxCodexScanDurationPerRefresh = 60
        let recorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = recorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)

        let firstMetrics = recorder.snapshot()
        let firstCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(firstMetrics.codexCandidateSelectionVisits == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(firstMetrics.codexFileScanAttempts == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(firstMetrics.codexProgressAccountingVisits == 0)
        #expect(firstCache.codexActiveLookbackState?.pendingFilePaths == [incompletePath.resolvingTemporaryPath])
        #expect(firstCache.files[incompletePath]?.codexScanComplete == false)
        #expect(firstCache.codexScanCompletedFiles == corpusSize - 1)
        #expect(firstCache.codexScanTotalFiles == corpusSize)
        #expect(firstCache.codexScanInventoryPaths == nil)
        #expect(firstCache.codexScanCatchUpPending == true)

        let secondRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = secondRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(2),
            options: options)
        let secondMetrics = secondRecorder.snapshot()
        let secondCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(secondMetrics.codexCandidateSelectionVisits == 1)
        #expect(secondMetrics.codexFileScanAttempts == 1)
        #expect(secondMetrics.codexProgressAccountingVisits == 0)
        #expect(secondCache.files[incompletePath]?.codexScanComplete == true)
        #expect(secondCache.codexActiveLookbackState?.pendingFilePaths.isEmpty == true)
        #expect(secondCache.codexScanCompletedFiles == corpusSize)
        #expect(secondCache.codexScanTotalFiles == corpusSize)
        #expect(secondCache.codexScanCatchUpPending == true)

        let finalCache = try Self.finishBoundedCatchUp(
            env: env,
            day: day,
            options: &options,
            startingAt: 3)
        #expect(finalCache.codexActiveLookbackState == nil)
        #expect(finalCache.codexScanCompletedFiles == corpusSize)
        #expect(finalCache.codexScanTotalFiles == corpusSize)
        #expect(finalCache.codexScanCatchUpPending == false)
    }

    @Test
    func `bounded queue restores an omitted cached partial file before selecting candidates`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let fileURLs = try Self.writeSyntheticCorpus(env: env, day: day, fileCount: 2)

        var options = Self.boundedOptions(env: env)
        options.maxCodexScanDurationPerRefresh = nil
        options.preferNewestCodexSessionsFirst = false
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)

        var pendingCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let baselineDays = pendingCache.days
        let partialURL = fileURLs[0]
        let queuedURL = fileURLs[1]
        let partialPath = try #require(pendingCache.files.keys.first {
            $0.hasSuffix(partialURL.lastPathComponent)
        })
        let queuedPath = try #require(pendingCache.files.keys.first {
            $0.hasSuffix(queuedURL.lastPathComponent)
        })
        #expect(pendingCache.codexSessionDiscovery != nil)
        pendingCache.files[partialPath]?.codexScanComplete = false
        pendingCache.files[partialPath]?.parsedBytes = 0
        pendingCache.files[partialPath]?.codexTokenIndexAnchor = nil
        pendingCache.codexActiveLookbackState = try Self.completedLookbackState(
            cache: pendingCache,
            options: options,
            pendingFilePaths: [
                queuedPath.resolvingTemporaryPath,
                queuedPath.resolvingTemporaryPath,
            ])
        pendingCache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: pendingCache)

        options.maxCodexScanDurationPerRefresh = 60
        let recorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = recorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)

        let metrics = recorder.snapshot()
        let repairedCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(metrics.codexCandidateSelectionVisits == 2)
        #expect(metrics.codexFileScanAttempts == 2)
        #expect(metrics.codexCandidateSelectionVisits <= CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(repairedCache.files[partialPath]?.codexScanComplete == true)
        #expect(repairedCache.files[partialPath]?.parsedBytes == repairedCache.files[partialPath]?.size)
        #expect(repairedCache.codexActiveLookbackState?.pendingFilePaths.isEmpty == true)
        #expect(repairedCache.days == baselineDays)

        let finalCache = try Self.finishBoundedCatchUp(
            env: env,
            day: day,
            options: &options,
            startingAt: 2)
        #expect(finalCache.codexScanCatchUpPending == false)
        #expect(finalCache.days == baselineDays)
    }

    @Test
    func `bounded queue rescans an appended cached complete path outside the first slice`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let corpusSize = CostUsageScanner.codexCatchUpScanCandidateLimit + 2
        let fileURLs = try Self.writeSyntheticCorpus(env: env, day: day, fileCount: corpusSize)
        let oldModificationDate = day.addingTimeInterval(-24 * 60 * 60)
        for fileURL in fileURLs {
            try FileManager.default.setAttributes(
                [.modificationDate: oldModificationDate],
                ofItemAtPath: fileURL.path)
        }

        var options = Self.boundedOptions(env: env)
        options.maxCodexScanDurationPerRefresh = nil
        options.preferNewestCodexSessionsFirst = false
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)

        let appendedURL = fileURLs[CostUsageScanner.codexCatchUpScanCandidateLimit]
        let incompleteURL = try #require(fileURLs.last)
        var pendingCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let appendedPath = try #require(pendingCache.files.keys.first { $0.hasSuffix(appendedURL.lastPathComponent) })
        let incompletePath = try #require(pendingCache.files.keys
            .first { $0.hasSuffix(incompleteURL.lastPathComponent) })
        let beforeTotals = try #require(pendingCache.files[appendedPath]?.lastCountedTotals)
        #expect(beforeTotals.input == 100)
        #expect(beforeTotals.cached == 20)
        pendingCache.files[incompletePath]?.codexScanComplete = false
        pendingCache.codexActiveLookbackState = try Self.completedLookbackState(
            cache: pendingCache,
            options: options,
            pendingFilePaths: fileURLs.map(\.path.resolvingTemporaryPath))
        pendingCache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: pendingCache)

        options.maxCodexScanDurationPerRefresh = 60
        let firstRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = firstRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)
        let firstMetrics = firstRecorder.snapshot()
        let firstCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(firstMetrics.codexCandidateSelectionVisits == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(firstMetrics.codexFileScanAttempts == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(firstMetrics.codexProgressAccountingVisits == 0)
        #expect(firstCache.codexActiveLookbackState?.pendingFilePaths.count == 2)

        let iso = env.isoString(for: day.addingTimeInterval(2))
        let appendedLine = [
            #"{"type":"event_msg","timestamp":"\#(iso)","payload":{"type":"token_count","info":"#,
            #"{"total_token_usage":{"input_tokens":250,"cached_input_tokens":80,"output_tokens":30},"#,
            #""model":"openai/gpt-5.2-codex"}}}"#,
        ].joined()
        let handle = try FileHandle(forWritingTo: appendedURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((appendedLine + "\n").utf8))
        try handle.close()

        let secondRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = secondRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(2),
            options: options)
        let secondMetrics = secondRecorder.snapshot()
        let secondCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let afterTotals = try #require(secondCache.files[appendedPath]?.lastCountedTotals)
        #expect(secondMetrics.codexCandidateSelectionVisits == 2)
        #expect(secondMetrics.codexFileScanAttempts == 2)
        #expect(secondMetrics.codexProgressAccountingVisits == 0)
        #expect(afterTotals.input == 250)
        #expect(afterTotals.cached == 80)
        #expect(afterTotals.output == 30)
        #expect(afterTotals != beforeTotals)
        #expect(secondCache.files[incompletePath]?.codexScanComplete == true)
        #expect(secondCache.codexActiveLookbackState?.pendingFilePaths.isEmpty == true)
        #expect(secondCache.codexScanCompletedFiles == corpusSize)
        #expect(secondCache.codexScanTotalFiles == corpusSize)
        #expect(secondCache.codexScanCatchUpPending == true)

        let finalCache = try Self.finishBoundedCatchUp(
            env: env,
            day: day,
            options: &options,
            startingAt: 3)
        #expect(finalCache.codexActiveLookbackState == nil)
        #expect(finalCache.codexScanCompletedFiles == corpusSize)
        #expect(finalCache.codexScanTotalFiles == corpusSize)
        #expect(finalCache.codexScanCatchUpPending == false)
    }

    @Test
    func `active bounded queue appends a newly discovered tail path`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let corpusSize = CostUsageScanner.codexCatchUpScanCandidateLimit + 1
        try Self.writeSyntheticCorpus(env: env, day: day, fileCount: corpusSize)

        var options = Self.boundedOptions(env: env)
        options.preferNewestCodexSessionsFirst = false
        let firstRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = firstRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)
        let firstCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(firstRecorder.snapshot().codexFileScanAttempts == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(firstCache.codexActiveLookbackState?.pendingFilePaths.isEmpty == true)

        let iso = env.isoString(for: day.addingTimeInterval(1))
        _ = try env.writeCodexSessionFile(
            day: day,
            filename: "progress-new-tail.jsonl",
            contents: [
                #"{"type":"session_meta","timestamp":"\#(iso)","payload":{"session_id":"progress-new-tail"}}"#,
                #"{"type":"turn_context","timestamp":"\#(iso)","payload":{"model":"openai/gpt-5.2-codex"}}"#,
                #"{"type":"event_msg","timestamp":"\#(iso)","payload":{"type":"token_count","info":"#
                    + #"{"total_token_usage":{"input_tokens":300,"cached_input_tokens":40,"output_tokens":20},"#
                    + #""model":"openai/gpt-5.2-codex"}}}"#,
            ].joined(separator: "\n") + "\n")

        let secondRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = secondRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)
        let secondMetrics = secondRecorder.snapshot()
        let secondCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(secondMetrics.codexCandidateSelectionVisits == 1)
        #expect(secondMetrics.codexFileScanAttempts == 1)
        #expect(secondMetrics.codexProgressAccountingVisits == 0)
        #expect(secondCache.codexActiveLookbackState?.pendingFilePaths.isEmpty == true)
        #expect(secondCache.files.count == corpusSize)
        #expect(secondCache.codexScanCatchUpPending == true)

        let exactCache = try Self.finishBoundedCatchUp(
            env: env,
            day: day,
            options: &options,
            startingAt: 2)
        #expect(exactCache.files.count == corpusSize + 1)
        #expect(exactCache.codexActiveLookbackState == nil)
        #expect(exactCache.codexScanCompletedFiles == corpusSize + 1)
        #expect(exactCache.codexScanTotalFiles == corpusSize + 1)
        #expect(exactCache.codexScanCatchUpPending == false)
    }

    @Test
    func `current day discovery jumps ahead of a historical bounded queue`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let historicalDay = try env.makeLocalNoon(year: 2026, month: 5, day: 8)
        let currentDay = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let corpusSize = CostUsageScanner.codexCatchUpScanCandidateLimit * 2 + 1
        let historicalURLs = try Self.writeSyntheticCorpus(env: env, day: historicalDay, fileCount: corpusSize)
        for url in historicalURLs {
            try FileManager.default.setAttributes([.modificationDate: historicalDay], ofItemAtPath: url.path)
        }

        var options = Self.boundedOptions(env: env)
        options.preferNewestCodexSessionsFirst = false
        options.useCodexCatchUpWorkingSet = true
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: historicalDay,
            until: currentDay,
            now: historicalDay,
            options: options)

        let iso = env.isoString(for: currentDay)
        let currentURL = try env.writeCodexSessionFile(
            day: currentDay,
            filename: "rollout-2026-05-10-current-priority.jsonl",
            contents: [
                #"{"type":"session_meta","timestamp":"\#(iso)","payload":{"session_id":"current-priority"}}"#,
                #"{"type":"turn_context","timestamp":"\#(iso)","payload":{"model":"openai/gpt-5.2-codex"}}"#,
                #"{"type":"event_msg","timestamp":"\#(iso)","payload":{"type":"token_count","info":"#
                    + #"{"total_token_usage":{"input_tokens":300,"cached_input_tokens":40,"output_tokens":20},"#
                    + #""model":"openai/gpt-5.2-codex"}}}"#,
            ].joined(separator: "\n") + "\n")

        try FileManager.default.setAttributes([.modificationDate: currentDay], ofItemAtPath: currentURL.path)
        var queuedCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        queuedCache.codexActiveLookbackState?.pendingFilePaths.append(currentURL.path)
        queuedCache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: queuedCache)

        let recorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = recorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: historicalDay,
            until: currentDay,
            now: currentDay,
            options: options)

        let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(recorder.snapshot().codexFileScanAttempts <= CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(cache.files[currentURL.path]?.codexScanComplete == true)
        #expect(cache.codexActiveLookbackState?.pendingFilePaths.contains(currentURL.path) == false)
        #expect(cache.codexScanCatchUpPending == true)
        let currentDayKey = CostUsageScanner.CostUsageDayRange.dayKey(
            from: currentDay,
            calendar: options.calendar)
        #expect(CostUsageScanner.codexCurrentDayProjectionGateReason(
            cache: cache,
            roots: CostUsageScanner.codexSessionsRoots(options: options),
            dayKey: currentDayKey,
            calendar: options.calendar) == nil)
        let projection = CostUsageStore(cacheRoot: env.cacheRoot).syncReadCodexReportProjection(
            calendar: options.calendar,
            temporalRange: (sinceDay: currentDayKey, untilDay: currentDayKey))
        #expect(projection.verifiedDayKeys.contains(currentDayKey))
        #expect((projection.verifiedDayEvidence[currentDayKey]?.revision ?? 0) > 0)
    }

    @Test
    func `older incomplete missing parent fork resumes ahead of history without hiding fairness`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let historicalDay = try env.makeLocalNoon(year: 2026, month: 5, day: 8)
        let currentDay = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        var options = Self.boundedOptions(env: env)
        options.preferNewestCodexSessionsFirst = true
        options.useCodexCatchUpWorkingSet = true
        options.maxCodexScanDurationPerRefresh = nil
        let fixture = try Self.prepareResumableMissingParentFixture(
            env: env,
            historicalDay: historicalDay,
            currentDay: currentDay,
            options: &options)
        let historicalURLs = fixture.historicalURLs
        let forkURL = fixture.forkURL
        let todayKey = fixture.todayKey
        let currentISO = fixture.currentISO

        // Appended token rows keep each cached parser anchor valid while making all saved
        // historical waiters genuinely dirty across the persisted queue round trip.
        try Self.appendHistoryUsageRows(historicalURLs, timestamp: currentISO, modificationDate: historicalDay)
        let forkPath = forkURL.resolvingSymlinksInPath().standardizedFileURL.path
        let partialCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let oldestHistoryPath = historicalURLs[0].path.resolvingTemporaryPath
        let oldestHistoryInputBeforeBoost = try #require(
            partialCache.files[oldestHistoryPath]?.lastCountedTotals?.input)
        let partial = try #require(partialCache.files[forkPath])
        #expect(partial.codexScanComplete == false)
        #expect(partial.codexReplacementScanPending == true)
        #expect(partial.parsedBytes ?? 0 < partial.size)
        #expect(partial.hasCurrentCodexParser)
        #expect(CostUsageScanner.isUnresolvedMissingParentFork(partial))
        let roots = CostUsageScanner.codexSessionsRoots(options: options)
        #expect(CostUsageScanner.codexCurrentDayProjectionGateReason(
            cache: partialCache,
            roots: roots,
            dayKey: todayKey,
            calendar: options.calendar) == .fork)
        let beforeResume = CostUsageStore(cacheRoot: env.cacheRoot).syncReadCodexReportProjection(
            calendar: options.calendar,
            temporalRange: (sinceDay: todayKey, untilDay: todayKey))
        #expect(!beforeResume.verifiedDayKeys.contains(todayKey))

        // Model a persisted queue that contains the historical backlog but omitted its cached
        // partial fork. Reconciliation must restore the fork before bounded candidate admission.
        var queued = partialCache
        queued.codexActiveLookbackState = try Self.completedLookbackState(
            cache: queued,
            options: options,
            pendingFilePaths: historicalURLs.map(\.path.resolvingTemporaryPath))
        queued.codexScanCatchUpPending = true
        let metadataCandidateIndexBefore = queued.codexSessionDiscovery?.metadataCandidateIndex
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: queued)

        let forkBeforePromotion = try #require(queued.files[forkPath]?.parsedBytes)
        let firstBoostBudget = CostUsageScanner.CodexScanBudget(maxFileBytes: 512, maxBytesPerRefresh: 512)
        let firstBoostRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanBudgetForTesting = firstBoostBudget
        options.codexScanWorkRecorderForTesting = firstBoostRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: historicalDay,
            until: currentDay,
            now: currentDay.addingTimeInterval(2),
            options: options)

        let afterBoost = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let boostedPaths = firstBoostRecorder.attemptedCodexFilePaths()
        let metadataCandidateIndexAfter = afterBoost.codexSessionDiscovery?.metadataCandidateIndex
        let attemptedPathNames = boostedPaths.map {
            URL(fileURLWithPath: $0).lastPathComponent
        }.sorted().prefix(8)
        let progressedPathNames = afterBoost.files.compactMap { path, usage -> String? in
            guard let previousBytes = queued.files[path]?.parsedBytes,
                  let parsedBytes = usage.parsedBytes,
                  parsedBytes > previousBytes
            else { return nil }
            return URL(fileURLWithPath: path).lastPathComponent
        }
        #expect(
            boostedPaths.contains(forkPath),
            "attempted files: \(Array(attemptedPathNames))")
        #expect(
            afterBoost.files[forkPath]?.parsedBytes ?? 0 > forkBeforePromotion,
            """
            progress: \(progressedPathNames.sorted().prefix(8)); metadata index:
            \(String(describing: metadataCandidateIndexBefore))->\(String(describing: metadataCandidateIndexAfter));
            bytes: \(firstBoostBudget.bytesConsumed)
            """)
        #expect(afterBoost.files[forkPath]?.codexScanComplete == false)
        #expect(afterBoost.files[oldestHistoryPath]?.lastCountedTotals?.input == oldestHistoryInputBeforeBoost)
        let boostedUsage = try #require(afterBoost.files[forkPath])
        #expect(boostedUsage.codexScanComplete == false)
        let admissionDebt = try #require(afterBoost.codexActiveLookbackState?.priorityAdmissionDebt)
        #expect(admissionDebt > 0)
        #expect(firstBoostRecorder.snapshot().codexCandidateSelectionVisits
            <= CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(firstBoostBudget.bytesConsumed <= 512)

        // The promoted partial owes the oldest saved waiter a bounded FIFO turn before it can
        // jump the queue again.
        let fairnessBudget = CostUsageScanner.CodexScanBudget(maxFileBytes: 1024, maxBytesPerRefresh: 1024)
        let fairnessRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanBudgetForTesting = fairnessBudget
        options.codexScanWorkRecorderForTesting = fairnessRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: historicalDay,
            until: currentDay,
            now: currentDay.addingTimeInterval(3),
            options: options)

        let afterFairness = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(fairnessRecorder.attemptedCodexFilePaths().contains(oldestHistoryPath))
        #expect(!fairnessRecorder.attemptedCodexFilePaths().contains(forkPath))
        #expect(afterFairness.files[oldestHistoryPath]?.codexScanComplete == true)
        #expect(afterFairness.files[oldestHistoryPath]?.lastCountedTotals?.input == 150)
        #expect((afterFairness.codexActiveLookbackState?.priorityAdmissionDebt ?? 0) < admissionDebt)
        #expect(fairnessBudget.bytesConsumed <= 1024)

        options.codexScanBudgetForTesting = nil
        options.maxCodexSessionFileBytes = 4 * 1024 * 1024
        options.maxCodexScanBytesPerRefresh = 4 * 1024 * 1024
        for pass in 0..<6 {
            let current = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
            if current.files[forkPath]?.codexScanComplete == true { break }
            let budget = CostUsageScanner.CodexScanBudget(
                maxFileBytes: 4 * 1024 * 1024,
                maxBytesPerRefresh: 4 * 1024 * 1024)
            let recorder = CostUsageScanner.CodexScanWorkRecorder()
            options.codexScanBudgetForTesting = budget
            options.codexScanWorkRecorderForTesting = recorder
            _ = CostUsageControlledClockScanner.loadDailyReport(
                provider: .codex,
                since: historicalDay,
                until: currentDay,
                now: currentDay.addingTimeInterval(TimeInterval(pass + 4)),
                options: options)
            #expect(recorder.snapshot().codexCandidateSelectionVisits
                <= CostUsageScanner.codexCatchUpScanCandidateLimit)
            #expect(budget.bytesConsumed <= 4 * 1024 * 1024)
        }

        options.codexScanBudgetForTesting = nil
        let resumed = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let resumedFork = try #require(resumed.files[forkPath])
        #expect(resumedFork.codexScanComplete == true)
        #expect(resumedFork.parsedBytes == resumedFork.size)
        #expect(resumedFork.hasCurrentCodexParser)
        #expect(CostUsageScanner.isUnresolvedMissingParentFork(resumedFork))
        #expect(CostUsageScanner.codexCurrentDayProjectionGateReason(
            cache: resumed,
            roots: roots,
            dayKey: todayKey,
            calendar: options.calendar) == nil)
        let afterResume = CostUsageStore(cacheRoot: env.cacheRoot).syncReadCodexReportProjection(
            calendar: options.calendar,
            temporalRange: (sinceDay: todayKey, untilDay: todayKey))
        #expect(afterResume.verifiedDayKeys.contains(todayKey))
        #expect((afterResume.verifiedDayEvidence[todayKey]?.revision ?? 0) > 0)
    }

    @Test
    func `stale cached parent identity gets a bounded FIFO turn before child retries`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let historicalDay = try env.makeLocalNoon(year: 2026, month: 5, day: 8)
        let currentDay = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        var options = Self.boundedOptions(env: env)
        options.preferNewestCodexSessionsFirst = true
        options.useCodexCatchUpWorkingSet = true
        options.maxCodexScanDurationPerRefresh = nil
        let parentSessionID = "target-000"
        let fixture = try Self.prepareResumableMissingParentFixture(
            env: env,
            historicalDay: historicalDay,
            currentDay: currentDay,
            options: &options,
            parentSessionID: parentSessionID,
            includeForkTimestamp: true)
        let forkPath = fixture.forkURL.resolvingSymlinksInPath().standardizedFileURL.path
        let parentURL = try #require(fixture.historicalURLs.first)
        let parentPath = parentURL.resolvingSymlinksInPath().standardizedFileURL.path

        let initial = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let initialParent = try #require(initial.files[parentPath])
        let initialParentSessionID = try #require(initialParent.sessionId)
        #expect(initialParent.codexScanComplete == true)
        #expect(initialParent.hasCurrentCodexParser)
        let initialDiscovery = try #require(initial.codexSessionDiscovery)

        // The durable metadata index has the correct parent path, while the compact cached
        // parent entry has lost its session ID. Keep the file's size, identity, and mtime stable
        // so bounded metadata refresh cannot discover the mismatch by stat alone.
        let originalParentData = try Data(contentsOf: parentURL)
        let originalParentText = try #require(String(bytes: originalParentData, encoding: .utf8))
        let updatedParentText = originalParentText.replacingOccurrences(
            of: #"session_id":"\#(initialParentSessionID)"#,
            with: #"session_id":"\#(parentSessionID)"#)
        #expect(updatedParentText != originalParentText)
        #expect(updatedParentText.utf8.count == originalParentData.count)
        let parentHandle = try FileHandle(forWritingTo: parentURL)
        try parentHandle.seek(toOffset: 0)
        try parentHandle.write(contentsOf: Data(updatedParentText.utf8))
        try parentHandle.close()
        let parentMtime = Date(timeIntervalSince1970: TimeInterval(initialParent.mtimeUnixMs) / 1000)
        try FileManager.default.setAttributes([.modificationDate: parentMtime], ofItemAtPath: parentURL.path)

        var staleParentCache = initial
        var staleParent = initialParent
        staleParent.sessionId = nil
        staleParent.codexSession?.sessionId = nil
        staleParent.codexSession?.concreteSessionId = nil
        staleParentCache.files[parentPath] = staleParent
        var completedDiscovery = initialDiscovery
        completedDiscovery.filePathBySessionId.removeValue(forKey: initialParentSessionID)
        completedDiscovery.filePathBySessionId[parentSessionID] = parentPath
        completedDiscovery.missingSessionIds.removeAll { $0 == parentSessionID }
        completedDiscovery.pendingSessionIds.removeAll { $0 == parentSessionID }
        completedDiscovery.metadataCandidateIndex = completedDiscovery.filePaths.count
        completedDiscovery.metadataInventoryEstablished = true
        completedDiscovery.isComplete = true
        staleParentCache.codexSessionDiscovery = completedDiscovery
        staleParentCache.codexActiveLookbackState = try Self.completedLookbackState(
            cache: staleParentCache,
            options: options,
            pendingFilePaths: fixture.historicalURLs.map(\.path.resolvingTemporaryPath))
        staleParentCache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: staleParentCache)

        let beforeResume = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let beforeChild = try #require(beforeResume.files[forkPath])
        #expect(beforeChild.codexScanComplete == false)
        #expect(CostUsageScanner.isUnresolvedMissingParentFork(beforeChild))
        #expect(beforeChild.codexBufferedUnresolvedForkLines?.contains { buffered in
            guard case let .sessionMeta(metadata) = buffered.line else { return false }
            return metadata.forkTimestamp != nil
        } == true)
        #expect(beforeResume.codexSessionDiscovery?.metadataCandidateIndex == completedDiscovery.filePaths.count)
        #expect(beforeResume.codexSessionDiscovery?.metadataInventoryEstablished == true)
        #expect(beforeResume.codexSessionDiscovery?.filePathBySessionId[parentSessionID] == parentPath)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)

        // The boosted child cannot use the cached parent row because its session identity is
        // missing. It defers before spending byte budget and queues that parent for the next pass.
        let blockedBudget = CostUsageScanner.CodexScanBudget(maxFileBytes: 512, maxBytesPerRefresh: 512)
        let blockedRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanBudgetForTesting = blockedBudget
        options.codexScanWorkRecorderForTesting = blockedRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: historicalDay,
            until: currentDay,
            now: currentDay.addingTimeInterval(2),
            options: options)

        let blocked = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(blockedRecorder.attemptedCodexFilePaths().contains(forkPath))
        #expect(!blockedRecorder.attemptedCodexFilePaths().contains(parentPath))
        #expect(blocked.codexActiveLookbackState?.pendingFilePaths.first == parentPath)
        #expect(blocked.files[parentPath]?.sessionId == nil)
        #expect(blockedBudget.bytesConsumed == 0)
        #expect(CostUsageScanner.codexCurrentDayProjectionGateReason(
            cache: blocked,
            roots: roots,
            dayKey: fixture.todayKey,
            calendar: options.calendar) == .fork)

        // Debt must let the newly queued dependency parse before promoting the blocking child
        // again. A 512-byte refresh admits only one uncached detail path at a time.
        let parentTurnBudget = CostUsageScanner.CodexScanBudget(maxFileBytes: 512, maxBytesPerRefresh: 512)
        let parentTurnRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanBudgetForTesting = parentTurnBudget
        options.codexScanWorkRecorderForTesting = parentTurnRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: historicalDay,
            until: currentDay,
            now: currentDay.addingTimeInterval(3),
            options: options)

        let parentTurn = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let parsedParent = try #require(parentTurn.files[parentPath])
        #expect(parentTurnRecorder.attemptedCodexFilePaths().contains(parentPath))
        #expect(parsedParent.sessionId == parentSessionID)
        #expect(parsedParent.parsedBytes == parsedParent.size)
        #expect(parentTurnBudget.bytesConsumed > 0)
        #expect(parentTurnBudget.bytesConsumed <= 512)
        #expect(CostUsageScanner.codexCurrentDayProjectionGateReason(
            cache: parentTurn,
            roots: roots,
            dayKey: fixture.todayKey,
            calendar: options.calendar) == .fork)

        options.maxCodexSessionFileBytes = 4 * 1024 * 1024
        options.maxCodexScanBytesPerRefresh = 4 * 1024 * 1024
        for pass in 0..<6 {
            let current = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
            if current.files[forkPath]?.codexScanComplete == true { break }
            let budget = CostUsageScanner.CodexScanBudget(
                maxFileBytes: 4 * 1024 * 1024,
                maxBytesPerRefresh: 4 * 1024 * 1024)
            let recorder = CostUsageScanner.CodexScanWorkRecorder()
            options.codexScanBudgetForTesting = budget
            options.codexScanWorkRecorderForTesting = recorder
            _ = CostUsageControlledClockScanner.loadDailyReport(
                provider: .codex,
                since: historicalDay,
                until: currentDay,
                now: currentDay.addingTimeInterval(TimeInterval(pass + 4)),
                options: options)
            #expect(recorder.snapshot().codexCandidateSelectionVisits
                <= CostUsageScanner.codexCatchUpScanCandidateLimit)
            #expect(budget.bytesConsumed <= 4 * 1024 * 1024)
        }

        options.codexScanBudgetForTesting = nil
        let resolved = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let resolvedChild = try #require(resolved.files[forkPath])
        #expect(resolvedChild.codexScanComplete == true)
        #expect(!CostUsageScanner.isUnresolvedMissingParentFork(resolvedChild))
        #expect(CostUsageScanner.codexCurrentDayProjectionGateReason(
            cache: resolved,
            roots: roots,
            dayKey: fixture.todayKey,
            calendar: options.calendar) == nil)
        let projection = CostUsageStore(cacheRoot: env.cacheRoot).syncReadCodexReportProjection(
            calendar: options.calendar,
            temporalRange: (sinceDay: fixture.todayKey, untilDay: fixture.todayKey))
        #expect(projection.verifiedDayKeys.contains(fixture.todayKey))
        #expect((projection.verifiedDayEvidence[fixture.todayKey]?.revision ?? 0) > 0)
    }

    @Test
    func `settled missing parent fork with a current activity suffix still blocks today's proof`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let historicalDay = try env.makeLocalNoon(year: 2026, month: 5, day: 8)
        let currentDay = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let oldTimestamp = env.isoString(for: historicalDay)
        let currentTimestamp = env.isoString(for: currentDay)
        let fileURL = try env.writeCodexSessionFile(
            day: historicalDay,
            filename: "rollout-2026-05-08-current-orphan.jsonl",
            contents: [
                [
                    #"{"type":"session_meta","timestamp":"\#(oldTimestamp)","payload":{"#,
                    #""id":"current-orphan","forked_from_id":"#,
                    #""missing-parent"}}"#,
                ].joined(),
                #"{"type":"turn_context","timestamp":"\#(oldTimestamp)","payload":{"model":"openai/gpt-5.4"}}"#,
                [
                    #"{"type":"event_msg","timestamp":"\#(currentTimestamp)","payload":{"type":"token_count","info":"#,
                    #"{"total_token_usage":{"input_tokens":50,"output_tokens":5}}}}"#,
                ].joined(),
            ].joined(separator: "\n") + "\n")
        try FileManager.default.setAttributes([.modificationDate: historicalDay], ofItemAtPath: fileURL.path)

        var options = Self.boundedOptions(env: env)
        options.useCodexCatchUpWorkingSet = true
        options.maxCodexScanDurationPerRefresh = nil
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: historicalDay,
            until: currentDay,
            now: currentDay,
            options: options)
        let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let filePath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
        let usage = try #require(cache.files[filePath])
        #expect(usage.codexScanComplete == true)
        #expect(usage.hasCurrentCodexParser)
        #expect(CostUsageScanner.isUnresolvedMissingParentFork(usage))
        #expect(usage.touchesCodexScanWindow(
            sinceKey: CostUsageScanner.CostUsageDayRange.dayKey(from: currentDay, calendar: options.calendar),
            untilKey: CostUsageScanner.CostUsageDayRange.dayKey(from: currentDay, calendar: options.calendar),
            calendar: options.calendar))
        let todayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: currentDay, calendar: options.calendar)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)
        #expect(CostUsageScanner.codexCurrentDayProjectionGateReason(
            cache: cache,
            roots: roots,
            dayKey: todayKey,
            calendar: options.calendar) == .fork)
        let projection = CostUsageStore(cacheRoot: env.cacheRoot).syncReadCodexReportProjection(
            calendar: options.calendar,
            temporalRange: (sinceDay: todayKey, untilDay: todayKey))
        #expect(!projection.verifiedDayKeys.contains(todayKey))

        var unknownActivity = cache
        unknownActivity.files[filePath]?.codexSession?.startedAtUnixMs = nil
        unknownActivity.files[filePath]?.codexSession?.latestActivityUnixMs = nil
        #expect(CostUsageScanner.codexCurrentDayProjectionGateReason(
            cache: unknownActivity,
            roots: roots,
            dayKey: todayKey,
            calendar: options.calendar) == .fork)
    }

    @Test
    func `most recent closed day jumps ahead of a growing current day queue`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let closedDay = try env.makeLocalNoon(year: 2026, month: 5, day: 9)
        let currentDay = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let currentURLs = try Self.writeSyntheticCorpus(
            env: env,
            day: currentDay,
            fileCount: CostUsageScanner.codexCatchUpScanCandidateLimit + 1)
        let closedURL = try #require(
            Self.writeSyntheticCorpus(env: env, day: closedDay, fileCount: 1).first)
        try FileManager.default.setAttributes(
            [.modificationDate: closedDay],
            ofItemAtPath: closedURL.path)

        var options = Self.boundedOptions(env: env)
        options.maxCodexScanDurationPerRefresh = nil
        options.preferNewestCodexSessionsFirst = false
        options.useCodexCatchUpWorkingSet = true
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: closedDay,
            until: currentDay,
            now: currentDay,
            options: options)

        var pendingCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
            .sorted()
        pendingCache.codexActiveLookbackState = try CostUsageCodexActiveLookbackState(
            scanSinceKey: #require(pendingCache.scanSinceKey),
            rootPaths: roots,
            completedRootPaths: roots,
            pendingFilePaths: currentURLs.map(\.path.resolvingTemporaryPath)
                + [closedURL.path.resolvingTemporaryPath],
            currentWindowNextDayKeyByRoot: [:],
            currentWindowDirectoryOffsetByRoot: [:],
            completedCurrentWindowRootPaths: roots,
            currentWindowFlatDirectoryOffsetByRoot: [:],
            completedCurrentWindowFlatRootPaths: roots,
            directoryCursorVersion: 3)
        pendingCache.codexScanInventoryPaths = nil
        pendingCache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: pendingCache,
            calendar: options.calendar)

        options.maxCodexScanDurationPerRefresh = 60
        let recorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = recorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: closedDay,
            until: currentDay,
            now: currentDay,
            options: options)

        let attemptedPaths = recorder.attemptedCodexFilePaths()
        let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(attemptedPaths.contains(closedURL.path.resolvingTemporaryPath))
        #expect(cache.codexActiveLookbackState?.pendingFilePaths.contains(
            closedURL.path.resolvingTemporaryPath) == false)
        #expect(cache.codexActiveLookbackState?.pendingFilePaths.isEmpty == false)
    }

    @Test
    func `closed day verification ignores current day growth but fails closed for a changed closed day`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let closedDay = try env.makeLocalNoon(year: 2026, month: 5, day: 9)
        let currentDay = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let currentURL = try #require(Self.writeSyntheticCorpus(
            env: env,
            day: currentDay,
            fileCount: 1,
            sessionIDPrefix: "progress-current").first)
        let closedURL = try #require(Self.writeSyntheticCorpus(
            env: env,
            day: closedDay,
            fileCount: 1,
            sessionIDPrefix: "progress-closed").first)
        try FileManager.default.setAttributes(
            [.modificationDate: currentDay],
            ofItemAtPath: currentURL.path)
        try FileManager.default.setAttributes(
            [.modificationDate: closedDay],
            ofItemAtPath: closedURL.path)

        var options = Self.boundedOptions(env: env)
        options.maxCodexScanDurationPerRefresh = nil
        options.useCodexCatchUpWorkingSet = true
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: closedDay,
            until: currentDay,
            now: currentDay,
            options: options)

        let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)
        let closedPath = try #require(cache.files.keys.first {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path
                == closedURL.resolvingSymlinksInPath().standardizedFileURL.path
        })
        let closedUsage = try #require(cache.files[closedPath])
        #expect(closedUsage.codexScanComplete == true)
        #expect(closedUsage.parsedBytes == closedUsage.size)

        let closedDayKey = CostUsageScanner.CostUsageDayRange.dayKey(
            from: closedDay,
            calendar: options.calendar)
        let canPublish = {
            CostUsageScanner.codexCurrentDayProjectionCanPublish(
                cache: cache,
                roots: roots,
                dayKey: closedDayKey,
                calendar: options.calendar)
        }
        #expect(canPublish())
        #expect(CostUsageScanner.codexCurrentDayProjectionGateReason(
            cache: cache,
            roots: roots,
            dayKey: closedDayKey,
            calendar: options.calendar) == nil)

        var wrongScope = cache
        wrongScope.roots = [:]
        #expect(CostUsageScanner.codexCurrentDayProjectionGateReason(
            cache: wrongScope,
            roots: roots,
            dayKey: closedDayKey,
            calendar: options.calendar) == .scope)

        var legacyClosed = cache
        legacyClosed.files[closedPath]?.codexParserRevision = nil
        #expect(!CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: legacyClosed,
            roots: roots,
            dayKey: closedDayKey,
            calendar: options.calendar))
        #expect(CostUsageScanner.codexCurrentDayProjectionGateReason(
            cache: legacyClosed,
            roots: roots,
            dayKey: closedDayKey,
            calendar: options.calendar) == .unindexed)

        let iso = env.isoString(for: currentDay.addingTimeInterval(1))
        let appendedRow =
            #"{"type":"event_msg","timestamp":"\#(iso)","payload":{"type":"token_count","info":"#
                + #"{"total_token_usage":{"input_tokens":200,"cached_input_tokens":20,"output_tokens":10},"#
                + #""model":"openai/gpt-5.2-codex"}}}"#
        let currentHandle = try FileHandle(forWritingTo: currentURL)
        try currentHandle.seekToEnd()
        try currentHandle.write(contentsOf: Data((appendedRow + "\n").utf8))
        try currentHandle.close()
        try FileManager.default.setAttributes(
            [.modificationDate: currentDay.addingTimeInterval(1)],
            ofItemAtPath: currentURL.path)
        #expect(canPublish())

        let original = try String(contentsOf: closedURL, encoding: .utf8)
        let rewritten = original.replacingOccurrences(
            of: #""input_tokens":100"#,
            with: #""input_tokens":900"#)
        #expect(rewritten != original)
        try rewritten.write(to: closedURL, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: closedDay.addingTimeInterval(1)],
            ofItemAtPath: closedURL.path)
        #expect(!canPublish())
        #expect(CostUsageScanner.codexCurrentDayProjectionGateReason(
            cache: cache,
            roots: roots,
            dayKey: closedDayKey,
            calendar: options.calendar) == .stale)
    }

    @Test
    func `exact validation requeues a completed prefix path rewritten after its slice`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let corpusSize = CostUsageScanner.codexCatchUpScanCandidateLimit + 1
        let fileURLs = try Self.writeSyntheticCorpus(env: env, day: day, fileCount: corpusSize)

        var options = Self.boundedOptions(env: env)
        options.maxCodexScanDurationPerRefresh = nil
        options.preferNewestCodexSessionsFirst = false
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)

        let rewrittenURL = fileURLs[0]
        let incompleteURL = try #require(fileURLs.last)
        var pendingCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let rewrittenPath = try #require(pendingCache.files.keys.first { $0.hasSuffix(rewrittenURL.lastPathComponent) })
        let incompletePath = try #require(pendingCache.files.keys
            .first { $0.hasSuffix(incompleteURL.lastPathComponent) })
        pendingCache.files[incompletePath]?.codexScanComplete = false
        pendingCache.codexActiveLookbackState = nil
        pendingCache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: pendingCache)

        options.maxCodexScanDurationPerRefresh = 60
        let firstRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = firstRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)
        #expect(firstRecorder.snapshot().codexFileScanAttempts == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(firstRecorder.snapshot().codexProgressAccountingVisits == 0)

        let original = try String(contentsOf: rewrittenURL, encoding: .utf8)
        let rewritten = original.replacingOccurrences(of: #""input_tokens":100"#, with: #""input_tokens":900"#)
        #expect(rewritten != original)
        #expect(rewritten.utf8.count == original.utf8.count)
        try rewritten.write(to: rewrittenURL, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: day.addingTimeInterval(120)],
            ofItemAtPath: rewrittenURL.path)

        let secondRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = secondRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(2),
            options: options)
        let secondMetrics = secondRecorder.snapshot()
        let secondCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(secondMetrics.codexCandidateSelectionVisits == 1)
        #expect(secondMetrics.codexFileScanAttempts == 1)
        #expect(secondMetrics.codexProgressAccountingVisits == 0)
        #expect(secondCache.codexActiveLookbackState?.pendingFilePaths.isEmpty == true)
        #expect(secondCache.codexScanCompletedFiles == corpusSize)
        #expect(secondCache.codexScanInventoryPaths == nil)
        #expect(secondCache.codexScanCatchUpPending == true)

        let thirdRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = thirdRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(3),
            options: options)
        let thirdMetrics = thirdRecorder.snapshot()
        let thirdCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(thirdMetrics.codexDiscoveryVisits == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(thirdMetrics.codexProgressAccountingVisits == 0)
        #expect(thirdCache.codexScanCatchUpPending == true)

        let finalCache = try Self.finishBoundedCatchUp(
            env: env,
            day: day,
            options: &options,
            startingAt: 4)
        #expect(finalCache.files[rewrittenPath]?.lastCountedTotals?.input == 900)
        #expect(finalCache.codexActiveLookbackState == nil)
        #expect(finalCache.codexScanCompletedFiles == corpusSize)
        #expect(finalCache.codexScanTotalFiles == corpusSize)
        #expect(finalCache.codexScanCatchUpPending == false)
    }

    @Test
    func `missing queue prefix advances after scanner validation`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let corpusSize = CostUsageScanner.codexCatchUpScanCandidateLimit + 1
        let fileURLs = try Self.writeSyntheticCorpus(env: env, day: day, fileCount: corpusSize)

        var options = Self.boundedOptions(env: env)
        options.maxCodexScanDurationPerRefresh = nil
        options.preferNewestCodexSessionsFirst = false
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)

        var pendingCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let validURL = try #require(fileURLs.last)
        let validPath = try #require(pendingCache.files.keys.first { $0.hasSuffix(validURL.lastPathComponent) })
        let roots = CostUsageScanner.codexSessionsRoots(options: options)
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
            .sorted()
        let missingURLs = fileURLs.prefix(CostUsageScanner.codexCatchUpScanCandidateLimit)
        for fileURL in missingURLs {
            try FileManager.default.removeItem(at: fileURL)
        }
        pendingCache.files[validPath]?.codexScanComplete = false
        pendingCache.codexScanInventoryPaths = nil
        pendingCache.codexActiveLookbackState = try CostUsageCodexActiveLookbackState(
            scanSinceKey: #require(pendingCache.scanSinceKey),
            rootPaths: roots,
            completedRootPaths: roots,
            pendingFilePaths: missingURLs.map(\.path.resolvingTemporaryPath) + [validURL.path.resolvingTemporaryPath])
        pendingCache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: pendingCache)

        options.maxCodexScanDurationPerRefresh = 60
        let firstRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = firstRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)
        let firstMetrics = firstRecorder.snapshot()
        let firstCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(firstMetrics.codexCandidateSelectionVisits == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(firstMetrics.codexFileScanAttempts == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(firstMetrics.codexProgressAccountingVisits == 0)
        #expect(firstCache.codexActiveLookbackState?.pendingFilePaths == [validURL.path.resolvingTemporaryPath])
        #expect(firstCache.codexScanCatchUpPending == true)

        let finalRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = finalRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(2),
            options: options)
        let finalMetrics = finalRecorder.snapshot()
        let finalCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(finalMetrics.codexCandidateSelectionVisits == 1)
        #expect(finalMetrics.codexFileScanAttempts == 1)
        #expect(finalMetrics.codexProgressAccountingVisits == 0)
        #expect(finalCache.codexActiveLookbackState?.pendingFilePaths.isEmpty == true)
        #expect(finalCache.codexScanCompletedFiles == corpusSize)
        #expect(finalCache.codexScanTotalFiles == corpusSize)
        #expect(finalCache.codexScanCatchUpPending == true)

        let validationRecorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = validationRecorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(3),
            options: options)
        let validatedCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(validationRecorder.snapshot().codexCandidateSelectionVisits == 0)
        #expect(validationRecorder.snapshot().codexFileScanAttempts == 0)
        #expect(validationRecorder.snapshot().codexProgressAccountingVisits
            <= CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(validatedCache.codexActiveLookbackState == nil)
        #expect(validatedCache.codexScanCatchUpPending == false)

        let converged = try Self.finishBoundedCatchUp(
            env: env,
            day: day,
            options: &options,
            startingAt: 4)
        #expect(converged.codexActiveLookbackState == nil)
        #expect(converged.files.count == 1)
        #expect(converged.codexScanCompletedFiles == 1)
        #expect(converged.codexScanTotalFiles == 1)
        #expect(converged.codexScanCatchUpPending == false)
    }

    @Test
    func `time budget stop retains selected paths that were not scanned`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let corpusSize = CostUsageScanner.codexCatchUpScanCandidateLimit + 1
        let fileURLs = try Self.writeSyntheticCorpus(env: env, day: day, fileCount: corpusSize)

        var options = Self.boundedOptions(env: env)
        options.maxCodexScanDurationPerRefresh = nil
        options.preferNewestCodexSessionsFirst = false
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)

        var pendingCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let incompleteURL = try #require(fileURLs.last)
        let incompletePath = try #require(pendingCache.files.keys
            .first { $0.hasSuffix(incompleteURL.lastPathComponent) })
        pendingCache.files[incompletePath]?.codexScanComplete = false
        pendingCache.codexScanInventoryPaths = nil
        pendingCache.codexActiveLookbackState = nil
        pendingCache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: pendingCache)

        options.maxCodexScanDurationPerRefresh = .leastNonzeroMagnitude
        let recorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = recorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)
        let metrics = recorder.snapshot()
        let stoppedCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(metrics.codexCandidateSelectionVisits == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(metrics.codexFileScanAttempts == 0)
        #expect(metrics.activeLookbackCompletionCandidates == 0)
        #expect(metrics.codexProgressAccountingVisits == 0)
        #expect(stoppedCache.codexActiveLookbackState?.pendingFilePaths.count
            == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(stoppedCache.files[incompletePath]?.codexScanComplete == false)
        #expect(stoppedCache.codexScanCatchUpPending == true)
        #expect(try #require(stoppedCache.codexScanCompletedFiles) < #require(stoppedCache.codexScanTotalFiles))
    }

    @Test
    func `reset progress baseline counts validated cached snapshots`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let corpusSize = CostUsageScanner.codexCatchUpScanCandidateLimit + 1
        try Self.writeSyntheticCorpus(env: env, day: day, fileCount: corpusSize)

        var options = Self.boundedOptions(env: env)
        options.maxCodexScanDurationPerRefresh = nil
        options.preferNewestCodexSessionsFirst = false
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)

        var pendingCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        for path in pendingCache.files.keys {
            pendingCache.files[path]?.codexCostCacheComplete = false
        }
        pendingCache.codexScanInventoryPaths = nil
        pendingCache.codexActiveLookbackState = nil
        pendingCache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: pendingCache)

        options.maxCodexScanDurationPerRefresh = 60
        let recorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = recorder
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)
        let metrics = recorder.snapshot()
        let migratedCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(metrics.codexCandidateSelectionVisits == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(metrics.codexFileScanAttempts == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(metrics.codexProgressAccountingVisits == 0)
        #expect(migratedCache.codexScanCompletedFiles == CostUsageScanner.codexCatchUpScanCandidateLimit)
        #expect(migratedCache.codexScanTotalFiles == corpusSize)
        #expect(migratedCache.codexActiveLookbackState?.pendingFilePaths.count == 1)
        #expect(migratedCache.codexScanCatchUpPending == true)
    }

    private static func completedLookbackState(
        cache: CostUsageCache,
        options: CostUsageScanner.Options,
        pendingFilePaths: [String]) throws -> CostUsageCodexActiveLookbackState
    {
        let roots = CostUsageScanner.codexSessionsRoots(options: options)
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
            .sorted()
        return try CostUsageCodexActiveLookbackState(
            scanSinceKey: #require(cache.scanSinceKey),
            rootPaths: roots,
            completedRootPaths: roots,
            pendingFilePaths: pendingFilePaths,
            currentWindowNextDayKeyByRoot: [:],
            currentWindowDirectoryOffsetByRoot: [:],
            completedCurrentWindowRootPaths: roots,
            currentWindowFlatDirectoryOffsetByRoot: [:],
            completedCurrentWindowFlatRootPaths: roots,
            directoryCursorVersion: 3)
    }

    @Test
    func `parser migration reseed keeps persisted waiters ahead of revisited files`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        var options = Self.boundedOptions(env: env)
        let since = try #require(options.calendar.date(byAdding: .day, value: -364, to: day))
        let files = try Self.writeSyntheticCorpus(env: env, day: day, fileCount: 600)
        for (index, file) in files.enumerated() {
            try FileManager.default.setAttributes(
                [.modificationDate: day.addingTimeInterval(Double(-index))], ofItemAtPath: file.path)
        }
        options.maxCodexScanDurationPerRefresh = nil
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex, since: since, until: day, now: day, options: options)
        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(cache.files.count == 600)
        #expect(cache.codexScanCatchUpPending == false)

        // The 88 oldest files mimic completed revision-2 entries during this upgrade.
        let stalePaths = files[512...].map { $0.resolvingSymlinksInPath().path }
        for path in stalePaths {
            #expect(cache.files[path] != nil)
            cache.files[path]?.codexParserRevision = 2
        }
        cache.codexPricingKey = "migration-generation-1"
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache)

        options.maxCodexScanDurationPerRefresh = 60
        for pass in 1...2 {
            if pass > 1 {
                var mutated = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
                mutated.codexPricingKey = "migration-generation-\(pass)"
                CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: mutated)
            }
            let recorder = CostUsageScanner.CodexScanWorkRecorder()
            options.codexScanWorkRecorderForTesting = recorder
            _ = CostUsageControlledClockScanner.loadDailyReport(
                provider: .codex,
                since: since,
                until: day,
                now: day.addingTimeInterval(Double(pass)),
                options: options)
            #expect(recorder.snapshot().codexFileScanAttempts == CostUsageScanner.codexCatchUpScanCandidateLimit)
        }
        let migrated = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let remainingStale = stalePaths.filter { migrated.files[$0]?.hasCurrentCodexParser != true }
        #expect(remainingStale.isEmpty, "stale files never reached the bounded pass: \(remainingStale.count)")
        #expect(migrated.codexActiveLookbackState?.pendingFilePaths.count == 88)

        options.codexScanWorkRecorderForTesting = nil
        for index in 0..<8 {
            _ = CostUsageControlledClockScanner.loadDailyReport(
                provider: .codex,
                since: since,
                until: day,
                now: day.addingTimeInterval(Double(index + 10)),
                options: options)
            if CostUsageStoreAccess.read(cacheRoot: env.cacheRoot).codexScanCatchUpPending == false {
                break
            }
        }
        let completed = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(completed.codexScanCatchUpPending == false)
        #expect(completed.codexActiveLookbackState == nil)
        #expect(completed.codexScanCompletedFiles == 600)
        #expect(completed.codexScanTotalFiles == 600)
    }

    private static func boundedOptions(env: CostUsageTestEnvironment) -> CostUsageScanner.Options {
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"),
            maxCodexSessionFileBytes: 0,
            maxCodexScanBytesPerRefresh: 0,
            maxCodexScanDurationPerRefresh: 60)
        options.refreshMinIntervalSeconds = 0
        return options
    }

    private static func appendHistoryUsageRows(
        _ historyURLs: [URL],
        timestamp: String,
        modificationDate: Date) throws
    {
        let appendedRow = [
            #"{"type":"event_msg","timestamp":"\#(timestamp)","payload":{"type":"token_count","info":"#,
            #"{"total_token_usage":{"input_tokens":150,"cached_input_tokens":30,"output_tokens":15}}}}"#,
        ].joined() + "\n"
        for historyURL in historyURLs {
            let handle = try FileHandle(forWritingTo: historyURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(appendedRow.utf8))
            try handle.close()
            try FileManager.default.setAttributes(
                [.modificationDate: modificationDate],
                ofItemAtPath: historyURL.path)
        }
    }

    private static func prepareResumableMissingParentFixture(
        env: CostUsageTestEnvironment,
        historicalDay: Date,
        currentDay: Date,
        options: inout CostUsageScanner.Options,
        parentSessionID: String = "missing-parent",
        includeForkTimestamp: Bool = false) throws -> (
        historicalURLs: [URL],
        forkURL: URL,
        todayKey: String,
        currentISO: String)
    {
        let historicalURLs = try Self.writeSyntheticCorpus(
            env: env,
            day: historicalDay,
            fileCount: CostUsageScanner.codexCatchUpScanCandidateLimit + 32)
        let forkURL = try env.writeCodexSessionFile(
            day: historicalDay,
            filename: "rollout-2026-05-08-resumable-orphan.jsonl",
            contents: [
                [
                    #"{"type":"session_meta","timestamp":"2026-05-08T16:00:00Z","payload":{"#,
                    #""id":"old-orphan","forked_from_id":"#,
                    #""\#(parentSessionID)"}}"#,
                ].joined(),
                #"{"type":"turn_context","timestamp":"2026-05-08T16:00:01Z","payload":{"model":"openai/gpt-5.4"}}"#,
                [
                    #"{"type":"event_msg","timestamp":"2026-05-08T16:00:02Z","payload":{"type":"token_count","info":"#,
                    #"{"total_token_usage":{"input_tokens":50,"output_tokens":5}}}}"#,
                ].joined(),
            ].joined(separator: "\n") + "\n")
        for url in historicalURLs + [forkURL] {
            try FileManager.default.setAttributes([.modificationDate: historicalDay], ofItemAtPath: url.path)
        }

        let useWorkingSetAfterWarmup = options.useCodexCatchUpWorkingSet
        options.useCodexCatchUpWorkingSet = false
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: historicalDay,
            until: historicalDay,
            now: historicalDay,
            options: options)
        options.useCodexCatchUpWorkingSet = useWorkingSetAfterWarmup
        let initial = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(initial.files.count == historicalURLs.count + 1)
        #expect(initial.codexScanCatchUpPending == false)
        let todayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: currentDay, calendar: options.calendar)
        let beforeFork = CostUsageStore(cacheRoot: env.cacheRoot).syncReadCodexReportProjection(
            calendar: options.calendar,
            temporalRange: (sinceDay: todayKey, untilDay: todayKey))
        #expect(!beforeFork.verifiedDayKeys.contains(todayKey))

        let currentISO = env.isoString(for: historicalDay)
        let paddingLines = (0..<2000).map { _ in
            #"{"type":"turn_context","payload":{"model":"openai/gpt-5.4"}}"#
        }
        let forkTimestampField = includeForkTimestamp ? #","timestamp":"\#(currentISO)""# : ""
        let orphanContents = ([
            [
                #"{"type":"session_meta","timestamp":"\#(currentISO)","payload":{"id":"old-orphan","forked_from_id":"#,
                #""\#(parentSessionID)"\#(forkTimestampField)}}"#,
            ].joined(),
            #"{"type":"turn_context","timestamp":"\#(currentISO)","payload":{"model":"openai/gpt-5.4"}}"#,
            [
                #"{"type":"event_msg","timestamp":"\#(currentISO)","payload":{"type":"token_count","info":"#,
                #"{"total_token_usage":{"input_tokens":50,"output_tokens":5}}}}"#,
            ].joined(),
        ] + paddingLines).joined(separator: "\n") + "\n"
        try Data(orphanContents.utf8).write(to: forkURL)
        try FileManager.default.setAttributes([.modificationDate: historicalDay], ofItemAtPath: forkURL.path)

        let firstPartialBudget = CostUsageScanner.CodexScanBudget(maxFileBytes: 512, maxBytesPerRefresh: 512)
        options.maxCodexSessionFileBytes = 512
        options.maxCodexScanBytesPerRefresh = 512
        options.codexScanBudgetForTesting = firstPartialBudget
        _ = CostUsageControlledClockScanner.loadDailyReport(
            provider: .codex,
            since: historicalDay,
            until: currentDay,
            now: currentDay.addingTimeInterval(1),
            options: options)
        options.codexScanBudgetForTesting = nil
        #expect(firstPartialBudget.bytesConsumed <= 512)
        return (historicalURLs, forkURL, todayKey, currentISO)
    }

    private static func finishBoundedCatchUp(
        env: CostUsageTestEnvironment,
        day: Date,
        options: inout CostUsageScanner.Options,
        startingAt offset: Int) throws -> CostUsageCache
    {
        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        for pass in 0..<12 {
            let recorder = CostUsageScanner.CodexScanWorkRecorder()
            options.codexScanWorkRecorderForTesting = recorder
            _ = CostUsageControlledClockScanner.loadDailyReport(
                provider: .codex,
                since: day,
                until: day,
                now: day.addingTimeInterval(TimeInterval(offset + pass)),
                options: options)
            let metrics = recorder.snapshot()
            #expect(metrics.codexDiscoveryVisits <= CostUsageScanner.codexCatchUpScanCandidateLimit)
            #expect(metrics.codexProgressAccountingVisits <= CostUsageScanner.codexCatchUpScanCandidateLimit)
            #expect(metrics.codexDiscoveryVisits + metrics.codexProgressAccountingVisits
                <= CostUsageScanner.codexCatchUpScanCandidateLimit)
            cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
            if cache.codexScanCatchUpPending == false {
                return cache
            }
        }
        Issue.record("bounded catch-up did not complete within 12 persisted pages")
        return cache
    }

    @discardableResult
    private static func writeSyntheticCorpus(
        env: CostUsageTestEnvironment,
        day: Date,
        fileCount: Int,
        sessionIDPrefix: String = "progress") throws -> [URL]
    {
        let iso = env.isoString(for: day)
        var fileURLs: [URL] = []
        fileURLs.reserveCapacity(fileCount)
        for index in 0..<fileCount {
            let lines = [
                #"{"type":"session_meta","timestamp":"\#(iso)","payload":{"session_id":"\#(sessionIDPrefix)-\#(index)"}}"#,
                #"{"type":"turn_context","timestamp":"\#(iso)","payload":{"model":"openai/gpt-5.2-codex"}}"#,
                #"{"type":"event_msg","timestamp":"\#(iso)","payload":{"type":"token_count","info":"#
                    + #"{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10},"#
                    + #""model":"openai/gpt-5.2-codex"}}}"#,
            ]
            try fileURLs.append(env.writeCodexSessionFile(
                day: day,
                filename: String(format: "progress-%04d.jsonl", index),
                contents: lines.joined(separator: "\n") + "\n"))
        }
        return fileURLs
    }
}

extension String {
    fileprivate var resolvingTemporaryPath: String {
        URL(fileURLWithPath: self).resolvingSymlinksInPath().standardizedFileURL.path
            .replacingOccurrences(of: "/private/var/", with: "/var/", options: [.anchored])
    }
}

private final class BoundedProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        self.lock.withLock { self.count }
    }

    func increment() {
        self.lock.withLock { self.count += 1 }
    }
}
