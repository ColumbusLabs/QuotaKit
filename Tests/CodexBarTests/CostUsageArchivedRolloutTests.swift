import Foundation
import Testing
@testable import CodexBarCore
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

@Suite(.serialized)
struct CostUsageArchivedRolloutTests {
    @Test
    func `archiving parsed rollouts retains totals and coverage in both roots`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let first = try env.writeCodexSessionFile(day: day, filename: "first.jsonl", contents: Self.rollout(env, day))
        let second = env.codexArchivedSessionsRoot.appendingPathComponent("second.jsonl")
        try Self.rollout(env, day, tokens: 70).write(to: second, atomically: true, encoding: .utf8)
        let before = try await Self.establish(env, day)
        #expect(before.sessionTokens == 400)
        #expect((before.sessionCostUSD ?? 0) > 0)
        try Self.archive(first)
        try Self.archive(second)
        let after = try await Self.establish(env, day)
        #expect(after.sessionTokens == before.sessionTokens)
        #expect(after.sessionCostUSD == before.sessionCostUSD)
        #expect(after.historyCoverageIsEstablished)
        try FileManager.default.removeItem(at: first.appendingPathExtension("zst"))
        #expect(try await Self.establish(env, day).sessionTokens == 70)
    }

    @Test
    func `rollout presence distinguishes deletion from inaccessible paths`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let plain = env.codexSessionsRoot.appendingPathComponent("presence.jsonl")
        #expect(CostUsageScanner.codexRolloutPresence(plain.path) == .missing)
        try Data().write(to: plain.appendingPathExtension("zst"))
        #expect(CostUsageScanner.codexRolloutPresence(plain.path) == .archived)
        try Data().write(to: plain)
        #expect(CostUsageScanner.codexRolloutPresence(plain.path) == .plain)
        let loop = env.root.appendingPathComponent("loop")
        try FileManager.default.createSymbolicLink(atPath: loop.path, withDestinationPath: loop.path)
        #expect(CostUsageScanner.codexRolloutPresence(loop.appendingPathComponent("test.jsonl").path) == .unavailable)
        let leaf = env.codexSessionsRoot.appendingPathComponent("leaf.jsonl")
        try FileManager.default.createSymbolicLink(atPath: leaf.path, withDestinationPath: leaf.path)
        #expect(CostUsageScanner.codexRolloutPresence(leaf.path) == .unavailable)
        try FileManager.default.removeItem(at: leaf)
        try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: false)
        #expect(CostUsageScanner.codexRolloutPresence(leaf.path) == .unavailable)
        try FileManager.default.removeItem(at: leaf)
        try FileManager.default.createSymbolicLink(
            atPath: leaf.appendingPathExtension("zst").path, withDestinationPath: leaf.path)
        #expect(CostUsageScanner.codexRolloutPresence(leaf.path) == .unavailable)
    }

    @Test
    func `inaccessible history survives force rescan pruning and retention`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 1)
        let later = day.addingTimeInterval(30 * 86400)
        let plain = try env.writeCodexSessionFile(day: day, filename: "keep.jsonl", contents: Self.rollout(env, day))
        #expect(try await Self.establish(env, day).sessionTokens == 330)
        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        var plainCache = cache
        CostUsageScanner.pruneForceRescanFilesOutsideWindow(
            cache: &plainCache,
            range: .init(since: later, until: later),
            isForceRescan: true)
        #expect(plainCache.files[plain.path] == nil)
        let removedUsage = cache.files.removeValue(forKey: plain.path)
        let usage = try #require(removedUsage)
        let loop = env.root.appendingPathComponent("unavailable-loop")
        try FileManager.default.createSymbolicLink(atPath: loop.path, withDestinationPath: loop.path)
        let unavailable = loop.appendingPathComponent("keep.jsonl").path
        cache.files[unavailable] = usage
        let days = cache.days
        CostUsageScanner.pruneForceRescanFilesOutsideWindow(
            cache: &cache,
            range: .init(since: later, until: later),
            isForceRescan: true)
        #expect(cache.files[unavailable] != nil)
        #expect(cache.days == days)
        _ = CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, home: env.codexStoreHome, cache: cache)
        let store = CostUsageStore(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        _ = await store.retainDayWindow(sinceDay: "2026-08-30", untilDay: "2026-08-31")
        _ = await store.enforceBudgets(
            maxRows: 0, maxFileBytes: 0, requestedSinceDay: "2026-08-30", requestedUntilDay: "2026-08-31")
        let retained = await store.readSnapshot()
        #expect(retained.files.contains { $0.path == unavailable })
        #expect(!retained.fileDayAggregates.isEmpty)
        #expect(!retained.dayAggregates.isEmpty)
    }

    @Test
    func `a compatible parser predecessor retains archived usage across home scans`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let plain = try env.writeCodexSessionFile(day: day, filename: "first.jsonl", contents: Self.rollout(env, day))
        #expect(try await Self.establish(env, day).sessionTokens == 330)
        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        var usage = try #require(cache.files[plain.path])
        usage.codexParserRevision = 0
        cache.files[plain.path] = usage
        _ = CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, home: env.codexStoreHome, cache: cache)
        try Self.archive(plain)
        let databaseURL = CostUsageStore(cacheRoot: env.cacheRoot, home: env.codexStoreHome).databaseURL
        var database: OpaquePointer?
        try #require(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        let oldHash = "7d66d60c44b88609"
        #expect(CostUsageStore.compatiblePredecessorParserHashes.contains(oldHash))
        let version = CostUsageStore.combinedSchemaVersion(base: CostUsageStore.baseSchemaVersion, parserHash: oldHash)
        try #require(sqlite3_exec(
            database,
            "UPDATE meta SET value = '\(oldHash)' WHERE key = 'parser_hash'; PRAGMA user_version = \(version)",
            nil,
            nil,
            nil) == SQLITE_OK)
        sqlite3_close(database)
        let other = env.root.appendingPathComponent("other/sessions")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        var options = Self.options(env)
        options.codexSessionsRoot = other
        _ = CostUsageScanner.loadDailyReport(provider: .codex, since: day, until: day, now: day, options: options)
        let retained = try #require(await CostUsageFetcher.loadCachedCodexTokenSnapshot(
            now: day,
            codexHomePath: env.codexHomeRoot.path,
            historyDays: 1,
            allowScopedCodexHome: true,
            includePiSessions: false,
            scannerOptions: Self.options(env)))
        #expect(retained.sessionTokens == 330)
        #expect(retained.historyCoverageIsEstablished)
        #expect(try await Self.establish(env, day).sessionTokens == 330)
    }

    @Test
    func `unknown parser with compressed only history preserves the database`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let plain = try env.writeCodexSessionFile(
            day: day, filename: "unknown-parser.jsonl", contents: Self.rollout(env, day))
        #expect(try await Self.establish(env, day).sessionTokens == 330)
        try Self.archive(plain)
        let databaseURL = CostUsageStore.databaseURL(cacheRoot: env.cacheRoot)
        var raw: OpaquePointer?
        try #require(sqlite3_open(databaseURL.path, &raw) == SQLITE_OK)
        guard let raw else { throw CostUsageStore.StoreError.invalidData }
        defer { sqlite3_close(raw) }
        let unknown = "synthetic-unknown-archive-parser"
        let version = CostUsageStore.combinedSchemaVersion(base: CostUsageStore.baseSchemaVersion, parserHash: unknown)
        try CostUsageStore.writeMetaValue(unknown, key: "parser_hash", database: raw)
        try CostUsageStore.execute(raw, "PRAGMA user_version = \(version)")
        let beforeFiles = try CostUsageStore.scalarInt(raw, "SELECT COUNT(*) FROM files")
        let beforeRows = try CostUsageStore.scalarInt(raw, "SELECT COUNT(*) FROM usage_rows")
        let beforeAggregates = try CostUsageStore.scalarInt(raw, "SELECT COUNT(*) FROM file_day_aggregates")
        #expect(beforeFiles > 0)
        #expect(beforeRows > 0)
        #expect(beforeAggregates > 0)
        let store = CostUsageStore(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        #expect(await store.configuration() == nil)
        #expect(await store.rebuildCount == 0)
        // Reopen the same fixture through a second spelling so the scanner's retained
        // store registry does not hide the simulated change made by another process.
        let alias = env.root.appendingPathComponent("cache-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: env.cacheRoot)
        var options = Self.options(env)
        options.cacheRoot = alias
        do {
            _ = try CostUsageScanner.loadDailyReportCancellable(
                provider: .codex, since: day, until: day, now: day, options: options, checkCancellation: nil)
            Issue.record("An unreadable archived cache must fail the throwing scanner")
        } catch CostUsageError.cachedSnapshotUnavailable {
            // The previous cache remains intact for recovery with a compatible producer.
        } catch {
            Issue.record("Unexpected archive error: \(error)")
        }
        #expect(try CostUsageStore.scalarInt(raw, "PRAGMA user_version") == Int64(version))
        #expect(try CostUsageStore.scalarText(raw, "SELECT value FROM meta WHERE key = 'parser_hash'") == unknown)
        #expect(try CostUsageStore.scalarInt(raw, "SELECT COUNT(*) FROM files") == beforeFiles)
        #expect(try CostUsageStore.scalarInt(raw, "SELECT COUNT(*) FROM usage_rows") == beforeRows)
        #expect(try CostUsageStore.scalarInt(raw, "SELECT COUNT(*) FROM file_day_aggregates") == beforeAggregates)
        #expect(FileManager.default.fileExists(atPath: plain.appendingPathExtension("zst").path))
    }

    @Test
    func `time zone changes report archived history conflict and preserve stored data`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let plain = try env.writeCodexSessionFile(
            day: day, filename: "timezone.jsonl", contents: Self.rollout(env, day))
        #expect(try await Self.establish(env, day).sessionTokens == 330)
        try Self.archive(plain)
        let store = CostUsageStore(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        let before = await store.readSnapshot()
        let originalTimeZone = try #require(before.metadata.timeZoneIdentifier)
        var options = Self.options(env)
        let alternate = originalTimeZone == "Etc/GMT+11" ? "Etc/GMT-11" : "Etc/GMT+11"
        options.calendar.timeZone = try #require(TimeZone(identifier: alternate))
        do {
            _ = try CostUsageScanner.loadDailyReportCancellable(
                provider: .codex, since: day, until: day, now: day, options: options, checkCancellation: nil)
            Issue.record("A changed time zone must fail while compressed-only history exists")
        } catch CostUsageError.archivedHistoryTimeZoneConflict {
            // Without the original JSONL, the cached history cannot be safely re-attributed.
        } catch {
            Issue.record("Unexpected time zone conflict error: \(error)")
        }
        #expect(await store.readSnapshot() == before)
        #expect(await store.rebuildCount == 0)
        #expect(FileManager.default.fileExists(atPath: plain.appendingPathExtension("zst").path))
    }

    @Test
    func `both rollout forms count once during paged scans`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let plain = try env.writeCodexSessionFile(day: day, filename: "both.jsonl", contents: Self.rollout(env, day))
        try Data("unread archive".utf8).write(to: plain.appendingPathExtension("zst"))
        #expect(try await Self.establish(env, day).sessionTokens == 330)
        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        cache.codexScanCatchUpPending = true
        cache.codexScanTotalFiles = 600
        cache.codexScanInventoryPaths = (0..<600).map {
            env.codexSessionsRoot.appendingPathComponent("pending-\($0).jsonl").path
        }
        _ = CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, home: env.codexStoreHome, cache: cache)
        try Self.archive(plain)
        var options = Self.options(env)
        options.maxCodexScanDurationPerRefresh = 60
        for _ in 0..<3 {
            let report = CostUsageScanner.loadDailyReport(
                provider: .codex, since: day, until: day, now: day, options: options)
            #expect(report.summary?.totalTokens == 330)
        }
    }

    @Test
    func `a restored plain sibling preserves the debounced report then replaces archived usage`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let plain = try env.writeCodexSessionFile(
            day: day,
            filename: "restored.jsonl",
            contents: Self.rollout(env, day))
        #expect(try await Self.establish(env, day).sessionTokens == 330)
        try Self.archive(plain)
        #expect(try await Self.establish(env, day).sessionTokens == 330)

        try Self.rollout(env, day, tokens: 660).write(to: plain, atomically: true, encoding: .utf8)
        var options = Self.options(env)
        options.refreshMinIntervalSeconds = 3600
        let debounced = CostUsageScanner.loadDailyReport(
            provider: .codex, since: day, until: day, now: day, options: options)
        #expect(debounced.summary?.totalTokens == 330)
        #expect(try await Self.establish(env, day).sessionTokens == 660)
    }

    @Test
    func `forced and changed lookback windows retain archived accounting`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let olderDay = day.addingTimeInterval(-3 * 86400)
        let plain = try env.writeCodexSessionFile(
            day: day, filename: "retained.jsonl", contents: Self.rollout(env, day))
        let older = try env.writeCodexSessionFile(
            day: olderDay, filename: "older.jsonl", contents: Self.rollout(env, olderDay, tokens: 70))
        var options = Self.options(env)
        let initial = CostUsageScanner.loadDailyReport(
            provider: .codex, since: olderDay, until: day, now: day, options: options)
        #expect(initial.summary?.totalTokens == 400)
        try Self.archive(plain)
        try Self.archive(older)
        options.forceRescan = true
        let narrow = CostUsageScanner.loadDailyReport(
            provider: .codex, since: day, until: day, now: day, options: options)
        #expect(narrow.summary?.totalTokens == 330)
        options.forceRescan = false
        let wide = CostUsageScanner.loadDailyReport(
            provider: .codex, since: olderDay, until: day, now: day, options: options)
        #expect(wide.summary?.totalTokens == 400)
        #expect(try await Self.establish(env, day).historyCoverageIsEstablished)
    }

    @Test
    func `storage budgets preserve archived rows outside a narrowed report window`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let olderDay = day.addingTimeInterval(-3 * 86400)
        let older = try env.writeCodexSessionFile(
            day: olderDay, filename: "older.jsonl", contents: Self.rollout(env, olderDay, tokens: 70))
        let options = Self.options(env)
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex, since: olderDay, until: day, now: day, options: options)
        try Self.archive(older)
        let store = CostUsageStore(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        _ = await store.enforceBudgets(
            maxRows: 0,
            maxFileBytes: 0,
            requestedSinceDay: "2026-08-30",
            requestedUntilDay: "2026-08-30")
        let wide = CostUsageScanner.loadDailyReport(
            provider: .codex, since: olderDay, until: day, now: day, options: options)
        #expect(wide.summary?.totalTokens == 70)
        let beforeRetention = await store.readSnapshot()
        #expect(beforeRetention.files.contains { $0.path == older.path })
        #expect(!beforeRetention.fileDayAggregates.isEmpty)
        #expect(!beforeRetention.dayAggregates.isEmpty)
        let retention = await store.retainDayWindow(sinceDay: "2026-08-30", untilDay: "2026-08-30")
        let afterRetention = await store.readSnapshot()
        #expect(retention.deletedFiles == 0)
        #expect(retention.deletedFileDayAggregates == 0)
        #expect(retention.deletedDayAggregates == 0)
        #expect(afterRetention.files == beforeRetention.files)
        #expect(afterRetention.fileDayAggregates == beforeRetention.fileDayAggregates)
        #expect(afterRetention.dayAggregates == beforeRetention.dayAggregates)
    }

    @Test
    func `unseen archive only rollouts are ignored without decoding errors`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        try Data("not a zstd frame".utf8)
            .write(to: env.codexArchivedSessionsRoot.appendingPathComponent("unseen.jsonl.zst"))
        let report = try await Self.establish(env, day)
        #expect((report.sessionTokens ?? 0) == 0)
    }

    @Test
    func `a fork resolves a parent archived after its plain rollout was cached`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let parentDay = try env.makeLocalNoon(year: 2026, month: 8, day: 1)
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 17)
        let parentId = "0199f0a0-0000-7000-8000-000000000020"
        let childId = "0199f0a0-0000-7000-8000-000000000021"
        let parentName = "rollout-2026-08-01T12-00-00-\(parentId).jsonl"
        let parentContents = Self.forkParentRollout(env: env, id: parentId, at: parentDay)
        let parentURL = try env.writeCodexSessionFile(day: parentDay, filename: parentName, contents: parentContents)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"))
        options.refreshMinIntervalSeconds = 0
        func refresh(on date: Date) -> Int? {
            CostUsageScanner.loadDailyReport(provider: .codex, since: date, until: date, now: date, options: options)
                .summary?.totalTokens
        }
        for _ in 0..<3 {
            _ = refresh(on: parentDay)
        }
        #expect(CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, home: env.codexStoreHome).files.values
            .contains { $0.sessionId == parentId })

        // Codex archives the parent; a fork of it is scanned later, with the parent outside the window.
        try Self.archive(parentURL)
        _ = try env.writeCodexSessionFile(
            day: day,
            filename: "rollout-2026-09-17T12-00-00-\(childId).jsonl",
            contents: Self.forkChildRollout(env: env, id: childId, parent: parentId, at: day))
        var total: Int?
        for _ in 0..<4 {
            total = refresh(on: day)
        }

        #expect(total == 20)
        let child = try #require(CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, home: env.codexStoreHome).files
            .values.first {
                $0.sessionId == childId
            })
        #expect(!CostUsageScanner.isUnresolvedMissingParentFork(child))
    }

    @Test
    func `an archived fork keeps its inherited baseline after its ancestor is archived`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let firstDay = try env.makeLocalNoon(year: 2026, month: 8, day: 1)
        let parentDay = try env.makeLocalNoon(year: 2026, month: 8, day: 2)
        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 3)
        let firstID = "0199f0a0-0000-7000-8000-000000000030"
        let parentID = "0199f0a0-0000-7000-8000-000000000031"
        let childID = "0199f0a0-0000-7000-8000-000000000032"
        let first = try env.writeCodexSessionFile(
            day: firstDay,
            filename: "rollout-2026-08-01T12-00-00-\(firstID).jsonl",
            contents: Self.forkParentRollout(env: env, id: firstID, at: firstDay))
        var options = Self.options(env)
        func refresh(_ date: Date) -> Int? {
            CostUsageScanner.loadDailyReport(
                provider: .codex, since: date, until: date, now: date, options: options).summary?.totalTokens
        }
        for _ in 0..<3 {
            #expect(refresh(firstDay) == 1000)
        }
        let parent = try env.writeCodexSessionFile(
            day: parentDay,
            filename: "rollout-2026-08-02T12-00-00-\(parentID).jsonl",
            contents: Self.forkChildRollout(env: env, id: parentID, parent: firstID, at: parentDay))
        for _ in 0..<3 {
            #expect(refresh(parentDay) == 20)
        }
        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        cache.codexScanCatchUpPending = true
        cache.codexScanTotalFiles = 600
        cache.codexScanInventoryPaths = (0..<600).map {
            env.codexSessionsRoot.appendingPathComponent("pending-\($0).jsonl").path
        }
        _ = CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, home: env.codexStoreHome, cache: cache)
        options.maxCodexScanDurationPerRefresh = 60
        try Self.archive(first)
        try Self.archive(parent)
        _ = try env.writeCodexSessionFile(
            day: day,
            filename: "rollout-2026-08-03T12-00-00-\(childID).jsonl",
            contents: Self.forkChildRollout(
                env: env, id: childID, parent: parentID, at: day, inherited: 1020, added: 30))
        var total: Int?
        for _ in 0..<4 {
            total = refresh(day)
        }
        #expect(total == 30)
    }

    private static func forkMetadata(
        env: CostUsageTestEnvironment,
        id: String,
        parent: String?,
        at date: Date) -> String
    {
        let fork = parent.map { #","forked_from_id":"\#($0)""# } ?? ""
        return #"{"type":"session_meta","payload":{"id":"\#(id)","source":"vscode","#
            + #""thread_source":"user","timestamp":"\#(env.isoString(for: date))"\#(fork)}}"#
    }

    private static func forkTokens(env: CostUsageTestEnvironment, _ input: Int, last: Int?, at date: Date) -> String {
        let lastUsage = last.map { #","last_token_usage":{"input_tokens":\#($0),"output_tokens":0}"# } ?? ""
        return #"{"type":"event_msg","timestamp":"\#(env.isoString(for: date))","payload":{"type":"token_count","#
            + #""info":{"model":"gpt-5.4","total_token_usage":{"input_tokens":\#(input),"output_tokens":0}"#
            + #"\#(lastUsage)}}}"#
    }

    /// A parent session that used 1,000 tokens.
    private static func forkParentRollout(env: CostUsageTestEnvironment, id: String, at date: Date) -> String {
        [
            self.forkMetadata(env: env, id: id, parent: nil, at: date),
            self.forkTokens(env: env, 1000, last: 1000, at: date),
        ].joined(separator: "\n") + "\n"
    }

    /// A fork with known inherited counters and its own suffix.
    private static func forkChildRollout(
        env: CostUsageTestEnvironment,
        id: String,
        parent: String,
        at date: Date,
        inherited: Int = 1000,
        added: Int = 20)
        -> String
    {
        [
            self.forkMetadata(env: env, id: id, parent: parent, at: date),
            self.forkTokens(env: env, inherited, last: nil, at: date.addingTimeInterval(1)),
            self.forkTokens(env: env, inherited + added, last: added, at: date.addingTimeInterval(2)),
        ].joined(separator: "\n") + "\n"
    }

    private static func options(_ env: CostUsageTestEnvironment) -> CostUsageScanner.Options {
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"))
        options.refreshMinIntervalSeconds = 0
        return options
    }

    private static func establish(_ env: CostUsageTestEnvironment, _ day: Date) async throws -> CostUsageTokenSnapshot {
        var result: CostUsageTokenSnapshot?
        for _ in 0..<3 {
            result = try await CostUsageFetcher.loadTokenSnapshot(
                provider: .codex,
                environment: [:],
                now: day,
                codexHomePath: env.codexHomeRoot.path,
                historyDays: 1,
                allowPricingRefresh: false,
                includePiSessions: false,
                bypassScannerDebounce: true,
                scannerOptions: Self.options(env))
        }
        return try #require(result)
    }

    private static func archive(_ plain: URL) throws {
        try Data("archive is never read".utf8).write(to: plain.appendingPathExtension("zst"))
        try FileManager.default.removeItem(at: plain)
    }

    private static func rollout(_ env: CostUsageTestEnvironment, _ day: Date, tokens: Int = 330) -> String {
        let context = #"{"type":"turn_context","timestamp":"\#(env.isoString(for: day))","#
            + #""payload":{"model":"gpt-5.4"}}"#
        let timestamp = env.isoString(for: day.addingTimeInterval(1))
        let usage = #"{"type":"event_msg","timestamp":"\#(timestamp)","#
            + #""payload":{"type":"token_count","info":{"model":"gpt-5.4","#
            + #""last_token_usage":{"input_tokens":\#(tokens),"output_tokens":0}}}}"#
        return "\(context)\n\(usage)\n"
    }
}
