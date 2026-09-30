import CodexBarCore
import Foundation

enum CodexSubscriptionMetadataEnrichmentPolicy {
    static func expectedEmail(
        input: CodexDashboardAuthorityInput,
        decision: CodexDashboardAuthorityDecision) -> String?
    {
        guard input.sourceKind == .liveWeb,
              decision.disposition == .attach,
              !input.proof.requiresWorkspaceBalanceScope,
              ManagedCodexAccount.normalizeWorkspaceAccountID(input.proof.dashboardAccountID) == nil,
              case let .emailOnly(identityEmail) = input.proof.currentIdentity,
              let normalizedIdentityEmail = CodexIdentityResolver.normalizeEmail(identityEmail),
              CodexIdentityResolver.normalizeEmail(input.proof.expectedScopedEmail) == normalizedIdentityEmail,
              CodexIdentityResolver.normalizeEmail(input.proof.dashboardSignedInEmail) == normalizedIdentityEmail
        else { return nil }
        return normalizedIdentityEmail
    }
}

@MainActor
private enum CodexSubscriptionMetadataEnrichmentRegistry {
    private struct Entry {
        let key: String
        let token: UUID
    }

    private static var entries: [ObjectIdentifier: Entry] = [:]

    static func begin(for store: UsageStore, key: String) -> UUID? {
        let storeID = ObjectIdentifier(store)
        guard self.entries[storeID]?.key != key else { return nil }
        let token = UUID()
        self.entries[storeID] = Entry(key: key, token: token)
        return token
    }

    static func isCurrent(_ token: UUID, for store: UsageStore) -> Bool {
        self.entries[ObjectIdentifier(store)]?.token == token
    }

    static func finish(_ token: UUID, for store: UsageStore) {
        let storeID = ObjectIdentifier(store)
        guard self.entries[storeID]?.token == token else { return }
        self.entries.removeValue(forKey: storeID)
    }
}

#if DEBUG
enum CodexSubscriptionMetadataEnrichmentTestOverrides {
    typealias Loader = @MainActor @Sendable (String) async -> OpenAISubscriptionFetchResult
    typealias Completion = @MainActor @Sendable () -> Void

    @TaskLocal static var loader: Loader?
    @TaskLocal static var completion: Completion?
}
#endif

@MainActor
extension UsageStore {
    func scheduleCodexSubscriptionMetadataEnrichment(
        dashboard: OpenAIDashboardSnapshot,
        authorityInput: CodexDashboardAuthorityInput,
        decision: CodexDashboardAuthorityDecision,
        applicationContext: CodexOpenAIDashboardApplicationContext)
    {
        guard dashboard.subscriptionExpiresAt == nil,
              dashboard.subscriptionRenewsAt == nil,
              let expectedEmail = CodexSubscriptionMetadataEnrichmentPolicy.expectedEmail(
                  input: authorityInput,
                  decision: decision)
        else { return }

        let accountGuard = applicationContext.expectedGuard ?? self.freshCodexOpenAIWebRefreshGuard()
        guard case let .emailOnly(guardEmail) = accountGuard.identity,
              CodexIdentityResolver.normalizeEmail(guardEmail) == expectedEmail,
              CodexIdentityResolver.normalizeEmail(accountGuard.accountKey) == expectedEmail
        else { return }

        let key = [
            expectedEmail,
            String(dashboard.updatedAt.timeIntervalSince1970),
            String(describing: accountGuard.source),
            String(describing: accountGuard.identity),
            accountGuard.authFingerprint ?? "",
        ].joined(separator: "\0")
        guard let enrichmentToken = CodexSubscriptionMetadataEnrichmentRegistry.begin(for: self, key: key) else {
            return
        }

        Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            defer {
                CodexSubscriptionMetadataEnrichmentRegistry.finish(enrichmentToken, for: self)
                #if DEBUG
                CodexSubscriptionMetadataEnrichmentTestOverrides.completion?()
                #endif
            }
            guard self.isCurrentCodexSubscriptionMetadataEnrichment(
                enrichmentToken,
                dashboard: dashboard,
                expectedEmail: expectedEmail,
                accountGuard: accountGuard,
                refreshTaskToken: applicationContext.refreshTaskToken)
            else { return }

            let result = await self.fetchCodexSubscriptionMetadata(
                expectedEmail,
                cacheScope: applicationContext.cacheScope)
            guard case let .success(metadata) = result,
                  self.isCurrentCodexSubscriptionMetadataEnrichment(
                      enrichmentToken,
                      dashboard: dashboard,
                      expectedEmail: expectedEmail,
                      accountGuard: accountGuard,
                      refreshTaskToken: applicationContext.refreshTaskToken)
            else { return }

            let enrichedDashboard = dashboard.withSubscriptionMetadata(metadata)
            self.openAIDashboard = enrichedDashboard
            self.lastOpenAIDashboardSnapshot = enrichedDashboard
            OpenAIDashboardCacheStore.save(OpenAIDashboardCache(
                accountEmail: expectedEmail,
                snapshot: enrichedDashboard))

            if let currentUsage = self.snapshots[.codex],
               let publicationGuard = self.lastCodexUsagePublicationGuard,
               Self.codexScopedRefreshGuardsMatchAccount(publicationGuard, accountGuard),
               CodexIdentityResolver.normalizeEmail(currentUsage.accountEmail(for: .codex)) == expectedEmail
            {
                self.snapshots[.codex] = currentUsage.withSubscriptionMetadata(
                    expiresAt: metadata?.expiresAt,
                    renewsAt: metadata?.renewsAt)
            }
            self.persistWidgetSnapshot(reason: "codex-subscription-metadata")
        }
    }

    private func fetchCodexSubscriptionMetadata(
        _ expectedEmail: String,
        cacheScope: CookieHeaderCache.Scope?) async -> OpenAISubscriptionFetchResult
    {
        #if DEBUG
        if let loader = CodexSubscriptionMetadataEnrichmentTestOverrides.loader {
            return await loader(expectedEmail)
        }
        #endif
        return await OpenAIDashboardFetcher().fetchSubscriptionMetadata(
            accountEmail: expectedEmail,
            cacheScope: cacheScope,
            logger: { [weak self] line in self?.logOpenAIWeb(line) },
            timeout: 8,
            expectedSignedInEmail: expectedEmail)
    }

    private func isCurrentCodexSubscriptionMetadataEnrichment(
        _ enrichmentToken: UUID,
        dashboard: OpenAIDashboardSnapshot,
        expectedEmail: String,
        accountGuard: CodexAccountScopedRefreshGuard,
        refreshTaskToken: UUID?) -> Bool
    {
        guard !Task.isCancelled,
              CodexSubscriptionMetadataEnrichmentRegistry.isCurrent(enrichmentToken, for: self),
              self.openAIDashboardAttachmentAuthorized,
              self.openAIDashboard == dashboard,
              self.openAIDashboardRefreshTaskToken == nil ||
              self.openAIDashboardRefreshTaskToken == refreshTaskToken,
              self.shouldApplyOpenAIDashboardRefreshGuard(
                  expectedGuard: accountGuard,
                  routingTargetEmail: expectedEmail)
        else { return false }

        let currentAuthority = self.evaluateCodexDashboardAuthority(
            dashboard: dashboard,
            sourceKind: .liveWeb,
            routingTargetEmail: expectedEmail)
        return CodexSubscriptionMetadataEnrichmentPolicy.expectedEmail(
            input: currentAuthority.input,
            decision: currentAuthority.decision) == expectedEmail
    }
}
