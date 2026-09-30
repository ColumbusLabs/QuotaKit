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

    @Test
    func `successful fallback carries a safe diagnostic for the prior live failure`() async throws {
        let pipeline = ProviderFetchPipeline(
            resolveStrategies: { _ in
                [
                    PriorFailureDiagnosticFixtureStrategy(id: "antigravity.cli-https", fails: true),
                    PriorFailureDiagnosticFixtureStrategy(id: "antigravity.offline", fails: false),
                ]
            })
        let outcome = await pipeline.fetch(context: self.context(sourceMode: .auto), provider: .antigravity)

        let result = try outcome.result.get()
        #expect(result.diagnostic == "Offline conversation metadata shown after a network error.")
        #expect(outcome.attempts.map(\.strategyID) == ["antigravity.cli-https", "antigravity.offline"])
        #expect(outcome.attempts.map(\.outcome.rawValue) == ["failed", "succeeded"])
    }

    @Test
    func `antigravity offline diagnostic describes the failure category without raw details`() {
        let diagnostic = AntigravityOfflineFetchStrategy().diagnostic(forPriorFailure:
            AntigravityStatusProbeError.apiError("HTTP 503 token=fixture-secret")) ?? ""

        #expect(diagnostic ==
            "Live usage is unavailable; showing offline conversation metadata after an API error.")
        #expect(!diagnostic.contains("fixture-secret"))
    }

    @Test
    func `antigravity offline diagnostic identifies unauthorized HTTP responses as authentication failures`() {
        for statusCode in [401, 403] {
            let diagnostic = AntigravityOfflineFetchStrategy().diagnostic(forPriorFailure:
                AntigravityStatusProbeError.apiError("HTTP \(statusCode) token=fixture-secret")) ?? ""

            #expect(diagnostic ==
                "Live usage is unavailable; showing offline conversation metadata after an authentication error.")
            #expect(!diagnostic.contains("fixture-secret"))
        }
    }

    @Test
    func `antigravity offline diagnostic identifies missing credentials as authentication failures`() {
        let diagnostic = AntigravityOfflineFetchStrategy().diagnostic(forPriorFailure:
            AntigravityStatusProbeError.apiError("Antigravity provider access token is missing")) ?? ""

        #expect(diagnostic ==
            "Live usage is unavailable; showing offline conversation metadata after an authentication error.")
        #expect(!diagnostic.localizedCaseInsensitiveContains("access token"))
    }

    @Test
    func `antigravity offline diagnostic classifies missing local csrf as configuration`() {
        let diagnostic = AntigravityOfflineFetchStrategy().diagnostic(forPriorFailure:
            AntigravityStatusProbeError.missingCSRFToken) ?? ""

        #expect(diagnostic ==
            "Live usage is unavailable; showing offline conversation metadata after a configuration problem.")
        #expect(!diagnostic.localizedCaseInsensitiveContains("csrf token"))
    }

    private func context(sourceMode: ProviderSourceMode = .api) -> ProviderFetchContext {
        ProviderFetchContext(
            runtime: .cli,
            sourceMode: sourceMode,
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

private struct PriorFailureDiagnosticFixtureStrategy: ProviderFetchStrategy {
    let id: String
    let fails: Bool
    var kind: ProviderFetchKind {
        self.fails ? .cli : .localProbe
    }

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        if self.fails {
            throw AntigravityStatusProbeError.apiError("network timeout token=fixture-secret")
        }
        return self.makeResult(
            usage: UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)),
            sourceLabel: "offline")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        self.fails
    }

    func diagnostic(forPriorFailure error: Error) -> String? {
        guard !self.fails else { return nil }
        let category = ProviderDiagnosticFetchAttempt.errorCategoryLabel(error.localizedDescription)
        return "Offline conversation metadata shown after a \(category) error."
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
