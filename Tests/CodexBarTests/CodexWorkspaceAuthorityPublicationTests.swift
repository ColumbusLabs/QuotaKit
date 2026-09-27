import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct CodexWorkspaceAuthorityPublicationTests {
    @Test
    func `personal credit dashboards preserve existing email authority`() {
        let email = "fixture@example.com"
        let decision = CodexDashboardAuthority.evaluate(CodexDashboardAuthorityInput(
            sourceKind: .cachedDashboard,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .providerAccount(id: "workspace-a"),
                expectedScopedEmail: email,
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: email,
                dashboardAccountID: "other-personal-scope",
                requiresWorkspaceBalanceScope: false,
                knownOwners: [CodexDashboardKnownOwnerCandidate(
                    identity: .providerAccount(id: "workspace-a"), normalizedEmail: email)]),
            routing: CodexDashboardRoutingHints(targetEmail: nil, lastKnownDashboardRoutingEmail: nil)))
        #expect(decision.allowedEffects.contains(.cachedDashboardReuse))
    }

    @Test
    func `unscoped OAuth usage cannot attach a workspace balance`() async throws {
        #expect(try await Self.unscopedOAuthBalanceIsRejected())
    }

    static func unscopedOAuthBalanceIsRejected() async throws -> Bool {
        let data = Data(#"{"plan_type":"business","credits":{"has_credits":true,"balance":null}}"#.utf8)
        let credentials = CodexOAuthCredentials(
            accessToken: "fixture-access",
            refreshToken: "fixture-refresh",
            idToken: nil,
            accountId: "workspace-a",
            lastRefresh: Date())
        let original = try CodexOAuthFetchStrategy._mapResultForTesting(data, credentials: credentials)
        let browser = BrowserDetection(cacheTTL: 0)
        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: .oauth,
            includeCredits: true,
            webTimeout: 10,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: nil,
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browser),
            browserDetection: browser)
        let result = try await CodexOAuthFetchStrategy._applyWorkspaceRemainingBalanceForTesting(
            original,
            usage: CodexOAuthUsageFetcher._decodeUsageResponseForTesting(data),
            credentials: credentials,
            context: context,
            fetcher: { _ in
                try JSONDecoder().decode(
                    CodexWorkspaceRemainingBalanceResponse.self,
                    from: Data(#"{"balance":42}"#.utf8))
            })
        return result.credits == original.credits && result.credits?.hasWorkspaceBalance != true
    }
}
