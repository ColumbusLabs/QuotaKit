import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageStoreReadPerformanceTests {
    @Test
    func `full cache and transient reports stream native rows without losing their decoded ownership`() throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let rows = [Self.row(model: "gpt-5.5", input: 10, eventIndex: 0),
                    Self.row(model: "gpt-5.5", input: 30, eventIndex: 1)]
        let path = "/sessions/streamed-full-cache.jsonl"
        var cache = Self.seededCache()
        var usage = CostUsageFileUsage(mtimeUnixMs: 1, size: 64, days: ["2026-08-01": ["gpt-5.5": [40, 0, 20]]])
        usage.sessionId = "streamed-full-cache"
        usage.codexRows = rows
        cache.files[path] = usage
        cache.days = usage.days
        let store = CostUsageStore(cacheRoot: fixture.root)
        #expect(!store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01")).catchUpRequired)
        #if DEBUG
        let visits = LockedReadPerformanceValues<StreamedUsageRowVisit>()
        var hooks = CostUsageStoreTestHooks.current
        hooks.codexStreamedUsageRow = { path, rowIndex, payloadBytes, decoded in
            visits.append(StreamedUsageRowVisit(path: path, rowIndex: rowIndex, payloadBytes: payloadBytes, decoded: decoded))
        }
        #endif
        let read = {
            let full = store.syncLoadCodexCache(calendar: calendar)
            let report = CostUsageStoreAccess.readView(cacheRoot: fixture.root, calendar: calendar, purpose: .report)
            return (full, report)
        }
        #if DEBUG
        let (full, view) = CostUsageStoreTestHooks.$current.withValue(hooks) { read() }
        #else
        let (full, view) = read()
        #endif
        #expect(full.files[path]?.codexRows == rows)
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let range = CostUsageScanner.CostUsageDayRange(since: day, until: day, calendar: calendar)
        #expect(view.dailyReport(range: range, cacheRoot: fixture.root).summary?.totalTokens == 60)
        #expect(view.sessions(range: range, cacheRoot: fixture.root, roots: [URL(fileURLWithPath: "/sessions")])
            .first?.totalTokens == 60)
        #if DEBUG
        #expect(visits.value.map(\.rowIndex) == [0, 1, 0, 1])
        #expect(visits.value.allSatisfy(\.decoded))
        #endif
    }

    @Test
    func `warm activity and status reuse the stamped activity view`() throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let writer = CostUsageStore(cacheRoot: fixture.root)
        let cache = Self.seededCache()
        let saved = writer.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!saved.catchUpRequired)

        #if DEBUG
        let snapshotPurposes = LockedReadPerformanceValues<CostUsageStoreReadPurpose>()
        let decodePurposes = LockedReadPerformanceValues<CostUsageStoreReadPurpose>()
        let integrityChecks = LockedReadPerformanceCounter()
        let usageRowReads = LockedReadPerformanceCounter()
        var hooks = CostUsageStoreTestHooks.current
        hooks.codexReadViewIntegrityCheck = { url in
            if url == writer.databaseURL { integrityChecks.increment() }
        }
        hooks.codexReadViewSnapshot = { url, purpose in
            if url == writer.databaseURL { snapshotPurposes.append(purpose) }
        }
        hooks.codexReadViewDecode = { url, purpose in
            if url == writer.databaseURL { decodePurposes.append(purpose) }
        }
        hooks.codexReadViewUsageRows = { url in
            if url == writer.databaseURL { usageRowReads.increment() }
        }
        #endif

        let readViews = {
            let activity = CostUsageStoreAccess.readView(
                cacheRoot: fixture.root,
                calendar: calendar,
                purpose: .activity)
            let status = CostUsageStoreAccess.readView(
                cacheRoot: fixture.root,
                calendar: calendar,
                purpose: .status)
            return (activity, status)
        }
        #if DEBUG
        let (activity, status) = CostUsageStoreTestHooks.$current.withValue(hooks) {
            readViews()
        }
        #else
        let (activity, status) = readViews()
        #endif

        #expect(activity.days == status.days)
        #expect(activity.days["2026-08-01"]?["gpt-5.5"] == [10, 0, 3])
        #if DEBUG
        #expect(snapshotPurposes.value == [.activity])
        #expect(decodePurposes.value == [.activity])
        #expect(integrityChecks.value == 1)
        #expect(usageRowReads.value == 0)
        #endif
    }

    @Test
    func `report reads stay transient and do not replace the activity view`() throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let writer = CostUsageStore(cacheRoot: fixture.root)
        let saved = writer.syncSaveCodexCache(
            Self.seededCache(),
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!saved.catchUpRequired)

        #if DEBUG
        let snapshotPurposes = LockedReadPerformanceValues<CostUsageStoreReadPurpose>()
        let decodePurposes = LockedReadPerformanceValues<CostUsageStoreReadPurpose>()
        let usageRowReads = LockedReadPerformanceCounter()
        var hooks = CostUsageStoreTestHooks.current
        hooks.codexReadViewSnapshot = { url, purpose in
            if url == writer.databaseURL { snapshotPurposes.append(purpose) }
        }
        hooks.codexReadViewDecode = { url, purpose in
            if url == writer.databaseURL { decodePurposes.append(purpose) }
        }
        hooks.codexReadViewUsageRows = { url in
            if url == writer.databaseURL { usageRowReads.increment() }
        }
        #endif

        let readViews = {
            let activity = CostUsageStoreAccess.readView(
                cacheRoot: fixture.root,
                calendar: calendar,
                purpose: .activity)
            _ = CostUsageStoreAccess.readView(
                cacheRoot: fixture.root,
                calendar: calendar,
                purpose: .report)
            let status = CostUsageStoreAccess.readView(
                cacheRoot: fixture.root,
                calendar: calendar,
                purpose: .status)
            return (activity, status)
        }
        #if DEBUG
        let (activity, status) = CostUsageStoreTestHooks.$current.withValue(hooks) {
            readViews()
        }
        #else
        let (activity, status) = readViews()
        #endif

        #expect(activity.days == status.days)
        #if DEBUG
        #expect(snapshotPurposes.value == [.activity, .report])
        #expect(decodePurposes.value == [.activity, .report])
        #expect(usageRowReads.value == 1)
        #endif
    }

    @Test
    func `Codex cache decode constructs one decoder per pass`() async throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let path = "/sessions/read-view-decoder.jsonl"
        var cache = Self.seededCache()
        var usage = CostUsageFileUsage(mtimeUnixMs: 1, size: 64, days: [:])
        usage.codexRows = [
            Self.row(model: "gpt-5.5", input: 10, eventIndex: 0),
            Self.row(model: "gpt-5.5", input: 20, eventIndex: 1),
        ]
        cache.files[path] = usage
        let store = CostUsageStore(cacheRoot: fixture.root)
        let saved = store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!saved.catchUpRequired)

        let snapshot = await store.readSnapshot()
        var decoderConstructions = 0
        let decoder = CountingReadPerformanceDecoder()
        let decoded = CostUsageStore.decodeCodexCache(from: snapshot, makeDecoder: {
            decoderConstructions += 1
            return decoder
        })

        #expect(decoderConstructions == 1)
        for file in snapshot.files {
            let payload = try #require(file.scanState.detailsPayload)
            #expect(decoder.count(for: payload) == 1)
        }
        #expect(decoded.days == cache.days)
        #expect(decoded.files[path]?.codexRows?.map(\.input) == [10, 20])
    }

    @Test(arguments: [false, true], [false, true])
    func `one details decode preserves complete legacy malformed and lazy restoration`(
        manifestOnly: Bool,
        preserveMalformed: Bool) async throws
    {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        let snapshot = try await Self.detailsSnapshot(root: fixture.root)
        let decoder = CountingReadPerformanceDecoder()
        let paths: Set<String>? = manifestOnly ? [] : nil
        let decoded = CostUsageStore.decodeCodexCache(
            from: snapshot,
            hydratingPaths: paths,
            preserveMalformedFiles: preserveMalformed,
            makeDecoder: { decoder })

        for file in snapshot.files {
            if let payload = file.scanState.detailsPayload {
                #expect(decoder.count(for: payload) == 1)
            }
        }
        let malformedPaths: Set = ["/sessions/malformed.jsonl", "/sessions/missing.jsonl"]
        #expect(decoded.codexMalformedDetailsPaths == malformedPaths)
        #expect(decoded.days == ["2026-08-01": ["gpt-5.5": [40, 0, 20]]])
        let typed = try #require(decoded.files["/sessions/typed.jsonl"])
        #expect(typed.codexTypedResponseIdentity == true)
        #expect(typed.projectPath == "/synthetic/project")
        #expect(typed.codexParserRevision == CostUsageFileUsage.currentCodexParserRevision)
        #expect(typed.codexCostNanos?["2026-08-01"]?["gpt-5.5"] == 123_000_000)
        let legacy = try #require(decoded.files["/sessions/legacy.jsonl"])
        #expect(legacy.codexHasTypedResponseIdentity == nil)
        #expect(legacy.codexParserRevision == nil)
        if manifestOnly {
            #expect(typed.codexRows == nil)
            #expect(typed.codexTokenSnapshots == nil)
            #expect(typed.codexRequestLedgerState == nil)
            #expect(legacy.codexRows == nil)
        } else {
            #expect(typed.codexRows?.first?.responseID == "saved-response")
            #expect(typed.codexRows?.first?.knownCostNanos == 123_000_000)
            #expect(typed.codexRows?.first?.day == "2026-08-01")
            #expect(typed.codexRows?.first?.pricingMode == "priority")
            #expect(typed.codexRows?.first?.requestMirrorKeys == ["saved-mirror"])
            let expectedSnapshots = [CostUsageCodexTokenSnapshot(
                timestamp: "2026-08-01T12:00:00Z",
                last: nil,
                total: CostUsageCodexTotals(input: 10, cached: 0, output: 5),
                endOffset: 64)]
            #expect(typed.codexTokenSnapshots == expectedSnapshots)
            let expectedLedger = CostUsageScanner.CodexRequestLedgerState(
                responseIDs: ["saved-response"],
                mirroredResponses: ["saved-mirror": "saved-response"])
            #expect(typed.codexRequestLedgerState == expectedLedger)
            #expect(legacy.codexRows?.first?.responseID == nil)
        }
        for path in malformedPaths {
            if manifestOnly || preserveMalformed {
                let usage = try #require(decoded.files[path])
                #expect(usage.codexHasTypedResponseIdentity == nil)
                if manifestOnly {
                    #expect(usage.codexRows == nil)
                    #expect(usage.codexTokenSnapshots == nil)
                } else {
                    #expect(usage.codexRows?.count == 1)
                    #expect(usage.codexTokenSnapshots?.count == 1)
                }
            } else {
                #expect(decoded.files[path] == nil)
            }
        }
        let persistence = CostUsageStore.CodexPersistenceState(
            snapshot: snapshot,
            malformedDetailsPaths: decoded.codexMalformedDetailsPaths)
        #expect(persistence.malformedDetailsPaths == malformedPaths)
        #expect(persistence.files.map(\.scanState.detailsPayload) == snapshot.files.map(\.scanState.detailsPayload))
    }

    @Test(arguments: [false, true])
    func `duplicate paths retain path wide malformed token authority`(invalidFirst: Bool) async throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        var snapshot = try await Self.detailsSnapshot(root: fixture.root)
        var valid = try #require(snapshot.files.first { $0.path == "/sessions/legacy.jsonl" })
        valid.scanState.detailsPayload = try Self.detailsPayload(valid, removing: [], parserRevision: true)
        var invalid = valid
        invalid.scanState.detailsPayload = Data("invalid duplicate".utf8)
        snapshot.files = invalidFirst ? [invalid, valid] : [valid, invalid]
        snapshot.tokenSnapshots = []
        snapshot.tokenSnapshotCounts = [valid.path: 0]
        snapshot.tokenSnapshotsLoaded = false

        let decoder = CountingReadPerformanceDecoder()
        let decoded = CostUsageStore.decodeCodexCache(
            from: snapshot,
            tokenSnapshotsLoaded: false,
            makeDecoder: { decoder })
        let usage = try #require(decoded.files[valid.path])
        #expect(decoded.codexMalformedDetailsPaths == [valid.path])
        #expect(usage.codexRows?.first?.input == 10)
        #expect(usage.codexTokenSnapshots == nil)
        #expect(usage.codexHasTypedResponseIdentity == nil)
        // Duplicate records alone keep the original path-wide validation fallback.
        let validPayload = try #require(valid.scanState.detailsPayload)
        let invalidPayload = try #require(invalid.scanState.detailsPayload)
        #expect(decoder.count(for: validPayload) == 2)
        #expect(decoder.count(for: invalidPayload) == 2)
        let compact = CostUsageStore.decodeCodexCache(
            from: snapshot,
            hydratingPaths: [],
            tokenSnapshotsLoaded: false)
        #expect(compact.files[valid.path]?.codexRows == nil)
        #expect(compact.files[valid.path]?.codexTokenSnapshots == nil)
        #expect(compact.files[valid.path]?.codexHasTypedResponseIdentity == nil)
        #expect(compact.codexMalformedDetailsPaths == [valid.path])
    }

    @Test
    func `supplied empty malformed set remains authoritative for persistence`() async throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        let snapshot = try await Self.detailsSnapshot(root: fixture.root)
        let defaultPersistence = CostUsageStore.CodexPersistenceState(snapshot: snapshot)
        #expect(defaultPersistence.malformedDetailsPaths == ["/sessions/malformed.jsonl", "/sessions/missing.jsonl"])
        let supplied = CostUsageStore.CodexPersistenceState(snapshot: snapshot, malformedDetailsPaths: [])
        #expect(supplied.malformedDetailsPaths.isEmpty)
    }

    @Test
    func `malformed details do not certify omitted empty token history`() async throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        var snapshot = try await Self.detailsSnapshot(root: fixture.root)
        snapshot.tokenSnapshots = []
        snapshot.tokenSnapshotsLoaded = false
        snapshot.tokenSnapshotCounts = Dictionary(uniqueKeysWithValues: snapshot.files.map { ($0.path, 0) })
        let decoded = CostUsageStore.decodeCodexCache(
            from: snapshot,
            tokenSnapshotsLoaded: false,
            preserveMalformedFiles: true)
        #expect(decoded.files["/sessions/typed.jsonl"]?.codexTokenSnapshots?.isEmpty == true)
        #expect(decoded.files["/sessions/malformed.jsonl"]?.codexTokenSnapshots == nil)
        #expect(decoded.files["/sessions/missing.jsonl"]?.codexTokenSnapshots == nil)
        let malformedPaths: Set = ["/sessions/malformed.jsonl", "/sessions/missing.jsonl"]
        let hydrated = CostUsageStore.decodeCodexCache(
            from: snapshot,
            tokenSnapshotsLoaded: false,
            explicitlyLoadedTokenSnapshotPaths: malformedPaths,
            preserveMalformedFiles: true)
        for path in malformedPaths {
            #expect(hydrated.files[path]?.codexTokenSnapshots?.isEmpty == true)
        }
    }

    @Test
    func `external database commits invalidate retained activity`() throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let writer = CostUsageStore(cacheRoot: fixture.root)
        var cache = Self.seededCache()
        let saved = writer.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!saved.catchUpRequired)

        #if DEBUG
        let snapshots = LockedReadPerformanceCounter()
        let decodes = LockedReadPerformanceCounter()
        var hooks = CostUsageStoreTestHooks.current
        hooks.codexReadViewSnapshot = { url, _ in
            if url == writer.databaseURL { snapshots.increment() }
        }
        hooks.codexReadViewDecode = { url, _ in
            if url == writer.databaseURL { decodes.increment() }
        }
        #endif

        let refreshAfterExternalCommit = {
            _ = CostUsageStoreAccess.readView(
                cacheRoot: fixture.root,
                calendar: calendar,
                purpose: .activity)
            cache.days["2026-08-01"]?["gpt-5.5"] = [20, 0, 6]
            let updated = writer.syncSaveCodexCache(
                cache,
                calendar: calendar,
                requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
            let refreshed = CostUsageStoreAccess.readView(
                cacheRoot: fixture.root,
                calendar: calendar,
                purpose: .activity)
            return (refreshed, updated.catchUpRequired)
        }
        #if DEBUG
        let (refreshed, catchUpRequired) = CostUsageStoreTestHooks.$current.withValue(hooks) {
            refreshAfterExternalCommit()
        }
        #else
        let (refreshed, catchUpRequired) = refreshAfterExternalCommit()
        #endif
        #expect(!catchUpRequired)
        #expect(refreshed.days["2026-08-01"]?["gpt-5.5"] == [20, 0, 6])
        #if DEBUG
        #expect(snapshots.value == 2)
        #expect(decodes.value == 2)
        #endif
    }

    @Test
    func `read view use preserves the scanner save receipt`() throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let store = CostUsageStore(cacheRoot: fixture.root)
        let saved = store.syncSaveCodexCache(
            Self.seededCache(),
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!saved.catchUpRequired)

        let scan = store.syncLoadCodexScan(calendar: calendar)
        defer { scan.release() }
        _ = store.syncLoadCodexReadView(calendar: calendar, purpose: .activity)
        var updated = scan.cache
        updated.files["/sessions/read-view-receipt.jsonl"] = CostUsageFileUsage(
            mtimeUnixMs: 1,
            size: 0,
            days: [:])
        let result = store.syncSaveCodexCache(
            updated,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
            expectedScanStamp: scan.scanStamp,
            receipt: scan.receipt)

        #expect(!result.catchUpRequired)
    }

    @Test
    func `scanner streams physical usage rows with the eager fallback semantics`() async throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let store = CostUsageStore(cacheRoot: fixture.root)
        let partialPath = "/sessions/a-partial.jsonl"
        let fallbackPath = "/sessions/z-malformed.jsonl"
        let first = Self.row(model: "gpt-5.5", input: 10, eventIndex: 0)
        let second = Self.row(model: "gpt-5.5", input: 20, eventIndex: 1)
        var cache = Self.seededCache()
        var partial = CostUsageFileUsage(mtimeUnixMs: 1, size: 64, days: [
            "2026-08-01": ["gpt-5.5": [30, 0, 6]],
        ])
        partial.codexRows = [first, second]
        cache.files[partialPath] = partial
        var fallback = CostUsageFileUsage(mtimeUnixMs: 2, size: 32, days: [
            "2026-08-01": ["gpt-5.6-sol": [7, 0, 2]],
        ])
        fallback.codexRows = [Self.row(model: "gpt-5.6-sol", input: 7, eventIndex: 0)]
        cache.files[fallbackPath] = fallback
        // Persist the files before marking the partial path as retained by a hydration retry.
        // Full saves preserve retained paths without creating or rewriting their file rows.
        let seeded = store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!seeded.catchUpRequired)

        let retry = CodexHistoryHydrationRetry(retainedPaths: [partialPath], forceFullRescan: true)
        cache.codexHistoryHydrationRetries = [partialPath: retry]
        let saved = store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!saved.catchUpRequired)

        #expect(await store.replaceUsageRows(path: partialPath, rows: [
            Self.persistedRow(path: partialPath, index: 0, row: first),
            CostUsageStoreUsageRow(path: partialPath, rowIndex: 1, payload: Data("invalid-json".utf8)),
            Self.persistedRow(path: partialPath, index: 2, row: second),
        ]))
        #expect(await store.replaceUsageRows(path: fallbackPath, rows: [
            CostUsageStoreUsageRow(path: fallbackPath, rowIndex: 0, payload: Data("bad-row-a".utf8)),
            CostUsageStoreUsageRow(path: fallbackPath, rowIndex: 1, payload: Data("bad-row-b".utf8)),
        ]))

        let eager = await store.readSnapshot()
        let expected = CostUsageStore.decodeCodexCache(
            from: eager,
            preserveMalformedFiles: true)
        #if DEBUG
        let visits = LockedReadPerformanceValues<StreamedUsageRowVisit>()
        var hooks = CostUsageStoreTestHooks.current
        hooks.codexStreamedUsageRow = { path, rowIndex, payloadBytes, decoded in
            visits.append(StreamedUsageRowVisit(
                path: path,
                rowIndex: rowIndex,
                payloadBytes: payloadBytes,
                decoded: decoded))
        }
        #endif
        let loadScan = { store.syncLoadCodexScan(calendar: calendar) }
        #if DEBUG
        let loaded = CostUsageStoreTestHooks.$current.withValue(hooks) { loadScan() }
        #else
        let loaded = loadScan()
        #endif
        defer { loaded.release() }

        #expect(loaded.cache.files[partialPath]?.codexRows == expected.files[partialPath]?.codexRows)
        #expect(loaded.cache.files[fallbackPath]?.codexRows == expected.files[fallbackPath]?.codexRows)
        #expect(loaded.cache.codexHistoryHydrationRetries == cache.codexHistoryHydrationRetries)
        #if DEBUG
        #expect(visits.value.map { "\($0.path)#\($0.rowIndex)" } == [
            "\(partialPath)#0",
            "\(partialPath)#1",
            "\(partialPath)#2",
            "\(fallbackPath)#0",
            "\(fallbackPath)#1",
        ])
        #expect(visits.value.map(\.decoded) == [true, false, true, false, false])
        #expect(await store.fetchDetailCounts(path: partialPath).rowCount == 3)
        #expect(await store.fetchDetailCounts(path: fallbackPath).rowCount == 2)
        #endif
    }

    private static func detailsSnapshot(root: URL) async throws -> CostUsageStoreSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var cache = Self.seededCache()
        cache.days = ["2026-08-01": ["gpt-5.5": [40, 0, 20]]]
        for name in ["typed", "legacy", "malformed", "missing"] {
            var row = Self.row(model: "gpt-5.5", input: 10, eventIndex: 0)
            row.knownCostNanos = 123_000_000
            row.pricingMode = "priority"
            if name == "typed" {
                row = CostUsageScanner.CodexUsageRow(
                    day: row.day,
                    model: row.model,
                    turnID: row.turnID,
                    eventIndex: row.eventIndex,
                    input: row.input,
                    cached: row.cached,
                    output: row.output,
                    knownCostNanos: row.knownCostNanos,
                    pricingModel: row.pricingModel,
                    pricingMode: row.pricingMode,
                    responseID: "saved-response",
                    requestMirrorKeys: ["saved-mirror"])
            }
            var usage = CostUsageScanner.makeFileUsage(
                mtimeUnixMs: 1,
                size: 64,
                days: ["2026-08-01": ["gpt-5.5": [10, 0, 5]]],
                parsedBytes: 64,
                projectPath: "/synthetic/project",
                codexRows: [row],
                codexTokenSnapshots: [CostUsageCodexTokenSnapshot(
                    timestamp: "2026-08-01T12:00:00Z",
                    last: nil,
                    total: CostUsageCodexTotals(input: 10, cached: 0, output: 5),
                    endOffset: 64)],
                codexScanComplete: true)
            if name == "typed" {
                usage.codexRequestLedgerState = .init(
                    responseIDs: ["saved-response"],
                    mirroredResponses: ["saved-mirror": "saved-response"])
            }
            cache.files["/sessions/\(name).jsonl"] = usage
        }
        let store = CostUsageStore(cacheRoot: root)
        #expect(!store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01")).catchUpRequired)
        var snapshot = await store.readSnapshot()
        for index in snapshot.files.indices {
            switch snapshot.files[index].path {
            case "/sessions/legacy.jsonl":
                snapshot.files[index].scanState.detailsPayload = try Self.detailsPayload(
                    snapshot.files[index], removing: ["parserRevision", "requestLedgerState"])
            case "/sessions/malformed.jsonl":
                snapshot.files[index].scanState.detailsPayload = Data("malformed details".utf8)
            case "/sessions/missing.jsonl":
                snapshot.files[index].scanState.detailsPayload = nil
            default:
                break
            }
        }
        return snapshot
    }

    private static func detailsPayload(
        _ file: CostUsageStoreFile,
        removing keys: [String],
        parserRevision: Bool = false) throws -> Data
    {
        let payload = try #require(file.scanState.detailsPayload)
        var object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        for key in keys {
            object.removeValue(forKey: key)
        }
        if parserRevision { object["parserRevision"] = CostUsageFileUsage.currentCodexParserRevision }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func seededCache() -> CostUsageCache {
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.roots = [:]
        cache.days = ["2026-08-01": ["gpt-5.5": [10, 0, 3]]]
        return cache
    }

    private static func row(model: String, input: Int, eventIndex: Int) -> CostUsageScanner.CodexUsageRow {
        CostUsageScanner.CodexUsageRow(
            day: "2026-08-01",
            model: model,
            turnID: "turn-\(eventIndex)",
            eventIndex: eventIndex,
            input: input,
            cached: 0,
            output: input / 2,
            reasoning: 0,
            knownCostNanos: nil,
            unpricedTokens: nil,
            pricingModel: model,
            pricingMode: "standard")
    }

    private static func persistedRow(
        path: String,
        index: Int,
        row: CostUsageScanner.CodexUsageRow) -> CostUsageStoreUsageRow
    {
        CostUsageStoreUsageRow(
            path: path,
            rowIndex: index,
            payload: (try? JSONEncoder().encode(row)) ?? Data())
    }
}

private struct ReadPerformanceFixture: Sendable {
    let root: URL

    init() throws {
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBar-CostUsageReadPerformance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: self.root)
    }
}

private final class LockedReadPerformanceCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.count += 1
    }

    var value: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.count
    }
}

private final class LockedReadPerformanceValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    func append(_ value: Value) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.storage.append(value)
    }

    var value: [Value] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.storage
    }
}

private struct StreamedUsageRowVisit: Sendable {
    let path: String
    let rowIndex: Int
    let payloadBytes: Int
    let decoded: Bool
}

private final class CountingReadPerformanceDecoder: JSONDecoder, @unchecked Sendable {
    private var counts: [Data: Int] = [:]

    override func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        self.counts[data, default: 0] += 1
        return try super.decode(type, from: data)
    }

    func count(for data: Data) -> Int {
        self.counts[data] ?? 0
    }
}
