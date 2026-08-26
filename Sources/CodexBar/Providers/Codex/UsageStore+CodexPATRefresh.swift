import CodexBarCore
import Foundation

extension UsageStore {
    func shouldUseAmbientCodexPATForUsage() -> Bool {
        switch self.settings.codexUsageDataSource {
        case .pat:
            true
        case .auto:
            (try? CodexOAuthCredentialsStore.loadPATResolvingScopedHome(env: self.codexFetchEnvironment()))
                != nil
        case .oauth, .cli:
            false
        }
    }

    func codexFetchEnvironment() -> [String: String] {
        // Provider-specific by design: PAT admission reads the selected Codex CODEX_HOME fetch environment.
        ProviderRegistry.makeEnvironment(
            base: self.environmentBase,
            provider: .codex,
            settings: self.settings,
            tokenOverride: nil)
    }

    struct CodexRefreshOutcomeResolution {
        let provider: UsageProvider
        let initialOutcome: ProviderFetchOutcome
        let expectedGuard: CodexAccountScopedRefreshGuard?
        let previousSnapshot: UsageSnapshot?
        let previousSourceLabel: String?
        let missingWindowBackfillSnapshot: UsageSnapshot?
        let pendingWeeklyResetCandidate: CodexWeeklyResetPublicationCandidate?
        let fetchOutcome: @Sendable () async -> ProviderFetchOutcome
        let generation: UInt64
    }

    nonisolated static func isCodexPATOutcome(_ outcome: ProviderFetchOutcome) -> Bool {
        guard case let .success(result) = outcome.result else { return false }
        return result.strategyID == "codex.pat" || result.sourceLabel == "pat"
    }

    nonisolated static func codexPublicationRefreshOverrides(
        provider: UsageProvider,
        outcome: ProviderFetchOutcome,
        explicitPAT: Bool,
        expectedGuard: CodexAccountScopedRefreshGuard?,
        limitResetOwnerKey: CodexLimitResetOwnerKey?) -> (
        CodexAccountScopedRefreshGuard?,
        CodexLimitResetOwnerKey?)
    {
        let publishesPAT = provider == .codex && self.isCodexPATOutcome(outcome)
        let explicitPATFailure = explicitPAT && {
            if case .failure = outcome.result {
                return true
            }
            return false
        }()
        if publishesPAT || explicitPATFailure {
            return (nil, publishesPAT ? nil : limitResetOwnerKey)
        }
        return (expectedGuard, limitResetOwnerKey)
    }

    func resolvedCodexRefreshOutcome(
        _ resolution: CodexRefreshOutcomeResolution) async -> ProviderFetchOutcome?
    {
        guard resolution.provider == .codex else { return resolution.initialOutcome }
        if case let .success(result) = resolution.initialOutcome.result,
           !Self.isCodexPATOutcome(resolution.initialOutcome),
           let expectedGuard = resolution.expectedGuard,
           !self.shouldApplyCodexUsageResult(
               expectedGuard: expectedGuard,
               usage: result.usage.scoped(to: .codex))
        {
            self.retireCodexStateIfRefreshOwnerChanged(
                expectedGuard: expectedGuard,
                generation: resolution.generation)
            return nil
        }
        let admission = await Self.codexOutcomeAdmittedForPublication(
            initialOutcome: resolution.initialOutcome,
            previousSnapshot: resolution.previousSnapshot,
            previousSourceLabel: resolution.previousSourceLabel,
            missingWindowBackfillSnapshot: resolution.missingWindowBackfillSnapshot,
            pendingCandidate: resolution.pendingWeeklyResetCandidate,
            fetchConfirmation: resolution.fetchOutcome)
        self.persistCodexWeeklyResetPublicationCandidate(
            admission.pendingCandidate,
            expectedGuard: resolution.expectedGuard,
            previousSnapshot: resolution.previousSnapshot)
        guard let admittedOutcome = admission.outcome else {
            if let expectedGuard = resolution.expectedGuard {
                self.retireCodexStateIfRefreshOwnerChanged(
                    expectedGuard: expectedGuard,
                    generation: resolution.generation)
            }
            return nil
        }
        if case let .success(result) = admittedOutcome.result,
           !Self.isCodexPATOutcome(admittedOutcome),
           let expectedGuard = resolution.expectedGuard,
           !self.shouldApplyCodexUsageResult(
               expectedGuard: expectedGuard,
               usage: result.usage.scoped(to: .codex))
        {
            self.retireCodexStateIfRefreshOwnerChanged(
                expectedGuard: expectedGuard,
                generation: resolution.generation)
            return nil
        }
        return admittedOutcome
    }

    func recordCodexRefreshSuccessPublication(
        scoped: UsageSnapshot,
        backfilled: UsageSnapshot,
        result: ProviderFetchResult,
        expectedGuard: CodexAccountScopedRefreshGuard?,
        expectedOwnerKey: CodexLimitResetOwnerKey?)
    {
        self.rememberLiveSystemCodexEmailIfNeeded(scoped.accountEmail(for: .codex))
        let publishesPAT = result.strategyID == "codex.pat" || result.sourceLabel == "pat"
        if publishesPAT {
            let publicationSource: CodexActiveSource = switch result.codexPATCredentialOwner {
            case let .scopedCodexHome(path):
                self.codexPATSource(forCredentialHome: path)
            default:
                .liveSystem
            }
            self.seedCodexPATRefreshGuard(
                source: publicationSource,
                accountEmail: scoped.accountEmail(for: .codex))
        } else {
            self.seedCodexAccountScopedRefreshGuard(accountEmail: scoped.accountEmail(for: .codex))
        }
        self.lastCodexUsagePublicationGuard = self.lastCodexAccountScopedRefreshGuard
        self.persistSingleCodexAccountSnapshot(
            backfilled,
            sourceLabel: result.sourceLabel,
            expectedGuard: expectedGuard,
            expectedOwnerKey: expectedOwnerKey)
    }

    private func codexPATSource(forCredentialHome path: String) -> CodexActiveSource {
        let credentialHome = URL(fileURLWithPath: path).standardizedFileURL.path
        if let ambientHome = self.environmentBase["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ambientHome.isEmpty
        {
            let ambientCodexHome = URL(fileURLWithPath: ambientHome, isDirectory: true)
                .appendingPathComponent(".codex", isDirectory: true)
                .standardizedFileURL.path
            if credentialHome == ambientCodexHome {
                return .liveSystem
            }
        }
        return .profileHome(path: credentialHome)
    }

    private func persistSingleCodexAccountSnapshot(
        _ snapshot: UsageSnapshot,
        sourceLabel: String,
        expectedGuard: CodexAccountScopedRefreshGuard?,
        expectedOwnerKey: CodexLimitResetOwnerKey?)
    {
        guard let expectedGuard,
              let expectedOwnerKey
        else { return }

        let currentGuard = self.freshCodexAccountScopedRefreshGuard()
        guard Self.codexScopedRefreshGuardsMatchAccount(expectedGuard, currentGuard),
              let currentOwnerKey = CodexLimitResetOwnerKey(
                  identity: currentGuard.identity,
                  accountEmail: currentGuard.accountKey),
              currentOwnerKey == expectedOwnerKey
        else { return }

        let visibleAccounts = self.freshCodexVisibleAccountsForSnapshotHydration()
        let activeMatches = visibleAccounts.filter {
            $0.isActive &&
                $0.selectionSource == currentGuard.source &&
                CodexIdentityResolver.normalizeEmail($0.email) == currentGuard.accountKey
        }
        guard activeMatches.count == 1,
              let account = activeMatches.first,
              let snapshotEmail = CodexIdentityResolver.normalizeEmail(snapshot.accountEmail(for: .codex)),
              snapshotEmail == CodexIdentityResolver.normalizeEmail(currentGuard.accountKey),
              snapshotEmail == CodexIdentityResolver.normalizeEmail(account.email),
              self.codexLimitResetOwnerKey(
                  forVisibleAccount: account,
                  visibleAccounts: visibleAccounts) == currentOwnerKey
        else { return }

        let identity = snapshot.identity(for: .codex)
        let relabeled = snapshot.withIdentity(ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: account.email,
            accountOrganization: identity?.accountOrganization,
            loginMethod: identity?.loginMethod ?? account.workspaceLabel))
        let currentSnapshots = [CodexAccountUsageSnapshot(
            account: account,
            snapshot: relabeled,
            error: nil,
            sourceLabel: sourceLabel)]
        self.codexAccountSnapshots = currentSnapshots
        self.codexAccountUsageSnapshotStore?.store(currentSnapshots)
    }
}
