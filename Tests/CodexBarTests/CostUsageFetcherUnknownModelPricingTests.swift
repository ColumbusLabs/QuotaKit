import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct CostUsageFetcherUnknownModelPricingTests {
    @Test
    func `fetcher reprices an unknown model after an on demand catalog refresh`() async throws {
        let fixture = try UnknownModelPricingFixture()
        defer { fixture.environment.cleanup() }

        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: fixture.day,
            refreshPricingInBackground: false,
            includePiSessions: false,
            scannerOptions: fixture.options,
            modelsDevClient: ModelsDevClient(transport: CostUsageFetcherModelsDevTransport(
                data: fixture.refreshedCatalog)))

        let activeDay = try Self.dailyEntry(on: fixture.day, in: snapshot, calendar: fixture.options.calendar)
        #expect(Self.areCertifiedZeroDays(
            snapshot.daily.filter { $0.totalTokens == 0 },
            options: fixture.options))
        let breakdown = try #require(activeDay.modelBreakdowns?.first)
        #expect(breakdown.modelName == "gpt-new")
        #expect(abs((breakdown.costUSD ?? 0) - 0.00028) < 0.0000001)
    }

    @Test
    func `fetcher excludes routed opencode go models from the Codex snapshot`() async throws {
        let fixture = try UnknownModelPricingFixture()
        defer { fixture.environment.cleanup() }
        let qualifiedTurnContext: [String: Any] = [
            "type": "turn_context",
            "timestamp": fixture.environment.isoString(for: fixture.day),
            "payload": ["model": "opencode-go/deepseek-v4-flash"],
        ]
        let qualifiedTokenCount: [String: Any] = [
            "type": "event_msg",
            "timestamp": fixture.environment.isoString(for: fixture.day.addingTimeInterval(1)),
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": [
                        "input_tokens": 100,
                        "cached_input_tokens": 20,
                        "output_tokens": 10,
                    ],
                ],
            ],
        ]
        _ = try fixture.environment.writeCodexSessionFile(
            day: fixture.day,
            filename: "unknown-qualified-model.jsonl",
            contents: fixture.environment.jsonl([qualifiedTurnContext, qualifiedTokenCount]))

        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: fixture.day,
            refreshPricingInBackground: false,
            includePiSessions: false,
            scannerOptions: fixture.options,
            modelsDevClient: ModelsDevClient(transport: CostUsageFetcherModelsDevTransport(
                data: fixture.refreshedCatalog)))

        #expect(Self.areCertifiedZeroDays(
            snapshot.daily.filter { $0.totalTokens == 0 },
            options: fixture.options))
        #expect(!(snapshot.daily
                .flatMap { $0.modelBreakdowns ?? [] }
                .contains { $0.modelName == "opencode-go/deepseek-v4-flash" }))
    }

    @Test
    func `fetcher reprices a bare claude vendor model after an on demand catalog refresh`() async throws {
        let fixture = try UnknownModelPricingFixture()
        defer { fixture.environment.cleanup() }
        let assistant: [String: Any] = [
            "type": "assistant",
            "timestamp": fixture.environment.isoString(for: fixture.day),
            "message": [
                "model": "deepseek-v4-flash",
                "usage": [
                    "input_tokens": 100,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": 0,
                    "output_tokens": 10,
                ],
            ],
        ]
        _ = try fixture.environment.writeClaudeProjectFile(
            relativePath: "project-a/unknown-vendor-model.jsonl",
            contents: fixture.environment.jsonl([assistant]))

        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .claude,
            now: fixture.day,
            refreshPricingInBackground: false,
            includePiSessions: false,
            scannerOptions: fixture.options,
            modelsDevClient: ModelsDevClient(transport: CostUsageFetcherModelsDevTransport(
                data: fixture.refreshedCatalog)))

        let activeDay = try Self.dailyEntry(on: fixture.day, in: snapshot, calendar: fixture.options.calendar)
        let breakdown = try #require(activeDay.modelBreakdowns?.first)
        #expect(breakdown.modelName == "deepseek-v4-flash")
        #expect(abs((breakdown.costUSD ?? 0) - 0.0000168) < 0.0000001)
    }

    @Test
    func `pricing retry preserves disabled pi session merging`() async throws {
        let fixture = try UnknownModelPricingFixture()
        defer { fixture.environment.cleanup() }
        let piAssistant: [String: Any] = [
            "type": "message",
            "timestamp": fixture.environment.isoString(for: fixture.day),
            "message": [
                "role": "assistant",
                "provider": "openai-codex",
                "model": "openai/gpt-5.4",
                "timestamp": Int(fixture.day.timeIntervalSince1970 * 1000),
                "usage": ["input": 50, "output": 10, "totalTokens": 60],
            ],
        ]
        _ = try fixture.environment.writePiSessionFile(
            relativePath: "2026-04-12T12-00-00-000Z_retry.jsonl",
            contents: fixture.environment.jsonl([piAssistant]))
        let piOptions = PiSessionCostScanner.Options(
            piSessionsRoot: fixture.environment.piSessionsRoot,
            cacheRoot: fixture.environment.cacheRoot,
            refreshMinIntervalSeconds: 0)

        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: fixture.day,
            refreshPricingInBackground: false,
            includePiSessions: false,
            scannerOptions: fixture.options,
            piScannerOptions: piOptions,
            modelsDevClient: ModelsDevClient(transport: CostUsageFetcherModelsDevTransport(
                data: fixture.refreshedCatalog)))

        let nativeDay = try Self.dailyEntry(on: fixture.day, in: snapshot, calendar: fixture.options.calendar)
        #expect(nativeDay.totalTokens == 110)
        #expect(nativeDay.modelBreakdowns?.map(\.modelName) == ["gpt-new"])
        #expect(Self.hasValidCodexDayEvidence(for: nativeDay, options: fixture.options))
        #expect(Self.areCertifiedZeroDays(
            snapshot.daily.filter { $0.totalTokens == 0 },
            options: fixture.options))
    }

    @Test
    func `background pricing refresh returns unpriced usage before catalog download finishes`() async throws {
        let fixture = try UnknownModelPricingFixture()
        defer { fixture.environment.cleanup() }
        let gate = UnknownModelPricingTransportGate()
        let completion = UnknownModelPricingCompletionProbe()
        let task = Task {
            let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
                provider: .codex,
                now: fixture.day,
                refreshPricingInBackground: true,
                includePiSessions: false,
                scannerOptions: fixture.options,
                modelsDevClient: ModelsDevClient(transport: CostUsageFetcherGatedModelsDevTransport(
                    data: fixture.refreshedCatalog,
                    gate: gate)))
            await completion.markCompleted()
            return snapshot
        }

        await gate.waitUntilStarted()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while await !(completion.isCompleted), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let returnedBeforeRelease = await completion.isCompleted
        await gate.release()
        let snapshot = try await task.value

        #expect(returnedBeforeRelease)
        let activeDay = try Self.dailyEntry(on: fixture.day, in: snapshot, calendar: fixture.options.calendar)
        #expect(Self.areCertifiedZeroDays(
            snapshot.daily.filter { $0.totalTokens == 0 },
            options: fixture.options))
        let breakdown = try #require(activeDay.modelBreakdowns?.first)
        #expect(breakdown.modelName == "gpt-new")
        #expect(breakdown.totalTokens == 110)
        #expect(breakdown.costUSD == nil)

        let refreshDeadline = clock.now.advanced(by: .seconds(1))
        while ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "gpt-new",
            cacheRoot: fixture.environment.cacheRoot) == nil,
            clock.now < refreshDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "gpt-new",
            cacheRoot: fixture.environment.cacheRoot) != nil)
    }

    @Test
    func `unattributed codex usage does not request a pricing refresh`() async throws {
        let environment = try CostUsageTestEnvironment()
        defer { environment.cleanup() }
        let day = try environment.makeLocalNoon(year: 2026, month: 4, day: 12)
        let staleCatalog = try JSONDecoder().decode(ModelsDevCatalog.self, from: Data("""
        {
          "openai": {
            "id": "openai",
            "models": { "known-test-model": { "id": "known-test-model", "cost": { "input": 1, "output": 4 } } }
          }
        }
        """.utf8))
        ModelsDevCache.save(
            catalog: staleCatalog,
            fetchedAt: day.addingTimeInterval(-901),
            cacheRoot: environment.cacheRoot)
        let tokenCount: [String: Any] = [
            "type": "event_msg",
            "timestamp": environment.isoString(for: day),
            "payload": [
                "type": "token_count",
                "info": [
                    "last_token_usage": [
                        "input_tokens": 100,
                        "cached_input_tokens": 20,
                        "output_tokens": 10,
                    ],
                ],
            ],
        ]
        _ = try environment.writeCodexSessionFile(
            day: day,
            filename: "unattributed-model.jsonl",
            contents: environment.jsonl([tokenCount]))
        let options = CostUsageScanner.Options(
            codexSessionsRoot: environment.codexSessionsRoot,
            claudeProjectsRoots: [environment.claudeProjectsRoot],
            cacheRoot: environment.cacheRoot,
            codexTraceDatabaseURL: environment.root.appendingPathComponent("missing-traces.sqlite"))
        let counter = UnknownModelPricingRequestCounter()

        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            refreshPricingInBackground: false,
            includePiSessions: false,
            scannerOptions: options,
            modelsDevClient: ModelsDevClient(transport: CostUsageFetcherCountingModelsDevTransport(counter: counter)))

        let activeDay = try Self.dailyEntry(on: day, in: snapshot, calendar: options.calendar)
        #expect(Self.areCertifiedZeroDays(
            snapshot.daily.filter { $0.totalTokens == 0 },
            options: options))
        let breakdown = try #require(activeDay.modelBreakdowns?.first)
        let requestCount = await counter.requestCount
        #expect(breakdown.modelName == CostUsagePricing.codexUnattributedModel)
        #expect(breakdown.totalTokens == 110)
        #expect(breakdown.costUSD == nil)
        #expect(requestCount == 0)
    }

    @Test(arguments: [false, true])
    func `local only fetch skips every pricing network refresh`(includePiSessions: Bool) async throws {
        let fixture = try UnknownModelPricingFixture()
        defer { fixture.environment.cleanup() }
        try fixture.writePiSession()
        let counter = UnknownModelPricingRequestCounter()

        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: fixture.day,
            allowPricingRefresh: false,
            refreshPricingInBackground: false,
            includePiSessions: includePiSessions,
            scannerOptions: fixture.options,
            piScannerOptions: fixture.piOptions,
            modelsDevClient: ModelsDevClient(
                transport: CostUsageFetcherCountingModelsDevTransport(counter: counter)))

        let activeDay = try Self.dailyEntry(on: fixture.day, in: snapshot, calendar: fixture.options.calendar)
        #expect(Self.areCertifiedZeroDays(
            snapshot.daily.filter { $0.totalTokens == 0 },
            options: fixture.options))
        let breakdown = try #require(activeDay.modelBreakdowns?.first)
        #expect(breakdown.modelName == "gpt-new")
        #expect(breakdown.costUSD == nil)
        #expect(snapshot.sessionTokens == (includePiSessions ? 170 : 110))
        #expect(snapshot.last30DaysTokens == (includePiSessions ? 170 : 110))
        #expect(await counter.requestCount == 0)
        if includePiSessions {
            #expect(activeDay.dayEvidence == nil)
        } else {
            #expect(Self.hasValidCodexDayEvidence(for: activeDay, options: fixture.options))
        }
    }

    @Test
    func `foreground pricing scheduling still requests a catalog for native plus pi usage`() async throws {
        let fixture = try UnknownModelPricingFixture()
        defer { fixture.environment.cleanup() }
        try fixture.writePiSession()
        let counter = UnknownModelPricingRequestCounter()

        // This was the timestamp fixtures' old configuration: foreground is not an opt-out.
        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: fixture.day,
            refreshPricingInBackground: false,
            scannerOptions: fixture.options,
            piScannerOptions: fixture.piOptions,
            modelsDevClient: ModelsDevClient(
                transport: CostUsageFetcherCountingModelsDevTransport(counter: counter)))

        #expect(snapshot.sessionTokens == 170)
        #expect(await counter.requestCount == 1)
    }
}

extension CostUsageFetcherUnknownModelPricingTests {
    private static func dailyEntry(
        on day: Date,
        in snapshot: CostUsageTokenSnapshot,
        calendar: Calendar) throws -> CostUsageDailyReport.Entry
    {
        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day, calendar: calendar)
        return try #require(snapshot.daily.first { $0.date == dayKey })
    }

    private static func areCertifiedZeroDays(
        _ entries: [CostUsageDailyReport.Entry],
        options: CostUsageScanner.Options) -> Bool
    {
        entries.allSatisfy { entry in
            entry.inputTokens == 0
                && entry.outputTokens == 0
                && entry.totalTokens == 0
                && entry.requestCount == 0
                && entry.costUSD == 0
                && entry.modelsUsed == nil
                && entry.modelBreakdowns == nil
                && Self.hasValidCodexDayEvidence(for: entry, options: options)
        }
    }

    private static func hasValidCodexDayEvidence(
        for entry: CostUsageDailyReport.Entry,
        options: CostUsageScanner.Options) -> Bool
    {
        guard let evidence = entry.dayEvidence else { return false }
        let rootPaths = CostUsageScanner.codexSessionsRoots(options: options)
            .map(\.standardizedFileURL.path)
            .sorted()
        let expectedScopeID = CostUsageScanner.codexDayEvidenceScopeID(
            rootPaths: rootPaths,
            calendar: options.calendar)
        let verifiedAt = evidence.verifiedAt.timeIntervalSince1970
        return evidence.sourceKind == "codexLocalLedger"
            && evidence.scopeID == expectedScopeID
            && !evidence.lineageID.isEmpty
            && evidence.revision > 0
            && verifiedAt.isFinite
            && verifiedAt > 0
    }
}

private struct UnknownModelPricingFixture {
    let environment: CostUsageTestEnvironment
    let day: Date
    let options: CostUsageScanner.Options
    let refreshedCatalog: Data

    var piOptions: PiSessionCostScanner.Options {
        PiSessionCostScanner.Options(
            piSessionsRoot: self.environment.piSessionsRoot,
            cacheRoot: self.environment.cacheRoot,
            refreshMinIntervalSeconds: 0)
    }

    func writePiSession() throws {
        _ = try self.environment.writePiSessionFile(
            relativePath: "2026-04-12T12-00-00-000Z_pricing.jsonl",
            contents: self.environment.jsonl([[
                "type": "message",
                "timestamp": self.environment.isoString(for: self.day),
                "message": [
                    "role": "assistant",
                    "provider": "openai-codex",
                    "model": "gpt-new",
                    "timestamp": Int(self.day.timeIntervalSince1970 * 1000),
                    "usage": ["input": 50, "output": 10, "totalTokens": 60],
                ],
            ]]))
    }

    init() throws {
        let environment = try CostUsageTestEnvironment()
        self.environment = environment
        self.day = try environment.makeLocalNoon(year: 2026, month: 4, day: 12)
        let oldCatalog = try JSONDecoder().decode(ModelsDevCatalog.self, from: Data("""
        {
          "openai": {
            "id": "openai",
            "models": { "gpt-old": { "id": "gpt-old", "cost": { "input": 1, "output": 4 } } }
          },
          "anthropic": {
            "id": "anthropic",
            "models": { "claude-old": { "id": "claude-old", "cost": { "input": 3, "output": 15 } } }
          }
        }
        """.utf8))
        ModelsDevCache.save(
            catalog: oldCatalog,
            fetchedAt: self.day.addingTimeInterval(-901),
            cacheRoot: environment.cacheRoot)

        self.refreshedCatalog = Data("""
        {
          "openai": {
            "id": "openai",
            "models": { "gpt-new": { "id": "gpt-new", "cost": { "input": 2, "output": 8 } } }
          },
          "opencode-go": {
            "id": "opencode-go",
            "models": {
              "deepseek-v4-flash": {
                "id": "deepseek-v4-flash",
                "cost": { "input": 0.07, "output": 0.14 }
              }
            }
          },
          "deepseek": {
            "id": "deepseek",
            "models": {
              "deepseek-v4-flash": {
                "id": "deepseek-v4-flash",
                "cost": { "input": 0.14, "output": 0.28 }
              }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": { "claude-new": { "id": "claude-new", "cost": { "input": 3, "output": 15 } } }
          }
        }
        """.utf8)
        let turnContext: [String: Any] = [
            "type": "turn_context",
            "timestamp": environment.isoString(for: self.day),
            "payload": ["model": "gpt-new"],
        ]
        let tokenCount: [String: Any] = [
            "type": "event_msg",
            "timestamp": environment.isoString(for: self.day.addingTimeInterval(1)),
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": [
                        "input_tokens": 100,
                        "cached_input_tokens": 20,
                        "output_tokens": 10,
                    ],
                ],
            ],
        ]
        _ = try environment.writeCodexSessionFile(
            day: self.day,
            filename: "unknown-model.jsonl",
            contents: environment.jsonl([turnContext, tokenCount]))
        self.options = CostUsageScanner.Options(
            codexSessionsRoot: environment.codexSessionsRoot,
            claudeProjectsRoots: [environment.claudeProjectsRoot],
            cacheRoot: environment.cacheRoot,
            codexTraceDatabaseURL: environment.root.appendingPathComponent("missing-traces.sqlite"))
    }
}

private struct CostUsageFetcherModelsDevTransport: ModelsDevHTTPTransport {
    let data: Data

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil)!
        return (self.data, response)
    }
}

private struct CostUsageFetcherGatedModelsDevTransport: ModelsDevHTTPTransport {
    let data: Data
    let gate: UnknownModelPricingTransportGate

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        await self.gate.markStartedAndWaitForRelease()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil)!
        return (self.data, response)
    }
}

private actor UnknownModelPricingTransportGate {
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func markStartedAndWaitForRelease() async {
        self.started = true
        let startWaiters = self.startWaiters
        self.startWaiters.removeAll()
        startWaiters.forEach { $0.resume() }
        guard !self.released else { return }
        await withCheckedContinuation { continuation in
            self.releaseWaiters.append(continuation)
        }
    }

    func waitUntilStarted() async {
        guard !self.started else { return }
        await withCheckedContinuation { continuation in
            self.startWaiters.append(continuation)
        }
    }

    func release() {
        self.released = true
        let releaseWaiters = self.releaseWaiters
        self.releaseWaiters.removeAll()
        releaseWaiters.forEach { $0.resume() }
    }
}

private actor UnknownModelPricingCompletionProbe {
    private(set) var isCompleted = false

    func markCompleted() {
        self.isCompleted = true
    }
}

private actor UnknownModelPricingRequestCounter {
    private(set) var requestCount = 0

    func recordRequest() {
        self.requestCount += 1
    }
}

private struct CostUsageFetcherCountingModelsDevTransport: ModelsDevHTTPTransport {
    let counter: UnknownModelPricingRequestCounter

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        await self.counter.recordRequest()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil)!
        return (Data(#"{"openai":{"id":"openai","models":{}}}"#.utf8), response)
    }
}
