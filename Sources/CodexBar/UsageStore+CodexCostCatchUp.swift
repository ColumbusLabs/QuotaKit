import CodexBarCore
import Foundation

private final class CodexCostCatchUpContext {
    let token: UUID
    let codexHomePath: String?
    let historyDays: Int
    let scopeSignature: String
    let pauseScopeSignature: String
    let providerConfigRevision: UInt64
    let costUsageSettingsRevision: UInt64
    var workerTokenSnapshotPublicationRevision: UInt64?

    init(
        token: UUID,
        codexHomePath: String?,
        historyDays: Int,
        scopeSignature: String,
        pauseScopeSignature: String,
        providerConfigRevision: UInt64,
        costUsageSettingsRevision: UInt64,
        workerTokenSnapshotPublicationRevision: UInt64?)
    {
        self.token = token
        self.codexHomePath = codexHomePath
        self.historyDays = historyDays
        self.scopeSignature = scopeSignature
        self.pauseScopeSignature = pauseScopeSignature
        self.providerConfigRevision = providerConfigRevision
        self.costUsageSettingsRevision = costUsageSettingsRevision
        self.workerTokenSnapshotPublicationRevision = workerTokenSnapshotPublicationRevision
    }
}

private enum CodexCostCatchUpNoProgressPolicy {
    // A bounded scanner pass can legitimately discover no new work (for example, while the
    // session tail is being appended). Give it a few chances before recording a stalled pause.
    static let maxConsecutiveNoProgressPasses = 3
    static let retryDelays: [TimeInterval] = [5, 15, 60]

    static func retryDelay(after passCount: Int) -> TimeInterval {
        let index = min(max(0, passCount - 1), self.retryDelays.count - 1)
        return self.retryDelays[index]
    }
}

extension UsageStore {
    func startCodexCostCatchUpIfNeeded(afterRefreshing provider: UsageProvider) {
        guard provider == .codex else { return }
        self.startCodexCostCatchUpIfNeeded(mode: .automatic, resumePaused: false)
    }

    func startCodexCostCatchUpIfNeeded(
        mode: CodexCostCatchUpMode = .automatic,
        requestedHistoryDays: Int? = nil,
        resumePaused: Bool = false)
    {
        let scope = self.tokenCostScope(for: .codex)
        let scopeSignature = self.tokenSnapshotScopeSignature(for: .codex)
        let providerConfigRevision = self.settings.providerConfigRevision(for: .codex)
        let pauseScopeSignature = "\(scopeSignature)\u{0}providerConfig=\(providerConfigRevision)"
        let historyDays = max(self.settings.costUsageHistoryDays, requestedHistoryDays ?? 0)
        guard !self.codexCostCatchUpStopRequested || resumePaused else { return }
        if !resumePaused,
           self.codexCostCatchUpTask == nil,
           self.codexCostCatchUpPausedScopeSignature == pauseScopeSignature
        {
            self.scheduleCodexCostCatchUpProgressProbe(
                codexHomePath: scope.codexHomePath,
                historyDays: max(historyDays, self.codexCostCatchUpHistoryDays),
                mode: mode,
                pauseScopeSignature: pauseScopeSignature)
            return
        }
        if self.codexCostCatchUpTask != nil,
           self.codexCostCatchUpScopeSignature == scopeSignature
        {
            let modeIsUnchanged = self.codexCostCatchUpMode == mode
            if historyDays > self.codexCostCatchUpHistoryDays {
                self.codexCostCatchUpHistoryDays = historyDays
                if self.codexCostCatchUpPassIsRunning {
                    self.codexCostCatchUpRestartRequested = true
                    self.codexCostCatchUpMode = mode
                    return
                }
                if modeIsUnchanged {
                    self.cancelCodexCostCatchUp()
                    self.startCodexCostCatchUpIfNeeded(
                        mode: mode,
                        requestedHistoryDays: historyDays,
                        resumePaused: false)
                    return
                }
            }
            if modeIsUnchanged {
                // Repeated refresh/configuration observations are coalesced. A worker that has
                // already paused on an unchanged semantic progress key must wait for a real
                // source change or explicit user/configuration event instead of rebuilding the
                // same cache again.
                return
            }
            self.codexCostCatchUpMode = mode
            // Never cancel a pass while it may be committing a resume checkpoint. The new mode
            // applies immediately after that bounded pass completes.
            if self.codexCostCatchUpPassIsRunning {
                return
            }
        }

        self.cancelCodexCostCatchUp()
        let token = UUID()
        let context = CodexCostCatchUpContext(
            token: token,
            codexHomePath: scope.codexHomePath,
            historyDays: historyDays,
            scopeSignature: scopeSignature,
            pauseScopeSignature: pauseScopeSignature,
            providerConfigRevision: providerConfigRevision,
            costUsageSettingsRevision: self.settings.costUsageSettingsRevision,
            workerTokenSnapshotPublicationRevision: nil)
        self.codexCostCatchUpToken = token
        self.codexCostCatchUpScopeSignature = scopeSignature
        self.codexCostCatchUpMode = mode
        self.codexCostCatchUpStopRequested = false
        self.codexCostCatchUpPassIsRunning = false
        self.codexCostCatchUpHistoryDays = historyDays
        self.codexCostCatchUpPausedScopeSignature = nil
        self.codexCostCatchUpPausedProgressKey = nil
        let priority: TaskPriority = mode == .accelerated ? .utility : .background
        self.codexCostCatchUpTask = Task(priority: priority) { @MainActor [weak self] in
            guard let self else { return }
            defer {
                // Catch-up parses the large Codex cache in bounded passes. Ask malloc to return
                // free pages after every worker lifetime, including cancellation and failures.
                self.scheduleMemoryPressureRelief()
                if self.codexCostCatchUpToken == token {
                    self.codexCostCatchUpTask = nil
                    self.codexCostCatchUpToken = nil
                    self.codexCostCatchUpScopeSignature = nil
                    if self.codexCostCatchUpRestartRequested {
                        let restartHistoryDays = max(
                            self.settings.costUsageHistoryDays,
                            self.codexCostCatchUpHistoryDays)
                        let restartMode = self.codexCostCatchUpMode
                        self.codexCostCatchUpRestartRequested = false
                        self.startCodexCostCatchUpIfNeeded(
                            mode: restartMode,
                            requestedHistoryDays: restartHistoryDays,
                            resumePaused: false)
                    }
                }
            }
            await self.runCodexCostCatchUp(context: context)
        }
    }

    func cancelCodexCostCatchUp() {
        let hadWorker = self.codexCostCatchUpTask != nil
        self.codexCostCatchUpTask?.cancel()
        self.codexCostCatchUpProgressProbeTask?.cancel()
        if hadWorker {
            self.scheduleMemoryPressureRelief()
        }
        self.codexCostCatchUpTask = nil
        self.codexCostCatchUpToken = nil
        self.codexCostCatchUpScopeSignature = nil
        self.codexCostCatchUpStopRequested = false
        self.codexCostCatchUpPassIsRunning = false
        self.codexCostCatchUpRestartRequested = false
        self.codexCostCatchUpHistoryDays = 0
        self.codexCostCatchUpPausedScopeSignature = nil
        self.codexCostCatchUpPausedProgressKey = nil
        self.codexCostCatchUpProgressProbeTask = nil
        self.codexCostCatchUpActivity = nil
    }

    func startAcceleratedCodexCostCatchUp() {
        self.startCodexCostCatchUpIfNeeded(mode: .accelerated, resumePaused: true)
    }

    func returnCodexCostCatchUpToBackground() {
        self.startCodexCostCatchUpIfNeeded(mode: .automatic, resumePaused: true)
    }

    func stopCodexCostCatchUp() {
        guard self.codexCostCatchUpTask != nil
            || self.codexCostCatchUpProgressProbeTask != nil
        else { return }
        guard self.codexCostCatchUpTask != nil else {
            self.codexCostCatchUpProgressProbeTask?.cancel()
            self.codexCostCatchUpProgressProbeTask = nil
            self.codexCostCatchUpStopRequested = true
            if let activity = self.codexCostCatchUpActivity {
                let pausedActivity = CodexCostCatchUpActivity(
                    phase: .paused,
                    mode: activity.mode,
                    processedBytes: activity.processedBytes,
                    totalBytes: activity.totalBytes,
                    completedFiles: activity.completedFiles,
                    totalFiles: activity.totalFiles,
                    pauseReason: .user,
                    staleSnapshotUpdatedAt: activity.staleSnapshotUpdatedAt)
                self.codexCostCatchUpActivity = pausedActivity
                if self.spendDashboardCodexCostCatchUpUsesPrimaryWorker {
                    self.spendDashboardCodexCostCatchUpActivity = pausedActivity
                }
            }
            return
        }
        self.codexCostCatchUpStopRequested = true
        self.codexCostCatchUpRestartRequested = false
        self.scheduleMemoryPressureRelief()
        guard !self.codexCostCatchUpPassIsRunning else { return }
        if let activity = self.codexCostCatchUpActivity {
            let pausedActivity = CodexCostCatchUpActivity(
                phase: .paused,
                mode: activity.mode,
                processedBytes: activity.processedBytes,
                totalBytes: activity.totalBytes,
                completedFiles: activity.completedFiles,
                totalFiles: activity.totalFiles,
                pauseReason: .user,
                staleSnapshotUpdatedAt: activity.staleSnapshotUpdatedAt)
            self.codexCostCatchUpActivity = pausedActivity
            if self.spendDashboardCodexCostCatchUpUsesPrimaryWorker {
                self.spendDashboardCodexCostCatchUpActivity = pausedActivity
            }
        }
        self.codexCostCatchUpTask?.cancel()
        self.codexCostCatchUpTask = nil
        self.codexCostCatchUpToken = nil
        self.codexCostCatchUpScopeSignature = nil
    }

    // This is an explicit checkpointed state machine; keeping its exit paths together prevents
    // cancellation, restart, and publication transitions from drifting apart.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func runCodexCostCatchUp(context: CodexCostCatchUpContext) async {
        while self.codexCostCatchUpContextIsCurrent(context) {
            var status = await self.loadCodexCostCatchUpStatus(codexHomePath: context.codexHomePath)
            self.publishCodexCostCatchUpActivity(
                status: status,
                context: context,
                phase: status.pending ? .indexing : .complete)
            var didAdvance = false
            var (previousActiveDuration, seenProgressKeys): (TimeInterval?, Set<String>) =
                (nil, [status.progressKey])
            var consecutiveNoProgressPasses = 0
            var pendingNoProgressRetryDelay: TimeInterval?
            while status.pending {
                do {
                    guard self.codexCostCatchUpContextIsCurrent(context) else { return }
                    if self.codexCostCatchUpStopRequested {
                        self.publishCodexCostCatchUpActivity(
                            status: status,
                            context: context,
                            phase: .paused,
                            pauseReason: .user)
                        return
                    }

                    let decision = self.codexCostCatchUpDecision(
                        mode: self.codexCostCatchUpMode,
                        previousActiveDuration: previousActiveDuration)
                    switch decision.action {
                    case let .pause(delay, reason):
                        self.publishCodexCostCatchUpActivity(
                            status: status,
                            context: context,
                            phase: .paused,
                            pauseReason: reason)
                        try await self.sleepBetweenCodexCostCatchUpPasses(seconds: delay)
                        continue
                    case let .runAfter(delay):
                        self.publishCodexCostCatchUpActivity(
                            status: status,
                            context: context,
                            phase: .indexing)
                        let retryDelay = pendingNoProgressRetryDelay ?? 0
                        pendingNoProgressRetryDelay = nil
                        try await self.sleepBetweenCodexCostCatchUpPasses(
                            seconds: max(delay, retryDelay))
                    }

                    try Task.checkCancellation()
                    guard self.codexCostCatchUpContextIsCurrent(context) else { return }
                    if self.codexCostCatchUpStopRequested {
                        self.publishCodexCostCatchUpActivity(
                            status: status,
                            context: context,
                            phase: .paused,
                            pauseReason: .user)
                        return
                    }

                    let passStartedAt = ContinuousClock.now
                    self.codexCostCatchUpPassIsRunning = true
                    let nextStatus: CostUsageFetcher.CodexScanCatchUpStatus
                    do {
                        nextStatus = try await self.advanceCodexCostCatchUp(
                            now: Date(),
                            codexHomePath: context.codexHomePath,
                            historyDays: context.historyDays)
                        self.codexCostCatchUpPassIsRunning = false
                        self.scheduleMemoryPressureRelief()
                    } catch {
                        self.codexCostCatchUpPassIsRunning = false
                        self.scheduleMemoryPressureRelief()
                        throw error
                    }
                    let passDuration = ContinuousClock.now - passStartedAt
                    let durationComponents = passDuration.components
                    previousActiveDuration = max(
                        0,
                        Double(durationComponents.seconds)
                            + Double(durationComponents.attoseconds) / 1_000_000_000_000_000_000)
                    didAdvance = true
                    if self.spendDashboardCodexCostCatchUpUsesPrimaryWorker,
                       nextStatus.progressKey != status.progressKey
                    {
                        self.spendDashboardCodexCostCatchUpRevision &+= 1
                    }
                    guard self.codexCostCatchUpContextIsCurrent(context) else { return }
                    self.publishCodexCostCatchUpActivity(
                        status: nextStatus,
                        context: context,
                        phase: nextStatus.pending ? .indexing : .complete)
                    if nextStatus.pending {
                        await self.publishPendingCodexCostCatchUpSnapshotIfChanged(context: context)
                    }
                    if self.codexCostCatchUpRestartRequested {
                        return
                    }
                    if self.codexCostCatchUpStopRequested {
                        self.publishCodexCostCatchUpActivity(
                            status: nextStatus,
                            context: context,
                            phase: .paused,
                            pauseReason: .user)
                        return
                    }
                    if nextStatus.pending {
                        if nextStatus.progressKey == status.progressKey {
                            consecutiveNoProgressPasses += 1
                            if consecutiveNoProgressPasses
                                >= CodexCostCatchUpNoProgressPolicy.maxConsecutiveNoProgressPasses
                            {
                                self.codexCostCatchUpPausedScopeSignature = context.pauseScopeSignature
                                self.codexCostCatchUpPausedProgressKey = nextStatus.progressKey
                                self.publishCodexCostCatchUpActivity(
                                    status: nextStatus,
                                    context: context,
                                    phase: .paused,
                                    pauseReason: .noProgress)
                                CodexBarLog.logger(LogCategories.tokenCost).warning(
                                    "Codex cost catch-up stopped after bounded no-progress retries")
                                return
                            }
                            pendingNoProgressRetryDelay = CodexCostCatchUpNoProgressPolicy.retryDelay(
                                after: consecutiveNoProgressPasses)
                        } else {
                            // A real state transition makes a subsequent same-key result a new
                            // consecutive stall, while a revisit of any earlier state remains an
                            // infinite-cycle guard.
                            consecutiveNoProgressPasses = 0
                            guard seenProgressKeys.insert(nextStatus.progressKey).inserted else {
                                self.codexCostCatchUpPausedScopeSignature = context.pauseScopeSignature
                                self.codexCostCatchUpPausedProgressKey = nextStatus.progressKey
                                self.publishCodexCostCatchUpActivity(
                                    status: nextStatus,
                                    context: context,
                                    phase: .paused,
                                    pauseReason: .noProgress)
                                CodexBarLog.logger(LogCategories.tokenCost).warning(
                                    "Codex cost catch-up stopped because progress revisited an earlier state")
                                return
                            }
                        }
                    }
                    status = nextStatus
                } catch is CancellationError {
                    return
                } catch {
                    self.publishCodexCostCatchUpActivity(
                        status: status,
                        context: context,
                        phase: .paused,
                        pauseReason: .error(error.localizedDescription))
                    CodexBarLog.logger(LogCategories.tokenCost).warning(
                        "Codex cost catch-up stopped after error: \(error.localizedDescription)")
                    return
                }
            }

            guard self.codexCostCatchUpContextIsCurrent(context) else { return }
            guard didAdvance else {
                self.publishCodexCostCatchUpActivity(
                    status: status,
                    context: context,
                    phase: .complete)
                return
            }
            do {
                status = try await self.publishStableCodexCostCatchUpSnapshot(context: context)
                guard status.pending else { return }
            } catch is CancellationError {
                return
            } catch {
                self.publishCodexCostCatchUpActivity(
                    status: status,
                    context: context,
                    phase: .paused,
                    pauseReason: .error(error.localizedDescription))
                CodexBarLog.logger(LogCategories.tokenCost).warning(
                    "Codex cost catch-up final snapshot failed: \(error.localizedDescription)")
                return
            }
        }
    }

    private func publishPendingCodexCostCatchUpSnapshotIfChanged(
        context: CodexCostCatchUpContext) async
    {
        guard let current = self.tokenSnapshotPublicationForCurrentProviderConfig(for: .codex)?.snapshot
        else { return }
        let publicationRevision = self.codexCostCatchUpWorkerPublicationRevision(context: context)
        do {
            let now = Date()
            let snapshot: CostUsageTokenSnapshot? = if self._test_tokenUsageSnapshotLoaderOverride != nil {
                try await self.loadTokenUsageSnapshot(
                    provider: .codex,
                    force: true,
                    now: now,
                    codexHomePath: context.codexHomePath,
                    historyDays: context.historyDays)
            } else if let cached = await self.costUsageFetcher.loadCachedCodexTokenSnapshotResult(
                now: now,
                codexHomePath: context.codexHomePath,
                historyDays: context.historyDays,
                allowScopedCodexHome: context.codexHomePath != nil,
                includeProjectAndSessionBreakdowns: false,
                calendar: self.settings.costUsageBucketCalendar)
            {
                if cached.snapshot.historyCoverageIsEstablished {
                    cached.snapshot
                } else if current.historyCoverageIsEstablished,
                          cached.currentDayIsFullyVerified
                {
                    Self.codexCostSnapshotOverlayingVerifiedCurrentDay(
                        cached.snapshot,
                        onto: current,
                        calendar: self.settings.costUsageBucketCalendar)
                } else if !current.historyCoverageIsEstablished {
                    Self.codexCostSnapshotAdvancingPartialLowerBound(
                        cached.snapshot,
                        over: current,
                        calendar: self.settings.costUsageBucketCalendar)
                } else {
                    nil
                }
            } else {
                nil
            }
            try Task.checkCancellation()
            guard self.codexCostCatchUpContextIsCurrent(context),
                  self.tokenSnapshotPublicationRevision(for: .codex) == publicationRevision,
                  let snapshot,
                  !snapshot.daily.isEmpty || snapshot.meteredCostUSD != nil
            else { return }
            let publicationSnapshot = Self.codexCostSnapshot(
                snapshot,
                retainingBreakdownsFrom: current)
            if Self.codexCostSnapshotContentEquals(current, publicationSnapshot) {
                return
            }

            self.lastTokenFetchAt[.codex] = now
            self.lastTokenFetchScope[.codex] = context.scopeSignature
            self.publishTokenSnapshot(publicationSnapshot, for: .codex)
            context.workerTokenSnapshotPublicationRevision = self.tokenSnapshotPublicationRevision(
                for: .codex)
            self.tokenErrors[.codex] = nil
            self.tokenFailureGates[.codex]?.recordSuccess()
            self.persistWidgetSnapshot(reason: "token-usage-catch-up-tail")
        } catch is CancellationError {
            return
        } catch {
            CodexBarLog.logger(LogCategories.tokenCost).warning(
                "Codex cost catch-up fresh-day publication failed: \(error.localizedDescription)")
        }
    }

    private static func codexCostSnapshotContentEquals(
        _ lhs: CostUsageTokenSnapshot,
        _ rhs: CostUsageTokenSnapshot) -> Bool
    {
        lhs.sessionTokens == rhs.sessionTokens
            && lhs.sessionCostUSD == rhs.sessionCostUSD
            && lhs.sessionRequests == rhs.sessionRequests
            && lhs.last30DaysTokens == rhs.last30DaysTokens
            && lhs.last30DaysCostUSD == rhs.last30DaysCostUSD
            && lhs.last30DaysRequests == rhs.last30DaysRequests
            && lhs.currencyCode == rhs.currencyCode
            && lhs.historyDays == rhs.historyDays
            && lhs.historyCoverageIsEstablished == rhs.historyCoverageIsEstablished
            && lhs.historyLabel == rhs.historyLabel
            && lhs.meteredCostUSD == rhs.meteredCostUSD
            && lhs.costProvenance == rhs.costProvenance
            && lhs.credentialScopeFingerprint == rhs.credentialScopeFingerprint
            && lhs.ownership == rhs.ownership
            && lhs.daily == rhs.daily
            && lhs.projects == rhs.projects
            && lhs.sessions == rhs.sessions
            && lhs.hourly == rhs.hourly
    }

    private static func codexCostSnapshot(
        _ snapshot: CostUsageTokenSnapshot,
        retainingBreakdownsFrom current: CostUsageTokenSnapshot) -> CostUsageTokenSnapshot
    {
        CostUsageTokenSnapshot(
            sessionTokens: snapshot.sessionTokens,
            sessionCostUSD: snapshot.sessionCostUSD,
            sessionRequests: snapshot.sessionRequests,
            last30DaysTokens: snapshot.last30DaysTokens,
            last30DaysCostUSD: snapshot.last30DaysCostUSD,
            last30DaysRequests: snapshot.last30DaysRequests,
            currencyCode: snapshot.currencyCode,
            historyDays: snapshot.historyDays,
            historyCoverageIsEstablished: snapshot.historyCoverageIsEstablished,
            historyLabel: snapshot.historyLabel,
            meteredCostUSD: snapshot.meteredCostUSD,
            costProvenance: snapshot.costProvenance,
            credentialScopeFingerprint: snapshot.credentialScopeFingerprint,
            ownership: snapshot.ownership,
            daily: snapshot.daily,
            projects: current.projects,
            sessions: current.sessions,
            hourly: current.hourly,
            updatedAt: snapshot.updatedAt)
    }

    static func codexCostSnapshotOverlayingVerifiedCurrentDay(
        _ candidate: CostUsageTokenSnapshot,
        onto established: CostUsageTokenSnapshot,
        calendar: Calendar) -> CostUsageTokenSnapshot?
    {
        guard candidate.updatedAt > established.updatedAt,
              let currentDay = candidate.currentDayEntry(calendar: calendar),
              currentDay.costUSD != nil
        else { return nil }

        var daily = established.daily.filter { $0.date != currentDay.date }
        daily.append(currentDay)
        daily.sort { $0.date < $1.date }

        let allEntriesCarryTokens = daily.allSatisfy { $0.totalTokens != nil }
        let allEntriesCarryCost = daily.allSatisfy { $0.costUSD != nil }
        let allEntriesCarryRequests = daily.allSatisfy { $0.requestCount != nil }
        let totalTokens = allEntriesCarryTokens ? daily.compactMap(\.totalTokens).reduce(0, +) : nil
        let totalCost = allEntriesCarryCost ? daily.compactMap(\.costUSD).reduce(0, +) : nil
        let totalRequests = allEntriesCarryRequests ? daily.compactMap(\.requestCount).reduce(0, +) : nil

        return CostUsageTokenSnapshot(
            sessionTokens: currentDay.totalTokens,
            sessionCostUSD: currentDay.costUSD,
            sessionRequests: currentDay.requestCount,
            last30DaysTokens: totalTokens,
            last30DaysCostUSD: totalCost,
            last30DaysRequests: totalRequests,
            currencyCode: established.currencyCode,
            historyDays: established.historyDays,
            historyCoverageIsEstablished: true,
            historyLabel: established.historyLabel,
            meteredCostUSD: established.meteredCostUSD,
            costProvenance: established.costProvenance,
            credentialScopeFingerprint: established.credentialScopeFingerprint,
            ownership: established.ownership,
            daily: daily,
            projects: established.projects,
            sessions: established.sessions,
            hourly: established.hourly,
            updatedAt: candidate.updatedAt)
    }

    /// A cold cache has no complete baseline to protect yet. Publish bounded
    /// scan progress only when every already-visible lower bound remains
    /// present and non-decreasing. Complete snapshots use the authoritative
    /// path above and may still apply legitimate downward corrections.
    static func codexCostSnapshotAdvancingPartialLowerBound(
        _ candidate: CostUsageTokenSnapshot,
        over current: CostUsageTokenSnapshot,
        calendar: Calendar) -> CostUsageTokenSnapshot?
    {
        let sameSessionDay = calendar.isDate(
            candidate.updatedAt,
            inSameDayAs: current.updatedAt)
        guard !candidate.historyCoverageIsEstablished,
              !current.historyCoverageIsEstablished,
              candidate.updatedAt > current.updatedAt,
              !sameSessionDay
              || self.optionalLowerBound(candidate.sessionCostUSD, covers: current.sessionCostUSD),
              !sameSessionDay
              || self.optionalLowerBound(candidate.sessionTokens, covers: current.sessionTokens),
              self.optionalLowerBound(candidate.last30DaysCostUSD, covers: current.last30DaysCostUSD),
              self.optionalLowerBound(candidate.last30DaysTokens, covers: current.last30DaysTokens)
        else { return nil }

        let candidateByDay = Dictionary(uniqueKeysWithValues: candidate.daily.map { ($0.date, $0) })
        for existing in current.daily {
            guard let incoming = candidateByDay[existing.date],
                  Self.optionalLowerBound(incoming.costUSD, covers: existing.costUSD),
                  Self.optionalLowerBound(incoming.totalTokens, covers: existing.totalTokens)
            else { return nil }
        }
        return candidate
    }

    private static func optionalLowerBound<Value: Comparable>(
        _ candidate: Value?,
        covers current: Value?) -> Bool
    {
        guard let current else { return true }
        guard let candidate else { return false }
        return candidate >= current
    }

    private func publishStableCodexCostCatchUpSnapshot(
        context: CodexCostCatchUpContext) async throws -> CostUsageFetcher.CodexScanCatchUpStatus
    {
        let now = Date()
        let publicationRevision = self.codexCostCatchUpWorkerPublicationRevision(context: context)
        // Catch-up has already completed the authoritative scan. Publish from the compact
        // persisted report projection instead of forcing another scan and hydrating the entire
        // usage ledger a second time merely to build project/session breakdowns.
        let snapshot: CostUsageTokenSnapshot
        if self._test_tokenUsageSnapshotLoaderOverride != nil {
            snapshot = try await self.loadTokenUsageSnapshot(
                provider: .codex,
                force: true,
                now: now,
                codexHomePath: context.codexHomePath,
                historyDays: context.historyDays)
        } else if let cached = await self.costUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: now,
            codexHomePath: context.codexHomePath,
            historyDays: context.historyDays,
            allowScopedCodexHome: context.codexHomePath != nil,
            calendar: self.settings.costUsageBucketCalendar)?.snapshot
        {
            snapshot = cached
        } else {
            throw CostUsageError.cachedSnapshotUnavailable
        }
        try Task.checkCancellation()
        guard self.codexCostCatchUpContextIsCurrent(context),
              self.tokenSnapshotPublicationRevision(for: .codex) == publicationRevision
        else {
            throw CancellationError()
        }

        self.lastTokenFetchAt[.codex] = now
        self.lastTokenFetchScope[.codex] = context.scopeSignature
        if snapshot.daily.isEmpty, snapshot.meteredCostUSD == nil {
            self.publishConfirmedEmptyTokenSnapshot(for: .codex)
            self.tokenErrors[.codex] = Self.tokenCostNoDataMessage(for: .codex)
        } else {
            self.publishTokenSnapshot(snapshot, for: .codex)
            context.workerTokenSnapshotPublicationRevision = self.tokenSnapshotPublicationRevision(
                for: .codex)
            self.tokenErrors[.codex] = nil
        }
        self.tokenFailureGates[.codex]?.recordSuccess()
        self.persistWidgetSnapshot(reason: "token-usage-catch-up")

        let status = await self.loadCodexCostCatchUpStatus(codexHomePath: context.codexHomePath)
        self.publishCodexCostCatchUpActivity(
            status: status,
            context: context,
            phase: status.pending ? .indexing : .complete)
        return status
    }

    private func codexCostCatchUpWorkerPublicationRevision(
        context: CodexCostCatchUpContext) -> UInt64
    {
        if let workerRevision = context.workerTokenSnapshotPublicationRevision {
            return workerRevision
        }

        // The normal foreground refresh schedules catch-up before it publishes its first
        // snapshot. Anchor on the revision visible when the worker first attempts a publication,
        // so that foreground publication is treated as the worker's initial baseline. Once the
        // baseline is set, every later pass must observe either that revision or the worker's own
        // latest publication; a newer foreground revision cannot become a stale-worker baseline.
        let revision = self.tokenSnapshotPublicationRevision(for: .codex)
        context.workerTokenSnapshotPublicationRevision = revision
        return revision
    }

    private func codexCostCatchUpContextIsCurrent(_ context: CodexCostCatchUpContext) -> Bool {
        !Task.isCancelled
            && self.codexCostCatchUpToken == context.token
            && self.settings.providerConfigRevision(for: .codex) == context.providerConfigRevision
            && self.settings.costUsageSettingsRevision == context.costUsageSettingsRevision
            && self.settings.costUsageHistoryDays <= context.historyDays
            && self.settings.isCostUsageEffectivelyEnabled(for: .codex)
            && self.isEnabled(.codex)
            && self.tokenCostScope(for: .codex).codexHomePath == context.codexHomePath
            && self.tokenSnapshotScopeSignature(for: .codex) == context.scopeSignature
    }

    private func loadCodexCostCatchUpStatus(
        codexHomePath: String?) async -> CostUsageFetcher.CodexScanCatchUpStatus
    {
        if let override = self._test_codexCostCatchUpStatusOverride {
            return await override(codexHomePath)
        }
        return await self.costUsageFetcher.codexScanCatchUpStatus(
            codexHomePath: codexHomePath,
            calendar: self.settings.costUsageBucketCalendar)
    }

    private func scheduleCodexCostCatchUpProgressProbe(
        codexHomePath: String?,
        historyDays: Int,
        mode: CodexCostCatchUpMode,
        pauseScopeSignature: String)
    {
        guard self.codexCostCatchUpProgressProbeTask == nil,
              let stalledProgressKey = self.codexCostCatchUpPausedProgressKey
        else { return }

        self.codexCostCatchUpProgressProbeTask = Task(priority: .background) { @MainActor [weak self] in
            guard let self else { return }
            defer { self.codexCostCatchUpProgressProbeTask = nil }

            let status = await self.loadCodexCostCatchUpStatus(codexHomePath: codexHomePath)
            guard !Task.isCancelled,
                  self.codexCostCatchUpTask == nil,
                  self.codexCostCatchUpPausedScopeSignature == pauseScopeSignature,
                  self.codexCostCatchUpPausedProgressKey == stalledProgressKey
            else { return }
            guard status.progressKey != stalledProgressKey else { return }

            // Clear the pause before re-entering the normal start path. This lets the existing
            // scope/mode coalescing rules resume the authoritative worker without creating a
            // second scan pass for the same cache.
            self.codexCostCatchUpPausedScopeSignature = nil
            self.codexCostCatchUpPausedProgressKey = nil
            self.codexCostCatchUpProgressProbeTask = nil
            self.startCodexCostCatchUpIfNeeded(
                mode: mode,
                requestedHistoryDays: historyDays,
                resumePaused: false)
        }
    }

    private func advanceCodexCostCatchUp(
        now: Date,
        codexHomePath: String?,
        historyDays: Int) async throws -> CostUsageFetcher.CodexScanCatchUpStatus
    {
        if let override = self._test_codexCostCatchUpAdvanceOverride {
            return try await override(now, codexHomePath, historyDays)
        }
        return try await self.costUsageFetcher.advanceCodexScanCatchUp(
            now: now,
            codexHomePath: codexHomePath,
            historyDays: historyDays,
            calendar: self.settings.costUsageBucketCalendar)
    }

    private func codexCostCatchUpDecision(
        mode: CodexCostCatchUpMode,
        previousActiveDuration: TimeInterval?) -> CodexCostCatchUpPolicy.Decision
    {
        let resourceState = self._test_codexCostCatchUpResourceStateOverride?() ?? (
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

    private func publishCodexCostCatchUpActivity(
        status: CostUsageFetcher.CodexScanCatchUpStatus,
        context: CodexCostCatchUpContext,
        phase: CodexCostCatchUpActivity.Phase,
        pauseReason: CodexCostCatchUpPauseReason? = nil)
    {
        guard self.codexCostCatchUpToken == context.token else { return }
        let activity = CodexCostCatchUpActivity(
            phase: phase,
            mode: self.codexCostCatchUpMode,
            processedBytes: status.processedBytes,
            totalBytes: status.totalBytes,
            completedFiles: status.completedFiles,
            totalFiles: status.totalFiles,
            pauseReason: pauseReason,
            staleSnapshotUpdatedAt: status.staleSnapshotUpdatedAt)
        self.codexCostCatchUpActivity = activity
        if self.spendDashboardCodexCostCatchUpUsesPrimaryWorker {
            self.spendDashboardCodexCostCatchUpActivity = activity
        }
    }

    private func sleepBetweenCodexCostCatchUpPasses(seconds: TimeInterval) async throws {
        if let override = self._test_codexCostCatchUpSleepOverride {
            try await override(max(0, seconds))
            return
        }
        guard seconds > 0 else {
            await Task.yield()
            return
        }
        try await Task.sleep(for: .seconds(seconds))
    }
}
