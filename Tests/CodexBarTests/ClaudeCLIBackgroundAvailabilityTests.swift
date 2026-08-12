import Foundation
import Testing
@testable import CodexBarCore

private final class ClaudeOpaqueChildCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        self.lock.withLock { self.value += 1 }
    }

    var count: Int {
        self.lock.withLock { self.value }
    }
}

struct ClaudeCLIRuntimeBoundaryTests {
    @Test(arguments: ClaudeOAuthKeychainPromptMode.allCases)
    func `background app CLI is unavailable under every legacy prompt mode`(
        promptMode: ClaudeOAuthKeychainPromptMode) async
    {
        let strategy = self.makeStrategy()
        let context = self.makeContext(runtime: .app)

        await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(promptMode) {
            await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/bin/echo") {
                await ProviderInteractionContext.$current.withValue(.background) {
                    #expect(await !strategy.isAvailable(context))
                }
            }
        }
    }

    @Test
    func `direct background fetch rejects before invoking Claude child`() async {
        let strategy = self.makeStrategy()
        let context = self.makeContext(runtime: .app)
        let counter = ClaudeOpaqueChildCounter()
        let fetchOverride: ClaudeStatusProbe.FetchOverride = { _, _, _ in
            counter.increment()
            return Self.makeUsageStatusSnapshot()
        }

        await ProviderInteractionContext.$current.withValue(.background) {
            await #expect(throws: ClaudeUsageError.self) {
                try await ClaudeStatusProbe.$fetchOverride.withValue(fetchOverride) {
                    try await strategy.fetch(context)
                }
            }
        }
        #expect(counter.count < 1)
    }

    @Test
    func `background direct launch boundaries reject before Claude session work`() async {
        await ProviderInteractionContext.$current.withValue(.background) {
            await #expect(throws: ClaudeStatusProbeError.backgroundAccessDenied) {
                try await ClaudeStatusProbe(claudeBinary: "/bin/sh", timeout: 0.1).fetch()
            }
            await #expect(throws: ClaudeStatusProbeError.backgroundAccessDenied) {
                try await ClaudeStatusProbe.fetchIdentity(timeout: 0.1, environment: [:])
            }
            await #expect(throws: ClaudeStatusProbeError.backgroundAccessDenied) {
                try await ClaudeStatusProbe.touchOAuthAuthPath(timeout: 0.1, environment: [:])
            }
            await #expect(throws: ClaudeCLISession.SessionError.backgroundAccessDenied) {
                try await ClaudeCLISession.current.capture(
                    subcommand: "/status",
                    binary: "/bin/sh",
                    timeout: 0.1,
                    environment: [:])
            }
        }
    }

    @Test
    func `user initiated app fetch retains Claude CLI path`() async throws {
        let strategy = self.makeStrategy()
        let context = self.makeContext(runtime: .app)
        let counter = ClaudeOpaqueChildCounter()
        let fetchOverride: ClaudeStatusProbe.FetchOverride = { _, _, _ in
            counter.increment()
            return Self.makeUsageStatusSnapshot()
        }

        let result = try await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/bin/echo") {
            try await ProviderInteractionContext.$current.withValue(.userInitiated) {
                #expect(await strategy.isAvailable(context))
                return try await ClaudeStatusProbe.$fetchOverride.withValue(fetchOverride) {
                    try await strategy.fetch(context)
                }
            }
        }

        #expect(result.strategyID == "claude.cli")
        #expect(counter.count == 1)
    }

    @Test
    func `explicit QuotaKit CLI fetch retains Claude CLI path`() async throws {
        let strategy = self.makeStrategy()
        let context = self.makeContext(runtime: .cli)
        let counter = ClaudeOpaqueChildCounter()
        let fetchOverride: ClaudeStatusProbe.FetchOverride = { _, _, _ in
            counter.increment()
            return Self.makeUsageStatusSnapshot()
        }

        let result = try await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/bin/echo") {
            try await ClaudeCLIAuthStatusProbe.withResultOverrideForTesting(true) {
                #expect(await strategy.isAvailable(context))
                return try await ClaudeStatusProbe.$fetchOverride.withValue(fetchOverride) {
                    try await strategy.fetch(context)
                }
            }
        }

        #expect(result.strategyID == "claude.cli")
        #expect(counter.count == 1)
    }

    private func makeStrategy() -> ClaudeCLIFetchStrategy {
        ClaudeCLIFetchStrategy(
            useWebExtras: false,
            includePrepaidBalance: false,
            manualCookieHeader: nil,
            browserDetection: BrowserDetection(cacheTTL: 0),
            hasWebFallback: false)
    }

    private func makeContext(runtime: ProviderRuntime) -> ProviderFetchContext {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        return ProviderFetchContext(
            runtime: runtime,
            sourceMode: .cli,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: nil,
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection, environment: [:]),
            browserDetection: browserDetection)
    }

    private static func makeUsageStatusSnapshot() -> ClaudeStatusSnapshot {
        ClaudeStatusSnapshot(
            sessionPercentLeft: 88,
            weeklyPercentLeft: 60,
            opusPercentLeft: 95,
            accountEmail: "user@example.com",
            accountOrganization: "Example Org",
            loginMethod: nil,
            primaryResetDescription: "Resets 11am",
            secondaryResetDescription: "Resets Nov 21",
            opusResetDescription: "Resets Nov 21",
            rawText: "stub")
    }
}
