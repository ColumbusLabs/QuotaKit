import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
@Suite(.serialized)
struct ClaudeOAuthFetchStrategyAvailabilityTests {
    private struct StubClaudeFetcher: ClaudeUsageFetching {
        func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
            throw ClaudeUsageError.parseFailed("stub")
        }

        func debugRawProbe(model _: String) async -> String {
            "stub"
        }

        func detectVersion() -> String? {
            nil
        }
    }

    @Test
    func skipsRefreshFailureGate_whenEnvironmentOAuthTokenIsPresent() async {
        let env: [String: String] = [
            ClaudeOAuthCredentialsStore.environmentTokenKey: "env-token",
            ClaudeOAuthCredentialsStore.environmentScopesKey: "user:profile",
        ]

        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: .oauth,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: nil,
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))

        let strategy = ClaudeOAuthFetchStrategy()
        // Even if the refresh gate would block, environment credentials should remain usable.
        let available = await ClaudeOAuthRefreshFailureGate.$shouldAttemptOverride.withValue(false) {
            await ClaudeOAuthFetchStrategy.$nonInteractiveCredentialsOverride.withValue(nil) {
                await strategy.isAvailable(context)
            }
        }
        #expect(available == true)
    }

    @Test
    func appliesRefreshFailureGate_whenEnvironmentOAuthTokenIsAbsent() async {
        let env: [String: String] = [:]
        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: .oauth,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: nil,
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))

        let strategy = ClaudeOAuthFetchStrategy()
        let expiredCredentials = ClaudeOAuthCredentials(
            accessToken: "expired-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSinceNow: -60),
            scopes: ["user:profile"],
            rateLimitTier: nil)
        let available = await ClaudeOAuthRefreshFailureGate.$shouldAttemptOverride.withValue(false) {
            await ClaudeOAuthFetchStrategy.$nonInteractiveCredentialsOverride.withValue(expiredCredentials) {
                await strategy.isAvailable(context)
            }
        }
        #expect(available == false)
    }

    @Test
    func allowsOAuthAvailability_whenNonEnvironmentCredentialIsStillUsable() async {
        let env: [String: String] = [:]
        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: .auto,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: nil,
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))

        let strategy = ClaudeOAuthFetchStrategy()
        let unexpiredCredentials = ClaudeOAuthCredentials(
            accessToken: "valid-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSinceNow: 60 * 60),
            scopes: ["user:profile"],
            rateLimitTier: nil)
        let available = await ClaudeOAuthRefreshFailureGate.$shouldAttemptOverride.withValue(false) {
            await ClaudeOAuthFetchStrategy.$nonInteractiveCredentialsOverride.withValue(unexpiredCredentials) {
                await strategy.isAvailable(context)
            }
        }
        #expect(available == true)
    }
}
#endif
