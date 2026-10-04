import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct UsageStoreCodexCostCatchUpPublicationTests {
    @Test
    func `automatic discovery publishes fresh today before the next scheduling sleep`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let now = try env.makeLocalNoon(year: 2026, month: 10, day: 3)
        let iso = env.isoString(for: now)
        let today = try env.writeCodexSessionFile(
            day: now,
            filename: "rollout-today.jsonl",
            contents: """
            {"type":"session_meta","timestamp":"\(iso)","payload":{"session_id":"today"}}
            {"type":"turn_context","timestamp":"\(iso)","payload":{"model":"openai/gpt-5.2-codex"}}
            \(Self.tokenRecord(iso: iso, input: 100))

            """)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"))
        options.refreshMinIntervalSeconds = 0
        let initial = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            environment: [:],
            now: now,
            allowPricingRefresh: false,
            includePiSessions: false,
            scannerOptions: options)
        #expect(initial.historyCoverageIsEstablished)
        #expect(initial.last30DaysTokens == 100)

        // Establish the publication baseline before adding a large discovery backlog. Keeping
        // the backlog out of the initial scan makes the baseline independent of filesystem
        // enumeration order on slower CI runners.
        for index in 0..<1600 {
            _ = try env.writeCodexSessionFile(
                day: now.addingTimeInterval(-86400),
                filename: "rollout-history-\(index).jsonl",
                contents: #"{"type":"session_meta","payload":{"session_id":"history-\#(index)"}}"# + "\n")
        }

        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        cache.codexPricingKey = "previous-pricing-generation"
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache)
        try Self.append(Self.tokenRecord(iso: iso, input: 200), to: today)
        let instant = ContinuousClock.now
        options.maxCodexScanDurationPerRefresh = 2
        var stagingOptions = options
        stagingOptions.codexScanBudgetForTesting = .init(
            maxFileBytes: 0,
            maxBytesPerRefresh: 0,
            maxDuration: 2,
            now: { instant })
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: now.addingTimeInterval(-29 * 86400),
            until: now,
            now: now.addingTimeInterval(1),
            options: stagingOptions)
        cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(cache.codexScanCatchUpPending == true)
        #expect(cache.codexActiveLookbackState?.currentWindowNextDayKeyByRoot?.isEmpty == false)

        _ = try env.writeCodexSessionFile(
            day: now,
            filename: "rollout-fresh-today.jsonl",
            contents: """
            {"type":"session_meta","timestamp":"\(iso)","payload":{"session_id":"fresh-today"}}
            {"type":"turn_context","timestamp":"\(iso)","payload":{"model":"openai/gpt-5.2-codex"}}
            \(Self.tokenRecord(iso: iso, input: 50))

            """)
        let scanOptions = options
        let fetcher = CostUsageFetcher(scannerOptions: scanOptions)
        let store = try Self.makeStore(suite: "discovery-scheduling", costUsageFetcher: fetcher)
        defer { store.cancelCodexCostCatchUp() }
        store.settings.backgroundWorkLowPowerModePreference = .off
        store.publishTokenSnapshot(initial, for: .codex)
        store._test_widgetSnapshotSaveOverride = { _ in }
        store._test_cachedCodexTokenSnapshotLoaderOverride = { _, _, days in
            await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
                now: now.addingTimeInterval(2),
                historyDays: days,
                includePiSessions: false,
                requireCompleteHistory: true,
                scannerOptions: scanOptions)
                .map { ($0.snapshot, $0.lastRefreshAt, $0.staleSnapshotUpdatedAt) }
        }
        var advances = 0
        store._test_codexCostCatchUpActiveDuration = 0.1
        store._test_codexCostCatchUpAdvanceOverride = { _, _, days in
            advances += 1
            return try await fetcher.advanceCodexScanCatchUp(
                now: now.addingTimeInterval(2), historyDays: days).value
        }
        var scheduledDelay: TimeInterval = 0
        store._test_codexCostCatchUpSleepOverride = { delay in
            scheduledDelay += delay
            if advances >= CodexCostCatchUpPolicy.automaticMaximumBurstPasses {
                throw CancellationError()
            }
        }
        store.startCodexCostCatchUpIfNeeded()
        await store.codexCostCatchUpTask?.value
        await store.widgetSnapshotPersistTask?.value

        #expect(advances > 1 && advances <= CodexCostCatchUpPolicy.automaticMaximumBurstPasses)
        #expect(scheduledDelay == 0)
        let published = try #require(store.tokenSnapshot(for: .codex))
        #expect(published.last30DaysTokens == 250)
        #expect(published.historyCoverageIsEstablished)
        #expect(!published.historyScanIsPartial)
        #expect(store.codexCostCatchUpActivity?.phase == .complete)
    }

    private static func makeStore(
        suite: String,
        costUsageFetcher: CostUsageFetcher) throws -> UsageStore
    {
        let settings = testSettingsStore(
            suiteName: "UsageStoreCodexCostCatchUpPublicationTests-\(suite)",
            userDefaults: InMemoryUserDefaults())
        settings.costUsageEnabled = true
        settings.costUsageHistoryDays = 30
        let metadata = try #require(ProviderRegistry.shared.metadata[.codex])
        settings.setProviderEnabled(provider: .codex, metadata: metadata, enabled: true)
        return UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            costUsageFetcher: costUsageFetcher,
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
    }

    private static func tokenRecord(iso: String, input: Int) -> String {
        #"{"type":"event_msg","timestamp":"\#(iso)","payload":{"type":"token_count","info":"#
            + #"{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":0,"output_tokens":0},"#
            + #""model":"openai/gpt-5.2-codex"}}}"#
    }

    private static func append(_ contents: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((contents + "\n").utf8))
        try handle.close()
    }
}
