import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageLazyScannerHistoryTests {
    @Test
    func `warm unchanged multi-file scan avoids raw history reads`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        _ = try Self.writeSession(
            in: env,
            day: day,
            filename: "first.jsonl",
            sessionID: "first-session",
            events: [.init(seconds: 1, input: 100, output: 10)])
        _ = try Self.writeSession(
            in: env,
            day: day,
            filename: "second.jsonl",
            sessionID: "second-session",
            events: [.init(seconds: 1, input: 200, output: 20)])
        let options = Self.options(for: env)

        let initial = try Self.scan(day: day, options: options)
        #expect(Self.totalTokens(initial) == 330)

        let probe = HistoryReadProbe(databaseURL: CostUsageStore(cacheRoot: env.cacheRoot).databaseURL)
        let warm = try Self.withReadObservation(probe) {
            try Self.scan(day: day, options: options)
        }

        #expect(Self.totalTokens(warm) == Self.totalTokens(initial))
        #expect(probe.snapshotTableReadCount == 0)
        #expect(probe.snapshotPaths.isEmpty)
    }

    @Test
    func `appending one file hydrates only its history and preserves the other file`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let firstURL = try Self.writeSession(
            in: env,
            day: day,
            filename: "first.jsonl",
            sessionID: "first-session",
            events: [.init(seconds: 1, input: 100, output: 10)])
        let secondURL = try Self.writeSession(
            in: env,
            day: day,
            filename: "second.jsonl",
            sessionID: "second-session",
            events: [.init(seconds: 1, input: 200, output: 20)])
        let firstPath = firstURL.standardizedFileURL.path
        let secondPath = secondURL.standardizedFileURL.path
        let options = Self.options(for: env)
        let initial = try Self.scan(day: day, options: options)
        #expect(Self.totalTokens(initial) == 330)

        let before = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
        let firstSnapshots = try #require(before.files[firstPath]?.codexTokenSnapshots)
        let untouchedSnapshots = try #require(before.files[secondPath]?.codexTokenSnapshots)
        #expect(firstSnapshots.count == 1)
        #expect(untouchedSnapshots.count == 1)

        try Self.append(
            .init(seconds: 2, input: 150, output: 25),
            to: firstURL,
            day: day,
            env: env)

        let probe = HistoryReadProbe(databaseURL: CostUsageStore(cacheRoot: env.cacheRoot).databaseURL)
        let updated = try Self.withReadObservation(probe) {
            try Self.scan(day: day, options: options)
        }

        #expect(Self.totalTokens(updated) == 395)
        #expect(probe.snapshotTableReadCount == 1)
        #expect(probe.snapshotPaths == [firstPath])

        let reopened = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
        let updatedSnapshots = try #require(reopened.files[firstPath]?.codexTokenSnapshots)
        #expect(updatedSnapshots.count == 2)
        #expect(updatedSnapshots.first == firstSnapshots.first)
        #expect(reopened.files[secondPath]?.codexTokenSnapshots == untouchedSnapshots)
    }

    @Test
    func `unavailable forced rescan keeps rows pending and retry completes`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let fileURL = try Self.writeSession(
            in: env,
            day: day,
            filename: "forced-rescan.jsonl",
            sessionID: "forced-session",
            events: [.init(seconds: 1, input: 100, output: 10)])
        let path = fileURL.standardizedFileURL.path
        let options = Self.options(for: env)
        let initial = try Self.scan(day: day, options: options)
        #expect(Self.totalTokens(initial) == 110)
        let initialSnapshots = try #require(
            CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
                .files[path]?.codexTokenSnapshots)
        let store = CostUsageStore(cacheRoot: env.cacheRoot)
        let initialUsageRows = await store.fetchUsageRows(path: path)
        #expect(!initialUsageRows.isEmpty)

        var forcedOptions = options
        forcedOptions.forceRescan = true
        let probe = HistoryReadProbe(databaseURL: store.databaseURL)
        let deferred = try Self.withUnavailableHydration(probe, paths: [path]) {
            try Self.scan(day: day, options: forcedOptions)
        }

        #expect(probe.injectedFailureCount == 1)
        #expect(probe.injectedPaths == [Set([path])])
        #expect(Self.totalTokens(deferred) == 110)
        let afterFailure = CostUsageStoreAccess.readWithoutTokenSnapshots(
            cacheRoot: env.cacheRoot,
            calendar: options.calendar)
        #expect(afterFailure.codexScanCatchUpPending == true)
        #expect(afterFailure.codexActiveLookbackState?.pendingFilePaths.contains(path) == true)
        #expect(CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
            .files[path]?.codexTokenSnapshots == initialSnapshots)
        #expect(await store.fetchUsageRows(path: path) == initialUsageRows)

        let retried = try Self.scan(day: day, options: options)
        #expect(Self.totalTokens(retried) == 110)
        let afterRetry = CostUsageStoreAccess.readWithoutTokenSnapshots(
            cacheRoot: env.cacheRoot,
            calendar: options.calendar)
        #expect(afterRetry.codexScanCatchUpPending == false)
        #expect(afterRetry.codexActiveLookbackState?.pendingFilePaths.contains(path) != true)
        #expect(CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
            .files[path]?.codexTokenSnapshots == initialSnapshots)
        // A successful full reparse can reorder JSON keys; retention failures above must preserve exact bytes.
        let retriedUsageRows = await store.fetchUsageRows(path: path)
        let decodedRetryRows = try Self.decodedUsageRows(retriedUsageRows)
        let decodedInitialRows = try Self.decodedUsageRows(initialUsageRows)
        #expect(decodedRetryRows == decodedInitialRows)
    }

    @Test
    func `unavailable alias hydration retains old path until retry reconciles it`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let oldURL = try Self.writeSession(
            in: env,
            day: day,
            filename: "before-rename.jsonl",
            sessionID: "renamed-session",
            events: [.init(seconds: 1, input: 100, output: 10)])
        let oldPath = oldURL.standardizedFileURL.path
        let options = Self.options(for: env)
        let initial = try Self.scan(day: day, options: options)
        #expect(Self.totalTokens(initial) == 110)
        let initialSnapshots = try #require(
            CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
                .files[oldPath]?.codexTokenSnapshots)
        let store = CostUsageStore(cacheRoot: env.cacheRoot)
        let initialUsageRows = await store.fetchUsageRows(path: oldPath)
        #expect(!initialUsageRows.isEmpty)

        let oldFileID = CostUsageScanner.codexFileMetadata(fileURL: oldURL).fileId
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent("after-rename.jsonl")
        try FileManager.default.moveItem(at: oldURL, to: newURL)
        let newPath = newURL.standardizedFileURL.path
        #expect(CostUsageScanner.codexFileMetadata(fileURL: newURL).fileId == oldFileID)

        var forcedOptions = options
        forcedOptions.forceRescan = true
        let probe = HistoryReadProbe(databaseURL: store.databaseURL)
        let deferred = try Self.withUnavailableHydration(probe, paths: [oldPath]) {
            try Self.scan(day: day, options: forcedOptions)
        }

        #expect(probe.injectedFailureCount == 1)
        #expect(probe.injectedPaths == [Set([oldPath])])
        #expect(Self.totalTokens(deferred) == 110)
        let afterFailure = CostUsageStoreAccess.readWithoutTokenSnapshots(
            cacheRoot: env.cacheRoot,
            calendar: options.calendar)
        #expect(afterFailure.codexScanCatchUpPending == true)
        #expect(CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
            .files[oldPath]?.codexTokenSnapshots == initialSnapshots)
        #expect(await store.fetchUsageRows(path: oldPath) == initialUsageRows)
        let failedNewPathRows = await store.fetchUsageRows(path: newPath)
        #expect(failedNewPathRows.isEmpty)

        let retried = try Self.scan(day: day, options: options)
        #expect(Self.totalTokens(retried) == 110)
        let reconciled = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
        #expect(reconciled.files[oldPath] == nil)
        #expect(reconciled.files[newPath]?.codexTokenSnapshots == initialSnapshots)
        let retriedNewPathRows = await store.fetchUsageRows(path: newPath)
        #expect(!retriedNewPathRows.isEmpty)
    }

    @Test(arguments: [false, true])
    func `deleted rename targets and aliases discharge deferred history without leaking rows`(
        useCatchUpWorkingSet: Bool) async throws
    {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let oldURL = try Self.writeSession(
            in: env,
            day: day,
            filename: "deleted-before-rename.jsonl",
            sessionID: "deleted-renamed-session",
            events: [.init(seconds: 1, input: 100, output: 10)])
        let options = Self.options(for: env)
        #expect(try Self.totalTokens(Self.scan(day: day, options: options)) == 110)
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent("deleted-after-rename.jsonl")
        try FileManager.default.moveItem(at: oldURL, to: newURL)
        let store = CostUsageStore(cacheRoot: env.cacheRoot)
        let probe = HistoryReadProbe(databaseURL: store.databaseURL)
        var forcedOptions = options
        forcedOptions.forceRescan = true
        let forcedReport = try Self.withUnavailableHydration(probe, paths: [oldURL.path]) {
            try Self.scan(day: day, options: forcedOptions)
        }
        #expect(Self.totalTokens(forcedReport) == 110)
        #expect(probe.injectedFailureCount == 1)
        #expect(CostUsageStoreAccess.readWithoutTokenSnapshots(
            cacheRoot: env.cacheRoot,
            calendar: options.calendar).codexScanCatchUpPending == true)

        try FileManager.default.removeItem(at: newURL)
        var retryOptions = options
        retryOptions.useCodexCatchUpWorkingSet = useCatchUpWorkingSet
        #expect(try Self.totalTokens(Self.scan(day: day, options: retryOptions)) == 0)
        let finished = CostUsageStoreAccess.readWithoutTokenSnapshots(
            cacheRoot: env.cacheRoot,
            calendar: options.calendar)
        #expect(finished.codexScanCatchUpPending == false)
        #expect(finished.codexHistoryHydrationRetries?.isEmpty != false)
        #expect(finished.files[oldURL.path] == nil)
        #expect(finished.files[newURL.path] == nil)
        #expect(await store.fetchFile(path: oldURL.path) == nil)
        #expect(await store.fetchFile(path: newURL.path) == nil)
        #expect(await store.fetchUsageRows(path: oldURL.path).isEmpty)
        #expect(await store.fetchTokenSnapshots(path: oldURL.path).isEmpty)
        #expect(await store.fetchFileDayAggregates(path: oldURL.path).isEmpty)
    }

    @Test(arguments: [false, true])
    func `malformed details with unavailable history preserve usage rows until retry`(
        emptyTokenHistory: Bool) async throws
    {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let fileURL = try Self.writeSession(
            in: env,
            day: day,
            filename: "malformed-details.jsonl",
            sessionID: "malformed-session",
            events: [.init(seconds: 1, input: 100, output: 10)])
        let path = fileURL.standardizedFileURL.path
        let options = Self.options(for: env)
        let initial = try Self.scan(day: day, options: options)
        #expect(Self.totalTokens(initial) == 110)
        let initialSnapshots = try #require(
            CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
                .files[path]?.codexTokenSnapshots)
        let store = CostUsageStore(cacheRoot: env.cacheRoot)
        let initialUsageRows = await store.fetchUsageRows(path: path)
        #expect(!initialUsageRows.isEmpty)

        if emptyTokenHistory {
            #expect(await store.replaceTokenSnapshots(path: path, snapshots: []))
        }
        let retainedTokenRows = await store.fetchTokenSnapshots(path: path)
        var malformedFile = try #require(await store.fetchFile(path: path))
        malformedFile.scanState.detailsPayload = Data("{malformed".utf8)
        #expect(await store.upsertFile(malformedFile))

        var forcedOptions = options
        forcedOptions.forceRescan = true
        let probe = HistoryReadProbe(databaseURL: store.databaseURL)
        let deferred = try Self.withUnavailableHydration(probe, paths: [path]) {
            try Self.scan(day: day, options: forcedOptions)
        }

        #expect(probe.injectedFailureCount == 1)
        #expect(probe.injectedPaths == [Set([path])])
        #expect(Self.totalTokens(deferred) == 110)
        #expect(CostUsageStoreAccess.readWithoutTokenSnapshots(
            cacheRoot: env.cacheRoot,
            calendar: options.calendar).codexScanCatchUpPending == true)
        #expect(await store.fetchFile(path: path) == malformedFile)
        #expect(await store.fetchTokenSnapshots(path: path) == retainedTokenRows)
        #expect(await store.fetchUsageRows(path: path) == initialUsageRows)

        let retried = try Self.scan(day: day, options: options)
        #expect(Self.totalTokens(retried) == 110)
        #expect(CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
            .files[path]?.codexTokenSnapshots == initialSnapshots)
        // A successful full reparse can reorder JSON keys; retention failures above must preserve exact bytes.
        let retriedUsageRows = await store.fetchUsageRows(path: path)
        let decodedRetryRows = try Self.decodedUsageRows(retriedUsageRows)
        let decodedInitialRows = try Self.decodedUsageRows(initialUsageRows)
        #expect(decodedRetryRows == decodedInitialRows)
    }

    @Test
    func `released receipt rejects history hydration without changing persisted rows`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let fileURL = try Self.writeSession(
            in: env,
            day: day,
            filename: "released-receipt.jsonl",
            sessionID: "released-session",
            events: [.init(seconds: 1, input: 100, output: 10)])
        let path = fileURL.standardizedFileURL.path
        let options = Self.options(for: env)
        _ = try Self.scan(day: day, options: options)

        let loaded = CostUsageStoreAccess.load(cacheRoot: env.cacheRoot, calendar: options.calendar)
        let storedRows = await loaded.store.fetchTokenSnapshots(path: path)
        #expect(!storedRows.isEmpty)
        let probe = HistoryReadProbe(databaseURL: CostUsageStore(cacheRoot: env.cacheRoot).databaseURL)
        loaded.release()
        let hydrator = CodexScanHistoryHydrator(storeLoad: loaded, checkCancellation: nil)
        let hydration = try Self.withReadObservation(probe) {
            try hydrator.hydrate(paths: [path])
        }
        #expect(hydration == .stale)

        #expect(probe.snapshotTableReadCount == 0)
        #expect(probe.snapshotPaths.isEmpty)
        #expect(loaded.cache.files[path]?.codexTokenSnapshots == nil)
        #expect(await loaded.store.fetchTokenSnapshots(path: path) == storedRows)
    }

    @Test
    func `cancellation after lazy history hydration leaves persisted rows unchanged`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let fileURL = try Self.writeSession(
            in: env,
            day: day,
            filename: "cancel-hydration.jsonl",
            sessionID: "cancel-session",
            events: [.init(seconds: 1, input: 100, output: 10)])
        let path = fileURL.standardizedFileURL.path
        let options = Self.options(for: env)
        let initial = try Self.scan(day: day, options: options)
        #expect(Self.totalTokens(initial) == 110)
        let storedSnapshots = try #require(
            CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
                .files[path]?.codexTokenSnapshots)
        let store = CostUsageStore(cacheRoot: env.cacheRoot)
        let storedUsageRows = await store.fetchUsageRows(path: path)
        #expect(!storedUsageRows.isEmpty)

        try Self.append(
            .init(seconds: 2, input: 150, output: 25),
            to: fileURL,
            day: day,
            env: env)
        let probe = HistoryReadProbe(databaseURL: store.databaseURL)
        try Self.withReadObservation(probe) {
            #expect(throws: CancellationError.self) {
                try CostUsageScanner.loadDailyReportCancellable(
                    provider: .codex,
                    since: day,
                    until: day,
                    now: day.addingTimeInterval(60),
                    options: options,
                    checkCancellation: {
                        if probe.didRead(path: path) { throw CancellationError() }
                    })
            }
        }

        #expect(probe.snapshotTableReadCount == 1)
        #expect(probe.snapshotPaths == [path])
        #expect(CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: options.calendar)
            .files[path]?.codexTokenSnapshots == storedSnapshots)
        #expect(await store.fetchUsageRows(path: path) == storedUsageRows)
    }

    @Test
    func `committing an older scan preserves newer and unobserved retry requests`() {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("retry-registry-\(UUID().uuidString).sqlite")
        let target = "/synthetic/target.jsonl"
        let otherTarget = "/synthetic/other.jsonl"
        let first = CodexHistoryHydrationRetry(retainedPaths: [target], forceFullRescan: false)
        let captured = CodexScanHistoryHydrationRetryRegistry.retain(
            databaseURL: databaseURL,
            retries: [target: first])
        let newer = CodexHistoryHydrationRetry(
            retainedPaths: [target, "/synthetic/renamed-alias.jsonl"],
            forceFullRescan: true)
        let latest = CodexScanHistoryHydrationRetryRegistry.retain(
            databaseURL: databaseURL,
            retries: [target: newer, otherTarget: first])
        defer { CodexScanHistoryHydrationRetryRegistry.clear(databaseURL: databaseURL, committed: latest) }

        CodexScanHistoryHydrationRetryRegistry.clear(databaseURL: databaseURL, committed: captured)
        var cache = CostUsageCache()
        let pending = CodexScanHistoryHydrationRetryRegistry.mergePending(databaseURL: databaseURL, into: &cache)
        #expect(cache.codexHistoryHydrationRetries?[target] == newer)
        #expect(cache.codexHistoryHydrationRetries?[otherTarget] == first)
        #expect(cache.codexScanCatchUpPending == true)

        CodexScanHistoryHydrationRetryRegistry.clear(databaseURL: databaseURL, committed: pending)
        var cleared = CostUsageCache()
        _ = CodexScanHistoryHydrationRetryRegistry.mergePending(databaseURL: databaseURL, into: &cleared)
        #expect(cleared.codexHistoryHydrationRetries == nil)
    }

    private static let model = "openai/gpt-5.5"

    private static func options(
        for env: CostUsageTestEnvironment,
        forceRescan: Bool = false) -> CostUsageScanner.Options
    {
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("synthetic-codex-trace.sqlite"),
            forceRescan: forceRescan)
        options.refreshMinIntervalSeconds = 0
        return options
    }

    private static func scan(day: Date, options: CostUsageScanner.Options) throws -> CostUsageDailyReport {
        try CostUsageScanner.loadDailyReportCancellable(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(60),
            options: options,
            checkCancellation: nil)
    }

    private struct DecodedUsageRow: Equatable {
        let path: String
        let rowIndex: Int
        let row: CostUsageScanner.CodexUsageRow
    }

    private static func decodedUsageRows(_ rows: [CostUsageStoreUsageRow]) throws -> [DecodedUsageRow] {
        try rows.map {
            try DecodedUsageRow(
                path: $0.path,
                rowIndex: $0.rowIndex,
                row: JSONDecoder().decode(CostUsageScanner.CodexUsageRow.self, from: $0.payload))
        }
    }

    private static func totalTokens(_ report: CostUsageDailyReport) -> Int {
        report.data.reduce(0) { total, day in
            #expect(day.totalTokens != nil, "Synthetic history fixtures must retain known token totals")
            return total + (day.totalTokens ?? 0)
        }
    }

    private static func writeSession(
        in env: CostUsageTestEnvironment,
        day: Date,
        filename: String,
        sessionID: String,
        events: [TokenEvent]) throws -> URL
    {
        var objects: [Any] = [
            ["type": "session_meta", "payload": ["id": sessionID]],
            [
                "type": "turn_context",
                "timestamp": env.isoString(for: day),
                "payload": ["model": self.model],
            ],
        ]
        objects.append(contentsOf: events.map { self.tokenCount($0, environment: env, baseDay: day) })
        return try env.writeCodexSessionFile(day: day, filename: filename, contents: env.jsonl(objects))
    }

    private static func append(
        _ event: TokenEvent,
        to fileURL: URL,
        day: Date,
        env: CostUsageTestEnvironment) throws
    {
        let line = try env.jsonl([self.tokenCount(event, environment: env, baseDay: day)])
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
    }

    private static func tokenCount(
        _ event: TokenEvent,
        environment env: CostUsageTestEnvironment,
        baseDay: Date) -> [String: Any]
    {
        let timestamp = env.isoString(for: baseDay.addingTimeInterval(TimeInterval(event.seconds)))
        return [
            "type": "event_msg",
            "timestamp": timestamp,
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": [
                        "input_tokens": event.input,
                        "output_tokens": event.output,
                    ],
                    "model": self.model,
                ],
            ],
        ]
    }

    private static func withReadObservation<T>(
        _ probe: HistoryReadProbe,
        operation: () throws -> T) rethrows -> T
    {
        var hooks = CostUsageStoreTestHooks.current
        hooks.tokenSnapshotsRead = { storeURL in
            probe.recordSnapshotTableRead(storeURL: storeURL)
        }
        hooks.tokenSnapshotPathRead = { storeURL, path in
            probe.recordSnapshotPathRead(storeURL: storeURL, path: path)
        }
        return try CostUsageStoreTestHooks.$current.withValue(hooks, operation: operation)
    }

    private static func withUnavailableHydration<T>(
        _ probe: HistoryReadProbe,
        paths: Set<String>,
        operation: () throws -> T) rethrows -> T
    {
        var hooks = CostUsageStoreTestHooks.current
        hooks.codexTokenSnapshotHydrationFailure = { storeURL, unloadedPaths in
            guard probe.matches(storeURL), unloadedPaths == paths else { return false }
            probe.recordHydrationFailure(paths: unloadedPaths)
            return true
        }
        return try CostUsageStoreTestHooks.$current.withValue(hooks, operation: operation)
    }

    private struct TokenEvent {
        let seconds: Int
        let input: Int
        let output: Int
    }
}

private final class HistoryReadProbe: @unchecked Sendable {
    private let databasePath: String
    private let lock = NSLock()
    private var tableReads = 0
    private var paths: [String?] = []
    private var failurePaths: [Set<String>] = []

    init(databaseURL: URL) {
        self.databasePath = databaseURL.standardizedFileURL.path
    }

    var snapshotTableReadCount: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.tableReads
    }

    var snapshotPaths: [String?] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.paths
    }

    var injectedFailureCount: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.failurePaths.count
    }

    var injectedPaths: [Set<String>] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.failurePaths
    }

    func matches(_ storeURL: URL) -> Bool {
        storeURL.standardizedFileURL.path == self.databasePath
    }

    func recordSnapshotTableRead(storeURL: URL) {
        guard self.matches(storeURL) else { return }
        self.lock.lock()
        defer { self.lock.unlock() }
        self.tableReads += 1
    }

    func recordSnapshotPathRead(storeURL: URL, path: String?) {
        guard self.matches(storeURL) else { return }
        self.lock.lock()
        defer { self.lock.unlock() }
        self.paths.append(path)
    }

    func recordHydrationFailure(paths: Set<String>) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.failurePaths.append(paths)
    }

    func didRead(path: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.paths.contains(path)
    }
}
