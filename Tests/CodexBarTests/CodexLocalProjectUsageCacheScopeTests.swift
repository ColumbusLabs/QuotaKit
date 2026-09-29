import Foundation
import Testing
@testable import CodexBarCore

struct CodexLocalProjectUsageCacheScopeTests {
    @Test(arguments: [false, true])
    func `failed raw cache read preserves the last complete workspace history`(forceRefresh: Bool) throws {
        let fixture = try CacheScopeFixture()
        defer { fixture.env.cleanup() }
        let options = CodexLocalProjectUsageIndexer.Options(
            scannerOptions: fixture.scannerOptions,
            rawCacheReadOverrideForTesting: { _, _ in CostUsageCache() })

        #expect(throws: CodexLocalProjectUsageIndexer.IndexError.cacheScopeMismatch) {
            try CodexLocalProjectUsageIndexer.loadSnapshot(
                now: fixture.now,
                historyDays: 1,
                forceRefresh: forceRefresh,
                options: options)
        }

        #expect(try fixture.sidecar.usageCache(roots: fixture.baseline.rootsFingerprint) == fixture.sidecarSources)
        #expect(CodexLocalProjectUsageIndexer.cachedSnapshot(
            now: fixture.now,
            historyDays: 1,
            options: fixture.options) == fixture.baseline)
    }

    @Test(arguments: [false, true])
    func `raw cache from another Codex home is rejected before sidecar changes`(forceRefresh: Bool) throws {
        let fixture = try CacheScopeFixture()
        defer { fixture.env.cleanup() }
        let otherSessionsRoot = fixture.env.root
            .appendingPathComponent("other-codex-home/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: otherSessionsRoot, withIntermediateDirectories: true)
        let unavailableTrace = fixture.env.root.appendingPathComponent("unavailable-trace.sqlite", isDirectory: true)
        try FileManager.default.createDirectory(at: unavailableTrace, withIntermediateDirectories: true)
        var otherScannerOptions = fixture.scannerOptions
        otherScannerOptions.codexSessionsRoot = otherSessionsRoot
        otherScannerOptions.codexTraceDatabaseURL = unavailableTrace
        let retainedRawCache = fixture.rawCache
        let otherOptions = CodexLocalProjectUsageIndexer.Options(
            scannerOptions: otherScannerOptions,
            rawCacheReadOverrideForTesting: { _, _ in retainedRawCache })

        #expect(retainedRawCache.roots != CostUsageScanner.codexRootsFingerprint(options: otherScannerOptions))
        #expect(throws: CodexLocalProjectUsageIndexer.IndexError.cacheScopeMismatch) {
            try CodexLocalProjectUsageIndexer.loadSnapshot(
                now: fixture.now,
                historyDays: 1,
                forceRefresh: forceRefresh,
                options: otherOptions)
        }

        // The scanner may legitimately update its raw cache for the new source;
        // rejected imports must preserve the sidecar history and prior view.
        #expect(try fixture.sidecar.usageCache(roots: fixture.baseline.rootsFingerprint) == fixture.sidecarSources)
        #expect(CodexLocalProjectUsageIndexer.cachedSnapshot(
            now: fixture.now,
            historyDays: 1,
            options: fixture.options) == fixture.baseline)
        #expect(CodexLocalProjectUsageIndexer.cachedSnapshot(
            now: fixture.now,
            historyDays: 1,
            options: otherOptions) == nil)
    }

    @Test(arguments: [false, true])
    func `valid empty scan publishes an empty workspace snapshot`(forceRefresh: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let now = try env.makeLocalNoon(year: 2026, month: 8, day: 1)
        var scannerOptions = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        scannerOptions.refreshMinIntervalSeconds = 0
        scannerOptions.codexTraceDatabaseURL = env.root.appendingPathComponent("missing-trace.sqlite")
        let options = CodexLocalProjectUsageIndexer.Options(scannerOptions: scannerOptions)

        let snapshot = try CodexLocalProjectUsageIndexer.loadSnapshot(
            now: now,
            historyDays: 1,
            forceRefresh: forceRefresh,
            options: options)

        #expect(snapshot.total == .empty)
        #expect(snapshot.indexedFileCount == 0)
        #expect(snapshot.projects.isEmpty)
        #expect(snapshot.sessions.isEmpty)
        #expect(CostUsageStoreAccess.read(
            cacheRoot: env.cacheRoot,
            calendar: scannerOptions.calendar).roots == CostUsageScanner.codexRootsFingerprint(options: scannerOptions))
        #expect(CodexLocalProjectUsageIndexer.cachedSnapshot(
            now: now,
            historyDays: 1,
            options: options) == snapshot)
    }
}

private struct CacheScopeFixture {
    let env: CostUsageTestEnvironment
    let now: Date
    let scannerOptions: CostUsageScanner.Options
    let options: CodexLocalProjectUsageIndexer.Options
    let rawCache: CostUsageCache
    let baseline: CodexLocalProjectUsageSnapshot
    let sidecar: CodexWorkspaceUsageSidecar
    let sidecarSources: CostUsageCache

    init() throws {
        let env = try CostUsageTestEnvironment()
        let now = try env.makeLocalNoon(year: 2026, month: 8, day: 1)
        let events: [[String: Any]] = [
            [
                "type": "session_meta",
                "timestamp": env.isoString(for: now),
                "payload": ["id": "cache-scope-session"],
            ],
            [
                "type": "turn_context",
                "timestamp": env.isoString(for: now),
                "payload": ["cwd": env.root.path, "model": "openai/gpt-5.4"],
            ],
            [
                "type": "event_msg",
                "timestamp": env.isoString(for: now.addingTimeInterval(1)),
                "payload": [
                    "type": "token_count",
                    "info": [
                        "last_token_usage": [
                            "input_tokens": 10,
                            "cached_input_tokens": 1,
                            "output_tokens": 3,
                        ],
                        "model": "openai/gpt-5.4",
                    ],
                ],
            ],
        ]
        _ = try env.writeCodexSessionFile(
            day: now,
            filename: "cache-scope-session.jsonl",
            contents: env.jsonl(events))
        var scannerOptions = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        scannerOptions.refreshMinIntervalSeconds = 0
        scannerOptions.codexTraceDatabaseURL = env.root.appendingPathComponent("missing-trace.sqlite")
        let options = CodexLocalProjectUsageIndexer.Options(scannerOptions: scannerOptions)
        let baseline = try CodexLocalProjectUsageIndexer.loadSnapshot(
            now: now,
            historyDays: 1,
            forceRefresh: true,
            options: options)
        #expect(!baseline.sessions.isEmpty)
        #expect((baseline.total.totalTokens ?? 0) > 0)
        let rawCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: scannerOptions.calendar)
        let sidecar = CodexWorkspaceUsageSidecar(cacheRoot: env.cacheRoot)
        let sidecarSources = try sidecar.usageCache(roots: baseline.rootsFingerprint)
        #expect(!sidecarSources.files.isEmpty)

        self.env = env
        self.now = now
        self.scannerOptions = scannerOptions
        self.options = options
        self.rawCache = rawCache
        self.baseline = baseline
        self.sidecar = sidecar
        self.sidecarSources = sidecarSources
    }
}
