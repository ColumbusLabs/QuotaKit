import CodexBarCore
import Foundation

struct SpendDashboardCodexCostCatchUpContext: Sendable {
    let token: UUID
    let accounts: [CodexSpendScanRequest]
    let historyDays: Int
    let scopeSignature: String
    let pauseScopeSignature: String
    let providerConfigRevision: UInt64
    let costUsageSettingsRevision: UInt64
}

extension UsageStore {
    /// Whether a currently visible dashboard surface explicitly requires
    /// full-year Codex history (#160). This is ephemeral active demand
    /// (`SpendDashboardController.activeRequestedHistoryDays == scanDays`),
    /// not the persisted `SpendDashboardController.selectedDays` preference:
    /// a persisted All selection with the dashboard closed must read false so
    /// routine background work stays bounded.
    var spendDashboardExtendedCodexHistoryRequired: Bool {
        self.sharedSpendDashboardControllerStorage?.activeRequestedHistoryDays == SpendDashboardSource.scanDays
    }

    /// Effective Codex history horizon for dashboard snapshot/activity loading
    /// (#160). Always the `SpendDashboardSource.requiredCodexHistoryDays`
    /// policy value: `max(configured routine window, active visible dashboard
    /// demand)`. In particular this no longer escalates to the full scan
    /// window merely because the primary cache worker converged, because the
    /// account cache is independent of the ambient worker, or because a
    /// persisted dashboard range happens to be wide while the dashboard is
    /// closed.
    var spendDashboardCodexHistoryDays: Int {
        SpendDashboardSource.requiredCodexHistoryDays(
            configuredWindowDays: self.settings.costUsageHistoryDays,
            activeDashboardRequestedDays: self.sharedSpendDashboardControllerStorage?.activeRequestedHistoryDays)
    }

    private func codexCostCatchUpUsesPrimaryCache(_ account: CodexSpendScanRequest) -> Bool {
        // The primary worker owns the ambient Codex cache only when the normal token-cost
        // scope is ambient as well. A managed/profile selection can still coexist with the
        // live account, but its home path must not reuse the ambient cursor/checkpoint.
        guard account.source == .liveSystem,
              self.tokenCostScope(for: .codex).codexHomePath == nil
        else { return false }
        let primaryCacheRoot = Self.costUsageCacheDirectory()
            .deletingLastPathComponent()
            .standardizedFileURL
        return SpendDashboardSource.codexCacheRoot(for: account).standardizedFileURL == primaryCacheRoot
    }

    func synchronizeSpendDashboardCodexCostCatchUp(
        accounts: [CodexSpendScanRequest],
        preferredMode: CodexCostCatchUpMode? = nil)
    {
        let allAccounts = Self.uniqueSpendDashboardCodexAccounts(accounts)
        guard !allAccounts.isEmpty,
              self.settings.isCostUsageEffectivelyEnabled(for: .codex),
              self.isEnabled(.codex)
        else {
            self.cancelSpendDashboardCodexCostCatchUp()
            return
        }
        // A user-requested stop must stay durable until they explicitly resume; background
        // synchronization would otherwise restart the worker behind their back.
        guard !self.spendDashboardCodexCostCatchUpStopRequested else { return }
        var mode = preferredMode
            ?? (self.spendDashboardCodexCostCatchUpUsesPrimaryWorker
                ? self.codexCostCatchUpMode
                : self.spendDashboardCodexCostCatchUpTask == nil
                ? .automatic
                : self.spendDashboardCodexCostCatchUpMode)
        if preferredMode == .accelerated,
           self.spendDashboardCodexCostCatchUpTask == nil
           || self.spendDashboardCodexCostCatchUpMode != .accelerated,
           case .pause = self.codexCostCatchUpDecision(
               mode: .automatic,
               previousActiveDuration: nil,
               resourceState: self._test_spendDashboardCodexCostCatchUpResourceStateOverride?()).action
        {
            mode = .automatic
        }
        let sharedAccounts = allAccounts.filter(self.codexCostCatchUpUsesPrimaryCache)
        let independentAccounts = allAccounts.filter { !self.codexCostCatchUpUsesPrimaryCache($0) }
        if !sharedAccounts.isEmpty {
            self.spendDashboardCodexCostCatchUpUsesPrimaryWorker = true
            self.spendDashboardCodexCostCatchUpActivity = self.codexCostCatchUpActivity
            // #160 correction: the shared primary cache must converge the
            // active dashboard horizon, not just the configured routine
            // window. `spendDashboardCodexHistoryDays` is
            // `max(routine, active)` so closed stays routine while visible
            // 90/All widens the same serialized primary worker.
            self.startCodexCostCatchUpIfNeeded(
                mode: mode,
                requestedHistoryDays: self.spendDashboardCodexHistoryDays,
                resumePaused: false)
        } else {
            self.reconcilePrimaryWorkerAfterSharedDashboardScopeChange()
        }
        if independentAccounts.isEmpty {
            self.clearSpendDashboardCodexCostCatchUpWorker()
        } else {
            self.startSpendDashboardCodexCostCatchUpIfNeeded(
                accounts: independentAccounts,
                mode: mode,
                resumePaused: false)
        }
    }

    /// Withdraws dashboard-only widening from the shared primary worker when
    /// the dashboard no longer shares that cache. Independent 90/All demand
    /// must never widen the ambient cache, so the primary target is the
    /// configured routine window. Touches the primary worker only when it
    /// exists to avoid spawning routine work from a dashboard-only sync.
    private func reconcilePrimaryWorkerAfterSharedDashboardScopeChange() {
        let wasUsingPrimary = self.spendDashboardCodexCostCatchUpUsesPrimaryWorker
        self.spendDashboardCodexCostCatchUpUsesPrimaryWorker = false
        guard wasUsingPrimary,
              self.codexCostCatchUpTask != nil || self.codexCostCatchUpProgressProbeTask != nil
        else { return }
        self.startCodexCostCatchUpIfNeeded(
            mode: self.codexCostCatchUpMode,
            requestedHistoryDays: self.settings.costUsageHistoryDays,
            resumePaused: false)
    }

    func startSpendDashboardCodexCostCatchUpIfNeeded(
        accounts: [CodexSpendScanRequest],
        mode: CodexCostCatchUpMode = .automatic,
        resumePaused: Bool = true)
    {
        let allAccounts = Self.uniqueSpendDashboardCodexAccounts(accounts)
        guard !allAccounts.isEmpty,
              self.settings.isCostUsageEffectivelyEnabled(for: .codex),
              self.isEnabled(.codex)
        else {
            self.cancelSpendDashboardCodexCostCatchUp()
            return
        }

        let sharedAccounts = allAccounts.filter(self.codexCostCatchUpUsesPrimaryCache)
        let accounts = allAccounts.filter { !self.codexCostCatchUpUsesPrimaryCache($0) }
        if !sharedAccounts.isEmpty {
            self.spendDashboardCodexCostCatchUpUsesPrimaryWorker = true
            self.spendDashboardCodexCostCatchUpActivity = self.codexCostCatchUpActivity
            if resumePaused {
                self.spendDashboardCodexCostCatchUpStopRequested = false
            }
            // Same shared-primary policy as `synchronize...`: propagate
            // active 90/All demand to the serialized primary worker.
            self.startCodexCostCatchUpIfNeeded(
                mode: mode,
                requestedHistoryDays: self.spendDashboardCodexHistoryDays,
                resumePaused: resumePaused)
        } else {
            self.reconcilePrimaryWorkerAfterSharedDashboardScopeChange()
        }
        guard !accounts.isEmpty else {
            self.clearSpendDashboardCodexCostCatchUpWorker()
            return
        }

        // #160: the worker scans exactly the dashboard policy horizon. It must
        // not independently widen to the full scan window; expansion to 90/365
        // happens only through `spendDashboardCodexHistoryDays` when the
        // visible dashboard actively demands it (or a 365-day configured
        // window requires it), which also rotates this scope signature so
        // stale narrower work cannot satisfy the broader scope.
        let historyDays = self.spendDashboardCodexHistoryDays
        let accountScopeSignature = accounts
            .map { "\($0.id)|\($0.cacheIdentity)" }
            .joined(separator: "\u{0}")
        let scopeSignature = "\(historyDays)\u{0}\(accountScopeSignature)"
        let providerConfigRevision = self.settings.providerConfigRevision(for: .codex)
        let pauseScopeSignature = "\(scopeSignature)\u{0}providerConfig=\(providerConfigRevision)"
        if !resumePaused,
           self.spendDashboardCodexCostCatchUpTask == nil,
           self.spendDashboardCodexCostCatchUpActivity?.requiresExplicitResume == true
        {
            if self.spendDashboardCodexCostCatchUpActivity?.pauseReason == .noProgress,
               let pausedContext = self.spendDashboardCodexCostCatchUpPausedContext,
               accounts.map(\.cacheIdentity) == pausedContext.accounts.map(\.cacheIdentity),
               pausedContext.scopeSignature == scopeSignature,
               pausedContext.pauseScopeSignature == pauseScopeSignature
            {
                self.checkSpendDashboardCodexCostCatchUpCompletion(
                    accounts: accounts,
                    context: pausedContext)
            } else {
                self.spendDashboardCodexCostCatchUpCompletionProbeTask?.cancel()
                self.spendDashboardCodexCostCatchUpCompletionProbeTask = nil
                self.spendDashboardCodexCostCatchUpCompletionProbeToken = nil
            }
            return
        }
        if !resumePaused,
           self.spendDashboardCodexCostCatchUpTask == nil,
           self.spendDashboardCodexCostCatchUpPausedScopeSignature == pauseScopeSignature
        {
            self.scheduleSpendDashboardCodexCostCatchUpProgressProbe(
                accounts: accounts,
                mode: mode,
                pauseScopeSignature: pauseScopeSignature)
            return
        }
        if self.spendDashboardCodexCostCatchUpTask != nil,
           self.spendDashboardCodexCostCatchUpScopeSignature == scopeSignature
        {
            if self.spendDashboardCodexCostCatchUpMode == mode {
                // Repeated dashboard observations are coalesced. A stalled semantic progress
                // key is resumed only by a real source change or an explicit request/scope/mode
                // change.
                return
            }
            self.spendDashboardCodexCostCatchUpMode = mode
            // A bounded parser pass may be committing a resume checkpoint. Let it finish and
            // apply the new mode before scheduling the next account instead of cancelling it.
            if self.spendDashboardCodexCostCatchUpPassIsRunning {
                return
            }
        }

        self.clearSpendDashboardCodexCostCatchUpWorker()
        let token = UUID()
        let context = SpendDashboardCodexCostCatchUpContext(
            token: token,
            accounts: accounts,
            historyDays: historyDays,
            scopeSignature: scopeSignature,
            pauseScopeSignature: pauseScopeSignature,
            providerConfigRevision: providerConfigRevision,
            costUsageSettingsRevision: self.settings.costUsageSettingsRevision)
        self.spendDashboardCodexCostCatchUpToken = token
        self.spendDashboardCodexCostCatchUpScopeSignature = scopeSignature
        self.spendDashboardCodexCostCatchUpMode = mode
        self.spendDashboardCodexCostCatchUpStopRequested = false
        self.spendDashboardCodexCostCatchUpPassIsRunning = false
        self.spendDashboardCodexCostCatchUpPausedScopeSignature = nil
        self.spendDashboardCodexCostCatchUpPausedProgressKey = nil
        let priority: TaskPriority = mode == .accelerated ? .utility : .background
        self.spendDashboardCodexCostCatchUpTask = Task(priority: priority) { @MainActor [weak self] in
            guard let self else { return }
            defer {
                // Catch-up parses the large Codex cache in bounded passes. Ask malloc to return
                // free pages after every worker lifetime, including cancellation and failures.
                self.scheduleMemoryPressureRelief()
                if self.spendDashboardCodexCostCatchUpToken == token {
                    // Scope invalidation can exit without publishing a terminal activity.
                    if self.spendDashboardCodexCostCatchUpActivity?.phase == .indexing {
                        self.spendDashboardCodexCostCatchUpActivity = nil
                    }
                    self.spendDashboardCodexCostCatchUpTask = nil
                    self.spendDashboardCodexCostCatchUpToken = nil
                    self.spendDashboardCodexCostCatchUpScopeSignature = nil
                    if self.spendDashboardCodexCostCatchUpRestartRequested {
                        self.spendDashboardCodexCostCatchUpRestartRequested = false
                        self.startSpendDashboardCodexCostCatchUpIfNeeded(
                            accounts: context.accounts,
                            mode: self.spendDashboardCodexCostCatchUpMode)
                    }
                }
            }
            await self.runSpendDashboardCodexCostCatchUp(context: context)
        }
    }

    func stopSpendDashboardCodexCostCatchUp() {
        guard self.spendDashboardCodexCostCatchUpTask != nil
            || self.spendDashboardCodexCostCatchUpUsesPrimaryWorker
            || self.spendDashboardCodexCostCatchUpProgressProbeTask != nil
            || self.spendDashboardCodexCostCatchUpCompletionProbeTask != nil
        else { return }
        self.spendDashboardCodexCostCatchUpCompletionProbeTask?.cancel()
        self.spendDashboardCodexCostCatchUpCompletionProbeTask = nil
        self.spendDashboardCodexCostCatchUpCompletionProbeToken = nil
        self.spendDashboardCodexCostCatchUpPausedContext = nil
        if self.spendDashboardCodexCostCatchUpUsesPrimaryWorker {
            self.stopCodexCostCatchUp()
            self.spendDashboardCodexCostCatchUpStopRequested = true
            self.spendDashboardCodexCostCatchUpActivity = self.codexCostCatchUpActivity
            self.spendDashboardCodexCostCatchUpUsesPrimaryWorker = false
        }
        guard self.spendDashboardCodexCostCatchUpTask != nil else {
            self.spendDashboardCodexCostCatchUpProgressProbeTask?.cancel()
            self.spendDashboardCodexCostCatchUpProgressProbeTask = nil
            self.spendDashboardCodexCostCatchUpStopRequested = true
            if let activity = self.spendDashboardCodexCostCatchUpActivity {
                self.spendDashboardCodexCostCatchUpActivity = CodexCostCatchUpActivity(
                    phase: .paused,
                    mode: activity.mode,
                    processedBytes: activity.processedBytes,
                    totalBytes: activity.totalBytes,
                    completedFiles: activity.completedFiles,
                    totalFiles: activity.totalFiles,
                    pauseReason: .user,
                    staleSnapshotUpdatedAt: activity.staleSnapshotUpdatedAt)
            }
            return
        }
        self.spendDashboardCodexCostCatchUpStopRequested = true
        self.spendDashboardCodexCostCatchUpRestartRequested = false
        self.scheduleMemoryPressureRelief()
        guard !self.spendDashboardCodexCostCatchUpPassIsRunning else { return }
        if let activity = self.spendDashboardCodexCostCatchUpActivity {
            self.spendDashboardCodexCostCatchUpActivity = CodexCostCatchUpActivity(
                phase: .paused,
                mode: activity.mode,
                processedBytes: activity.processedBytes,
                totalBytes: activity.totalBytes,
                completedFiles: activity.completedFiles,
                totalFiles: activity.totalFiles,
                pauseReason: .user,
                staleSnapshotUpdatedAt: activity.staleSnapshotUpdatedAt)
        }
        self.spendDashboardCodexCostCatchUpTask?.cancel()
        self.spendDashboardCodexCostCatchUpTask = nil
        self.spendDashboardCodexCostCatchUpToken = nil
        self.spendDashboardCodexCostCatchUpScopeSignature = nil
    }

    func cancelSpendDashboardCodexCostCatchUp() {
        self.clearSpendDashboardCodexCostCatchUpWorker()
        self.spendDashboardCodexCostCatchUpUsesPrimaryWorker = false
    }

    private func clearSpendDashboardCodexCostCatchUpWorker() {
        let hadWorker = self.spendDashboardCodexCostCatchUpTask != nil
        self.spendDashboardCodexCostCatchUpCompletionProbeTask?.cancel()
        self.spendDashboardCodexCostCatchUpCompletionProbeTask = nil
        self.spendDashboardCodexCostCatchUpCompletionProbeToken = nil
        self.spendDashboardCodexCostCatchUpTask?.cancel()
        self.spendDashboardCodexCostCatchUpProgressProbeTask?.cancel()
        if hadWorker {
            self.scheduleMemoryPressureRelief()
        }
        self.spendDashboardCodexCostCatchUpTask = nil
        self.spendDashboardCodexCostCatchUpToken = nil
        self.spendDashboardCodexCostCatchUpScopeSignature = nil
        self.spendDashboardCodexCostCatchUpStopRequested = false
        self.spendDashboardCodexCostCatchUpPassIsRunning = false
        self.spendDashboardCodexCostCatchUpRestartRequested = false
        self.spendDashboardCodexCostCatchUpPausedScopeSignature = nil
        self.spendDashboardCodexCostCatchUpPausedProgressKey = nil
        self.spendDashboardCodexCostCatchUpPausedContext = nil
        self.spendDashboardCodexCostCatchUpProgressProbeTask = nil
        self.spendDashboardCodexCostCatchUpActivity = nil
    }

    private func runSpendDashboardCodexCostCatchUp(
        context: SpendDashboardCodexCostCatchUpContext) async
    {
        var statuses = await self.loadSpendDashboardCodexCostCatchUpStatuses(
            context.accounts,
            historyDays: context.historyDays)
        guard self.spendDashboardCodexCostCatchUpContextIsCurrent(context) else { return }
        self.publishSpendDashboardCodexCostCatchUpActivity(
            statuses: statuses,
            context: context,
            phase: Self.spendDashboardCodexCatchUpIsPending(statuses) ? .indexing : .complete)

        var didChangeCache = false
        var previousActiveDuration: TimeInterval?
        var completedPasses = 0
        var recoveredCaches: Set<String> = []
        var (stalledCacheIdentities, seenKeysByCache) =
            (Set<String>(), statuses.mapValues { Set([$0.progressKey]) })
        while Self.spendDashboardCodexCatchUpIsPending(statuses) {
            do {
                guard self.spendDashboardCodexCostCatchUpContextIsCurrent(context) else { return }
                if self.spendDashboardCodexCostCatchUpStopRequested {
                    self.publishSpendDashboardCodexCostCatchUpActivity(
                        statuses: statuses,
                        context: context,
                        phase: .paused,
                        pauseReason: .user)
                    self.publishSpendDashboardCodexCostCatchUpRevisionIfNeeded(didChangeCache)
                    return
                }

                guard let account = context.accounts.first(where: {
                    statuses[$0.cacheIdentity]?.pending == true
                        && !stalledCacheIdentities.contains($0.cacheIdentity)
                }) else {
                    self.spendDashboardCodexCostCatchUpPausedScopeSignature = context.pauseScopeSignature
                    self.spendDashboardCodexCostCatchUpPausedProgressKey =
                        Self.spendDashboardCodexCostCatchUpProgressKey(statuses)
                    self.publishSpendDashboardCodexCostCatchUpActivity(
                        statuses: statuses,
                        context: context,
                        phase: .paused,
                        pauseReason: .noProgress)
                    self.publishSpendDashboardCodexCostCatchUpRevisionIfNeeded(didChangeCache)
                    CodexBarLog.logger(LogCategories.tokenCost).warning(
                        "Spend Dashboard Codex cost catch-up stopped because all pending account caches stalled")
                    return
                }

                let decision = self.codexCostCatchUpDecision(
                    mode: self.spendDashboardCodexCostCatchUpMode,
                    previousActiveDuration: previousActiveDuration,
                    completedPasses: completedPasses,
                    resourceState: self._test_spendDashboardCodexCostCatchUpResourceStateOverride?())
                switch decision.action {
                case let .pause(delay, reason):
                    self.publishSpendDashboardCodexCostCatchUpActivity(
                        statuses: statuses,
                        context: context,
                        phase: .paused,
                        pauseReason: reason)
                    try await self.sleepBetweenCodexCostCatchUpPasses(seconds: delay, dashboard: true)
                    continue
                case let .runAfter(delay):
                    self.publishSpendDashboardCodexCostCatchUpActivity(
                        statuses: statuses,
                        context: context,
                        phase: .indexing)
                    if delay > 0 || self.spendDashboardCodexCostCatchUpMode == .accelerated {
                        previousActiveDuration = nil
                        completedPasses = 0
                    }
                    try await self.sleepBetweenCodexCostCatchUpPasses(seconds: delay, dashboard: true)
                }

                try Task.checkCancellation()
                guard self.spendDashboardCodexCostCatchUpContextIsCurrent(context) else { return }
                if self.spendDashboardCodexCostCatchUpStopRequested {
                    self.publishSpendDashboardCodexCostCatchUpActivity(
                        statuses: statuses,
                        context: context,
                        phase: .paused,
                        pauseReason: .user)
                    self.publishSpendDashboardCodexCostCatchUpRevisionIfNeeded(didChangeCache)
                    return
                }

                let previousStatus = statuses[account.cacheIdentity]
                let result = try await self.advanceSpendDashboardCodexCostCatchUp(
                    context: context,
                    account: account,
                    now: Date(),
                    historyDays: context.historyDays,
                    previousActiveDuration: previousActiveDuration)
                let nextStatus = result.value
                previousActiveDuration = (previousActiveDuration ?? 0) + result.activeDuration
                completedPasses += 1
                didChangeCache = didChangeCache || nextStatus.progressKey != previousStatus?.progressKey
                if nextStatus.progressKey != previousStatus?.progressKey {
                    self.spendDashboardCodexCostCatchUpPausedScopeSignature = nil
                    self.spendDashboardCodexCostCatchUpPausedProgressKey = nil
                    self.spendDashboardCodexCostCatchUpPausedContext = nil
                }
                statuses[account.cacheIdentity] = nextStatus
                if nextStatus.pending,
                   !seenKeysByCache[account.cacheIdentity, default: []].insert(nextStatus.progressKey).inserted
                {
                    if nextStatus.progressKey == previousStatus?.progressKey,
                       nextStatus.yieldedBeforeFileAttempt,
                       recoveredCaches.insert(account.cacheIdentity).inserted
                    {
                        previousActiveDuration = max(
                            previousActiveDuration ?? 0,
                            CodexCostCatchUpPolicy.automaticBurstDuration)
                    } else {
                        stalledCacheIdentities.insert(account.cacheIdentity)
                    }
                } else {
                    stalledCacheIdentities.remove(account.cacheIdentity)
                }

                guard self.spendDashboardCodexCostCatchUpContextIsCurrent(context) else { return }
                let isPending = Self.spendDashboardCodexCatchUpIsPending(statuses)
                self.publishSpendDashboardCodexCostCatchUpActivity(
                    statuses: statuses,
                    context: context,
                    phase: isPending ? .indexing : .complete)
                if self.spendDashboardCodexCostCatchUpStopRequested {
                    self.publishSpendDashboardCodexCostCatchUpActivity(
                        statuses: statuses,
                        context: context,
                        phase: .paused,
                        pauseReason: .user)
                    self.publishSpendDashboardCodexCostCatchUpRevisionIfNeeded(didChangeCache)
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.spendDashboardCodexCostCatchUpContextIsCurrent(context) else { return }
                self.publishSpendDashboardCodexCostCatchUpActivity(
                    statuses: statuses,
                    context: context,
                    phase: .paused,
                    pauseReason: .error(error.localizedDescription))
                self.publishSpendDashboardCodexCostCatchUpRevisionIfNeeded(didChangeCache)
                CodexBarLog.logger(LogCategories.tokenCost).warning(
                    "Spend Dashboard Codex cost catch-up stopped after error: \(error.localizedDescription)")
                return
            }
        }

        self.publishSpendDashboardCodexCostCatchUpRevisionIfNeeded(didChangeCache)
    }

    private func spendDashboardCodexCostCatchUpContextIsCurrent(
        _ context: SpendDashboardCodexCostCatchUpContext) -> Bool
    {
        !Task.isCancelled
            && self.spendDashboardCodexCostCatchUpToken == context.token
            && self.spendDashboardCodexCostCatchUpScopeSignature == context.scopeSignature
            && self.spendDashboardCodexCostCatchUpConfigurationIsCurrent(context)
    }

    private func spendDashboardCodexCostCatchUpConfigurationIsCurrent(
        _ context: SpendDashboardCodexCostCatchUpContext) -> Bool
    {
        self.settings.providerConfigRevision(for: .codex) == context.providerConfigRevision
            && self.settings.costUsageSettingsRevision == context.costUsageSettingsRevision
            && self.spendDashboardCodexHistoryDays == context.historyDays
            && self.settings.isCostUsageEffectivelyEnabled(for: .codex)
            && self.isEnabled(.codex)
            && context.accounts.allSatisfy(SpendDashboardSource.codexAuthFingerprintMatches)
    }

    private func checkSpendDashboardCodexCostCatchUpCompletion(
        accounts: [CodexSpendScanRequest],
        context: SpendDashboardCodexCostCatchUpContext)
    {
        guard self.spendDashboardCodexCostCatchUpCompletionProbeTask == nil,
              self.spendDashboardCodexCostCatchUpActivity?.pauseReason == .noProgress,
              self.spendDashboardCodexCostCatchUpTask == nil,
              accounts.map(\.cacheIdentity) == context.accounts.map(\.cacheIdentity),
              self.spendDashboardCodexCostCatchUpConfigurationIsCurrent(context)
        else { return }

        let probeToken = UUID()
        self.spendDashboardCodexCostCatchUpCompletionProbeToken = probeToken
        self.spendDashboardCodexCostCatchUpCompletionProbeTask = Task(priority: .background) { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.spendDashboardCodexCostCatchUpCompletionProbeToken == probeToken {
                    self.spendDashboardCodexCostCatchUpCompletionProbeTask = nil
                    self.spendDashboardCodexCostCatchUpCompletionProbeToken = nil
                }
            }

            let statuses = await self.loadSpendDashboardCodexCostCatchUpStatuses(
                accounts,
                historyDays: context.historyDays)
            guard !Task.isCancelled,
                  self.spendDashboardCodexCostCatchUpCompletionProbeToken == probeToken,
                  self.spendDashboardCodexCostCatchUpPausedContext?.token == context.token,
                  self.spendDashboardCodexCostCatchUpTask == nil,
                  !self.spendDashboardCodexCostCatchUpStopRequested,
                  self.spendDashboardCodexCostCatchUpActivity?.pauseReason == .noProgress,
                  self.spendDashboardCodexCostCatchUpConfigurationIsCurrent(context),
                  accounts.allSatisfy({ account in
                      let status = statuses[account.cacheIdentity]
                      return status?.pending == false && status?.completionIsConfirmed == true
                  })
            else { return }

            self.spendDashboardCodexCostCatchUpActivity?.phase = .complete
            self.spendDashboardCodexCostCatchUpActivity?.pauseReason = nil
            self.spendDashboardCodexCostCatchUpPausedScopeSignature = nil
            self.spendDashboardCodexCostCatchUpPausedProgressKey = nil
            self.spendDashboardCodexCostCatchUpPausedContext = nil
            self.spendDashboardCodexCostCatchUpRevision &+= 1
        }
    }

    private func loadSpendDashboardCodexCostCatchUpStatuses(
        _ accounts: [CodexSpendScanRequest],
        historyDays: Int? = nil) async -> [String: CostUsageFetcher.CodexScanCatchUpStatus]
    {
        var statuses: [String: CostUsageFetcher.CodexScanCatchUpStatus] = [:]
        for account in accounts {
            if let override = self._test_spendDashboardCodexCostCatchUpStatusOverride {
                statuses[account.cacheIdentity] = await override(account)
            } else {
                statuses[account.cacheIdentity] = await CostUsageFetcher(
                    cacheRoot: SpendDashboardSource.codexCacheRoot(for: account),
                    calendar: self.settings.costUsageBucketCalendar)
                    .codexScanCatchUpStatus(
                        codexHomePath: account.homePath,
                        calendar: self.settings.costUsageBucketCalendar,
                        historyDays: historyDays)
            }
        }
        return statuses
    }

    private func scheduleSpendDashboardCodexCostCatchUpProgressProbe(
        accounts: [CodexSpendScanRequest],
        mode: CodexCostCatchUpMode,
        pauseScopeSignature: String)
    {
        guard self.spendDashboardCodexCostCatchUpProgressProbeTask == nil,
              let stalledProgressKey = self.spendDashboardCodexCostCatchUpPausedProgressKey
        else { return }

        self.spendDashboardCodexCostCatchUpProgressProbeTask = Task(priority: .background) { @MainActor [weak self] in
            guard let self else { return }
            defer { self.spendDashboardCodexCostCatchUpProgressProbeTask = nil }

            let statuses = await self.loadSpendDashboardCodexCostCatchUpStatuses(
                accounts,
                historyDays: self.spendDashboardCodexHistoryDays)
            guard !Task.isCancelled,
                  self.spendDashboardCodexCostCatchUpTask == nil,
                  !self.spendDashboardCodexCostCatchUpStopRequested,
                  self.spendDashboardCodexCostCatchUpPausedScopeSignature == pauseScopeSignature,
                  self.spendDashboardCodexCostCatchUpPausedProgressKey == stalledProgressKey
            else { return }
            guard Self.spendDashboardCodexCostCatchUpProgressKey(statuses) != stalledProgressKey
            else { return }

            self.spendDashboardCodexCostCatchUpPausedScopeSignature = nil
            self.spendDashboardCodexCostCatchUpPausedProgressKey = nil
            self.spendDashboardCodexCostCatchUpProgressProbeTask = nil
            self.startSpendDashboardCodexCostCatchUpIfNeeded(
                accounts: accounts,
                mode: mode,
                resumePaused: false)
        }
    }

    private func advanceSpendDashboardCodexCostCatchUp(
        context: SpendDashboardCodexCostCatchUpContext,
        account: CodexSpendScanRequest,
        now: Date,
        historyDays: Int,
        previousActiveDuration: TimeInterval?) async throws
        -> CostUsageScanExecutor.TimedResult<CostUsageFetcher.CodexScanCatchUpStatus>
    {
        let durationBudget = self.spendDashboardCodexCostCatchUpMode
            .scanDurationPerRefresh(after: previousActiveDuration)
        self._test_codexCostCatchUpBudgetObserver?(durationBudget)
        self.spendDashboardCodexCostCatchUpPassIsRunning = true
        defer {
            if self.spendDashboardCodexCostCatchUpToken == context.token {
                self.spendDashboardCodexCostCatchUpPassIsRunning = false
            }
            self.scheduleMemoryPressureRelief()
        }
        if let override = self._test_spendDashboardCodexCostCatchUpAdvanceOverride {
            return try await .init(
                value: override(account, now, historyDays),
                activeDuration: self._test_spendDashboardCodexCostCatchUpActiveDuration)
        }
        return try await CostUsageFetcher(
            cacheRoot: SpendDashboardSource.codexCacheRoot(for: account),
            calendar: self.settings.costUsageBucketCalendar)
            .advanceCodexScanCatchUp(
                now: now,
                codexHomePath: account.homePath,
                historyDays: historyDays,
                scanDurationPerRefresh: durationBudget,
                calendar: self.settings.costUsageBucketCalendar)
    }

    private func publishSpendDashboardCodexCostCatchUpActivity(
        statuses: [String: CostUsageFetcher.CodexScanCatchUpStatus],
        context: SpendDashboardCodexCostCatchUpContext,
        phase: CodexCostCatchUpActivity.Phase,
        pauseReason: CodexCostCatchUpPauseReason? = nil)
    {
        guard self.spendDashboardCodexCostCatchUpToken == context.token else { return }
        if phase == .paused, let pauseReason {
            switch pauseReason {
            case .noProgress, .error:
                self.spendDashboardCodexCostCatchUpPausedContext = context
            case .lowPower, .thermal, .user:
                self.spendDashboardCodexCostCatchUpPausedContext = nil
            }
        } else if phase != .paused {
            self.spendDashboardCodexCostCatchUpPausedContext = nil
        }
        let values = context.accounts.compactMap { statuses[$0.cacheIdentity] }
        let hasIndeterminatePendingStatus = values.contains {
            $0.pending && $0.totalBytes == 0 && $0.totalFiles == 0
        }
        self.spendDashboardCodexCostCatchUpActivity = CodexCostCatchUpActivity(
            phase: phase,
            mode: self.spendDashboardCodexCostCatchUpMode,
            processedBytes: hasIndeterminatePendingStatus ? 0 : values.reduce(0) { $0 + $1.processedBytes },
            totalBytes: hasIndeterminatePendingStatus ? 0 : values.reduce(0) { $0 + $1.totalBytes },
            completedFiles: hasIndeterminatePendingStatus ? 0 : values.reduce(0) { $0 + $1.completedFiles },
            totalFiles: hasIndeterminatePendingStatus ? 0 : values.reduce(0) { $0 + $1.totalFiles },
            pauseReason: pauseReason,
            staleSnapshotUpdatedAt: values.compactMap(\.staleSnapshotUpdatedAt).min())
    }

    private func publishSpendDashboardCodexCostCatchUpRevisionIfNeeded(_ didChangeCache: Bool) {
        guard didChangeCache else { return }
        self.spendDashboardCodexCostCatchUpRevision &+= 1
    }

    private static func uniqueSpendDashboardCodexAccounts(
        _ accounts: [CodexSpendScanRequest]) -> [CodexSpendScanRequest]
    {
        var seen: Set<String> = []
        return accounts.filter { seen.insert($0.cacheIdentity).inserted }
    }

    private static func spendDashboardCodexCatchUpIsPending(
        _ statuses: [String: CostUsageFetcher.CodexScanCatchUpStatus]) -> Bool
    {
        statuses.values.contains(where: \.pending)
    }

    private static func spendDashboardCodexCostCatchUpProgressKey(
        _ statuses: [String: CostUsageFetcher.CodexScanCatchUpStatus]) -> String
    {
        statuses.sorted { $0.key < $1.key }.map { entry in
            let cacheIdentity = entry.key
            let progressKey = entry.value.progressKey
            return "\(cacheIdentity.count):\(cacheIdentity)\(progressKey.count):\(progressKey)"
        }.joined()
    }
}
