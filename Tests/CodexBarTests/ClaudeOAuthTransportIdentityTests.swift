import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeOAuthTransportIdentityTests {
    @Test
    func `OAuth usage wrapper retains URL transport code and diagnostic text`() async {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, userInfo: [
            NSLocalizedDescriptionKey: "fixture transport failure",
            "fixture-marker": "preserved",
        ])
        let failure = await Self.captureFailure(underlying: underlying)
        let wrapped = failure as NSError

        #expect(wrapped.domain == NSURLErrorDomain)
        #expect(wrapped.code == NSURLErrorCannotFindHost)
        #expect(wrapped.userInfo["fixture-marker"] as? String == "preserved")
        #expect(failure.localizedDescription == "Claude OAuth network error: fixture transport failure")
    }

    @Test
    func `OAuth task cancellation remains typed and terminal`() async {
        let failure = await Self.captureFailure(underlying: CancellationError())

        #expect(failure is CancellationError)
    }

    @Test
    func `missing usage scope gives accurate Claude recovery guidance`() async {
        let failure = await Self.captureFailure(scopes: [])
        let description = failure.localizedDescription

        #expect(description.contains("Claude Code sign-in token"))
        #expect(description.contains("user:profile"))
        #expect(description.contains("remove any configured OAuth token override"))
        #expect(!description.contains("setup-token"))
    }

    @Test
    func `scope rejection from OAuth endpoint uses the same recovery guidance`() async {
        let failure = await Self.captureFailure(fetchError: .serverError(403, "missing user:profile"))
        let description = failure.localizedDescription

        #expect(description.contains("Claude Code sign-in token"))
        #expect(description.contains("remove any configured OAuth token override"))
        #expect(!description.contains("setup-token"))
    }

    private static func captureFailure(
        underlying: (any Error)? = nil,
        scopes: [String] = ["user:profile"],
        fetchError: ClaudeOAuthFetchError? = nil) async -> any Error
    {
        let transport = ProviderHTTPTransportStub { _ in
            if let underlying { throw underlying }
            throw NSError(domain: "UnexpectedTransport", code: 1)
        }
        let credentials = ClaudeOAuthCredentials(
            accessToken: "synthetic-access-token",
            refreshToken: "synthetic-refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            scopes: scopes,
            rateLimitTier: "fixture-tier",
            subscriptionType: "pro")
        let loadCredentials: @Sendable ([String: String], Bool, Bool) async throws
            -> ClaudeOAuthCredentials = { _, _, _ in credentials }
        let fetchUsage: @Sendable (String, Bool) async throws -> OAuthUsageResponse = { token, _ in
            if let fetchError { throw fetchError }
            return try await ClaudeOAuthUsageFetcher.fetchUsage(
                accessToken: token,
                detectClaudeVersion: false,
                environment: [:],
                transport: transport)
        }
        let fetcher = ClaudeUsageFetcher(
            browserDetection: BrowserDetection(cacheTTL: 0),
            environment: [:],
            runtime: .cli,
            dataSource: .oauth,
            preserveInvalidOAuthCache: true)

        do {
            try await ClaudeUsageFetcher.$loadOAuthCredentialsOverride.withValue(loadCredentials) {
                try await ClaudeUsageFetcher.$fetchOAuthUsageOverride.withValue(fetchUsage) {
                    _ = try await fetcher.loadLatestUsage(model: "sonnet")
                }
            }
            Issue.record("Expected the injected transport failure")
            return NSError(domain: "missing-fixture-error", code: 1)
        } catch {
            return error
        }
    }
}
