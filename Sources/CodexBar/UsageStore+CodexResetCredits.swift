import CodexBarCore
import Foundation

extension UsageStore {
    typealias CodexResetCreditsFetcher = @Sendable ([String: String]) async throws
        -> CodexRateLimitResetCreditsSnapshot?

    func codexResetCreditsFetcher() -> CodexResetCreditsFetcher {
        if let override = self._test_codexResetCreditsFetcherOverride {
            return override
        }
        return { env in
            try await Self.fetchCodexResetCredits(env: env)
        }
    }

    func handleCodexResetCreditNotifications(snapshot: UsageSnapshot) {
        guard self.settings.showOptionalCreditsAndExtraUsage,
              let resetCredits = snapshot.codexResetCredits
        else {
            return
        }
        CodexResetCreditExpiryNotifier().postExpiringCreditsIfNeeded(
            snapshot: resetCredits,
            resetStyle: self.settings.resetTimeDisplayStyle)
    }

    nonisolated static func attachingCodexResetCreditsIfNeeded(
        to outcome: ProviderFetchOutcome,
        env: [String: String],
        fetcher: @escaping CodexResetCreditsFetcher) async -> ProviderFetchOutcome
    {
        guard case let .success(result) = outcome.result else { return outcome }
        let requiresResetCreditRescue = Self.requiresResetCreditRescue(result)
        let embeddedResetCredits = result.usage.codexResetCredits
        if let embeddedResetCredits,
           !Self.requiresSupplementalResetCreditDetails(
               embeddedResetCredits,
               at: result.usage.updatedAt)
        {
            return outcome
        }

        do {
            try Task.checkCancellation()
            let supplementalResetCredits = try await fetcher(env)
            try Task.checkCancellation()
            if requiresResetCreditRescue,
               (supplementalResetCredits?.availableCount ?? 0) <= 0
            {
                return outcome.replacingResult(with: .failure(UsageError.noRateLimitsFound))
            }
            let resetCredits = Self.mergingCodexResetCredits(
                embedded: embeddedResetCredits,
                supplemental: supplementalResetCredits)
            return outcome.replacingUsage(result.usage.withCodexResetCredits(resetCredits))
        } catch {
            if error is CancellationError || Task.isCancelled {
                return ProviderFetchOutcome(result: .failure(CancellationError()), attempts: outcome.attempts)
            }
            if requiresResetCreditRescue {
                return outcome.replacingResult(with: .failure(UsageError.noRateLimitsFound))
            }
            // Preserve fresh app-server data when only the best-effort detail enrichment fails.
            // Without embedded data, a successful usage refresh must not retain older inventory.
            return embeddedResetCredits == nil
                ? outcome.replacingUsage(result.usage.withCodexResetCredits(nil))
                : outcome
        }
    }

    private nonisolated static func requiresSupplementalResetCreditDetails(
        _ snapshot: CodexRateLimitResetCreditsSnapshot,
        at date: Date) -> Bool
    {
        snapshot.availableInventory(at: date).count < snapshot.availableCount
    }

    private nonisolated static func mergingCodexResetCredits(
        embedded: CodexRateLimitResetCreditsSnapshot?,
        supplemental: CodexRateLimitResetCreditsSnapshot?) -> CodexRateLimitResetCreditsSnapshot?
    {
        guard let embedded else { return supplemental }
        guard let supplemental else { return embedded }

        var seenIDs = Set(embedded.credits.map(\.id))
        let supplementalDetails = supplemental.credits.filter { credit in
            seenIDs.insert(credit.id).inserted
        }
        return CodexRateLimitResetCreditsSnapshot(
            credits: embedded.credits + supplementalDetails,
            availableCount: embedded.availableCount,
            updatedAt: max(embedded.updatedAt, supplemental.updatedAt))
    }

    private nonisolated static func requiresResetCreditRescue(_ result: ProviderFetchResult) -> Bool {
        result.strategyID == "codex.oauth"
            && result.credits == nil
            && result.usage.primary == nil
            && result.usage.secondary == nil
            && result.usage.tertiary == nil
            && (result.usage.extraRateWindows?.isEmpty ?? true)
    }

    nonisolated static func fetchCodexResetCredits(
        env: [String: String]) async throws -> CodexRateLimitResetCreditsSnapshot?
    {
        try Task.checkCancellation()
        let credentials = try CodexOAuthCredentialsStore.loadOAuthTokens(env: env)
        return try await Self.fetchCodexResetCredits(
            credentials: credentials,
            env: env,
            request: { accessToken, accountId, requestEnvironment in
                try await CodexOAuthUsageFetcher.fetchRateLimitResetCredits(
                    accessToken: accessToken,
                    accountId: accountId,
                    env: requestEnvironment)
            })
    }

    private nonisolated static func fetchCodexResetCredits(
        credentials: CodexOAuthCredentials,
        env: [String: String],
        request: @escaping @Sendable (String, String?, [String: String]) async throws
            -> CodexRateLimitResetCreditsSnapshot?) async throws -> CodexRateLimitResetCreditsSnapshot?
    {
        try Task.checkCancellation()
        // Supplemental inventory is strictly read-only. The main OAuth usage strategy owns token refreshes;
        // CLI/web winners with stale credentials simply skip this best-effort GET.
        guard !credentials.needsRefresh else { return nil }
        return try await request(credentials.accessToken, credentials.accountId, env)
    }

    nonisolated static func _fetchCodexResetCreditsForTesting(
        credentials: CodexOAuthCredentials,
        env: [String: String] = [:],
        request: @escaping @Sendable (String, String?, [String: String]) async throws
            -> CodexRateLimitResetCreditsSnapshot?) async throws -> CodexRateLimitResetCreditsSnapshot?
    {
        try await self.fetchCodexResetCredits(credentials: credentials, env: env, request: request)
    }
}

extension ProviderFetchOutcome {
    func replacingUsage(_ usage: UsageSnapshot) -> ProviderFetchOutcome {
        guard case let .success(result) = self.result else { return self }
        return ProviderFetchOutcome(
            result: .success(ProviderFetchResult(
                usage: usage,
                credits: result.credits,
                dashboard: result.dashboard,
                sourceLabel: result.sourceLabel,
                strategyID: result.strategyID,
                strategyKind: result.strategyKind,
                diagnostic: result.diagnostic,
                claudeOAuthKeychainPersistentRefHash: result.claudeOAuthKeychainPersistentRefHash,
                claudeOAuthHistoryOwnerIdentifier: result.claudeOAuthHistoryOwnerIdentifier,
                claudeOAuthKeychainCredentialMismatch: result.claudeOAuthKeychainCredentialMismatch,
                claudeOAuthKeychainCredentialAbsent: result.claudeOAuthKeychainCredentialAbsent,
                claudeOAuthKeychainCredentialUnavailable: result.claudeOAuthKeychainCredentialUnavailable)),
            attempts: self.attempts)
    }

    fileprivate func replacingResult(
        with result: Result<ProviderFetchResult, Error>) -> ProviderFetchOutcome
    {
        ProviderFetchOutcome(result: result, attempts: self.attempts)
    }
}
