import CodexBarCore
import Foundation

private struct SpendDashboardCodexCostCatchUpContext {
    let token: UUID
    let accounts: [CodexSpendScanRequest]
    let historyDays: Int
    let scopeSignature: String
    let pauseScopeSignature: String
    let providerConfigRevision: UInt64
    let costUsageSettingsRevision: UInt64
}

extension UsageStore {
    /// Shared dashboard loads start with the normal token-cost window while its primary cache
    /// worker is still converging. The full dashboard window is safe once that worker reports a
    /// stable snapshot, and remains available for independent account caches immediately.
    var spendDashboardCodexHistoryDays: Int {
        // This is captured before dashboard synchronization marks the shared worker as owned.
        // Resolve the scope from settings so the first startup load cannot widen the primary
        // scan to the dashboard window. Local session-ledger mode still has to honor a managed
        // or profile selection, whose dashboard cache is independent of the ambient worker.
        guard self.tokenCostScope(for: .codex).codexHomePath == nil,
              self.settings.codexResolvedActiveSource == .liveSystem,
              self.codexCostCatchUpActivity?.phase != .complete
        else { return SpendDashboardSource.scanDays }
        return max(1, min(SpendDashboardSource.scanDays, self.settings.costUsageHistoryDays))
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
           case .pause = self.spendDashboardCodexCostCatchUpDecision(
               mode: .automatic,
               previousActiveDuration: nil).action
        {
            mode = .automatic
        }
        let sharedAccounts = allAccounts.filter(self.codexCostCatchUpUsesPrimaryCache)
        let independentAccounts = allAccounts.filter { !self.codexCostCatchUpUsesPrimaryCache($0) }
        if !sharedAccounts.isEmpty {
            self.spendDashboardCodexCostCatchUpUsesPrimaryWorker = true
            self.spendDashboardCodexCostCatchUpActivity = self.codexCostCatchUpActivity
            self.startCodexCostCatchUpIfNeeded(
                mode: mode,
                requestedHistoryDays: self.settings.costUsageHistoryDays,
                resumePaused: false)
        } else {
            self.spendDashboardCodexCostCatchUpUsesPrimaryWorker = false
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
            self.startCodexCostCatchUpIfNeeded(
                mode: mode,
                requestedHistoryDays: self.settings.costUsageHistoryDays,
                resumePaused: resumePaused)
        } else {
            self.spendDashboardCodexCostCatchUpUsesPrimaryWorker = false
        }
        guard !accounts.isEmpty else {
            self.clearSpendDashboardCodexCostCatchUpWorker()
            return
        }

        let historyDays = max(SpendDashboardSource.scanDays, self.settings.costUsageHistoryDays)
        let accountScopeSignature = accounts
            .map { "\($0.id)|\($0.cacheIdentity)" }
            .joined(separator: "\u{0}")
        let scopeSignature = "\(historyDays)\u{0}\(accountScopeSignature)"
        let providerConfigRevision = self.settings.providerConfigRevision(for: .codex)
        let pauseScopeSignature = "\(scopeSignature)\u{0}providerConfig=\(providerConfigRevision)"
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
        else { return }
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
        self.spendDashboardCodexCostCatchUpProgressProbeTask = nil
        self.spendDashboardCodexCostCatchUpActivity = nil
    }

    private func runSpendDashboardCodexCostCatchUp(
        context: SpendDashboardCodexCostCatchUpContext) async
    {
        var statuses = await self.loadSpendDashboardCodexCostCatchUpStatuses(context.accounts)
        guard self.spendDashboardCodexCostCatchUpContextIsCurrent(context) else { return }
        self.publishSpendDashboardCodexCostCatchUpActivity(
            statuses: statuses,
            context: context,
            phase: Self.spendDashboardCodexCatchUpIsPending(statuses) ? .indexing : .complete)

        var didChangeCache = false
        var previousActiveDuration: TimeInterval?
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

                let decision = self.spendDashboardCodexCostCatchUpDecision(
                    mode: self.spendDashboardCodexCostCatchUpMode,
                    previousActiveDuration: previousActiveDuration)
                switch decision.action {
                case let .pause(delay, reason):
                    self.publishSpendDashboardCodexCostCatchUpActivity(
                        statuses: statuses,
                        context: context,
                        phase: .paused,
                        pauseReason: reason)
                    try await self.sleepBetweenSpendDashboardCodexCostCatchUpPasses(seconds: delay)
                    continue
                case let .runAfter(delay):
                    self.publishSpendDashboardCodexCostCatchUpActivity(
                        statuses: statuses,
                        context: context,
                        phase: .indexing)
                    try await self.sleepBetweenSpendDashboardCodexCostCatchUpPasses(seconds: delay)
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
                let passStartedAt = ContinuousClock.now
                self.spendDashboardCodexCostCatchUpPassIsRunning = true
                let nextStatus: CostUsageFetcher.CodexScanCatchUpStatus
                do {
                    nextStatus = try await self.advanceSpendDashboardCodexCostCatchUp(
                        account: account,
                        now: Date(),
                        historyDays: context.historyDays)
                    self.spendDashboardCodexCostCatchUpPassIsRunning = false
                    self.scheduleMemoryPressureRelief()
                } catch {
                    self.spendDashboardCodexCostCatchUpPassIsRunning = false
                    self.scheduleMemoryPressureRelief()
                    throw error
                }
                previousActiveDuration = Self.spendDashboardCodexCatchUpDuration(
                    since: passStartedAt)
                didChangeCache = didChangeCache || nextStatus.progressKey != previousStatus?.progressKey
                if nextStatus.progressKey != previousStatus?.progressKey {
                    self.spendDashboardCodexCostCatchUpPausedScopeSignature = nil
                    self.spendDashboardCodexCostCatchUpPausedProgressKey = nil
                }
                statuses[account.cacheIdentity] = nextStatus
                if nextStatus.pending,
                   !seenKeysByCache[account.cacheIdentity, default: []].insert(nextStatus.progressKey).inserted
                {
                    stalledCacheIdentities.insert(account.cacheIdentity)
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
            && self.settings.providerConfigRevision(for: .codex) == context.providerConfigRevision
            && self.settings.costUsageSettingsRevision == context.costUsageSettingsRevision
            && max(SpendDashboardSource.scanDays, self.settings.costUsageHistoryDays) == context.historyDays
            && self.settings.isCostUsageEffectivelyEnabled(for: .codex)
            && self.isEnabled(.codex)
            && context.accounts.allSatisfy(SpendDashboardSource.codexAuthFingerprintMatches)
    }

    private func loadSpendDashboardCodexCostCatchUpStatuses(
        _ accounts: [CodexSpendScanRequest]) async -> [String: CostUsageFetcher.CodexScanCatchUpStatus]
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
                        calendar: self.settings.costUsageBucketCalendar)
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

            let statuses = await self.loadSpendDashboardCodexCostCatchUpStatuses(accounts)
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
        account: CodexSpendScanRequest,
        now: Date,
        historyDays: Int) async throws -> CostUsageFetcher.CodexScanCatchUpStatus
    {
        if let override = self._test_spendDashboardCodexCostCatchUpAdvanceOverride {
            return try await override(account, now, historyDays)
        }
        return try await CostUsageFetcher(
            cacheRoot: SpendDashboardSource.codexCacheRoot(for: account),
            calendar: self.settings.costUsageBucketCalendar)
            .advanceCodexScanCatchUp(
                now: now,
                codexHomePath: account.homePath,
                historyDays: historyDays,
                scanDurationPerRefresh: self.spendDashboardCodexCostCatchUpMode.scanDurationPerRefresh,
                calendar: self.settings.costUsageBucketCalendar)
    }

    private func spendDashboardCodexCostCatchUpDecision(
        mode: CodexCostCatchUpMode,
        previousActiveDuration: TimeInterval?) -> CodexCostCatchUpPolicy.Decision
    {
        let resourceState = self._test_spendDashboardCodexCostCatchUpResourceStateOverride?() ?? (
            powerSource: CodexCostCatchUpPowerSource.current(),
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState)
        return CodexCostCatchUpPolicy().decision(for: .init(
            mode: mode,
            previousActiveDuration: previousActiveDuration,
            powerSource: resourceState.powerSource,
            lowPowerModeEnabled: resourceState.lowPowerModeEnabled,
            thermalState: resourceState.thermalState))
    }

    private func publishSpendDashboardCodexCostCatchUpActivity(
        statuses: [String: CostUsageFetcher.CodexScanCatchUpStatus],
        context: SpendDashboardCodexCostCatchUpContext,
        phase: CodexCostCatchUpActivity.Phase,
        pauseReason: CodexCostCatchUpPauseReason? = nil)
    {
        guard self.spendDashboardCodexCostCatchUpToken == context.token else { return }
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

    private func sleepBetweenSpendDashboardCodexCostCatchUpPasses(seconds: TimeInterval) async throws {
        if let override = self._test_spendDashboardCodexCostCatchUpSleepOverride {
            try await override(max(0, seconds))
            return
        }
        guard seconds > 0 else {
            await Task.yield()
            return
        }
        try await Task.sleep(for: .seconds(seconds))
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
        _ statuses: [String: CostUsageFetcher.CodexScanCatchUpStatus]) -> String?
    {
        let pendingKeys = statuses.compactMap { cacheIdentity, status -> String? in
            guard status.pending else { return nil }
            return "\(cacheIdentity)=\(status.progressKey)"
        }.sorted()
        guard !pendingKeys.isEmpty else { return nil }
        return pendingKeys.joined(separator: "\u{0}")
    }

    private static func spendDashboardCodexCatchUpDuration(
        since start: ContinuousClock.Instant) -> TimeInterval
    {
        let components = (ContinuousClock.now - start).components
        return max(
            0,
            Double(components.seconds)
                + Double(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
