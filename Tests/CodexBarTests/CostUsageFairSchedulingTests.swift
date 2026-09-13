import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageFairSchedulingTests {
    @Test
    func `admission quota decodes older lookback state and round trips`() throws {
        let legacy = Data("""
        {
          "scanSinceDay": "2026-05-07",
          "rootPaths": [],
          "nextDayByRoot": {},
          "completedRootPaths": [],
          "pendingFilePaths": [],
          "legacyRecursivePendingRootPaths": []
        }
        """.utf8)
        var state = try JSONDecoder().decode(CostUsageStoreLookbackState.self, from: legacy)
        #expect(state.priorityAdmissionDebt == nil)
        state.priorityAdmissionDebt = 2
        let restored = try JSONDecoder().decode(
            CostUsageStoreLookbackState.self,
            from: JSONEncoder().encode(state))
        #expect(restored.priorityAdmissionDebt == 2)
    }

    @Test(arguments: [false, true])
    func `new current sessions alternate with historical waiters under one file budgets`(timeOnly: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let today = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let oldDay = try #require(Calendar.current.date(byAdding: .day, value: -3, to: today))
        let slice: Int64 = 1024
        let historical = try (0..<3).map { index in
            try Self.write(env: env, day: oldDay, name: "historical-\(index)", rows: 80, mtime: oldDay)
        }
        var options = Self.options(env: env, slice: slice, budget: 3 * slice)
        options.useCodexCatchUpWorkingSet = true
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex, since: oldDay, until: today, now: oldDay, options: options)
        let seeded = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        for path in historical {
            #expect((seeded.files[path.path]?.parsedBytes ?? 0) > 0)
            #expect(seeded.files[path.path]?.codexScanComplete == false)
        }

        options.maxCodexSessionFileBytes = timeOnly ? 0 : slice
        options.maxCodexScanBytesPerRefresh = timeOnly ? 0 : slice
        for pass in 1...6 {
            let fresh = try Self.write(
                env: env,
                day: today,
                name: "new-current-\(pass)",
                rows: 40,
                mtime: today.addingTimeInterval(Double(pass)))
            let start = ContinuousClock.now
            let budgetReference = LockIsolated<CostUsageScanner.CodexScanBudget?>(nil)
            let budget = CostUsageScanner.CodexScanBudget(
                maxFileBytes: timeOnly ? 0 : slice,
                maxBytesPerRefresh: timeOnly ? 0 : slice,
                maxDuration: 60,
                now: {
                    (budgetReference.value?.bytesConsumed ?? 0) > 0
                        ? start.advanced(by: .seconds(61)) : start
                })
            budgetReference.setValue(budget)
            options.codexScanBudgetForTesting = budget
            let recorder = CostUsageScanner.CodexScanWorkRecorder()
            options.codexScanWorkRecorderForTesting = recorder
            _ = CostUsageScanner.loadDailyReport(
                provider: .codex,
                since: oldDay,
                until: today,
                now: today.addingTimeInterval(Double(pass)),
                options: options)
            #expect(recorder.attemptedCodexFilePaths().count == 1)
            if pass == 1 {
                let afterFirst = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
                #expect((afterFirst.files[fresh.path]?.parsedBytes ?? 0) > 0)
                #expect((afterFirst.codexActiveLookbackState?.priorityAdmissionDebt ?? 0) > 0)
            }
        }
        let final = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        for path in historical {
            #expect((final.files[path.path]?.parsedBytes ?? 0) > (seeded.files[path.path]?.parsedBytes ?? 0))
        }
    }

    @Test(arguments: [false, true])
    func `partial files advance while fresh files keep arriving`(timed: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let slice: Int64 = 1024
        var options = Self.options(env: env, slice: slice, budget: slice * 3)
        let waiting = try (0..<3).map { index in
            try Self.write(
                env: env,
                day: day,
                name: "waiting-\(index)",
                rows: 80,
                mtime: day.addingTimeInterval(Double(index)))
        }
        _ = Self.scan(day: day, pass: 0, options: options)
        let seeded = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        for file in waiting {
            #expect((seeded.files[file.path]?.parsedBytes ?? 0) > 0)
            #expect(seeded.files[file.path]?.codexScanComplete == false)
        }

        options.maxCodexScanBytesPerRefresh = slice
        options.maxCodexScanDurationPerRefresh = timed ? 60 : nil
        for pass in 1...4 {
            let fresh = try Self.write(
                env: env,
                day: day,
                name: "fresh-\(pass)",
                rows: 40,
                mtime: day.addingTimeInterval(Double(100 + pass)))
            #expect(CostUsageScanner.codexFileMetadata(fileURL: fresh).size > slice)
            let budget = CostUsageScanner.CodexScanBudget(
                maxFileBytes: slice,
                maxBytesPerRefresh: slice,
                maxDuration: timed ? 60 : nil)
            options.codexScanBudgetForTesting = budget
            _ = Self.scan(day: day, pass: pass, options: options)
            #expect(budget.bytesConsumed <= slice)
        }
        let final = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        for file in waiting {
            #expect((final.files[file.path]?.parsedBytes ?? 0) > (seeded.files[file.path]?.parsedBytes ?? 0))
        }
    }

    @Test
    func `two slice budget serves backlog and recent closed day`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let oldDay = try #require(Calendar.current.date(byAdding: .day, value: -2, to: day))
        let recentDay = try #require(Calendar.current.date(byAdding: .day, value: -1, to: day))
        let old = try Self.write(
            env: env,
            day: oldDay,
            name: "backlog",
            rows: 80,
            mtime: oldDay)
        let recent = try Self.write(
            env: env,
            day: recentDay,
            name: "recent",
            rows: 80,
            mtime: recentDay)
        var options = Self.options(env: env, slice: 1024, budget: 2048)
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex, since: oldDay, until: day, now: day, options: options)
        let before = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(before.files[old.path]?.codexScanComplete == false)
        #expect(before.files[recent.path]?.codexScanComplete == false)

        let budget = CostUsageScanner.CodexScanBudget(maxFileBytes: 1024, maxBytesPerRefresh: 2048)
        options.codexScanBudgetForTesting = budget
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: oldDay,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)
        let after = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect((after.files[old.path]?.parsedBytes ?? 0) > (before.files[old.path]?.parsedBytes ?? 0))
        #expect((after.files[recent.path]?.parsedBytes ?? 0) > (before.files[recent.path]?.parsedBytes ?? 0))
        #expect(budget.bytesConsumed <= 2048)
    }

    @Test
    func `live append in old partition cannot claim historical catch up slot`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let today = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let liveDay = try #require(Calendar.current.date(byAdding: .day, value: -9, to: today))
        let backlogDay = try #require(Calendar.current.date(byAdding: .day, value: -8, to: today))
        let closedDay = try #require(Calendar.current.date(byAdding: .day, value: -1, to: today))
        let live = try Self.write(env: env, day: liveDay, name: "live-old-partition", rows: 10, mtime: liveDay)
        let backlog = try Self.write(
            env: env,
            day: backlogDay,
            name: "historical-backlog",
            rows: 80,
            mtime: backlogDay)
        let closed = try Self.write(
            env: env,
            day: closedDay,
            name: "closed-day-priority",
            rows: 80,
            mtime: closedDay)
        let slice: Int64 = 1024
        var options = Self.options(env: env, slice: slice, budget: 3 * slice)
        options.useCodexCatchUpWorkingSet = true
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex, since: liveDay, until: today, now: today, options: options)
        let seeded = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        for file in [live, backlog, closed] {
            #expect((seeded.files[file.path]?.parsedBytes ?? 0) > 0)
            #expect(seeded.files[file.path]?.codexScanComplete == false)
        }

        options.maxCodexScanBytesPerRefresh = 2 * slice
        for pass in 1...6 {
            let iso = env.isoString(for: today.addingTimeInterval(Double(pass * 60)))
            let line = #"{"type":"event_msg","timestamp":"\#(iso)","payload":{"type":"token_count","info":{"#
                + #""total_token_usage":{"input_tokens":\#(9000 + pass * 100),"cached_input_tokens":0,"output_tokens":"#
                + #"\#(900 + pass * 10)},"model":"gpt-5.2-codex"}}}"# + "\n"
            let handle = try FileHandle(forWritingTo: live)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
            try FileManager.default.setAttributes(
                [.modificationDate: today.addingTimeInterval(Double(pass * 60))],
                ofItemAtPath: live.path)
            let budget = CostUsageScanner.CodexScanBudget(
                maxFileBytes: slice, maxBytesPerRefresh: 2 * slice)
            options.codexScanBudgetForTesting = budget
            _ = CostUsageScanner.loadDailyReport(
                provider: .codex,
                since: liveDay,
                until: today,
                now: today.addingTimeInterval(Double(pass * 60)),
                options: options)
            #expect(budget.bytesConsumed <= 2 * slice)
        }
        let after = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        for file in [live, backlog, closed] {
            #expect((after.files[file.path]?.parsedBytes ?? 0) > (seeded.files[file.path]?.parsedBytes ?? 0))
        }
        let currentDayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: today)
        #expect(after.files[live.path]?.days[currentDayKey] != nil)
    }

    private static func options(env: CostUsageTestEnvironment, slice: Int64, budget: Int64)
        -> CostUsageScanner.Options
    {
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"),
            maxCodexSessionFileBytes: slice,
            maxCodexScanBytesPerRefresh: budget)
        options.refreshMinIntervalSeconds = 0
        return options
    }

    private static func scan(day: Date, pass: Int, options: CostUsageScanner.Options) -> CostUsageDailyReport {
        CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(Double(pass)),
            options: options)
    }

    private static func write(env: CostUsageTestEnvironment, day: Date, name: String, rows: Int, mtime: Date)
        throws -> URL
    {
        let header = #"{"type":"session_meta","payload":{"id":"\#(name)"}}"# + "\n"
        let iso = env.isoString(for: day)
        let body = (1...rows).map { index in
            // swiftlint:disable:next line_length
            #"{"type":"event_msg","timestamp":"\#(iso)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(index * 100),"cached_input_tokens":0,"output_tokens":\#(index * 10)},"model":"gpt-5.2-codex"}}}"#
        }.joined(separator: "\n") + "\n"
        let url = try env.writeCodexSessionFile(day: day, filename: name + ".jsonl", contents: header + body)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
        return url
    }
}
