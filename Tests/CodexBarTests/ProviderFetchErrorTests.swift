import Foundation
import Testing
@testable import CodexBarCore

struct ProviderFetchErrorTests {
    @Test
    func `missing kiro strategy explains cli requirement`() {
        let message = ProviderFetchError.noAvailableStrategy(.kiro).localizedDescription

        #expect(message.contains("Kiro CLI"))
        #expect(message.contains("kiro-cli login"))
    }

    @Test
    func `classified transient errors retain bounded retry delay`() {
        #expect(ProviderFetchClassifiedError(
            kind: .rateLimited, message: "rate limited", retryAfterSeconds: 30).retryAfterSeconds == 10)
        #expect(ProviderFetchClassifiedError(
            kind: .rateLimited, message: "rate limited", retryAfterSeconds: .infinity).retryAfterSeconds == nil)
        #expect(ProviderFetchClassifiedError(
            kind: .authenticationExpired, message: "expired", retryAfterSeconds: 2).retryAfterSeconds == nil)
    }

    @Test
    func `pipeline retries a transient classified failure once after its bounded delay`() async {
        let strategy = RetryFixtureStrategy(failuresBeforeSuccess: 1)
        let delays = RetryDelayRecorder()
        let pipeline = ProviderFetchPipeline(
            resolveStrategies: { _ in [strategy] },
            retrySleeper: { seconds in await delays.record(seconds) })
        let outcome = await pipeline.fetch(context: self.context(), provider: .v0)

        guard case let .success(result) = outcome.result else {
            Issue.record("Expected retried strategy to succeed")
            return
        }
        #expect(result.sourceLabel == "fixture")
        #expect(await strategy.callCount == 2)
        #expect(await delays.values == [10])
    }

    @Test
    func `retry attempt is never retried again`() async {
        let strategy = RetryFixtureStrategy(failuresBeforeSuccess: .max)
        let delays = RetryDelayRecorder()
        let pipeline = ProviderFetchPipeline(
            resolveStrategies: { _ in [strategy] },
            retrySleeper: { seconds in await delays.record(seconds) })
        let outcome = await pipeline.fetch(context: self.context(), provider: .v0)

        guard case let .failure(error) = outcome.result else {
            Issue.record("Expected the single retry to fail")
            return
        }
        #expect(error is ProviderFetchClassifiedError)
        #expect(await strategy.callCount == 2)
        #expect(await delays.values == [10])
    }

    private func context() -> ProviderFetchContext {
        ProviderFetchContext(
            runtime: .cli,
            sourceMode: .api,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: nil,
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: RetryFixtureClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }
}

private struct RetryFixtureStrategy: ProviderFetchStrategy {
    let kind: ProviderFetchKind = .apiToken
    let failuresBeforeSuccess: Int
    private let calls = RetryCallCounter()
    var id: String {
        "retry-fixture"
    }

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let count = await self.calls.increment()
        if count <= self.failuresBeforeSuccess {
            throw ProviderFetchClassifiedError(kind: .rateLimited, message: "rate limited", retryAfterSeconds: 30)
        }
        let usage = UsageSnapshot(
            primary: RateWindow(usedPercent: 1, windowMinutes: 60, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        return ProviderFetchResult(
            usage: usage,
            credits: nil,
            dashboard: nil,
            sourceLabel: "fixture",
            strategyID: self.id,
            strategyKind: self.kind)
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    var callCount: Int {
        get async { await self.calls.value }
    }
}

private actor RetryCallCounter {
    private(set) var value = 0

    func increment() -> Int {
        self.value += 1
        return self.value
    }
}

private actor RetryDelayRecorder {
    private(set) var values: [TimeInterval] = []

    func record(_ seconds: TimeInterval) {
        self.values.append(seconds)
    }
}

private struct RetryFixtureClaudeFetcher: ClaudeUsageFetching {
    func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
        throw ClaudeUsageError.parseFailed("fixture")
    }

    func debugRawProbe(model _: String) async -> String {
        "fixture"
    }

    func detectVersion() -> String? {
        nil
    }
}
