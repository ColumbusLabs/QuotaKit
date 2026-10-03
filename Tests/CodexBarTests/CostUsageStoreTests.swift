import Foundation
import Testing
@testable import CodexBarCore

#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

// Store invariants share one fixture/helper vocabulary across focused extensions.
// swiftlint:disable file_length

struct CostUsageStoreTests {
    @Test
    func `identical save does not retain a snapshot pruned by SQLite`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let writer = CostUsageStore(cacheRoot: fixture.root)
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-03"
        let currentPath = "/rollouts/current.jsonl"
        cache.files[currentPath] = CostUsageFileUsage(mtimeUnixMs: 1000, size: 0, days: [:])
        _ = writer.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-03"))
        var stale = Self.file(path: "/rollouts/pruned-after-identical-save.jsonl", day: "2026-07-01")
        stale.scanState.detailsPayload = try #require(
            await writer.fetchFile(path: currentPath)?.scanState.detailsPayload)
        #expect(await writer.upsertFile(stale))

        let loaded = CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: calendar)
        defer { loaded.release() }
        #expect(loaded.cache.files[stale.path] != nil)
        let saved = CostUsageStoreAccess.save(
            store: loaded.store,
            cache: loaded.cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-03"),
            skipIdenticalContent: true,
            expectedScanStamp: loaded.scanStamp,
            receipt: loaded.receipt,
            requireScanStamp: true)
        #expect(!saved.catchUpRequired)
        #expect(saved.deletedRows == 0)
        let reloaded = CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: calendar)
        #expect(reloaded.store === loaded.store)
        #expect(reloaded.cache.files[stale.path] == nil)
    }

    @Test
    func `external Codex save invalidates scan and rejects stale receipt`() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let writer = CostUsageStore(cacheRoot: fixture.root)
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.files["/sessions/a.jsonl"] = CostUsageFileUsage(mtimeUnixMs: 1, size: 0, days: [:])
        _ = writer.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        let stale = CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: calendar)
        defer { stale.release() }

        cache.files["/sessions/b.jsonl"] = CostUsageFileUsage(mtimeUnixMs: 2, size: 0, days: [:])
        _ = writer.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        let refused = CostUsageStoreAccess.save(
            store: stale.store,
            cache: stale.cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
            expectedScanStamp: stale.scanStamp,
            receipt: stale.receipt,
            requireScanStamp: true)
        #expect(refused.catchUpRequired)
        let fresh = CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: calendar)
        defer { fresh.release() }
        #expect(fresh.cache.files["/sessions/b.jsonl"] != nil)
    }

    @Test
    func `scanner store retention stays bounded by cache root`() throws {
        let fixtures = try (0..<5).map { _ in try StoreFixture() }
        defer { fixtures.forEach { $0.remove() } }
        let calendar = Calendar(identifier: .gregorian)
        let first = CostUsageStoreAccess.load(cacheRoot: fixtures[0].root, calendar: calendar)
        for fixture in fixtures.dropFirst() {
            _ = CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: calendar)
        }
        let reloaded = CostUsageStoreAccess.load(cacheRoot: fixtures[0].root, calendar: calendar)
        #expect(first.store !== reloaded.store)
    }

    @Test
    func `changed Codex file writes stay bounded as unchanged files grow`() async throws {
        func changedSaveWrites(fileCount: Int) async throws -> Int {
            let fixture = try StoreFixture()
            defer { fixture.remove() }
            let store = CostUsageStore(cacheRoot: fixture.root)
            var cache = CostUsageCache()
            cache.scanSinceKey = "2026-08-01"
            cache.scanUntilKey = "2026-08-01"
            cache.files = Dictionary(uniqueKeysWithValues: (0..<fileCount).map { index in
                ("/sessions/\(index).jsonl", CostUsageFileUsage(
                    mtimeUnixMs: 1000,
                    size: 0,
                    days: [:]))
            })
            _ = store.syncSaveCodexCache(
                cache,
                calendar: .current,
                requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
            var changed = store.syncLoadCodexCache(calendar: .current)
            changed.lastScanUnixMs += 1000
            changed.files["/sessions/0.jsonl"]?.lastModel = "test-model"
            let before = await store.persistenceWriteMetricsForTesting()
            let result = store.syncSaveCodexCache(
                changed,
                calendar: .current,
                requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
                skipIdenticalContent: true)
            let after = await store.persistenceWriteMetricsForTesting()
            #expect(!result.catchUpRequired)
            var restoredFiles = store.syncLoadCodexCache(calendar: .current).files
            let changedPath = "/sessions/0.jsonl"
            #expect(restoredFiles[changedPath]?.codexLedgerRevision
                != changed.files[changedPath]?.codexLedgerRevision)
            restoredFiles[changedPath]?.codexLedgerRevision = changed.files[changedPath]?.codexLedgerRevision
            #expect(restoredFiles == changed.files)
            return after.rows - before.rows
        }

        let small = try await changedSaveWrites(fileCount: 2)
        let large = try await changedSaveWrites(fileCount: 12)
        #expect(large <= small + 5)
    }

    @Test
    func `full save refreshes unchanged file aggregates after pricing changes`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let path = "/sessions/pricing.jsonl"
        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000,
            size: 100,
            days: ["2026-08-01": ["gpt-5.6-sol": [10, 2, 3]]])
        usage.parsedBytes = 100
        usage.codexScanComplete = true
        usage.codexRows = [CostUsageScanner.CodexUsageRow(
            day: "2026-08-01",
            model: "gpt-5.6-sol",
            turnID: "turn-1",
            eventIndex: 0,
            input: 10,
            cached: 2,
            output: 3,
            knownCostNanos: 1200,
            pricingMode: "standard")]
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.files[path] = usage
        cache.days = usage.days
        cache.codexPricingKey = "pricing-v1"
        let scanWindow = (sinceKey: "2026-08-01", untilKey: "2026-08-01")
        _ = store.syncSaveCodexCache(cache, calendar: calendar, requestedScanWindow: scanWindow)

        let original = try #require(await store.fetchFileDayAggregates(path: path).first)
        var stale = original
        stale.standardResolvedCostNanos = 999
        #expect(await store.replaceFileDayAggregates(path: path, aggregates: [stale]))

        var repriced = store.syncLoadCodexCache(calendar: calendar)
        let unchangedUsage = repriced.files[path]
        repriced.codexPricingKey = "pricing-v2"
        let result = store.syncSaveCodexCache(
            repriced,
            calendar: calendar,
            requestedScanWindow: scanWindow,
            skipIdenticalContent: true)

        #expect(!result.catchUpRequired)
        var restoredUsage = store.syncLoadCodexCache(calendar: calendar).files[path]
        restoredUsage?.codexLedgerRevision = unchangedUsage?.codexLedgerRevision
        #expect(restoredUsage == unchangedUsage)
        #expect(await store.fetchFileDayAggregates(path: path) == [original])
    }

    @Test
    func `stable cursor persists changed pricing evidence in usage rows`() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let path = "/sessions/repriced.jsonl"
        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000,
            size: 100,
            days: ["2026-08-01": ["gpt-5.6-sol": [10, 0, 3]]])
        usage.parsedBytes = 100
        usage.codexScanComplete = true
        usage.codexRows = [CostUsageScanner.CodexUsageRow(
            day: "2026-08-01",
            model: "gpt-5.6-sol",
            turnID: "turn-1",
            eventIndex: 0,
            input: 10,
            cached: 0,
            output: 3,
            pricingMode: "standard")]
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.files[path] = usage
        cache.days = usage.days
        let window = (sinceKey: "2026-08-01", untilKey: "2026-08-01")
        _ = store.syncSaveCodexCache(cache, calendar: calendar, requestedScanWindow: window)

        usage.codexRows = [CostUsageScanner.CodexUsageRow(
            day: "2026-08-01",
            model: "gpt-5.6-sol",
            turnID: "turn-1",
            eventIndex: 0,
            input: 10,
            cached: 0,
            output: 3,
            pricingMode: "priority")]
        cache.files[path] = usage
        _ = store.syncSaveCodexCache(cache, calendar: calendar, requestedScanWindow: window)

        #expect(store.syncLoadCodexCache(calendar: calendar).files[path]?.codexRows?.first?.pricingMode == "priority")
    }

    @Test
    func `file aggregates keep event details with their day and model`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let path = "/sessions/grouped-history.jsonl"
        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000,
            size: 100,
            days: [
                "2026-08-01": ["model-a": [12, 0, 5]],
                "2026-08-02": ["model-b": [3, 0, 4]],
            ])
        usage.codexScanComplete = true
        usage.codexRows = [
            CostUsageScanner.CodexUsageRow(
                day: "2026-08-01",
                model: "model-a",
                turnID: "one",
                eventIndex: 0,
                input: 10,
                cached: 0,
                output: 2,
                knownCostNanos: 100,
                pricingMode: "standard"),
            CostUsageScanner.CodexUsageRow(
                day: "2026-08-02",
                model: "model-b",
                turnID: "two",
                eventIndex: 0,
                input: 3,
                cached: 0,
                output: 4,
                knownCostNanos: 200,
                pricingMode: "priority"),
            CostUsageScanner.CodexUsageRow(
                day: "2026-08-01",
                model: "model-a",
                turnID: "three",
                eventIndex: 0,
                input: 2,
                cached: 0,
                output: 3,
                knownCostNanos: 300,
                pricingMode: "standard"),
        ]
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-02"
        cache.files[path] = usage
        cache.days = usage.days
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        _ = store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-02"))

        let aggregates = await store.fetchFileDayAggregates(path: path)
        #expect(aggregates.map(\.day) == ["2026-08-01", "2026-08-02"])
        #expect(aggregates.map(\.requestCount) == [2, 1])
        #expect(aggregates.map(\.authoritativeCostNanos) == [400, 200])
        #expect(aggregates.map(\.standardTokens) == [17, 0])
        #expect(aggregates.map(\.priorityTokens) == [0, 7])
    }

    @Test
    func `pending Codex pricing survives a staged replacement reload`() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let path = "/sessions/pricing-replacement.jsonl"
        let evidence = CostUsageScanner.CodexPricingEvidence(
            pricingModel: "gpt-5.6-sol",
            pricingMode: "priority")
        var usage = CostUsageFileUsage(mtimeUnixMs: 1000, size: 100, days: [:])
        usage.parsedBytes = 50
        usage.codexScanFileId = "7:42"
        usage.codexScanTargetSize = 100
        usage.codexScanComplete = false
        usage.codexReplacementScanPending = true
        usage.codexPendingPricing = ["request-key": evidence]
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.files[path] = usage

        let result = store.syncSaveCodexCache(
            cache,
            calendar: .current,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!result.catchUpRequired)
        let restored = store.syncLoadCodexCache(calendar: .current)
        #expect(restored.files[path]?.codexPendingPricing == ["request-key": evidence])
        #expect(restored.files[path]?.codexReplacementScanPending == true)
    }

    @Test
    func `replacement lineage refreshes without changing the committed fork ledger`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let path = "/sessions/lineage-replacement.jsonl"
        let legacyState = try JSONDecoder().decode(
            CostUsageStoreScanState.self, from: Data(#"{"isComplete":true}"#.utf8))
        #expect(legacyState.replacementForkLineage == nil)
        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000, size: 100, days: ["2026-08-01": ["test-model": [40, 0, 4]]])
        #expect(usage.hasCurrentCodexParser)
        usage.sessionId = "child"
        usage.forkedFromId = "parent"
        usage.forkBaselineDependencyKey = "committed-parent-key"
        usage.parsedBytes = 100
        usage.codexScanComplete = true
        usage.codexRows = [.init(
            day: "2026-08-01", model: "test-model", turnID: nil, eventIndex: 0, input: 40, cached: 0, output: 4)]
        usage.codexTokenSnapshots = [.init(
            timestamp: "2026-08-01T12:00:00Z", last: nil, total: .init(input: 100, cached: 0, output: 10))]
        var cache = CostUsageCache()
        cache.lastScanUnixMs = 1000
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.files[path] = usage
        cache.days = usage.days
        let window = (sinceKey: "2026-08-01", untilKey: "2026-08-01")
        _ = store.syncSaveCodexCache(cache, calendar: calendar, requestedScanWindow: window)
        let committedLineage = try #require(await store.fetchForkLineage(path: path))
        let committedRows = await store.fetchUsageRows(path: path)
        let committedSnapshots = await store.fetchTokenSnapshots(path: path)
        let committedAggregates = await store.fetchFileDayAggregates(path: path)
        #expect(store.syncReadCodexReportProjection(calendar: calendar).verifiedUpdatedAtUnixMs == 1000)
        #expect(!committedRows.isEmpty)
        #expect(!committedSnapshots.isEmpty)

        // A wider refresh must not publish complete coverage while its new parent is missing.
        cache.scanSinceKey = "2026-07-31"
        usage.codexReplacementScanPending = true
        usage.codexRows = nil
        usage.codexStagedRecoveryRows = []
        usage.codexBufferedUnresolvedForkLines = [.init(
            lineIndex: 1,
            ordinal: nil,
            line: .tokenCount(.init(
                timestamp: "2026-08-01T12:00:00Z",
                model: "test-model",
                turnID: nil,
                last: nil,
                total: .init(input: 100, cached: 0, output: 10))))]
        // Missing discovery generations change when other files disappear. A later present
        // but unread parent clears that evidence; nil must not fall back to the old key.
        let lineages: [(parent: String?, key: String?)] = [
            ("parent", "missing|parent|discovery|first"),
            ("parent", "missing|parent|discovery|second"),
            ("parent", nil),
            (nil, nil),
        ]
        for (parent, key) in lineages {
            usage.forkedFromId = parent
            usage.forkBaselineDependencyKey = key
            cache.files[path] = usage
            cache.lastScanUnixMs += 1000
            cache.codexScanCatchUpPending = usage.hasPendingCodexScanWork
            #expect(!store.syncSaveCodexCache(
                cache, calendar: calendar, requestedScanWindow: window).catchUpRequired)
            let reopened = CostUsageStore(cacheRoot: fixture.root)
            let restored = try #require(reopened.syncLoadCodexCache(calendar: calendar).files[path])
            #expect(restored.forkedFromId == parent)
            #expect(restored.forkBaselineDependencyKey == key)
            #expect(restored.hasPendingCodexScanWork == (key == nil))
            let status = reopened.syncLoadCodexReadView(calendar: calendar, purpose: .status)
            #expect(status.hasPendingScan == (key == nil))
            let projection = reopened.syncReadCodexReportProjection(calendar: calendar)
            #expect(projection.verifiedUpdatedAtUnixMs == 1000)
            #expect(projection.verifiedScanSinceKey == "2026-08-01")
            let progress = reopened.syncReadCodexCatchUpProjection(calendar: calendar)
            #expect(progress.files.first?.forkedFromID == parent)
            #expect(progress.files.first?.forkBaselineDependencyKey == key)
            #expect(await reopened.fetchForkLineage(path: path) == committedLineage)
            #expect(await reopened.fetchUsageRows(path: path) == committedRows)
            #expect(await reopened.fetchTokenSnapshots(path: path) == committedSnapshots)
            #expect(await reopened.fetchFileDayAggregates(path: path) == committedAggregates)
        }
    }

    @Test
    func `rescan rows retain observed model and tier when fresh trace omits them`() {
        let row = CostUsageScanner.CodexUsageRow(
            day: "2026-08-01",
            model: "test-model",
            turnID: "turn-1",
            eventIndex: 0,
            input: 10,
            cached: 2,
            output: 3)
        let evidence = CostUsageScanner.CodexPricingEvidence(
            pricingModel: "test-priced-model", pricingMode: "priority")
        let classified = CostUsageScanner.codexRowsWithPricingMetadata(
            [row],
            priorityTurns: [:],
            preservingPricingFrom: { _ in evidence })

        #expect(classified.first?.pricingModel == evidence.pricingModel)
        #expect(classified.first?.pricingMode == evidence.pricingMode)
    }

    /// The store actor runs on a custom DispatchQueue-backed `SerialExecutor`, and its
    /// `sync*` bridges hand work to the actor from inside `queue.sync`. Getting that handoff
    /// wrong takes the app down on launch with "Incorrect actor executor assumption", so the
    /// bridges have to stay callable from an ordinary non-actor thread.
    ///
    /// The subprocess coverage in `CostUsageStoreExecutorIsolationTests` exercises the legacy
    /// runtime path that an in-process test cannot select.
    @Test
    func `sync bridges are callable from a plain thread`() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)

        final class Outcome: @unchecked Sendable {
            var loadedScanStamp: Int64?
            var savedRowCount: Int?
        }
        let outcome = Outcome()
        let finished = DispatchSemaphore(value: 0)

        let thread = Thread {
            let loaded = store.syncLoadCodexCache(calendar: .current)
            outcome.loadedScanStamp = loaded.lastScanUnixMs
            let saved = store.syncSaveCodexCache(
                loaded,
                calendar: .current,
                requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-03"))
            outcome.savedRowCount = saved.rowCount
            finished.signal()
        }
        thread.start()

        #expect(finished.wait(timeout: .now() + 30) == .success)
        #expect(outcome.loadedScanStamp == 0)
        #expect((outcome.savedRowCount ?? -1) >= 0)
    }

    @Test
    func `database lives beside the legacy artifact directory`() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)

        #expect(store.databaseURL.lastPathComponent == "cost-usage.sqlite")
        #expect(store.databaseURL.deletingLastPathComponent().lastPathComponent == "cost-usage")
    }

    @Test
    func `new database uses WAL`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let configuration = await CostUsageStore(cacheRoot: fixture.root).configuration()

        #expect(configuration?.journalMode.lowercased() == "wal")
    }

    @Test
    func `new database configures busy timeout`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let configuration = await CostUsageStore(cacheRoot: fixture.root).configuration()

        #expect(configuration?.busyTimeoutMilliseconds == 5000)
    }

    @Test
    func `new database enables foreign keys`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let configuration = await CostUsageStore(cacheRoot: fixture.root).configuration()

        #expect(configuration?.foreignKeysEnabled == true)
    }

    @Test
    func `new database uses incremental auto vacuum`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let configuration = await CostUsageStore(cacheRoot: fixture.root).configuration()

        #expect(configuration?.autoVacuumMode == 2)
    }

    @Test
    func `user version combines schema and parser hash`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let configuration = await CostUsageStore(cacheRoot: fixture.root).configuration()

        #expect(configuration?.userVersion == Int(CostUsageStore.schemaVersion))
        #expect(CostUsageStore.combinedSchemaVersion(base: 1, parserHash: "a") !=
            CostUsageStore.combinedSchemaVersion(base: 1, parserHash: "b"))
    }

    @Test
    func `schema contains phase two query indexes`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        _ = await store.configuration()

        let indexes = try SQLiteTestConnection.indexNames(at: store.databaseURL)
        #expect(indexes.contains("files_path_idx"))
        #expect(indexes.contains("file_day_aggregates_day_idx"))
        #expect(indexes.contains("file_day_aggregates_model_day_idx"))
        #expect(indexes.contains("day_aggregates_day_idx"))
        #expect(indexes.contains("day_aggregates_model_idx"))
        #expect(indexes.contains("day_aggregates_model_day_idx"))
    }

    @Test
    func `codex working set hydrates selected paths without reading full snapshot`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var first = Self.file(path: "/rollouts/first.jsonl", day: "2026-08-01")
        var second = Self.file(path: "/rollouts/second.jsonl", day: "2026-08-01")
        let details = Data(#"{"hasRows":false,"hasTurnIDs":false,"hasTokenSnapshots":true,"hasSeenRawTotals":false}"#
            .utf8)
        first.scanState.detailsPayload = details
        second.scanState.detailsPayload = details
        #expect(await store.upsertFile(first))
        #expect(await store.upsertFile(second))
        #expect(await store.appendTokenSnapshots([
            Self.snapshot(path: first.path, eventIndex: 0),
            Self.snapshot(path: second.path, eventIndex: 0),
        ]))

        let workingSet = store.syncLoadCodexCache(
            calendar: .current,
            hydratingPaths: [first.path])
        #expect(workingSet.files.count == 2)
        #expect(workingSet.files[first.path]?.codexTokenSnapshots?.count == 1)
        #expect(workingSet.files[second.path]?.codexTokenSnapshots == nil)
    }

    @Test
    func `priority turn lookup returns only matching persisted files`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let first = Self.file(path: "/rollouts/priority.jsonl", day: "2026-08-01")
        let second = Self.file(path: "/rollouts/standard.jsonl", day: "2026-08-01")
        #expect(await store.upsertFile(first))
        #expect(await store.upsertFile(second))
        #expect(await store.replaceUsageRows(path: first.path, rows: [
            CostUsageStoreUsageRow(
                path: first.path,
                rowIndex: 0,
                payload: Data(#"{"turnID":"turn-priority"}"#.utf8)),
        ]))
        #expect(await store.replaceUsageRows(path: second.path, rows: [
            CostUsageStoreUsageRow(
                path: second.path,
                rowIndex: 0,
                payload: Data(#"{"turnID":"turn-standard"}"#.utf8)),
        ]))

        #expect(try store.syncPathsContainingCodexTurnIDs(["turn-priority"]) == [first.path])
        #expect(try store.syncPathsContainingCodexTurnIDs(["missing"]).isEmpty)
    }

    @Test
    func `priority turn lookup propagates sqlite query failure`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let file = Self.file(path: "/rollouts/malformed.jsonl", day: "2026-08-01")
        #expect(await store.upsertFile(file))
        #expect(await store.replaceUsageRows(path: file.path, rows: [
            CostUsageStoreUsageRow(path: file.path, rowIndex: 0, payload: Data("not-json".utf8)),
        ]))

        #expect(throws: CostUsageStore.StoreError.self) {
            _ = try store.syncPathsContainingCodexTurnIDs(["turn-priority"])
        }
    }

    @Test
    func `bounded delta migrates file aliases without duplicating aggregate totals`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let aliasPath = "/sessions/active/rollout.jsonl"
        let canonicalPath = "/sessions/archived/rollout.jsonl"
        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000,
            size: 100,
            days: ["2026-08-01": ["gpt-5.6-sol": [10, 2, 3]]])
        usage.parsedBytes = 100
        usage.codexScanFileId = "7:42"
        usage.codexScanComplete = true
        usage.codexRows = [CostUsageScanner.CodexUsageRow(
            day: "2026-08-01",
            model: "gpt-5.6-sol",
            turnID: "priority-turn",
            eventIndex: 0,
            input: 10,
            cached: 2,
            output: 3,
            knownCostNanos: 1200,
            pricingMode: "priority")]
        var seed = CostUsageCache()
        seed.scanSinceKey = "2026-08-01"
        seed.scanUntilKey = "2026-08-01"
        seed.files = [aliasPath: usage]
        seed.days = usage.days
        _ = store.syncSaveCodexCache(
            seed,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        let aggregateBefore = await store.fetchDayAggregates(
            sinceDay: "2026-08-01",
            untilDay: "2026-08-01")

        var moved = store.syncLoadCodexCache(calendar: calendar, hydratingPaths: [aliasPath])
        moved.files.removeValue(forKey: aliasPath)
        moved.files[canonicalPath] = usage
        let result = store.syncSaveCodexCatchUpCache(
            moved,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
            hydratedPaths: [canonicalPath])

        #expect(!result.catchUpRequired)
        #expect(await store.fetchFile(path: aliasPath) == nil)
        #expect(await store.fetchFile(path: canonicalPath) != nil)
        #expect(await store.fetchDayAggregates(
            sinceDay: "2026-08-01",
            untilDay: "2026-08-01") == aggregateBefore)
    }

    @Test
    func `bounded delta invalidates unhydrated rows when the calendar time zone changes`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var oldCalendar = Calendar(identifier: .gregorian)
        oldCalendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let stalePath = "/sessions/stale.jsonl"
        let retainedPath = "/sessions/reparsed.jsonl"
        var oldUsage = CostUsageFileUsage(
            mtimeUnixMs: 1000,
            size: 100,
            days: ["2026-08-01": ["gpt-5.6-sol": [10, 0, 1]]])
        oldUsage.parsedBytes = 100
        oldUsage.codexScanComplete = true
        var seed = CostUsageCache()
        seed.scanSinceKey = "2026-08-01"
        seed.scanUntilKey = "2026-08-01"
        seed.files = [stalePath: oldUsage, retainedPath: oldUsage]
        seed.days = ["2026-08-01": ["gpt-5.6-sol": [20, 0, 2]]]
        _ = store.syncSaveCodexCache(
            seed,
            calendar: oldCalendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))

        var newCalendar = oldCalendar
        newCalendar.timeZone = try #require(TimeZone(secondsFromGMT: 3600))
        var rebuilt = store.syncLoadCodexCache(calendar: newCalendar, hydratingPaths: [retainedPath])
        #expect(rebuilt.files.isEmpty)
        var reparsedUsage = oldUsage
        reparsedUsage.days = ["2026-08-02": ["gpt-5.6-sol": [10, 0, 1]]]
        rebuilt.scanSinceKey = "2026-08-02"
        rebuilt.scanUntilKey = "2026-08-02"
        rebuilt.files[retainedPath] = reparsedUsage
        rebuilt.days = reparsedUsage.days
        _ = store.syncSaveCodexCatchUpCache(
            rebuilt,
            calendar: newCalendar,
            requestedScanWindow: (sinceKey: "2026-08-02", untilKey: "2026-08-02"),
            hydratedPaths: [retainedPath])

        #expect(await store.fetchFile(path: stalePath) == nil)
        #expect(await store.fetchFile(path: retainedPath) != nil)
        #expect(await store.fetchDayAggregates(
            sinceDay: "2026-08-01",
            untilDay: "2026-08-01").isEmpty)
        #expect(await store.fetchDayAggregates(
            sinceDay: "2026-08-02",
            untilDay: "2026-08-02").count == 1)
        #expect(await store.fetchMetadata().timeZoneIdentifier == newCalendar.timeZone.identifier)
    }

    @Test
    func `bounded delta preserves store on transient sqlite failure`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let path = "/sessions/rollout.jsonl"
        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000,
            size: 100,
            days: ["2026-08-01": ["gpt-5.6-sol": [1, 0, 1]]])
        usage.parsedBytes = 100
        usage.codexScanFileId = "7:99"
        usage.codexScanComplete = true
        var seed = CostUsageCache()
        seed.scanSinceKey = "2026-08-01"
        seed.scanUntilKey = "2026-08-01"
        seed.files = [path: usage]
        seed.days = usage.days
        _ = store.syncSaveCodexCache(
            seed,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))

        var changed = store.syncLoadCodexCache(calendar: calendar, hydratingPaths: [path])
        changed.files[path]?.parsedBytes = 200
        var hooks = CostUsageStoreTestHooks.current
        hooks.codexCatchUpDeltaFailure = { databaseURL in
            guard databaseURL == store.databaseURL else { return }
            throw CostUsageStore.StoreError.sqlite(SQLITE_FULL)
        }
        let result = CostUsageStoreTestHooks.$current.withValue(hooks) {
            store.syncSaveCodexCatchUpCache(
                changed,
                calendar: calendar,
                requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
                hydratedPaths: [path])
        }

        #expect(result.catchUpRequired)
        #expect(await store.rebuildCount == 0)
        #expect(await store.fetchFile(path: path)?.parsedBytes == 100)
        #expect(FileManager.default.fileExists(atPath: store.databaseURL.path))
    }

    @Test
    func `budget pruning rolls back every mutation on transient sqlite failure`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-07-01"
        cache.scanUntilKey = "2026-07-02"
        cache.files = [
            "/sessions/one.jsonl": CostUsageFileUsage(
                mtimeUnixMs: 1, size: 10, days: ["2026-07-01": ["gpt-5.4": [10, 0, 1]]]),
            "/sessions/two.jsonl": CostUsageFileUsage(
                mtimeUnixMs: 2, size: 10, days: ["2026-07-02": ["gpt-5.4": [20, 0, 2]]]),
        ]
        cache.days = ["2026-07-01": ["gpt-5.4": [10, 0, 1]], "2026-07-02": ["gpt-5.4": [20, 0, 2]]]
        _ = store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-07-01", untilKey: "2026-07-02"))
        let before = await store.fetchDayAggregates(sinceDay: "2026-07-01", untilDay: "2026-07-02")
        var hooks = CostUsageStoreTestHooks.current
        hooks.budgetMutationFailure = { databaseURL in
            guard databaseURL == store.databaseURL else { return }
            throw CostUsageStore.StoreError.sqlite(SQLITE_FULL)
        }

        await CostUsageStoreTestHooks.$current.withValue(hooks) {
            await store.enforceBudgets(
                maxRows: 0,
                maxFileBytes: .max,
                requestedSinceDay: "2026-08-01",
                requestedUntilDay: "2026-08-01",
                calendar: calendar)
        }

        #expect(await store.fetchFile(path: "/sessions/one.jsonl") != nil)
        #expect(await store.fetchFile(path: "/sessions/two.jsonl") != nil)
        #expect(await store.fetchDayAggregates(sinceDay: "2026-07-01", untilDay: "2026-07-02") == before)
        #expect(await store.rebuildCount == 0)
    }
}

extension CostUsageStoreTests {
    @Test
    func `fresh store creates verified evidence when optional metadata is absent`() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        #expect(store.syncRecordVerifiedCodexDay(day: "2026-08-01", calendar: calendar))

        let database = try SQLiteTestConnection(url: store.databaseURL)
        #expect(try database.scalarInt("""
        SELECT COUNT(*) FROM meta
        WHERE key IN ('verified_day_lineage_id', 'verified_day_revision')
        """) == 2)
        #expect(try database.scalarInt("""
        SELECT COUNT(*) FROM verified_day_evidence WHERE day = '2026-08-01' AND revision > 0
        """) == 1)
    }

    @Test
    func `full ledger publication waits for buffered parser work`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let firstDay = "2026-08-01"
        let pendingDay = "2026-08-02"
        let firstPath = "/sessions/complete.jsonl"
        var completeFile = Self.file(path: firstPath, day: firstDay)
        completeFile.parsedBytes = completeFile.size
        completeFile.scanState.isComplete = true
        completeFile.scanState.resumePayload = nil
        let firstAggregate = Self.aggregate(day: firstDay, model: "fixture-model", scale: 1)
        var metadata = CostUsageStoreMetadata.empty
        metadata.lastScanUnixMs = 1_800_000_000_000
        metadata.scanSinceDay = firstDay
        metadata.scanUntilDay = firstDay
        metadata.timeZoneIdentifier = "UTC"
        metadata.rootMtimes = ["/sessions": 1]
        metadata.catchUpPending = false

        #expect(await store.upsertFile(completeFile))
        #expect(await store.replaceFileDayAggregates(path: firstPath, aggregates: [firstAggregate]))
        #expect(await store.mergeDayAggregates([firstAggregate]))
        #expect(await store.setMetadata(metadata))
        _ = await store.enforceBudgets(
            maxRows: .max,
            maxFileBytes: .max,
            requestedSinceDay: firstDay,
            requestedUntilDay: firstDay)

        let beforePendingWork = try SQLiteTestConnection(url: store.databaseURL)
        #expect(try beforePendingWork.scalarInt(
            "SELECT COUNT(*) FROM verified_day_evidence WHERE day = '\(firstDay)'") == 1)
        let priorRevision = try beforePendingWork.scalarInt(
            "SELECT CAST(value AS INTEGER) FROM meta WHERE key = 'verified_day_revision'")
        #expect(priorRevision > 0)

        let pendingPath = "/sessions/buffered.jsonl"
        var pendingFile = Self.file(path: pendingPath, day: pendingDay)
        pendingFile.parsedBytes = pendingFile.size
        pendingFile.scanState.isComplete = true
        pendingFile.scanState.resumePayload = nil
        let pendingAggregate = Self.aggregate(day: pendingDay, model: "fixture-model", scale: 1)
        #expect(await store.upsertFile(pendingFile))
        #expect(await store.replaceFileDayAggregates(path: pendingPath, aggregates: [pendingAggregate]))
        #expect(await store.mergeDayAggregates([pendingAggregate]))
        #expect(await store.replaceBufferedLines(
            path: pendingPath,
            kind: .unresolvedFork,
            lines: [Self.bufferedLine(path: pendingPath, kind: .unresolvedFork, index: 0)]))
        metadata.scanUntilDay = pendingDay
        #expect(await store.setMetadata(metadata))

        let result = await store.enforceBudgets(
            maxRows: .max,
            maxFileBytes: .max,
            requestedSinceDay: firstDay,
            requestedUntilDay: pendingDay)

        let afterPendingWork = try SQLiteTestConnection(url: store.databaseURL)
        #expect(result.catchUpRequired == false)
        #expect(try afterPendingWork.scalarInt("SELECT COUNT(*) FROM buffered_lines") == 1)
        #expect(try afterPendingWork.scalarInt(
            "SELECT COUNT(*) FROM verified_day_evidence WHERE day = '\(pendingDay)'") == 0)
        #expect(try afterPendingWork.scalarInt(
            "SELECT COUNT(*) FROM verified_day_status WHERE day = '\(pendingDay)'") == 0)
        #expect(try afterPendingWork.scalarInt(
            "SELECT COUNT(*) FROM verified_day_aggregates WHERE day = '\(pendingDay)'") == 0)
        #expect(try afterPendingWork.scalarInt(
            "SELECT COUNT(*) FROM verified_day_evidence WHERE day = '\(firstDay)'") == 1)
        #expect(try afterPendingWork.scalarInt(
            "SELECT CAST(value AS INTEGER) FROM meta WHERE key = 'verified_day_revision'") == priorRevision)
    }

    @Test
    func `verified day proof survives reopen no op and aggregate corrections`() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = "2026-08-01"
        let path = "/sessions/proof.jsonl"
        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000,
            size: 100,
            days: [day: ["fixture-model": [20, 2, 4]]])
        usage.parsedBytes = 100
        usage.codexScanComplete = true
        usage.codexRows = [.init(
            day: day,
            model: "fixture-model",
            turnID: nil,
            eventIndex: 0,
            input: 20,
            cached: 2,
            output: 4)]
        var cache = CostUsageCache()
        cache.lastScanUnixMs = 1_800_000_000_000
        cache.scanSinceKey = day
        cache.scanUntilKey = day
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        cache.roots = ["/codex/sessions": 0]
        cache.files[path] = usage
        cache.days = usage.days
        let window = (sinceKey: day, untilKey: day)
        let store = CostUsageStore(cacheRoot: fixture.root)
        #expect(store.syncSaveCodexCache(cache, calendar: calendar, requestedScanWindow: window)
            .cacheWasPersisted)
        let expectedCommit = CostUsageStoreCodexScanCommit(
            lastScanUnixMs: cache.lastScanUnixMs,
            rootPaths: ["/codex/sessions"],
            timeZoneIdentifier: calendar.timeZone.identifier)

        func projection(from store: CostUsageStore) -> CostUsageStoreCodexReportProjection {
            store.syncReadCodexReportProjection(
                calendar: calendar,
                temporalRange: (sinceDay: day, untilDay: day))
        }
        let firstProjection = projection(from: store)
        let firstEvidence = try #require(firstProjection.verifiedDayEvidence[day])
        #expect(firstEvidence.sourceKind == "codexLocalLedger")
        #expect(firstEvidence.scopeID == CostUsageScanner.codexDayEvidenceScopeID(
            rootPaths: ["/codex/sessions"],
            calendar: calendar))
        #expect(firstEvidence.revision > 0)
        let dayRange = try CostUsageScanner.CostUsageDayRange(
            since: #require(CostUsageScanner.parseDayKey(day, calendar: calendar)),
            until: #require(CostUsageScanner.parseDayKey(day, calendar: calendar)),
            calendar: calendar)
        let unpricedReport = CostUsageCodexReportProjectionBuilder.buildVerifiedReport(
            projection: firstProjection,
            range: dayRange,
            cacheRoot: nil)
        let unpricedDay = try #require(unpricedReport.data.first)
        #expect(unpricedDay.costUSD == nil)
        #expect(unpricedDay.dayEvidence == firstEvidence)

        var wrongScopeProjection = firstProjection
        wrongScopeProjection.verifiedDayEvidence[day] = CostUsageDayEvidence(
            scopeID: "sha256:wrong-scope",
            lineageID: firstEvidence.lineageID,
            revision: firstEvidence.revision,
            verifiedAt: firstEvidence.verifiedAt)
        let wrongScopeReport = CostUsageCodexReportProjectionBuilder.buildVerifiedReport(
            projection: wrongScopeProjection,
            range: dayRange,
            cacheRoot: nil)
        #expect(wrongScopeReport.data.isEmpty)

        let initialVerificationTime = firstEvidence.verifiedAt
        #expect(store.syncRecordVerifiedCodexDay(
            day: day,
            calendar: calendar,
            expectedCommit: expectedCommit,
            verifiedAt: initialVerificationTime.addingTimeInterval(3601)))
        let refreshedProjection = projection(from: store)
        let refreshedEvidence = try #require(refreshedProjection.verifiedDayEvidence[day])
        #expect(refreshedEvidence.revision == firstEvidence.revision)
        #expect(refreshedEvidence.verifiedAt == initialVerificationTime.addingTimeInterval(3601))

        let staleCommit = CostUsageStoreCodexScanCommit(
            lastScanUnixMs: cache.lastScanUnixMs + 1,
            rootPaths: ["/codex/sessions"],
            timeZoneIdentifier: calendar.timeZone.identifier)
        #expect(!store.syncRecordVerifiedCodexDay(
            day: day,
            calendar: calendar,
            expectedCommit: staleCommit,
            verifiedAt: initialVerificationTime.addingTimeInterval(7202)))
        #expect(projection(from: store).verifiedDayEvidence[day] == refreshedEvidence)
        #expect(store.syncRecordVerifiedCodexDay(
            day: day,
            calendar: calendar,
            expectedCommit: expectedCommit,
            verifiedAt: initialVerificationTime.addingTimeInterval(3602)))
        #expect(projection(from: store).verifiedDayEvidence[day] == refreshedEvidence)
        let reopened = CostUsageStore(cacheRoot: fixture.root)
        #expect(projection(from: reopened).verifiedDayEvidence[day] == refreshedEvidence)

        usage.days = [day: ["fixture-model": [4, 1, 1]]]
        usage.codexRows = [.init(
            day: day,
            model: "fixture-model",
            turnID: nil,
            eventIndex: 0,
            input: 4,
            cached: 1,
            output: 1)]
        cache.lastScanUnixMs += 1000
        cache.files[path] = usage
        cache.days = usage.days
        #expect(store.syncSaveCodexCache(cache, calendar: calendar, requestedScanWindow: window)
            .cacheWasPersisted)
        #expect(store.syncRecordVerifiedCodexDay(day: day, calendar: calendar))
        let decreased = projection(from: store)
        let decreasedEvidence = try #require(decreased.verifiedDayEvidence[day])
        #expect(decreasedEvidence.revision > firstEvidence.revision)
        #expect(decreased.verifiedDayAggregates.first?.inputTokens == 4)

        usage.days = [day: [:]]
        usage.codexRows = []
        cache.lastScanUnixMs += 1000
        cache.files[path] = usage
        cache.days = usage.days
        #expect(store.syncSaveCodexCache(cache, calendar: calendar, requestedScanWindow: window)
            .cacheWasPersisted)
        #expect(store.syncRecordVerifiedCodexDay(day: day, calendar: calendar))
        let zeroProjection = projection(from: store)
        let zeroEvidence = try #require(zeroProjection.verifiedDayEvidence[day])
        #expect(zeroEvidence.revision > decreasedEvidence.revision)
        #expect(zeroProjection.verifiedDayAggregates.filter { $0.day == day }.isEmpty)
        let zeroReport = CostUsageCodexReportProjectionBuilder.buildVerifiedReport(
            projection: zeroProjection,
            range: dayRange,
            cacheRoot: nil)
        let zeroDay = try #require(zeroReport.data.first)
        #expect(zeroDay.totalTokens == 0)
        #expect(zeroDay.costUSD == 0)
        #expect(zeroDay.dayEvidence == zeroEvidence)
    }

    @Test(arguments: ["0001601034856fb6", "c52728bbaeedeb90"])
    func `additive predecessor migration retains rows and baseline without inventing proof`(
        predecessorHash: String) throws
    {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = "2026-08-01"
        let path = "/rollouts/predecessor-ledger.jsonl"
        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000, size: 100, days: [day: ["fixture-model": [10, 0, 2]]])
        usage.parsedBytes = 100
        usage.codexScanComplete = true
        usage.codexRows = [.init(
            day: day,
            model: "fixture-model",
            turnID: "fixture-turn",
            eventIndex: 0,
            input: 10,
            cached: 0,
            output: 2)]
        usage.codexTokenSnapshots = [.init(
            timestamp: "2026-08-01T12:00:00Z", last: nil, total: .init(input: 10, cached: 0, output: 2))]
        var cache = CostUsageCache()
        cache.lastScanUnixMs = 1_800_000_000_000
        cache.scanSinceKey = day
        cache.scanUntilKey = day
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        cache.roots = ["/codex/sessions": 0]
        cache.files[path] = usage
        cache.days = usage.days
        let predecessorVersion = CostUsageStore.combinedSchemaVersion(
            base: CostUsageStore.baseSchemaVersion, parserHash: predecessorHash)
        let store = CostUsageStore(
            cacheRoot: fixture.root, schemaVersion: predecessorVersion, parserHash: predecessorHash)
        #expect(store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: day, untilKey: day)).cacheWasPersisted)
        #expect(store.syncRecordVerifiedCodexDay(day: day, calendar: calendar))
        let priorProjection = store.syncReadCodexReportProjection(calendar: calendar)
        let priorCache = store.syncLoadCodexCache(calendar: calendar)
        #expect(priorProjection.verifiedDayEvidence[day] != nil)
        #expect(priorCache.files[path]?.codexRows == usage.codexRows)
        #expect(priorCache.files[path]?.codexTokenSnapshots == usage.codexTokenSnapshots)
        #expect(try SQLiteTestConnection(url: store.databaseURL)
            .scalarInt("SELECT COUNT(*) FROM verified_day_status WHERE day = '\(day)'") == 1)

        try SQLiteTestConnection.execute(
            at: store.databaseURL,
            sql: "DROP TABLE verified_day_evidence")
        let migrated = CostUsageStore(cacheRoot: fixture.root)
        let projection = migrated.syncReadCodexReportProjection(
            calendar: calendar,
            temporalRange: (sinceDay: day, untilDay: day))
        #expect(projection.verifiedDayKeys.contains(day))
        #expect(projection.verifiedDayEvidence[day] == nil)
        #expect(projection.verifiedDayAggregates == priorProjection.verifiedDayAggregates)
        #expect(projection.verifiedUpdatedAtUnixMs == priorProjection.verifiedUpdatedAtUnixMs)
        #expect(migrated.syncLoadCodexCache(calendar: calendar).files == priorCache.files)
        #expect(try SQLiteTestConnection(url: store.databaseURL)
            .scalarInt("PRAGMA user_version") == Int64(CostUsageStore.schemaVersion))
        #expect(try SQLiteTestConnection(url: store.databaseURL)
            .scalarInt("SELECT COUNT(*) FROM verified_day_evidence") == 0)
        #expect(try SQLiteTestConnection(url: store.databaseURL)
            .scalarInt("SELECT COUNT(*) FROM verified_day_aggregates WHERE day = '\(day)'") > 0)
    }

    @Test
    func `zero day proof projects during a persisted catch up pass`() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = "2026-08-01"
        var cache = CostUsageCache()
        cache.lastScanUnixMs = 1_800_000_000_000
        cache.scanSinceKey = day
        cache.scanUntilKey = day
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        cache.roots = ["/codex/sessions": 0]
        let store = CostUsageStore(cacheRoot: fixture.root)
        let window = (sinceKey: day, untilKey: day)
        #expect(store.syncSaveCodexCache(cache, calendar: calendar, requestedScanWindow: window)
            .cacheWasPersisted)

        cache.lastScanUnixMs += 1000
        cache.codexScanCatchUpPending = true
        cache.codexActiveLookbackState = CostUsageCodexActiveLookbackState(
            scanSinceKey: day,
            rootPaths: ["/codex/sessions"],
            pendingFilePaths: ["/codex/sessions/historical-pending.jsonl"])
        let catchUp = store.syncSaveCodexCatchUpCache(
            cache,
            calendar: calendar,
            requestedScanWindow: window,
            hydratedPaths: [])
        #expect(catchUp.cacheWasPersisted)
        #expect(store.syncRecordVerifiedCodexDay(day: day, calendar: calendar))
        let projection = store.syncReadCodexReportProjection(
            calendar: calendar,
            temporalRange: (sinceDay: day, untilDay: day))
        #expect(projection.cache.codexScanCatchUpPending == true)
        #expect(projection.verifiedDayKeys.contains(day))
        #expect((projection.verifiedDayEvidence[day]?.revision ?? 0) > 0)
        let report = try CostUsageCodexReportProjectionBuilder.buildVerifiedReport(
            projection: projection,
            range: CostUsageScanner.CostUsageDayRange(
                since: #require(CostUsageScanner.parseDayKey(day, calendar: calendar)),
                until: #require(CostUsageScanner.parseDayKey(day, calendar: calendar)),
                calendar: calendar),
            cacheRoot: nil)
        let dayEntry = try #require(report.data.first)
        #expect(dayEntry.totalTokens == 0)
        #expect(dayEntry.costUSD == 0)
        #expect(dayEntry.dayEvidence != nil)
    }
}

extension CostUsageStoreTests {
    @Test
    func `file state round trips all validation fields`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let file = Self.file(path: "/rollouts/a.jsonl", day: "2026-08-01")

        #expect(await store.upsertFile(file))
        #expect(await store.fetchFile(path: file.path) == file)
    }

    @Test
    func `file upsert replaces mutable state`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var file = Self.file(path: "/rollouts/a.jsonl", day: "2026-08-01")
        #expect(await store.upsertFile(file))
        file.size = 999
        file.parsedBytes = 800
        file.scanState.isComplete = false
        file.updatedAtUnixMs = 20

        #expect(await store.upsertFile(file))
        #expect(await store.fetchFile(path: file.path) == file)
    }

    @Test
    func `missing file returns nil`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }

        #expect(await CostUsageStore(cacheRoot: fixture.root).fetchFile(path: "/missing") == nil)
    }

    @Test
    func `deleting file cascades dependent tables`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let file = Self.file(path: "/rollouts/a.jsonl", day: "2026-08-01")
        #expect(await store.upsertFile(file))
        #expect(await store.appendTokenSnapshots([Self.snapshot(path: file.path, eventIndex: 0)]))
        #expect(await store.replaceFileDayAggregates(
            path: file.path,
            aggregates: [Self.aggregate(day: "2026-08-01", model: "model-a", scale: 1)]))
        #expect(await store.upsertForkLineage(Self.lineage(path: file.path)))
        #expect(await store.upsertAccumulator(Self.accumulator(path: file.path)))

        #expect(await store.deleteFile(path: file.path))
        let snapshot = await store.readSnapshot()
        #expect(snapshot.files.isEmpty)
        #expect(snapshot.tokenSnapshots.isEmpty)
        #expect(snapshot.fileDayAggregates.isEmpty)
        #expect(snapshot.forkLineage.isEmpty)
        #expect(snapshot.accumulators.isEmpty)
    }
}

extension CostUsageStoreTests {
    @Test
    func `token snapshot deltas round trip`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let file = Self.file(path: "/rollouts/a.jsonl", day: "2026-08-01")
        #expect(await store.upsertFile(file))
        let snapshots = [
            Self.snapshot(path: file.path, eventIndex: 0),
            Self.snapshot(path: file.path, eventIndex: 1, day: "2026-08-02"),
        ]

        #expect(await store.appendTokenSnapshots(snapshots))
        #expect(await store.fetchTokenSnapshots(path: file.path) == snapshots)
    }

    @Test
    func `token snapshot append is idempotent by event index`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let file = Self.file(path: "/rollouts/a.jsonl", day: "2026-08-01")
        #expect(await store.upsertFile(file))
        var snapshot = Self.snapshot(path: file.path, eventIndex: 0)
        #expect(await store.appendTokenSnapshots([snapshot]))
        snapshot.endOffset = 222

        #expect(await store.appendTokenSnapshots([snapshot]))
        #expect(await store.fetchTokenSnapshots(path: file.path) == [snapshot])
    }

    @Test
    func `persistence planner materializes only the delta and store preserves absolute indexes`() async throws {
        var transformedIndexes: [Int] = []

        func materialize(
            _ action: CostUsagePersistenceAction,
            source: [Int]) -> [Int]
        {
            transformedIndexes = []
            return action.materialize(source) { index, value in
                transformedIndexes.append(index)
                return value
            }
        }

        let initialAction = CostUsagePersistencePlanner.action(
            canReuse: false,
            stableCursor: false,
            appendSafe: false,
            persistedCount: 0,
            sourceCount: 2)
        #expect(initialAction == .replace)
        #expect(materialize(initialAction, source: [10, 20]) == [10, 20])
        #expect(transformedIndexes == [0, 1])

        let stableAction = CostUsagePersistencePlanner.action(
            canReuse: true,
            stableCursor: true,
            appendSafe: false,
            persistedCount: 2,
            sourceCount: 2)
        #expect(stableAction == .reuse)
        #expect(materialize(stableAction, source: [10, 20]).isEmpty)
        #expect(transformedIndexes.isEmpty)

        let appendAction = CostUsagePersistencePlanner.action(
            canReuse: true,
            stableCursor: false,
            appendSafe: true,
            persistedCount: 2,
            sourceCount: 3)
        #expect(appendAction == .append(startingAt: 2))
        #expect(materialize(appendAction, source: [10, 20, 30]) == [30])
        #expect(transformedIndexes == [2])

        let replacementAction = CostUsagePersistencePlanner.action(
            canReuse: true,
            stableCursor: false,
            appendSafe: false,
            persistedCount: 3,
            sourceCount: 2)
        #expect(replacementAction == .replace)
        #expect(materialize(replacementAction, source: [40, 50]) == [40, 50])
        #expect(transformedIndexes == [0, 1])

        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let path = "/rollouts/delta.jsonl"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        func token(_ index: Int) -> CostUsageCodexTokenSnapshot {
            CostUsageCodexTokenSnapshot(
                timestamp: "2026-08-01T12:00:0\(index)Z",
                last: CostUsageCodexTotals(input: index + 1, cached: 0, output: 1),
                total: CostUsageCodexTotals(input: (index + 1) * 10, cached: 0, output: index + 1),
                endOffset: Int64(100 + index))
        }

        func row(_ index: Int) -> CostUsageScanner.CodexUsageRow {
            CostUsageScanner.CodexUsageRow(
                day: "2026-08-01",
                model: "model-\(index)",
                turnID: "turn-\(index)",
                eventIndex: index,
                timestampUnixMs: Int64(1_754_046_000_000 + index),
                input: index + 1,
                cached: 0,
                output: 1)
        }

        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000,
            size: 200,
            days: ["2026-08-01": ["model-0": [1, 0, 1]]])
        usage.parsedBytes = 200
        usage.codexScanFileId = "1:42"
        usage.codexScanComplete = true
        usage.codexTokenTimestampsMonotonic = true
        usage.codexTokenSnapshots = [token(0), token(1)]
        usage.codexRows = [row(0), row(1)]

        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.files = [path: usage]
        cache.days = usage.days

        func save() {
            _ = store.syncSaveCodexCache(
                cache,
                calendar: calendar,
                requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        }

        save()
        save()

        usage.parsedBytes = 300
        usage.size = 300
        usage.codexTokenSnapshots = [token(0), token(1), token(2)]
        usage.codexRows = [row(0), row(1), row(2)]
        cache.files[path] = usage
        save()

        #expect(await store.fetchTokenSnapshots(path: path).map(\.eventIndex) == [0, 1, 2])
        let appendedRows = await store.fetchUsageRows(path: path)
        #expect(appendedRows.map(\.rowIndex) == [0, 1, 2])
        #expect(try appendedRows.map {
            try JSONDecoder().decode(CostUsageScanner.CodexUsageRow.self, from: $0.payload)
        } == usage.codexRows)

        usage.parsedBytes = 400
        usage.size = 400
        usage.codexScanFileId = "2:99"
        usage.codexTokenSnapshots = [token(3), token(4)]
        usage.codexRows = [row(3), row(4)]
        cache.files[path] = usage
        save()

        let replacedSnapshots = await store.fetchTokenSnapshots(path: path)
        #expect(replacedSnapshots.map(\.eventIndex) == [0, 1])
        #expect(replacedSnapshots.map(\.timestamp) == usage.codexTokenSnapshots?.map(\.timestamp))
        let replacedRows = await store.fetchUsageRows(path: path)
        #expect(replacedRows.map(\.rowIndex) == [0, 1])
        #expect(try replacedRows.map {
            try JSONDecoder().decode(CostUsageScanner.CodexUsageRow.self, from: $0.payload)
        } == usage.codexRows)
    }

    @Test
    // swiftlint:disable:next function_body_length
    func `identical codex cache save skips content rewrites but advances the scan timestamp`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let path = "/rollouts/stable.jsonl"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        func token(_ index: Int) -> CostUsageCodexTokenSnapshot {
            CostUsageCodexTokenSnapshot(
                timestamp: "2026-08-01T12:00:0\(index)Z",
                last: CostUsageCodexTotals(input: index + 1, cached: 0, output: 1),
                total: CostUsageCodexTotals(input: (index + 1) * 10, cached: 0, output: index + 1),
                endOffset: Int64(100 + index))
        }

        func row(_ index: Int) -> CostUsageScanner.CodexUsageRow {
            CostUsageScanner.CodexUsageRow(
                day: "2026-08-01",
                model: "model-\(index)",
                turnID: "turn-\(index)",
                eventIndex: index,
                timestampUnixMs: Int64(1_754_046_000_000 + index),
                input: index + 1,
                cached: 0,
                output: 1)
        }

        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000,
            size: 200,
            days: ["2026-08-01": ["model-0": [1, 0, 1]]])
        usage.parsedBytes = 200
        usage.codexScanFileId = "1:42"
        usage.codexScanComplete = true
        usage.codexTokenTimestampsMonotonic = true
        usage.codexTokenSnapshots = [token(0), token(1)]
        usage.codexRows = [row(0), row(1)]

        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.files = [path: usage]
        cache.days = usage.days
        cache.lastScanUnixMs = 1000
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        cache.codexPricingKey = "pricing-v1"
        cache.codexPriorityMetadataKey = "priority-v1"
        cache.codexProjectMetadataVersion = 7
        cache.codexPriorityTurnKeys = ["turn-0": "priority"]
        cache.codexPriorityTurnIDsByDay = ["2026-08-01": ["turn-0"]]
        cache.codexScanCatchUpPending = false
        cache.codexScanProcessedBytes = 200
        cache.codexScanTotalBytes = 200
        cache.codexScanCompletedFiles = 1
        cache.codexScanTotalFiles = 1
        cache.roots = ["/synthetic/root": 123]
        cache.codexSessionDiscovery = CostUsageCodexSessionDiscovery(
            roots: ["/synthetic/root"],
            generation: "generation-v1",
            directoryStamps: [:],
            directoryPaths: [],
            nextDirectoryIndex: 0,
            filePaths: [path],
            nextFileIndex: 1,
            fileStamps: [:],
            headScan: nil,
            filePathBySessionId: ["session-1": path],
            missingSessionIds: [],
            pendingSessionIds: [],
            validationDirectoryIndex: 0,
            isComplete: true)
        cache.codexActiveLookbackState = CostUsageCodexActiveLookbackState(
            scanSinceKey: "2026-08-01",
            rootPaths: ["/synthetic/root"],
            nextDayKeyByRoot: ["/synthetic/root": "2026-08-02"])
        cache.codexPreviousReport = CostUsageCodexPreviousReport(
            report: CostUsageDailyReport(data: [
                CostUsageDailyReport.Entry(
                    date: "2026-08-01",
                    inputTokens: 1,
                    outputTokens: 1,
                    totalTokens: 2,
                    costUSD: nil,
                    modelsUsed: nil,
                    modelBreakdowns: nil),
            ], summary: nil),
            cache: cache,
            reportSinceKey: "2026-08-01",
            reportUntilKey: "2026-08-01")

        func save(_ cache: CostUsageCache) {
            _ = store.syncSaveCodexCache(
                cache,
                calendar: calendar,
                requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
                skipIdenticalContent: true)
        }

        save(cache)

        #expect(await store.setWALAutoCheckpointForTesting(0))
        #expect(await store.truncateWALForTesting())
        let dbURL = store.databaseURL
        let walURL = URL(fileURLWithPath: dbURL.path + "-wal")
        struct Footprint: Equatable {
            var size: Int64
            var mtime: Date?
        }

        func footprint() -> [URL: Footprint] {
            var out: [URL: Footprint] = [:]
            for url in [dbURL, walURL] {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                    out[url] = Footprint(
                        size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                        mtime: attributes[.modificationDate] as? Date)
                }
            }
            return out
        }

        let before = footprint()
        let snapshotBefore = await store.readSnapshot()
        _ = await store.persistenceWriteMetricsForTesting(resetPageCounter: true)
        let countersBefore = await store.persistenceWriteMetricsForTesting()

        // A later scan pass over unchanged files stamps a new timestamp: the content tables
        // stay untouched, but the durable timestamp advances so refresh debounce survives
        // cache reloads and app restarts.
        var reread = CostUsageStoreAccess.read(cacheRoot: fixture.root, calendar: calendar)
        #expect(reread.files[path] != nil)
        reread.lastScanUnixMs = 2000
        let noOpResult = store.syncSaveCodexCache(
            reread,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
            skipIdenticalContent: true)

        let after = footprint()
        let countersAfter = await store.persistenceWriteMetricsForTesting(resetPageCounter: true)
        var expectedSnapshot = snapshotBefore
        expectedSnapshot.metadata.lastScanUnixMs = 2000
        #expect(await store.readSnapshot() == expectedSnapshot)
        #expect(countersAfter.rows - countersBefore.rows == 1)
        #expect(countersAfter.pages <= 2)
        #expect(noOpResult.deletedRows == 0)
        #expect(after[dbURL]?.size == before[dbURL]?.size)
        #expect(after[walURL]?.size ?? 0 > 0)
        #expect(after[walURL]?.mtime != before[walURL]?.mtime)
        #expect(await store.fetchTokenSnapshots(path: path).map(\.eventIndex) == [0, 1])
        #expect(await store.fetchUsageRows(path: path).count == 2)
        let reloaded = CostUsageStoreAccess.read(cacheRoot: fixture.root, calendar: calendar)
        #expect(reloaded.lastScanUnixMs == 2000)

        // Repeating the unchanged scan checkpoints at most the prior metadata frame, then emits
        // exactly one new metadata-row change. Both files are measured using SQLite's real `-wal`
        // path; no claim of zero physical writes is made.
        var repeated = reloaded
        repeated.lastScanUnixMs = 2500
        let repeatBefore = footprint()
        let repeatCountersBefore = await store.persistenceWriteMetricsForTesting()
        save(repeated)
        let repeatAfter = footprint()
        let repeatCountersAfter = await store.persistenceWriteMetricsForTesting(resetPageCounter: true)
        #expect(repeatCountersAfter.rows - repeatCountersBefore.rows == 1)
        #expect(repeatCountersAfter.pages <= 2)
        #expect(repeatAfter[dbURL]?.size == repeatBefore[dbURL]?.size)
        #expect((repeatAfter[walURL]?.size ?? 0) > (after[walURL]?.size ?? 0))
        #expect(repeatAfter[dbURL]?.mtime != nil)
        #expect(repeatAfter[walURL]?.mtime != repeatBefore[walURL]?.mtime)
        print("[no-op-write-proof] first before=\(before) after=\(after)")
        print("[no-op-write-proof] repeat before=\(repeatBefore) after=\(repeatAfter)")

        // A real content change still uses the full all-or-nothing save.
        var changed = repeated
        changed.lastScanUnixMs = 3000
        changed.files[path]?.parsedBytes = 201
        changed.files[path]?.codexTokenSnapshots = [token(0), token(1), token(2)]
        changed.files[path]?.codexRows = [row(0), row(1), row(2)]
        let changedCountersBefore = await store.persistenceWriteMetricsForTesting()
        save(changed)
        let changedCountersAfter = await store.persistenceWriteMetricsForTesting(resetPageCounter: true)

        #expect(changedCountersAfter.rows - changedCountersBefore.rows > 1)
        #expect(await store.fetchTokenSnapshots(path: path).map(\.eventIndex) == [0, 1, 2])

        // Tightening the byte budget still runs enforcement before any identical-content
        // return, but requested-window content is protected, so the cap becomes best-effort
        // and the unchanged save completes without requesting a rescan.
        let tightenedBudget = store.syncSaveCodexCache(
            CostUsageStoreAccess.read(cacheRoot: fixture.root, calendar: calendar),
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
            fileBudgetBytes: 1,
            skipIdenticalContent: true)
        #expect(tightenedBudget.catchUpRequired == false)
        #expect(tightenedBudget.fileBytes > 1)
        #expect(await store.fetchUsageRows(path: path).count == 3)
    }

    @Test
    func `identical scanner save preserves content committed before the writer lock`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let path = "/rollouts/recheck.jsonl"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000,
            size: 100,
            days: ["2026-08-01": ["gpt-5.6-sol": [10, 2, 1]]])
        usage.parsedBytes = 100
        usage.codexScanFileId = "1:42"
        usage.codexScanComplete = true
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        cache.files = [path: usage]
        cache.days = usage.days
        cache.lastScanUnixMs = 1000

        func save(_ value: CostUsageCache) -> CostUsageStoreBudgetResult {
            store.syncSaveCodexCache(
                value,
                calendar: calendar,
                requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
                skipIdenticalContent: true)
        }

        _ = save(cache)
        var reread = CostUsageStoreAccess.read(cacheRoot: fixture.root, calendar: calendar)
        reread.lastScanUnixMs = 2000
        let interloper = try LockIsolated(SQLiteTestConnection(url: store.databaseURL))
        let checkpointError = LockIsolated<Error?>(nil)
        var hooks = CostUsageStoreTestHooks.current
        hooks.identicalContentPreLockCheckpoint = (databaseURL: store.databaseURL, checkpoint: {
            do {
                try interloper.value.execute("UPDATE files SET parsed_bytes = 999 WHERE path = '\(path)'")
            } catch {
                checkpointError.setValue(error)
            }
        })

        let result = CostUsageStoreTestHooks.$current.withValue(hooks) {
            store.syncSaveCodexCache(
                reread,
                calendar: calendar,
                requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
                fileBudgetBytes: 1,
                skipIdenticalContent: true)
        }

        #expect(checkpointError.value == nil)
        #expect(result.catchUpRequired)
        #expect(await store.rebuildCount == 0)
        #expect(await store.fetchFile(path: path)?.parsedBytes == 999)
        #expect(CostUsageStoreAccess.read(cacheRoot: fixture.root, calendar: calendar).lastScanUnixMs == 1000)

        var refreshed = CostUsageStoreAccess.read(cacheRoot: fixture.root, calendar: calendar)
        refreshed.lastScanUnixMs = 3000
        let retried = save(refreshed)
        #expect(!retried.catchUpRequired)
        #expect(await store.fetchFile(path: path)?.parsedBytes == 999)
        #expect(CostUsageStoreAccess.read(cacheRoot: fixture.root, calendar: calendar).lastScanUnixMs == 3000)
    }

    @Test(.timeLimit(.minutes(1)))
    func `identical scanner save reports retry while the writer lock is unavailable`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let path = "/rollouts/locked-save.jsonl"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000,
            size: 100,
            days: ["2026-08-01": ["gpt-5.6-sol": [10, 2, 1]]])
        usage.parsedBytes = 100
        usage.codexScanFileId = "1:42"
        usage.codexScanComplete = true
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        cache.files = [path: usage]
        cache.days = usage.days
        cache.lastScanUnixMs = 1000

        func save(_ value: CostUsageCache) -> CostUsageStoreBudgetResult {
            store.syncSaveCodexCache(
                value,
                calendar: calendar,
                requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
                skipIdenticalContent: true)
        }

        _ = save(cache)
        var reread = CostUsageStoreAccess.read(cacheRoot: fixture.root, calendar: calendar)
        reread.lastScanUnixMs = 2000
        let holder = try SQLiteTestConnection(url: store.databaseURL)
        try holder.execute("BEGIN IMMEDIATE")
        try holder.execute("INSERT OR REPLACE INTO meta(key, value) VALUES ('save-holder', '1')")

        let blocked = save(reread)

        #expect(blocked.catchUpRequired)
        #expect(await store.rebuildCount == 0)
        #expect(CostUsageStoreAccess.read(cacheRoot: fixture.root, calendar: calendar).lastScanUnixMs == 1000)

        var changed = reread
        changed.files[path]?.parsedBytes = 200
        changed.lastScanUnixMs = 2500
        let blockedFullSave = store.syncSaveCodexCache(
            changed,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(blockedFullSave.catchUpRequired)
        #expect(await store.fetchFile(path: path)?.parsedBytes == 100)
        #expect(CostUsageStoreAccess.read(cacheRoot: fixture.root, calendar: calendar).lastScanUnixMs == 1000)

        try holder.execute("COMMIT")
        let retried = save(reread)
        #expect(!retried.catchUpRequired)
        #expect(CostUsageStoreAccess.read(cacheRoot: fixture.root, calendar: calendar).lastScanUnixMs == 2000)
    }

    @Test
    func `day aggregate inserts and reads by model`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let aggregate = Self.aggregate(day: "2026-08-01", model: "gpt-5.6-sol", scale: 1)

        #expect(await store.mergeDayAggregates([aggregate]))
        #expect(await store.fetchDayAggregates(sinceDay: "2026-08-01", untilDay: "2026-08-01") == [aggregate])
    }

    @Test
    func `per file aggregates replace and round trip`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let file = Self.file(path: "/rollouts/a.jsonl", day: "2026-08-01")
        let first = Self.aggregate(day: "2026-08-01", model: "model-a", scale: 1)
        let replacement = Self.aggregate(day: "2026-08-02", model: "model-b", scale: 2)
        #expect(await store.upsertFile(file))
        #expect(await store.replaceFileDayAggregates(path: file.path, aggregates: [first]))
        #expect(await store.replaceFileDayAggregates(path: file.path, aggregates: [replacement]))

        #expect(await store.fetchFileDayAggregates(path: file.path) == [replacement])
    }

    @Test
    func `day aggregate merge adds every metric`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let first = Self.aggregate(day: "2026-08-01", model: "gpt-5.6-sol", scale: 1)
        let second = Self.aggregate(day: "2026-08-01", model: "gpt-5.6-sol", scale: 2)

        #expect(await store.mergeDayAggregates([first, second]))
        #expect(await store.fetchDayAggregates(sinceDay: "2026-08-01", untilDay: "2026-08-01") == [
            Self.aggregate(day: "2026-08-01", model: "gpt-5.6-sol", scale: 3),
        ])
    }

    @Test
    func `day aggregate range is inclusive and sorted`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let values = [
            Self.aggregate(day: "2026-08-03", model: "model-b", scale: 1),
            Self.aggregate(day: "2026-08-01", model: "model-a", scale: 1),
            Self.aggregate(day: "2026-08-02", model: "model-a", scale: 1),
        ]
        #expect(await store.mergeDayAggregates(values))

        let fetched = await store.fetchDayAggregates(sinceDay: "2026-08-01", untilDay: "2026-08-02")
        #expect(fetched.map(\.day) == ["2026-08-01", "2026-08-02"])
    }

    @Test
    func `negative aggregate delta subtracts prior contribution`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let first = Self.aggregate(day: "2026-08-01", model: "model-a", scale: 3)
        let delta = Self.aggregate(day: "2026-08-01", model: "model-a", scale: -1)
        #expect(await store.mergeDayAggregates([first, delta]))

        #expect(await store.fetchDayAggregates(sinceDay: "2026-08-01", untilDay: "2026-08-01") == [
            Self.aggregate(day: "2026-08-01", model: "model-a", scale: 2),
        ])
    }
}

extension CostUsageStoreTests {
    @Test
    func `fork lineage round trips typed and opaque state`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let file = Self.file(path: "/rollouts/child.jsonl", day: "2026-08-01")
        let lineage = Self.lineage(path: file.path)
        #expect(await store.upsertFile(file))

        #expect(await store.upsertForkLineage(lineage))
        #expect(await store.fetchForkLineage(path: file.path) == lineage)
    }

    @Test
    func `buffered lines round trip every retry kind`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let file = Self.file(path: "/rollouts/child.jsonl", day: "2026-08-01")
        #expect(await store.upsertFile(file))
        var expected: [CostUsageStoreBufferedLine] = []
        for (index, kind) in CostUsageStoreBufferedLineKind.allCases.enumerated() {
            let line = Self.bufferedLine(path: file.path, kind: kind, index: index)
            expected.append(line)
            #expect(await store.replaceBufferedLines(path: file.path, kind: kind, lines: [line]))
        }

        #expect(await store.fetchBufferedLines(path: file.path) == expected.sorted {
            $0.kind.rawValue < $1.kind.rawValue
        })
    }

    @Test
    func `buffer replacement is scoped by retry kind`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let file = Self.file(path: "/rollouts/child.jsonl", day: "2026-08-01")
        #expect(await store.upsertFile(file))
        let subagent = Self.bufferedLine(path: file.path, kind: .subagent, index: 1)
        let fork = Self.bufferedLine(path: file.path, kind: .unresolvedFork, index: 2)
        #expect(await store.replaceBufferedLines(path: file.path, kind: .subagent, lines: [subagent]))
        #expect(await store.replaceBufferedLines(path: file.path, kind: .unresolvedFork, lines: [fork]))

        #expect(await store.replaceBufferedLines(path: file.path, kind: .subagent, lines: []))
        #expect(await store.fetchBufferedLines(path: file.path) == [fork])
    }

    @Test
    func `discovery state round trips and clears`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let state = Self.discoveryState(paths: ["/a", "/b"])

        #expect(await store.setDiscoveryState(state))
        #expect(await store.fetchDiscoveryState() == state)
        #expect(await store.setDiscoveryState(nil))
        #expect(await store.fetchDiscoveryState() == nil)
    }

    @Test
    func `active lookback state round trips`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let state = CostUsageStoreLookbackState(
            scanSinceDay: "2026-07-01",
            rootPaths: ["/root"],
            nextDayByRoot: ["/root": "2026-07-10"],
            completedRootPaths: [],
            pendingFilePaths: ["/pending"],
            legacyRecursivePendingRootPaths: ["/legacy"],
            directoryCursorVersion: 3,
            directoryPendingNamesByCursor: ["current:/root": ["next.jsonl"]],
            legacyRecursiveDirectoryPathsByRoot: ["/root": ["/root/legacy"]],
            legacyRecursiveDirectoryOffsetByPath: ["/root/legacy": 12],
            exactInventoryPendingRootPaths: ["/root"],
            exactInventoryDirectoryPathsByRoot: ["/root": ["/root/current"]],
            exactInventoryDirectoryOffsetByPath: ["/root/current": 24],
            exactInventoryVisitedDirectoryPaths: ["/root/visited"],
            exactValidationPaths: ["/root/a.jsonl", "/root/b.jsonl"],
            exactValidationNextIndex: 1,
            exactValidationProcessedBytes: 100,
            exactValidationTotalBytes: 200,
            exactValidationCompletedFiles: 1,
            exactValidationTotalFiles: 2,
            exactValidationSeenIdentities: ["identity"],
            exactValidationInventoryPaths: ["/root/a.jsonl"],
            exactInventoryGeneration: "generation",
            exactInventoryScanSinceDay: "2026-07-01",
            exactInventoryScanUntilDay: "2026-07-31",
            exactInventoryNextDayByRoot: ["/root": "2026-07-10"],
            exactInventoryDirectoryOffsetByRoot: ["/root": 44],
            exactInventoryCompletedRootPaths: [],
            exactInventoryFlatDirectoryOffsetByRoot: ["/root": 55],
            exactInventoryCompletedFlatRootPaths: [],
            exactCachedValidationLastPath: "/root/a.jsonl")

        #expect(await store.setLookbackState(state))
        #expect(await store.fetchLookbackState() == state)
    }

    @Test
    func `scan metadata round trips`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let metadata = Self.metadata()

        #expect(await store.setMetadata(metadata))
        #expect(await store.fetchMetadata() == metadata)
    }

    @Test
    func `two stores advance freshness monotonically without losing current metadata`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let first = CostUsageStore(cacheRoot: fixture.root)
        let second = CostUsageStore(cacheRoot: fixture.root)
        var stale = Self.metadata()
        stale.lastScanUnixMs = 100
        #expect(await first.setMetadata(stale))

        // Simulate a second owner committing richer metadata after the first owner obtained
        // its stale input. The freshness operation must re-read this whole payload under its
        // writer lock rather than writing fields copied from the stale caller.
        var current = stale
        current.lastScanUnixMs = 250
        current.scanSinceDay = "2026-07-01"
        current.scanUntilDay = "2026-08-11"
        current.pricingKey = "pricing-v2"
        current.priorityMetadataKey = "priority-v2"
        current.catchUpPending = false
        current.rootMtimes = ["/current/root": 999]
        current.previousReportPayload = Data([9, 8, 7])
        current.priorityTurnStatePayload = Data([6, 5, 4])
        current.projectMetadataVersion = 9
        #expect(await second.setMetadata(current))

        #expect(await first.advanceLastScanUnixMs(200))
        #expect(await first.fetchMetadata() == current)
        #expect(await second.advanceLastScanUnixMs(300))
        var expected = current
        expected.lastScanUnixMs = 300
        #expect(await first.fetchMetadata() == expected)

        var catchUp = expected
        catchUp.catchUpPending = true
        catchUp.lastScanUnixMs = 0
        #expect(await second.setMetadata(catchUp))
        #expect(await first.advanceLastScanUnixMs(400))
        #expect(await first.fetchMetadata() == catchUp)
    }

    @Test(.timeLimit(.minutes(1)))
    func `held writer lock makes freshness advance fail soft without rebuilding`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var metadata = Self.metadata()
        metadata.catchUpPending = false
        #expect(await store.setMetadata(metadata))

        let holder = try SQLiteTestConnection(url: store.databaseURL)
        try holder.execute("BEGIN IMMEDIATE")
        try holder.execute("INSERT OR REPLACE INTO meta(key, value) VALUES ('freshness-holder', '1')")

        #expect(await store.advanceLastScanUnixMs(500) == false)
        #expect(await store.rebuildCount == 0)
        #expect(FileManager.default.fileExists(atPath: store.databaseURL.path))

        try holder.execute("COMMIT")
        #expect(await store.fetchMetadata() == metadata)
        #expect(await store.advanceLastScanUnixMs(500))
        var expected = metadata
        expected.lastScanUnixMs = 500
        #expect(await store.fetchMetadata() == expected)
        #expect(await store.rebuildCount == 0)
    }

    @Test
    func `terminal accumulator round trips all state`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let file = Self.file(path: "/rollouts/a.jsonl", day: "2026-08-01")
        let accumulator = Self.accumulator(path: file.path)
        #expect(await store.upsertFile(file))

        #expect(await store.upsertAccumulator(accumulator))
        #expect(await store.fetchAccumulator(path: file.path) == accumulator)
    }
}

extension CostUsageStoreTests {
    @Test
    func `full snapshot reads every table from one transaction`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let file = Self.file(path: "/rollouts/a.jsonl", day: "2026-08-01")
        let token = Self.snapshot(path: file.path, eventIndex: 0)
        let aggregate = Self.aggregate(day: "2026-08-01", model: "model-a", scale: 1)
        let lineage = Self.lineage(path: file.path)
        let line = Self.bufferedLine(path: file.path, kind: .subagent, index: 0)
        let discovery = Self.discoveryState(paths: [file.path])
        let lookback = CostUsageStoreLookbackState(
            scanSinceDay: "2026-08-01",
            rootPaths: ["/root"],
            nextDayByRoot: [:],
            completedRootPaths: [],
            pendingFilePaths: [],
            legacyRecursivePendingRootPaths: [])
        let accumulator = Self.accumulator(path: file.path)
        let metadata = Self.metadata()
        #expect(await store.upsertFile(file))
        #expect(await store.appendTokenSnapshots([token]))
        #expect(await store.replaceFileDayAggregates(path: file.path, aggregates: [aggregate]))
        #expect(await store.mergeDayAggregates([aggregate]))
        #expect(await store.upsertForkLineage(lineage))
        #expect(await store.replaceBufferedLines(path: file.path, kind: .subagent, lines: [line]))
        #expect(await store.setDiscoveryState(discovery))
        #expect(await store.setLookbackState(lookback))
        #expect(await store.upsertAccumulator(accumulator))
        #expect(await store.setMetadata(metadata))

        let snapshot = await store.readSnapshot()
        #expect(snapshot == CostUsageStoreSnapshot(
            metadata: metadata,
            files: [file],
            tokenSnapshots: [token],
            fileDayAggregates: [CostUsageStoreFileDayAggregate(path: file.path, aggregate: aggregate)],
            dayAggregates: [aggregate],
            forkLineage: [lineage],
            bufferedLines: [line],
            discoveryState: discovery,
            lookbackState: lookback,
            accumulators: [accumulator]))
    }

    @Test
    func `report readback includes metadata and bounded aggregates`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let metadata = Self.metadata()
        let inside = Self.aggregate(day: "2026-08-02", model: "model-a", scale: 1)
        let outside = Self.aggregate(day: "2026-07-31", model: "model-a", scale: 1)
        #expect(await store.setMetadata(metadata))
        #expect(await store.mergeDayAggregates([inside, outside]))

        #expect(await store.readReport(sinceDay: "2026-08-01", untilDay: "2026-08-03") ==
            CostUsageStoreReport(metadata: metadata, aggregates: [inside]))
    }

    @Test
    func `database persists across store instances`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let first = CostUsageStore(cacheRoot: fixture.root)
        let file = Self.file(path: "/rollouts/a.jsonl", day: "2026-08-01")
        #expect(await first.upsertFile(file))
        let second = CostUsageStore(cacheRoot: fixture.root)

        #expect(await second.fetchFile(path: file.path) == file)
        #expect(await second.rebuildCount == 0)
    }
}

extension CostUsageStoreTests {
    @Test
    func `legacy rowless duplicate reparses after contributor removal without rebuilding store`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let iso = env.isoString(for: day)
        let contents = #"{"type":"session_meta","timestamp":"\#(iso)","payload":{"session_id":"shared"}}"# + "\n"
            + #"{"type":"turn_context","timestamp":"\#(iso)","payload":{"model":"gpt-5.5"}}"# + "\n"
            + #"{"timestamp":"\#(iso)","usage":{"input_tokens":100,"output_tokens":10}}"# + "\n"
        let contributor = try env.writeCodexSessionFile(
            day: day,
            filename: "a-contributor.jsonl",
            contents: contents)
        let duplicate = try env.writeCodexSessionFile(
            day: day,
            filename: "b-duplicate.jsonl",
            contents: contents)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"),
            maxCodexSessionFileBytes: 0,
            maxCodexScanBytesPerRefresh: 0)
        options.refreshMinIntervalSeconds = 0
        options.preferNewestCodexSessionsFirst = false
        let first = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)
        #expect(first.summary?.totalTokens == 110)

        let store = CostUsageStore(cacheRoot: env.cacheRoot)
        var cache = store.syncLoadCodexCache(calendar: .current)
        var staleDuplicate = try #require(cache.files[contributor.path])
        let metadata = CostUsageScanner.codexFileMetadata(fileURL: duplicate)
        staleDuplicate.mtimeUnixMs = metadata.mtimeUnixMs
        staleDuplicate.codexScanFileId = metadata.fileId
        staleDuplicate.days = [:]
        staleDuplicate.codexRows = []
        staleDuplicate.codexTokenSnapshots = []
        staleDuplicate.codexTokenCheckpoints = []
        staleDuplicate.codexParserRevision = 2
        cache.files[duplicate.path] = staleDuplicate
        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day)
        _ = store.syncSaveCodexCache(
            cache,
            calendar: .current,
            requestedScanWindow: (sinceKey: dayKey, untilKey: dayKey))
        #expect(CostUsageStoreAccess.read(cacheRoot: env.cacheRoot).files[duplicate.path]?.codexRows?.isEmpty == true)

        let predecessorHash = "606a690018e2845e"
        let predecessorVersion = CostUsageStore.combinedSchemaVersion(
            base: CostUsageStore.baseSchemaVersion,
            parserHash: predecessorHash)
        let connection = try SQLiteTestConnection(url: store.databaseURL)
        try connection.execute("UPDATE meta SET value = '\(predecessorHash)' WHERE key = 'parser_hash'")
        try connection.execute("PRAGMA user_version = \(predecessorVersion)")
        let migrated = CostUsageStore(cacheRoot: env.cacheRoot)
        let migratedCache = migrated.syncLoadCodexCache(calendar: .current)
        #expect(await migrated.rebuildCount == 0)
        #expect(migratedCache.files[duplicate.path]?.codexParserRevision == 2)
        #expect(migratedCache.files[duplicate.path]?.hasCurrentCodexParser == false)

        try FileManager.default.removeItem(at: contributor)
        let recovered = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)
        #expect(recovered.summary?.totalTokens == 110)
        let after = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(after.files[duplicate.path]?.codexParserRevision == CostUsageFileUsage.currentCodexParserRevision)
        #expect(after.files[duplicate.path]?.codexRows?.count == 1)
    }

    @Test(arguments: ["606a690018e2845e", "c52728bbaeedeb90"])
    func `lf span parser adopts persisted partial checkpoint without rebuilding`(previousHash: String) async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let previousVersion = CostUsageStore.combinedSchemaVersion(
            base: CostUsageStore.baseSchemaVersion,
            parserHash: previousHash)
        let previous = CostUsageStore(
            cacheRoot: fixture.root,
            schemaVersion: previousVersion,
            parserHash: previousHash)
        let input = fixture.root.appendingPathComponent("partial.jsonl")
        let partial = Data("{}\n{\"body\":\"unfinished".utf8)
        try partial.write(to: input)
        let progress = try CostUsageJsonl.scanBounded(
            fileURL: input,
            maxLineBytes: 1024,
            prefixBytes: 1024,
            maxBytesToRead: nil,
            resumeState: nil,
            onLine: { _ in })
        let checkpoint = try #require(progress.resumeState)
        var file = Self.file(path: input.path, day: "2026-08-01")
        file.size = Int64(partial.count)
        file.parsedBytes = progress.committedOffset
        file.scanState.targetSize = file.size
        file.scanState.isComplete = false
        file.scanState.resumePayload = try JSONEncoder().encode(checkpoint)
        #expect(await previous.upsertFile(file))

        let current = CostUsageStore(cacheRoot: fixture.root)
        let adopted = try #require(await current.fetchFile(path: file.path))
        #expect(await current.rebuildCount == 0)
        let adoptedCheckpoint = try JSONDecoder().decode(
            CostUsageJsonl.ResumeState.self,
            from: #require(adopted.scanState.resumePayload))
        #expect(adoptedCheckpoint == checkpoint)

        try (partial + Data("\"}\n".utf8)).write(to: input)
        var resumedLines: [Data] = []
        let resumed = try CostUsageJsonl.scanBounded(
            fileURL: input,
            maxLineBytes: 1024,
            prefixBytes: 1024,
            maxBytesToRead: nil,
            resumeState: adoptedCheckpoint,
            onLine: { resumedLines.append($0.bytes) })
        #expect(resumedLines == [Data(#"{"body":"unfinished"}"#.utf8)])
        #expect(resumed.committedOffset == Int64(partial.count + 3))
        #expect(resumed.resumeState == nil)
    }

    @Test(arguments: [
        "c52728bbaeedeb90",
        "0001601034856fb6",
        "91aceec74bae13b6",
        "295616a4e7dcfc3f",
        "4e2ff98d27e5c601",
        "053a4fb6aa6156c2",
        "005a869f36400f7e",
        "15a7d46518e83cc0",
        "7607317f30850961",
    ])
    func `compatible predecessor parser hash adopts without rebuilding`(predecessorHash: String) async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        #expect(CostUsageStore.compatiblePredecessorParserHashes == [
            "c52728bbaeedeb90",
            "0001601034856fb6",
            "91aceec74bae13b6",
            "36872d2d0ebf9818",
            "053a4fb6aa6156c2",
            "4e2ff98d27e5c601",
            "7c53241287d9fe21",
            "4c666659fa05e700",
            "1dfdbe376483ff0c",
            "fd299eccf5e46671",
            "8214dde4d869b323",
            "6fd5257bc1319193",
            "154f5c0cc5ea50d3",
            "606a690018e2845e",
            "91a311c1117c5d33",
            "39536f87a26d851e",
            "a7f3e991314d5fde",
            "0538726d9c715433",
            "6ae28ea91dc80dcb",
            "996599f964eaba11",
            "a72e15e9d5724e06",
            "398d5964ff82286a",
            "f22371c47d2e006f",
            "295616a4e7dcfc3f",
            "238791b3f1229c6b",
            "f3c7abf13e841047",
            "1a8e14e8e822301c",
            "b5ecfaed30e652cd",
            "3d2771687ba0133f",
            "dd19ffa2dcfa8d47",
            "8050a4faf4fddb96",
            "cfd84d13ad7d4cfa",
            "98da5914d2f6a9cd",
            "43609cc56f76a003",
            "b975eb705f905b9a",
            "47144baa8daccf52",
            "2d17f4981b78d07f",
            "1ad1e41af7f25b3e",
            "be0bb04e9e92b697",
            "4c26d7b4f3200869",
            "776fe64ed298f47a",
            "ae84207057847ef9",
            "b68130304db92645",
            "f2bac4d17b6e80b7",
            "3053f2f21b526cb2",
            "794d08208e8b4be3",
            "a9e63a41a2306504",
            "005a869f36400f7e",
            "15a7d46518e83cc0",
            "7607317f30850961",
        ])
        let predecessorVersion = CostUsageStore.combinedSchemaVersion(
            base: CostUsageStore.baseSchemaVersion,
            parserHash: predecessorHash)
        let predecessor = CostUsageStore(
            cacheRoot: fixture.root,
            schemaVersion: predecessorVersion,
            parserHash: predecessorHash)
        var file = Self.file(path: "/rollouts/compatible.jsonl", day: "2026-08-01")
        file.scanState.isComplete = false
        let token = Self.snapshot(path: file.path, eventIndex: 0)
        let usageRow = CostUsageStoreUsageRow(path: file.path, rowIndex: 0, payload: Data([8, 9, 10]))
        let aggregate = Self.aggregate(day: "2026-08-01", model: "gpt-5.6-sol", scale: 1)
        let lineage = Self.lineage(path: file.path)
        let line = Self.bufferedLine(path: file.path, kind: .subagent, index: 0)
        let unresolvedLine = Self.bufferedLine(path: file.path, kind: .unresolvedFork, index: 1)
        let discovery = Self.discoveryState(paths: [file.path])
        let lookback = CostUsageStoreLookbackState(
            scanSinceDay: "2026-08-01",
            rootPaths: ["/root"],
            nextDayByRoot: ["/root": "2026-08-02"],
            completedRootPaths: [],
            pendingFilePaths: [file.path],
            legacyRecursivePendingRootPaths: [])
        let accumulator = Self.accumulator(path: file.path)
        let metadata = Self.metadata()
        #expect(await predecessor.upsertFile(file))
        #expect(await predecessor.appendTokenSnapshots([token]))
        #expect(await predecessor.replaceUsageRows(path: file.path, rows: [usageRow]))
        #expect(await predecessor.replaceFileDayAggregates(path: file.path, aggregates: [aggregate]))
        #expect(await predecessor.mergeDayAggregates([aggregate]))
        #expect(await predecessor.upsertForkLineage(lineage))
        #expect(await predecessor.replaceBufferedLines(path: file.path, kind: .subagent, lines: [line]))
        #expect(await predecessor.replaceBufferedLines(
            path: file.path,
            kind: .unresolvedFork,
            lines: [unresolvedLine]))
        #expect(await predecessor.setDiscoveryState(discovery))
        #expect(await predecessor.setLookbackState(lookback))
        #expect(await predecessor.upsertAccumulator(accumulator))
        #expect(await predecessor.setMetadata(metadata))
        var before = await predecessor.readSnapshot()
        if predecessorHash == "005a869f36400f7e" {
            // Only the derived report is invalidated; every parsed row and resume cursor survives.
            before.metadata.previousReportPayload = nil
        }

        let current = CostUsageStore(cacheRoot: fixture.root)
        let after = await current.readSnapshot()
        #expect(after == before)
        #expect(await current.rebuildCount == 0)
        #expect(await current.configuration()?.userVersion == Int(CostUsageStore.schemaVersion))
        let connection = try SQLiteTestConnection(url: fixture.databaseURL, readOnly: true)
        #expect(try connection.scalarInt(
            "SELECT COUNT(*) FROM meta WHERE key = 'parser_hash' AND value = '\(CodexParserHash.value)'") == 1)
    }

    @Test
    func `current live parser hash is an explicitly compatible predecessor`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let predecessorHash = "a9e63a41a2306504"
        let predecessorVersion = CostUsageStore.combinedSchemaVersion(
            base: CostUsageStore.baseSchemaVersion,
            parserHash: predecessorHash)
        let predecessor = CostUsageStore(
            cacheRoot: fixture.root,
            schemaVersion: predecessorVersion,
            parserHash: predecessorHash)
        let file = Self.file(path: "/rollouts/live-hash.jsonl", day: "2026-08-01")
        #expect(await predecessor.upsertFile(file))

        let current = CostUsageStore(cacheRoot: fixture.root)
        #expect(await current.fetchFile(path: file.path) == file)
        #expect(await current.rebuildCount == 0)
        #expect(await current.configuration()?.userVersion == Int(CostUsageStore.schemaVersion))
    }

    @Test
    func `provider pricing hash adopts existing cost rows without rebuilding`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let predecessorHash = "154f5c0cc5ea50d3"
        let predecessorVersion = CostUsageStore.combinedSchemaVersion(
            base: CostUsageStore.baseSchemaVersion,
            parserHash: predecessorHash)
        let predecessor = CostUsageStore(
            cacheRoot: fixture.root,
            schemaVersion: predecessorVersion,
            parserHash: predecessorHash)
        let file = Self.file(path: "/rollouts/provider-pricing.jsonl", day: "2026-08-01")
        let metadata = Self.metadata()
        #expect(await predecessor.upsertFile(file))
        #expect(await predecessor.setMetadata(metadata))
        let before = await predecessor.readSnapshot()

        let current = CostUsageStore(cacheRoot: fixture.root)
        #expect(await current.readSnapshot() == before)
        #expect(await current.rebuildCount == 0)
        #expect(await current.configuration()?.userVersion == Int(CostUsageStore.schemaVersion))
        let connection = try SQLiteTestConnection(url: fixture.databaseURL, readOnly: true)
        #expect(try connection.scalarInt(
            "SELECT COUNT(*) FROM meta WHERE key = 'parser_hash' AND value = '\(CodexParserHash.value)'") == 1)
    }

    @Test(arguments: [
        "f22371c47d2e006f",
        "8050a4faf4fddb96",
        "dd19ffa2dcfa8d47",
        "005a869f36400f7e",
    ])
    func `retained report migration preserves compatible rows and clears stale payload`(
        predecessorHash: String) async throws
    {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let predecessorVersion = CostUsageStore.combinedSchemaVersion(
            base: CostUsageStore.baseSchemaVersion,
            parserHash: predecessorHash)
        let predecessor = CostUsageStore(
            cacheRoot: fixture.root,
            schemaVersion: predecessorVersion,
            parserHash: predecessorHash)
        let file = Self.file(path: "/rollouts/retained-report.jsonl", day: "2026-08-01")
        let aggregate = Self.aggregate(day: "2026-08-01", model: "gpt-5.6-sol", scale: 1)
        #expect(await predecessor.upsertFile(file))
        #expect(await predecessor.replaceFileDayAggregates(path: file.path, aggregates: [aggregate]))
        #expect(await predecessor.mergeDayAggregates([aggregate]))
        #expect(await predecessor.setMetadata(Self.metadata()))
        var expected = await predecessor.readSnapshot()
        expected.metadata.previousReportPayload = nil

        let current = CostUsageStore(cacheRoot: fixture.root)

        #expect(await current.readSnapshot() == expected)
        #expect(await current.rebuildCount == 0)
        #expect(await current.configuration()?.userVersion == Int(CostUsageStore.schemaVersion))
    }

    @Test
    func `compatible predecessor parser hash adopts cursorless priority payload without rebuilding`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let predecessorHash = "2d17f4981b78d07f"
        let predecessorVersion = CostUsageStore.combinedSchemaVersion(
            base: CostUsageStore.baseSchemaVersion,
            parserHash: predecessorHash)
        let predecessor = CostUsageStore(
            cacheRoot: fixture.root,
            schemaVersion: predecessorVersion,
            parserHash: predecessorHash)
        let file = Self.file(path: "/rollouts/compatible.jsonl", day: "2026-08-01")
        var metadata = CostUsageStoreMetadata.empty
        metadata.priorityTurnStatePayload = Data(
            #"{"turnKeys":{"turn-a":"priority"},"turnIDsByDay":{"2026-05-10":["turn-a"]}}"#.utf8)
        #expect(await predecessor.upsertFile(file))
        #expect(await predecessor.setMetadata(metadata))

        let current = CostUsageStore(cacheRoot: fixture.root)
        let loaded = current.syncLoadCodexCache(calendar: .current)
        #expect(await current.fetchFile(path: file.path) == file)
        #expect(await current.fetchMetadata() == metadata)
        #expect(await current.rebuildCount == 0)
        #expect(await current.configuration()?.userVersion == Int(CostUsageStore.schemaVersion))
        #expect(loaded.codexPriorityTurnKeys == ["turn-a": "priority"])
        #expect(loaded.codexPriorityTurnIDsByDay == ["2026-05-10": ["turn-a"]])
        #expect(loaded.codexPriorityTurnsCursor == nil)
        let connection = try SQLiteTestConnection(url: fixture.databaseURL, readOnly: true)
        #expect(try connection.scalarInt(
            "SELECT COUNT(*) FROM meta WHERE key = 'parser_hash' AND value = '\(CodexParserHash.value)'") == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func `concurrent predecessor adoption never rebuilds a valid store`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let predecessorHash = "b975eb705f905b9a"
        let predecessorVersion = CostUsageStore.combinedSchemaVersion(
            base: CostUsageStore.baseSchemaVersion,
            parserHash: predecessorHash)
        let predecessor = CostUsageStore(
            cacheRoot: fixture.root,
            schemaVersion: predecessorVersion,
            parserHash: predecessorHash)
        let metadata = Self.metadata()
        #expect(await predecessor.setMetadata(metadata))

        let stores = (0..<16).map { _ in CostUsageStore(cacheRoot: fixture.root) }
        await withTaskGroup(of: Void.self) { group in
            for store in stores {
                group.addTask {
                    #expect(await store.fetchMetadata() == metadata)
                    #expect(await store.rebuildCount == 0)
                }
            }
        }
        let connection = try SQLiteTestConnection(url: fixture.databaseURL, readOnly: true)
        #expect(try connection.scalarInt("PRAGMA user_version") == Int64(CostUsageStore.schemaVersion))
        #expect(try connection.scalarInt(
            "SELECT COUNT(*) FROM meta WHERE key = 'parser_hash' AND value = '\(CodexParserHash.value)'") == 1)
    }

    @Test
    func `version mismatch drops and recreates`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let url = fixture.databaseURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SQLiteTestConnection.execute(at: url, sql: "PRAGMA user_version = 7")
        let store = CostUsageStore(cacheRoot: fixture.root)

        #expect(await store.fetchMetadata() == .empty)
        #expect(await store.rebuildCount == 1)
        #expect(await store.configuration()?.userVersion == Int(CostUsageStore.schemaVersion))
    }

    @Test
    func `parser hash mismatch drops and recreates`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let url = fixture.databaseURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SQLiteTestConnection.execute(at: url, sql: """
        PRAGMA auto_vacuum=INCREMENTAL;
        VACUUM;
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        INSERT INTO meta(key, value) VALUES ('parser_hash', 'old-parser');
        PRAGMA user_version = \(CostUsageStore.schemaVersion);
        """)
        let store = CostUsageStore(cacheRoot: fixture.root)

        #expect(await store.fetchMetadata() == .empty)
        #expect(await store.rebuildCount == 1)
    }

    @Test
    func `tokscale value-changing parser hash forces a rebuild`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let previousParserHash = "76877b47a94fe28c"
        let previousStore = CostUsageStore(
            cacheRoot: fixture.root,
            schemaVersion: CostUsageStore.combinedSchemaVersion(
                base: CostUsageStore.baseSchemaVersion,
                parserHash: previousParserHash),
            parserHash: previousParserHash)
        let cachedFile = Self.file(path: "/rollouts/stale-tokscale-values.jsonl", day: "2026-08-01")
        #expect(await previousStore.upsertFile(cachedFile))

        let currentStore = CostUsageStore(cacheRoot: fixture.root)

        #expect(await currentStore.fetchFile(path: cachedFile.path) == nil)
        #expect(await currentStore.rebuildCount == 1)
        #expect(await currentStore.configuration()?.userVersion == Int(CostUsageStore.schemaVersion))
        let connection = try SQLiteTestConnection(url: fixture.databaseURL, readOnly: true)
        #expect(try connection.scalarInt(
            "SELECT COUNT(*) FROM meta WHERE key = 'parser_hash' AND value = '\(CodexParserHash.value)'") == 1)
    }

    @Test
    func `v0_49_2 parser hash upgrades without rebuilding completed files`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let previousParserHash = "b975eb705f905b9a"
        let previousSchemaVersion = CostUsageStore.combinedSchemaVersion(
            base: CostUsageStore.baseSchemaVersion,
            parserHash: previousParserHash)
        let previousStore = CostUsageStore(
            cacheRoot: fixture.root,
            schemaVersion: previousSchemaVersion,
            parserHash: previousParserHash)
        let file = Self.file(path: "/rollouts/completed.jsonl", day: "2026-08-01")
        #expect(await previousStore.upsertFile(file))

        let upgradedStore = CostUsageStore(cacheRoot: fixture.root)

        #expect(await upgradedStore.fetchFile(path: file.path) == file)
        #expect(await upgradedStore.rebuildCount == 0)
        #expect(await upgradedStore.configuration()?.userVersion == Int(CostUsageStore.schemaVersion))
        let connection = try SQLiteTestConnection(url: fixture.databaseURL, readOnly: true)
        #expect(try connection.scalarInt(
            "SELECT COUNT(*) FROM meta WHERE key = 'parser_hash' AND value = '\(CodexParserHash.value)'") == 1)
    }

    @Test
    func `compatible predecessor hash with mismatched version still rebuilds`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let predecessorHash = "b975eb705f905b9a"
        let predecessorVersion = CostUsageStore.combinedSchemaVersion(
            base: CostUsageStore.baseSchemaVersion,
            parserHash: predecessorHash)
        let predecessor = CostUsageStore(
            cacheRoot: fixture.root,
            schemaVersion: predecessorVersion,
            parserHash: predecessorHash)
        #expect(await predecessor.setMetadata(Self.metadata()))
        try SQLiteTestConnection.execute(
            at: fixture.databaseURL,
            sql: "PRAGMA user_version = \(predecessorVersion + 1)")

        let current = CostUsageStore(cacheRoot: fixture.root)
        #expect(await current.fetchMetadata() == .empty)
        #expect(await current.rebuildCount == 1)
    }

    @Test
    func `compatible predecessor hash without incremental auto vacuum still rebuilds`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let predecessorHash = "b975eb705f905b9a"
        let predecessorVersion = CostUsageStore.combinedSchemaVersion(
            base: CostUsageStore.baseSchemaVersion,
            parserHash: predecessorHash)
        try FileManager.default.createDirectory(
            at: fixture.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try SQLiteTestConnection.execute(at: fixture.databaseURL, sql: """
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        INSERT INTO meta(key, value) VALUES ('parser_hash', '\(predecessorHash)');
        PRAGMA user_version = \(predecessorVersion);
        """)

        let current = CostUsageStore(cacheRoot: fixture.root)
        #expect(await current.fetchMetadata() == .empty)
        #expect(await current.rebuildCount == 1)
        #expect(await current.configuration()?.autoVacuumMode == 2)
    }

    @Test
    func `garbage database recovers by rebuild`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let url = fixture.databaseURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a sqlite database".utf8).write(to: url)
        let store = CostUsageStore(cacheRoot: fixture.root)

        #expect(await store.fetchMetadata() == .empty)
        #expect(await store.rebuildCount == 1)
        #expect(await store.configuration()?.journalMode.lowercased() == "wal")
    }

    @Test
    func `runtime sqlite error degrades to a fresh store`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        #expect(await store.mergeDayAggregates([Self.aggregate(day: "2026-08-01", model: "model-a", scale: 1)]))
        try SQLiteTestConnection.execute(at: store.databaseURL, sql: "DROP TABLE day_aggregates")

        #expect(await store.fetchDayAggregates(sinceDay: "2026-08-01", untilDay: "2026-08-01").isEmpty)
        #expect(await store.rebuildCount == 1)
    }
}

extension CostUsageStoreTests {
    @Test
    func `retention keeps inclusive window edges`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let days = ["2026-07-31", "2026-08-01", "2026-08-03", "2026-08-04"]
        for (index, day) in days.enumerated() {
            let file = Self.file(path: "/rollouts/\(index).jsonl", day: day)
            #expect(await store.upsertFile(file))
            #expect(await store.appendTokenSnapshots([Self.snapshot(path: file.path, eventIndex: 0, day: day)]))
            let aggregate = Self.aggregate(day: day, model: "model-a", scale: 1)
            #expect(await store.replaceFileDayAggregates(path: file.path, aggregates: [aggregate]))
            #expect(await store.mergeDayAggregates([aggregate]))
        }

        let result = await store.retainDayWindow(sinceDay: "2026-08-01", untilDay: "2026-08-03")
        #expect(result.deletedFiles == 2)
        #expect(result.deletedFileDayAggregates == 2)
        #expect(await (store.readSnapshot()).files.map(\.coverageSinceDay) == ["2026-08-01", "2026-08-03"])
        #expect(await (store.readSnapshot()).dayAggregates.map(\.day) == ["2026-08-01", "2026-08-03"])
    }

    @Test
    func `retention preserves incomplete out of window file`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var file = Self.file(path: "/rollouts/incomplete.jsonl", day: "2026-07-01")
        file.scanState.isComplete = false
        #expect(await store.upsertFile(file))

        _ = await store.retainDayWindow(sinceDay: "2026-08-01", untilDay: "2026-08-03")
        #expect(await store.fetchFile(path: file.path) != nil)
    }

    @Test
    func `retention preserves file with buffered retry lines`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let file = Self.file(path: "/rollouts/buffered.jsonl", day: "2026-07-01")
        let line = Self.bufferedLine(path: file.path, kind: .unresolvedFork, index: 0)
        #expect(await store.upsertFile(file))
        #expect(await store.replaceBufferedLines(path: file.path, kind: .unresolvedFork, lines: [line]))

        _ = await store.retainDayWindow(sinceDay: "2026-08-01", untilDay: "2026-08-03")
        #expect(await store.fetchFile(path: file.path) != nil)
    }

    @Test
    func `retention preserves parent referenced by surviving child`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var parent = Self.file(path: "/rollouts/parent.jsonl", day: "2026-07-01")
        parent.sessionID = "parent-session"
        let child = Self.file(path: "/rollouts/child.jsonl", day: "2026-08-02")
        var lineage = Self.lineage(path: child.path)
        lineage.forkedFromID = "parent-session"
        #expect(await store.upsertFile(parent))
        #expect(await store.upsertFile(child))
        #expect(await store.upsertForkLineage(lineage))

        _ = await store.retainDayWindow(sinceDay: "2026-08-01", untilDay: "2026-08-03")
        #expect(await store.fetchFile(path: parent.path) != nil)
    }

    @Test
    func `retention keeps recently modified file with stale coverage`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        var file = Self.file(path: "/rollouts/stale-but-active.jsonl", day: "2026-07-01")
        let recentMtime = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 1,
            hour: 6)))
        file.mtimeUnixMs = Int64(recentMtime.timeIntervalSince1970 * 1000)
        #expect(await store.upsertFile(file))

        _ = await store.retainDayWindow(
            sinceDay: "2026-08-01",
            untilDay: "2026-08-03",
            calendar: calendar)
        #expect(await store.fetchFile(path: file.path) != nil)
    }

    @Test
    func `retention prunes stale file modified before the window`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        var file = Self.file(path: "/rollouts/stale-and-idle.jsonl", day: "2026-07-01")
        let oldMtime = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 1,
            hour: 12)))
        file.mtimeUnixMs = Int64(oldMtime.timeIntervalSince1970 * 1000)
        #expect(await store.upsertFile(file))

        _ = await store.retainDayWindow(
            sinceDay: "2026-08-01",
            untilDay: "2026-08-03",
            calendar: calendar)
        #expect(await store.fetchFile(path: file.path) == nil)
    }

    @Test
    func `retention prunes stale file modified after the window`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        var file = Self.file(path: "/rollouts/stale-after-window.jsonl", day: "2026-07-01")
        let lateMtime = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 4,
            hour: 12)))
        file.mtimeUnixMs = Int64(lateMtime.timeIntervalSince1970 * 1000)
        #expect(await store.upsertFile(file))

        _ = await store.retainDayWindow(
            sinceDay: "2026-08-01",
            untilDay: "2026-08-03",
            calendar: calendar)
        #expect(await store.fetchFile(path: file.path) == nil)
    }

    @Test
    func `retention keeps stale file modified at the window edges`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let startMtime = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 1,
            hour: 0)))
        let endMtime = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 3,
            hour: 23,
            minute: 59,
            second: 59)))
        for (index, mtime) in [startMtime, endMtime].enumerated() {
            var file = Self.file(
                path: "/rollouts/edge-\(index).jsonl",
                day: "2026-07-01")
            file.mtimeUnixMs = Int64(mtime.timeIntervalSince1970 * 1000)
            #expect(await store.upsertFile(file))
        }

        _ = await store.retainDayWindow(
            sinceDay: "2026-08-01",
            untilDay: "2026-08-03",
            calendar: calendar)
        #expect(await store.fetchFile(path: "/rollouts/edge-0.jsonl") != nil)
        #expect(await store.fetchFile(path: "/rollouts/edge-1.jsonl") != nil)
    }

    @Test
    func `retention prunes discovery references for removed files`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var old = Self.file(path: "/rollouts/old.jsonl", day: "2026-07-01")
        old.sessionID = "old-session"
        #expect(await store.upsertFile(old))
        #expect(await store.setDiscoveryState(Self.discoveryState(paths: [old.path])))

        _ = await store.retainDayWindow(sinceDay: "2026-08-01", untilDay: "2026-08-03")
        let discovery = try #require(await store.fetchDiscoveryState())
        #expect(discovery.filePaths.isEmpty)
        #expect(discovery.pendingSessionIDs.isEmpty)
        #expect(discovery.filePathBySessionID.isEmpty)
    }

    @Test
    func `retention prunes the discovery payload in sync with typed state`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var old = Self.file(path: "/rollouts/old.jsonl", day: "2026-07-01")
        old.sessionID = "old-session"
        var kept = Self.file(path: "/rollouts/kept.jsonl", day: "2026-08-02")
        kept.sessionID = "kept-session"
        #expect(await store.upsertFile(old))
        #expect(await store.upsertFile(kept))
        let discovery = CostUsageCodexSessionDiscovery(
            roots: ["/rollouts"],
            generation: nil,
            directoryStamps: [:],
            directoryPaths: [],
            nextDirectoryIndex: 3,
            filePaths: [old.path, kept.path],
            nextFileIndex: 2,
            fileStamps: [
                old.path: .init(mtimeUnixMs: 1, size: 100, fileId: nil),
                kept.path: .init(mtimeUnixMs: 1, size: 100, fileId: nil),
            ],
            headScan: nil,
            filePathBySessionId: [
                "old-session": old.path,
                "kept-session": kept.path,
            ],
            missingSessionIds: ["old-session"],
            pendingSessionIds: [],
            validationDirectoryIndex: 1,
            isComplete: true)
        var state = Self.discoveryState(paths: [old.path, kept.path])
        state.payload = try JSONEncoder().encode(discovery)
        #expect(await store.setDiscoveryState(state))

        _ = await store.retainDayWindow(sinceDay: "2026-08-01", untilDay: "2026-08-03")

        // The scanner round-trips discovery through the opaque payload, so pruning must
        // reach it or deleted files resurface on the next load.
        let cache = store.syncLoadCodexCache(calendar: .current)
        let pruned = try #require(cache.codexSessionDiscovery)
        #expect(pruned.filePaths == [kept.path])
        #expect(pruned.fileStamps[old.path] == nil)
        #expect(pruned.fileStamps[kept.path] != nil)
        #expect(pruned.filePathBySessionId["old-session"] == nil)
        #expect(pruned.filePathBySessionId["kept-session"] != nil)
        #expect(pruned.missingSessionIds.isEmpty)
        #expect(pruned.isComplete == false)
        #expect(pruned.nextFileIndex == 0)
        #expect(pruned.nextDirectoryIndex == 0)
    }

    @Test
    func `retention does not protect a parent referenced only by a lineage only child`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var parent = Self.file(path: "/rollouts/parent.jsonl", day: "2026-07-01")
        parent.sessionID = "parent-session"
        let child = Self.file(path: "/rollouts/child.jsonl", day: "2026-08-02")
        var lineage = Self.lineage(path: child.path)
        lineage.forkedFromID = "parent-session"
        lineage.dependencyKey = CostUsageScanner.codexForkDependencyNotRequiredKey
        #expect(await store.upsertFile(parent))
        #expect(await store.upsertFile(child))
        #expect(await store.upsertForkLineage(lineage))

        _ = await store.retainDayWindow(sinceDay: "2026-08-01", untilDay: "2026-08-03")

        // Lineage-only children never resolve inherited totals, so they do not keep a
        // stale out-of-window parent alive.
        #expect(await store.fetchFile(path: parent.path) == nil)
        #expect(await store.fetchFile(path: child.path) != nil)
    }

    @Test
    func `retention drops a stale parent referenced only by a stale child`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var parent = Self.file(path: "/rollouts/parent.jsonl", day: "2026-07-01", updatedAt: 1)
        parent.sessionID = "parent-session"
        var child = Self.file(path: "/rollouts/child.jsonl", day: "2026-07-02", updatedAt: 2)
        child.sessionID = "child-session"
        var lineage = Self.lineage(path: child.path)
        lineage.forkedFromID = "parent-session"
        #expect(await store.upsertFile(parent))
        #expect(await store.upsertFile(child))
        #expect(await store.upsertForkLineage(lineage))

        let result = await store.retainDayWindow(sinceDay: "2026-08-01", untilDay: "2026-08-03")

        // One pass: deleting the stale child releases the parent's fork protection, and the
        // parent must not linger as an unreferenced out-of-window row.
        #expect(result.deletedFiles == 2)
        #expect(await store.fetchFile(path: parent.path) == nil)
        #expect(await store.fetchFile(path: child.path) == nil)
    }

    @Test
    func `retention preserves an out of window file modified inside the window`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let calendar = CostUsageScanner.CostUsageDayRange.localGregorianCalendar()
        let activeDate = try #require(CostUsageScanner.parseDayKey("2026-08-02", calendar: calendar))
        var active = Self.file(path: "/rollouts/active.jsonl", day: "2026-07-01")
        active.mtimeUnixMs = Int64(activeDate.addingTimeInterval(3600).timeIntervalSince1970 * 1000)
        var stale = Self.file(path: "/rollouts/stale.jsonl", day: "2026-07-01")
        stale.mtimeUnixMs = 1
        #expect(await store.upsertFile(active))
        #expect(await store.upsertFile(stale))

        _ = await store.retainDayWindow(sinceDay: "2026-08-01", untilDay: "2026-08-03", calendar: calendar)

        // A recent mtime means the file may hold unscanned in-window rows; dropping it would
        // force a rediscovery and full reparse on every refresh.
        #expect(await store.fetchFile(path: active.path) != nil)
        #expect(await store.fetchFile(path: stale.path) == nil)
    }
}

extension CostUsageStoreTests {
    @Test
    func `save preserves an existing previous report when protected data exceeds the byte cap`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-06-01"
        cache.scanUntilKey = "2026-07-01"
        var older = CostUsageFileUsage(
            mtimeUnixMs: 1,
            size: 100,
            days: ["2026-06-05": ["gpt-5.5": [1, 0, 0]]])
        older.sessionId = "older-session"
        var recent = CostUsageFileUsage(
            mtimeUnixMs: 1,
            size: 100,
            days: ["2026-06-28": ["gpt-5.5": [1, 0, 0]]])
        recent.sessionId = "recent-session"
        cache.files = [
            "/sessions/older.jsonl": older,
            "/sessions/recent.jsonl": recent,
        ]
        cache.days = [
            "2026-06-05": ["gpt-5.5": [1, 0, 0]],
            "2026-06-28": ["gpt-5.5": [1, 0, 0]],
        ]
        // Simulate an already pending catch-up pass with a complete previous report.
        cache.codexScanCatchUpPending = true
        cache.codexPreviousReport = CostUsageCodexPreviousReport(
            report: CostUsageDailyReport(data: [
                CostUsageDailyReport.Entry(
                    date: "2026-06-05",
                    inputTokens: 1,
                    outputTokens: 0,
                    totalTokens: 1,
                    costUSD: nil,
                    modelsUsed: nil,
                    modelBreakdowns: nil),
            ], summary: nil),
            cache: cache,
            reportSinceKey: "2026-06-01",
            reportUntilKey: "2026-07-01")

        let result = store.syncSaveCodexCache(
            cache,
            calendar: .current,
            requestedScanWindow: (sinceKey: "2026-06-01", untilKey: "2026-07-01"),
            reportWindow: (sinceKey: "2026-06-01", untilKey: "2026-07-01"),
            fileBudgetBytes: 1)

        #expect(result.catchUpRequired == false)
        let metadata = await store.fetchMetadata()
        let payload = try #require(metadata.previousReportPayload)
        let preserved = try JSONDecoder().decode(CostUsageCodexPreviousReport.self, from: payload)
        #expect(preserved.data.count == 1)
        #expect(preserved.data.first?.date == "2026-06-05")
        #expect(preserved.data.contains { $0.date == "2026-06-28" } == false)
    }

    @Test
    func `save over byte cap keeps non-gregorian in window report intact`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-06-01"
        cache.scanUntilKey = "2026-07-01"
        var entry = CostUsageFileUsage(
            mtimeUnixMs: 1,
            size: 100,
            days: ["2026-06-05": ["gpt-5.5": [1, 0, 0]]])
        entry.sessionId = "in-window-session"
        cache.files = ["/sessions/in-window.jsonl": entry]
        cache.days = ["2026-06-05": ["gpt-5.5": [1, 0, 0]]]

        let result = store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-06-01", untilKey: "2026-07-01"),
            reportWindow: (sinceKey: "2026-06-01", untilKey: "2026-07-01"),
            fileBudgetBytes: 1)
        let report = await store.readReport(sinceDay: "2026-06-01", untilDay: "2026-07-01")

        #expect(result.catchUpRequired == false)
        #expect(await store.fetchMetadata().previousReportPayload == nil)
        #expect(report.aggregates.map(\.day) == ["2026-06-05"])
        #expect(report.aggregates.contains { $0.day == "1483-06-05" } == false)
    }
}

extension CostUsageStoreTests {
    @Test
    func `narrow dashboard windows preserve wider retained cache under byte pressure`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let calendar = CostUsageScanner.CostUsageDayRange.localGregorianCalendar()
        let retainedWindow = (sinceKey: "2025-08-15", untilKey: "2026-08-14")
        let olderDay = "2026-01-15"
        let recentDay = "2026-08-14"
        let model = "gpt-5.5"
        let olderPath = "/rollouts/older.jsonl"
        let recentPath = "/rollouts/recent.jsonl"

        func usage(day: String, mtimeUnixMs: Int64) -> CostUsageFileUsage {
            var value = CostUsageFileUsage(
                mtimeUnixMs: mtimeUnixMs,
                size: 500,
                days: [day: [model: [1, 0, 0]]])
            value.parsedBytes = 500
            value.codexScanComplete = true
            return value
        }

        let olderUsage = usage(day: olderDay, mtimeUnixMs: 1)
        let recentUsage = usage(day: recentDay, mtimeUnixMs: 2)
        var cache = CostUsageCache()
        cache.scanSinceKey = retainedWindow.sinceKey
        cache.scanUntilKey = retainedWindow.untilKey
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        cache.files = [olderPath: olderUsage, recentPath: recentUsage]
        cache.days = olderUsage.days.merging(recentUsage.days) { _, recent in recent }

        let seeded = store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: retainedWindow,
            fileBudgetBytes: 1)
        #expect(seeded.deletedRows == 0)
        #expect(seeded.rowCount == 2)

        let dashboardWindows = [
            (sinceKey: "2026-07-16", skipIdenticalContent: true),
            (sinceKey: "2026-08-08", skipIdenticalContent: false),
        ]
        for dashboardWindow in dashboardWindows {
            let result = store.syncSaveCodexCache(
                cache,
                calendar: calendar,
                requestedScanWindow: (sinceKey: dashboardWindow.sinceKey, untilKey: recentDay),
                fileBudgetBytes: 1,
                skipIdenticalContent: dashboardWindow.skipIdenticalContent)
            let report = await store.readReport(
                sinceDay: retainedWindow.sinceKey,
                untilDay: retainedWindow.untilKey)
            let metadata = await store.fetchMetadata()

            #expect(result.catchUpRequired == false)
            #expect(result.deletedRows == 0)
            #expect(result.rowCount == 2)
            #expect(result.fileBytes > 1)
            #expect(await store.fetchFile(path: olderPath) != nil)
            #expect(await store.fetchFile(path: recentPath) != nil)
            #expect(report.aggregates.map(\.day) == [olderDay, recentDay])
            #expect(metadata.scanSinceDay == retainedWindow.sinceKey)
            #expect(metadata.scanUntilDay == retainedWindow.untilKey)
        }
    }

    @Test
    func `row budget deletes oldest rows to cap`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        for index in 0..<10 {
            let file = Self.file(path: "/rollouts/\(index).jsonl", day: "2026-08-01", updatedAt: Int64(index))
            #expect(await store.upsertFile(file))
            #expect(await store.replaceFileDayAggregates(
                path: file.path,
                aggregates: [Self.aggregate(day: "2026-08-01", model: "gpt-5.5", scale: 1)]))
        }
        #expect(await store.mergeDayAggregates([
            Self.aggregate(day: "2026-08-01", model: "gpt-5.5", scale: 10),
        ]))

        let result = await store.enforceBudgets(maxRows: 3, maxFileBytes: Int64.max)
        let report = await store.readReport(sinceDay: "2026-08-01", untilDay: "2026-08-01")
        #expect(result.rowCount <= 3)
        #expect(result.deletedRows >= 7)
        #expect(report.aggregates == [Self.aggregate(day: "2026-08-01", model: "gpt-5.5", scale: 3)])
    }

    @Test
    func `file size budget reclaims bytes after incremental vacuum`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        for index in 0..<8 {
            let file = Self.file(path: "/rollouts/\(index).jsonl", day: "2026-08-01", updatedAt: Int64(index))
            #expect(await store.upsertFile(file))
            let row = CostUsageStoreUsageRow(
                path: file.path,
                rowIndex: 0,
                payload: Data(repeating: UInt8(index), count: 256 * 1024))
            #expect(await store.replaceUsageRows(path: file.path, rows: [row]))
        }
        let before = await store.fileSizeBytes()
        let limit = max(1, before / 2)

        let result = await store.enforceBudgets(maxRows: .max, maxFileBytes: limit)
        #expect(result.fileBytes < before)
        #expect(result.deletedRows > 0)
    }

    @Test
    func `empty append and merge are no ops`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)

        #expect(await store.appendTokenSnapshots([]))
        #expect(await store.mergeDayAggregates([]))
        #expect(await (store.readSnapshot()).files.isEmpty)
    }

    @Test
    func `budget pruning uses the requested window and narrows retained coverage`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        #expect(await store.upsertFile(Self.file(path: "/rollouts/stale.jsonl", day: "2026-06-01", updatedAt: 1)))
        #expect(await store.upsertFile(Self.file(path: "/rollouts/current.jsonl", day: "2026-08-01", updatedAt: 2)))

        let result = await store.enforceBudgets(
            maxRows: 1,
            maxFileBytes: .max,
            requestedSinceDay: "2026-07-31",
            requestedUntilDay: "2026-08-02")

        #expect(result.rowCount == 1)
        #expect(await store.fetchFile(path: "/rollouts/stale.jsonl") == nil)
        #expect(await store.fetchFile(path: "/rollouts/current.jsonl") != nil)
        let metadata = await store.fetchMetadata()
        #expect(metadata.scanSinceDay == "2026-07-31")
        #expect(metadata.scanUntilDay == "2026-08-02")
    }

    @Test
    func `budget keeps a recently active zero day entry`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let calendar = CostUsageScanner.CostUsageDayRange.localGregorianCalendar()
        let activeDate = try #require(CostUsageScanner.parseDayKey("2026-08-01", calendar: calendar))
        var active = Self.file(path: "/rollouts/active.jsonl", day: "2026-08-01", updatedAt: 1)
        active.coverageSinceDay = nil
        active.coverageUntilDay = nil
        active.mtimeUnixMs = Int64(activeDate.addingTimeInterval(3600).timeIntervalSince1970 * 1000)
        var stale = Self.file(path: "/rollouts/stale-zero.jsonl", day: "2026-08-01", updatedAt: 0)
        stale.coverageSinceDay = nil
        stale.coverageUntilDay = nil
        stale.mtimeUnixMs = 1
        #expect(await store.upsertFile(active))
        #expect(await store.upsertFile(stale))

        _ = await store.enforceBudgets(
            maxRows: 1,
            maxFileBytes: .max,
            requestedSinceDay: "2026-08-01",
            requestedUntilDay: "2026-08-02",
            calendar: calendar)

        #expect(await store.fetchFile(path: active.path) != nil)
        #expect(await store.fetchFile(path: stale.path) == nil)
    }

    @Test
    func `byte budget preserves in window data across repeated enforcement`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let day = "2026-08-01"
        let model = "gpt-5.5"
        for (index, path) in ["/rollouts/one.jsonl", "/rollouts/two.jsonl"].enumerated() {
            let file = Self.file(path: path, day: day, updatedAt: Int64(index))
            #expect(await store.upsertFile(file))
            #expect(await store.replaceUsageRows(path: path, rows: [CostUsageStoreUsageRow(
                path: path,
                rowIndex: 0,
                payload: Data(repeating: UInt8(index), count: 256 * 1024))]))
            #expect(await store.replaceFileDayAggregates(
                path: path,
                aggregates: [Self.aggregate(day: day, model: model, scale: 1)]))
        }
        #expect(await store.mergeDayAggregates([Self.aggregate(day: day, model: model, scale: 2)]))

        let first = await store.enforceBudgets(
            maxRows: .max,
            maxFileBytes: 1,
            requestedSinceDay: day,
            requestedUntilDay: day)
        let second = await store.enforceBudgets(
            maxRows: .max,
            maxFileBytes: 1,
            requestedSinceDay: day,
            requestedUntilDay: day)
        let report = await store.readReport(sinceDay: day, untilDay: day)

        #expect(first.catchUpRequired == false)
        #expect(second.catchUpRequired == false)
        #expect(first.deletedRows == 0)
        #expect(second.deletedRows == 0)
        #expect(first.rowCount == 2)
        #expect(second.rowCount == 2)
        #expect(first.fileBytes > 1)
        #expect(second.fileBytes > 1)
        #expect(await store.fetchUsageRows(path: "/rollouts/one.jsonl").count == 1)
        #expect(await store.fetchUsageRows(path: "/rollouts/two.jsonl").count == 1)
        #expect(report.aggregates == [Self.aggregate(day: day, model: model, scale: 2)])
        #expect(await store.fetchMetadata().catchUpPending == false)
    }

    @Test
    func `row budget never deletes files touching the requested window`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        #expect(await store.upsertFile(Self.file(path: "/rollouts/stale.jsonl", day: "2026-06-01", updatedAt: 0)))
        #expect(await store.upsertFile(Self.file(path: "/rollouts/one.jsonl", day: "2026-08-01", updatedAt: 1)))
        #expect(await store.upsertFile(Self.file(path: "/rollouts/two.jsonl", day: "2026-08-02", updatedAt: 2)))

        let result = await store.enforceBudgets(
            maxRows: 1,
            maxFileBytes: .max,
            requestedSinceDay: "2026-08-01",
            requestedUntilDay: "2026-08-02")

        // The out-of-window file is pruned, but in-window files stay even though the row
        // count remains above the cap: the former entry budget never dropped in-window data.
        #expect(result.rowCount == 2)
        #expect(await store.fetchFile(path: "/rollouts/stale.jsonl") == nil)
        #expect(await store.fetchFile(path: "/rollouts/one.jsonl") != nil)
        #expect(await store.fetchFile(path: "/rollouts/two.jsonl") != nil)
        #expect(await store.fetchMetadata().catchUpPending == false)
    }

    @Test
    func `byte budget removes only data outside the requested window`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let stale = Self.file(path: "/rollouts/stale.jsonl", day: "2026-06-01", updatedAt: 0)
        let current = Self.file(path: "/rollouts/current.jsonl", day: "2026-08-01", updatedAt: 1)
        for file in [stale, current] {
            #expect(await store.upsertFile(file))
            #expect(await store.replaceUsageRows(path: file.path, rows: [CostUsageStoreUsageRow(
                path: file.path,
                rowIndex: 0,
                payload: Data(repeating: 7, count: 256 * 1024))]))
        }

        let result = await store.enforceBudgets(
            maxRows: .max,
            maxFileBytes: 1,
            requestedSinceDay: "2026-08-01",
            requestedUntilDay: "2026-08-02")

        #expect(result.deletedRows == 1)
        #expect(result.rowCount == 1)
        #expect(result.fileBytes > 1)
        #expect(await store.fetchFile(path: stale.path) == nil)
        #expect(await store.fetchFile(path: current.path) != nil)
        #expect(await store.fetchUsageRows(path: current.path).count == 1)
        #expect(await store.fetchMetadata().catchUpPending == false)
    }

    @Test
    func `byte budget preserves fork parent detail required by a surviving child`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var parent = Self.file(path: "/rollouts/parent.jsonl", day: "2026-06-01", updatedAt: 1)
        parent.sessionID = "parent-session"
        #expect(await store.upsertFile(parent))
        #expect(await store.upsertForkLineage(CostUsageStoreForkLineage(
            path: parent.path,
            sessionID: "parent-session",
            forkedFromID: nil,
            forkTimestamp: nil,
            dependencyKey: nil,
            subagentState: nil,
            accountingState: nil)))
        #expect(await store.replaceUsageRows(path: parent.path, rows: [CostUsageStoreUsageRow(
            path: parent.path,
            rowIndex: 0,
            payload: Data(repeating: 5, count: 256 * 1024))]))
        var child = Self.file(path: "/rollouts/child.jsonl", day: "2026-08-01", updatedAt: 2)
        child.sessionID = "child-session"
        child.scanState.isComplete = false
        var lineage = Self.lineage(path: child.path)
        lineage.forkedFromID = "parent-session"
        #expect(await store.upsertFile(child))
        #expect(await store.upsertForkLineage(lineage))

        let result = await store.enforceBudgets(
            maxRows: .max,
            maxFileBytes: 1,
            requestedSinceDay: "2026-08-01",
            requestedUntilDay: "2026-08-02")

        let retained = try #require(await store.fetchFile(path: parent.path))
        #expect(result.catchUpRequired == false)
        #expect(retained.parsedBytes == parent.parsedBytes)
        #expect(retained.scanState.isComplete)
        #expect(await store.fetchUsageRows(path: parent.path).count == 1)
        #expect(await store.fetchFile(path: child.path) != nil)
        #expect(await store.fetchMetadata().catchUpPending == false)
    }

    @Test(arguments: [false, true])
    func `retention protects committed and replacement fork parents`(enforceBudget: Bool) async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        var committed = Self.file(path: "/rollouts/committed-parent.jsonl", day: "2026-06-01")
        committed.sessionID = "committed-parent"
        var replacement = Self.file(path: "/rollouts/replacement-parent.jsonl", day: "2026-06-01")
        replacement.sessionID = "replacement-parent"
        var child = Self.file(path: "/rollouts/child.jsonl", day: "2026-08-01")
        child.scanState.isComplete = false
        child.scanState.replacementScanPending = true
        child.scanState.replacementForkLineage = .init(forkedFromID: "replacement-parent", dependencyKey: nil)
        let unrelated = Self.file(path: "/rollouts/unrelated.jsonl", day: "2026-06-01")
        for file in [committed, replacement, child, unrelated] {
            #expect(await store.upsertFile(file))
        }
        // Normal cache persistence stores structural lineage for root sessions as well.
        for parent in [committed, replacement] {
            #expect(await store.upsertForkLineage(CostUsageStoreForkLineage(
                path: parent.path,
                sessionID: parent.sessionID,
                forkedFromID: nil,
                forkTimestamp: nil,
                dependencyKey: nil,
                subagentState: nil,
                accountingState: nil)))
        }
        var lineage = Self.lineage(path: child.path)
        lineage.forkedFromID = "committed-parent"
        #expect(await store.upsertForkLineage(lineage))

        if enforceBudget {
            _ = await store.enforceBudgets(
                maxRows: 1,
                maxFileBytes: 1,
                requestedSinceDay: "2026-08-01",
                requestedUntilDay: "2026-08-01")
        } else {
            _ = await store.retainDayWindow(sinceDay: "2026-08-01", untilDay: "2026-08-01")
        }
        #expect(await store.fetchFile(path: committed.path) != nil)
        #expect(await store.fetchFile(path: replacement.path) != nil)
        #expect(await store.fetchFile(path: child.path) != nil)
        #expect(await store.fetchFile(path: unrelated.path) == nil)
    }

    @Test
    func `read only WAL reader keeps a consistent snapshot during write`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        #expect(await store.upsertFile(Self.file(path: "/rollouts/one.jsonl", day: "2026-08-01")))
        let reader = try SQLiteTestConnection(url: store.databaseURL, readOnly: true)
        try reader.execute("BEGIN")
        #expect(try reader.scalarInt("SELECT COUNT(*) FROM files") == 1)

        #expect(await store.upsertFile(Self.file(path: "/rollouts/two.jsonl", day: "2026-08-01")))
        #expect(try reader.scalarInt("SELECT COUNT(*) FROM files") == 1)
        try reader.execute("COMMIT")
        #expect(try reader.scalarInt("SELECT COUNT(*) FROM files") == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func `write lock held by another process skips the write instead of deleting the store`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        #expect(await store.upsertFile(Self.file(path: "/rollouts/one.jsonl", day: "2026-08-01")))

        // The CLI cost command scans through CostUsageFetcher and therefore opens its own
        // writable store connection. Hold that cross-process lock past the 5s busy timeout.
        let holder = try SQLiteTestConnection(url: store.databaseURL)
        try holder.execute("BEGIN IMMEDIATE")
        try holder.execute("INSERT OR REPLACE INTO meta(key, value) VALUES ('holder', '1')")

        let blocked = await store.upsertFile(Self.file(path: "/rollouts/two.jsonl", day: "2026-08-02"))
        #expect(blocked == false)
        #expect(await store.rebuildCount == 0)
        #expect(FileManager.default.fileExists(atPath: store.databaseURL.path))

        try holder.execute("COMMIT")
        #expect(await store.upsertFile(Self.file(path: "/rollouts/two.jsonl", day: "2026-08-02")))
        let reader = try SQLiteTestConnection(url: store.databaseURL, readOnly: true)
        #expect(try reader.scalarInt("SELECT COUNT(*) FROM files") == 2)
        #expect(await store.rebuildCount == 0)
    }
}

// MARK: - Fixtures

extension CostUsageStoreTests {
    private static func file(
        path: String,
        day: String,
        updatedAt: Int64 = 10) -> CostUsageStoreFile
    {
        CostUsageStoreFile(
            path: path,
            inode: 42,
            mtimeUnixMs: 1000,
            size: 500,
            parsedBytes: 400,
            anchor: CostUsageStoreValidationAnchor(indexedBytes: 400, windowStart: 144, sha256: "abc123"),
            scanState: CostUsageStoreScanState(
                targetSize: 500,
                isComplete: true,
                resumePayload: Data([1, 2, 3]),
                tokenTimestampsMonotonic: true,
                nextUsageRowIndex: 7,
                lastModel: "gpt-5.6-sol",
                lastTurnID: "turn-1",
                fileIdentity: "1:42",
                detailsPayload: Data([4, 5, 6]),
                inventoryValidationGeneration: "inventory-v1"),
            sessionID: "session-\(path)",
            coverageSinceDay: day,
            coverageUntilDay: day,
            updatedAtUnixMs: updatedAt)
    }

    private static func snapshot(
        path: String,
        eventIndex: Int,
        day: String = "2026-08-01") -> CostUsageStoreTokenSnapshot
    {
        CostUsageStoreTokenSnapshot(
            path: path,
            eventIndex: eventIndex,
            timestamp: "2026-08-01T12:00:00Z",
            timestampUnixMs: 1_754_046_000_000 + Int64(eventIndex),
            day: day,
            last: CostUsageStoreTotals(input: 2, cached: 1, output: 3, reasoning: 1),
            total: CostUsageStoreTotals(input: 20, cached: 10, output: 30, reasoning: 5),
            endOffset: 100 + Int64(eventIndex))
    }

    private static func aggregate(
        day: String,
        model: String,
        scale: Int64) -> CostUsageStoreDayAggregate
    {
        CostUsageStoreDayAggregate(
            day: day,
            model: model,
            inputTokens: 10 * scale,
            cachedTokens: 2 * scale,
            outputTokens: 3 * scale,
            reasoningTokens: 1 * scale,
            requestCount: 1 * scale,
            unpricedRequestCount: 1 * scale,
            authoritativeCostNanos: 1000 * scale,
            standardAuthoritativeCostNanos: 600 * scale,
            priorityAuthoritativeCostNanos: 400 * scale,
            standardInputTokens: 6 * scale,
            standardCachedTokens: 1 * scale,
            standardOutputTokens: 2 * scale,
            priorityInputTokens: 4 * scale,
            priorityCachedTokens: 1 * scale,
            priorityOutputTokens: 1 * scale,
            standardTokens: 9 * scale,
            priorityTokens: 6 * scale,
            standardResolvedCostNanos: 700 * scale,
            priorityResolvedCostNanos: 500 * scale,
            standardUnresolvedPricingCount: 2 * scale,
            priorityUnresolvedPricingCount: 1 * scale)
    }

    private static func lineage(path: String) -> CostUsageStoreForkLineage {
        CostUsageStoreForkLineage(
            path: path,
            sessionID: "child-session",
            forkedFromID: "parent-session",
            forkTimestamp: "2026-08-01T11:00:00Z",
            dependencyKey: "parent-key",
            subagentState: Data([4, 5]),
            accountingState: Data([6, 7]))
    }

    private static func bufferedLine(
        path: String,
        kind: CostUsageStoreBufferedLineKind,
        index: Int) -> CostUsageStoreBufferedLine
    {
        CostUsageStoreBufferedLine(
            path: path,
            kind: kind,
            lineIndex: index,
            ordinal: index + 10,
            endOffset: Int64(index + 100),
            payload: Data([UInt8(index), 9, 8]))
    }

    private static func discoveryState(paths: [String]) -> CostUsageStoreDiscoveryState {
        CostUsageStoreDiscoveryState(
            roots: ["/root"],
            generation: "generation-1",
            directoryPaths: ["/root/2026/08/01"],
            nextDirectoryIndex: 1,
            filePaths: paths,
            nextFileIndex: paths.count,
            filePathBySessionID: paths.isEmpty ? [:] : ["old-session": paths[0]],
            missingSessionIDs: ["old-session"],
            pendingSessionIDs: ["old-session"],
            validationDirectoryIndex: 2,
            isComplete: false,
            payload: Data([1, 3, 5]))
    }

    private static func accumulator(path: String) -> CostUsageStoreAccumulator {
        CostUsageStoreAccumulator(
            path: path,
            eventCount: 12,
            nextUsageRowIndex: 9,
            countedTotals: CostUsageStoreTotals(input: 10, cached: 2, output: 3, reasoning: 1),
            rawTotalsBaseline: CostUsageStoreTotals(input: 8, cached: 1, output: 2, reasoning: nil),
            rawTotalsWatermark: CostUsageStoreTotals(input: 12, cached: 3, output: 4, reasoning: 1),
            sawDivergentTotals: true,
            sawInterleavedTotals: true,
            seenRawTotals: [CostUsageStoreTotals(input: 9, cached: 1, output: 2, reasoning: nil)],
            updatedAtUnixMs: 99)
    }

    private static func metadata() -> CostUsageStoreMetadata {
        CostUsageStoreMetadata(
            lastScanUnixMs: 100,
            scanSinceDay: "2026-08-01",
            scanUntilDay: "2026-08-03",
            retainedLookbackDays: 30,
            timeZoneIdentifier: "UTC",
            pricingKey: "pricing-v1",
            priorityMetadataKey: "priority-v1",
            catchUpPending: true,
            processedBytes: 100,
            totalBytes: 200,
            completedFiles: 2,
            totalFiles: 4,
            scanInventoryPaths: ["/root/2026/08/01/session.jsonl"],
            rootMtimes: ["/root": 123],
            previousReportPayload: Data([2, 4, 6]),
            priorityTurnStatePayload: Data([1, 3, 5]),
            projectMetadataVersion: 2)
    }
}

private struct StoreFixture: Sendable {
    let root: URL

    init() throws {
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBar-CostUsageStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    var databaseURL: URL {
        self.root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("cost-usage.sqlite", isDirectory: false)
    }

    func remove() {
        try? FileManager.default.removeItem(at: self.root)
    }
}

private final class SQLiteTestConnection: @unchecked Sendable {
    enum TestError: Error {
        case sqlite(Int32)
    }

    private var database: OpaquePointer?

    init(url: URL, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let result = sqlite3_open_v2(url.path, &self.database, flags, nil)
        guard result == SQLITE_OK else { throw TestError.sqlite(result) }
        sqlite3_busy_timeout(self.database, 5000)
    }

    deinit {
        if let database {
            sqlite3_close_v2(database)
        }
    }

    func execute(_ sql: String) throws {
        let result = sqlite3_exec(self.database, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw TestError.sqlite(result) }
    }

    func scalarInt(_ sql: String) throws -> Int64 {
        var statement: OpaquePointer?
        let prepare = sqlite3_prepare_v2(self.database, sql, -1, &statement, nil)
        guard prepare == SQLITE_OK, let statement else { throw TestError.sqlite(prepare) }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else { throw TestError.sqlite(result) }
        return sqlite3_column_int64(statement, 0)
    }

    static func execute(at url: URL, sql: String) throws {
        try Self(url: url).execute(sql)
    }

    static func indexNames(at url: URL) throws -> Set<String> {
        let connection = try Self(url: url, readOnly: true)
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(
            connection.database,
            "SELECT name FROM sqlite_master WHERE type = 'index'",
            -1,
            &statement,
            nil)
        guard result == SQLITE_OK, let statement else { throw TestError.sqlite(result) }
        defer { sqlite3_finalize(statement) }
        var names: Set<String> = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            if let value = sqlite3_column_text(statement, 0) {
                names.insert(String(cString: value))
            }
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw TestError.sqlite(step) }
        return names
    }
}
