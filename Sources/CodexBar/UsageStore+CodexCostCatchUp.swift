import CodexBarCore
import Foundation

private struct CodexCostCatchUpContext {
    let token: UUID
    let codexHomePath: String?
    let historyDays: Int
    let scopeSignature: String
    let providerConfigRevision: UInt64
    let costUsageSettingsRevision: UInt64
}

extension UsageStore {
    func startCodexCostCatchUpIfNeeded(afterRefreshing provider: UsageProvider) {
        guard provider == .codex else { return }
        self.startCodexCostCatchUpIfNeeded(mode: .automatic)
    }

    func startCodexCostCatchUpIfNeeded(mode: CodexCostCatchUpMode = .automatic) {
        let scope = self.tokenCostScope(for: .codex)
        let scopeSignature = self.tokenSnapshotScopeSignature(for: .codex)
        if self.codexCostCatchUpTask != nil,
           self.codexCostCatchUpScopeSignature == scopeSignature
        {
            if self.codexCostCatchUpMode == mode {
                // Hydration can observe a complete cache while the foreground refresh that follows it
                // creates new tail work. Keep one restart queued so that refresh cannot lose the race
                // with the existing task's completion cleanup.
                self.codexCostCatchUpRestartRequested = true
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
            historyDays: self.settings.costUsageHistoryDays,
            scopeSignature: scopeSignature,
            providerConfigRevision: self.settings.providerConfigRevision(for: .codex),
            costUsageSettingsRevision: self.settings.costUsageSettingsRevision)
        self.codexCostCatchUpToken = token
        self.codexCostCatchUpScopeSignature = scopeSignature
        self.codexCostCatchUpMode = mode
        self.codexCostCatchUpStopRequested = false
        self.codexCostCatchUpPassIsRunning = false
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
                        self.codexCostCatchUpRestartRequested = false
                        self.startCodexCostCatchUpIfNeeded(mode: self.codexCostCatchUpMode)
                    }
                }
            }
            await self.runCodexCostCatchUp(context: context)
        }
    }

    func cancelCodexCostCatchUp() {
        let hadWorker = self.codexCostCatchUpTask != nil
        self.codexCostCatchUpTask?.cancel()
        if hadWorker {
            self.scheduleMemoryPressureRelief()
        }
        self.codexCostCatchUpTask = nil
        self.codexCostCatchUpToken = nil
        self.codexCostCatchUpScopeSignature = nil
        self.codexCostCatchUpStopRequested = false
        self.codexCostCatchUpPassIsRunning = false
        self.codexCostCatchUpRestartRequested = false
        self.codexCostCatchUpActivity = nil
    }

    func startAcceleratedCodexCostCatchUp() {
        self.startCodexCostCatchUpIfNeeded(mode: .accelerated)
    }

    func returnCodexCostCatchUpToBackground() {
        self.startCodexCostCatchUpIfNeeded(mode: .automatic)
    }

    func stopCodexCostCatchUp() {
        guard self.codexCostCatchUpTask != nil else { return }
        self.codexCostCatchUpStopRequested = true
        self.codexCostCatchUpRestartRequested = false
        self.scheduleMemoryPressureRelief()
        guard !self.codexCostCatchUpPassIsRunning else { return }
        if let activity = self.codexCostCatchUpActivity {
            self.codexCostCatchUpActivity = CodexCostCatchUpActivity(
                phase: .paused,
                mode: activity.mode,
                processedBytes: activity.processedBytes,
                totalBytes: activity.totalBytes,
                completedFiles: activity.completedFiles,
                totalFiles: activity.totalFiles,
                pauseReason: .user,
                staleSnapshotUpdatedAt: activity.staleSnapshotUpdatedAt)
        }
        self.codexCostCatchUpTask?.cancel()
        self.codexCostCatchUpTask = nil
        self.codexCostCatchUpToken = nil
        self.codexCostCatchUpScopeSignature = nil
    }

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
                        try await self.sleepBetweenCodexCostCatchUpPasses(seconds: delay)
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
                    guard self.codexCostCatchUpContextIsCurrent(context) else { return }
                    self.publishCodexCostCatchUpActivity(
                        status: nextStatus,
                        context: context,
                        phase: nextStatus.pending ? .indexing : .complete)
                    if nextStatus.pending {
                        await self.publishPendingCodexCostCatchUpSnapshotIfChanged(context: context)
                    }
                    if self.codexCostCatchUpStopRequested {
                        self.publishCodexCostCatchUpActivity(
                            status: nextStatus,
                            context: context,
                            phase: .paused,
                            pauseReason: .user)
                        return
                    }
                    if nextStatus.pending, !seenProgressKeys.insert(nextStatus.progressKey).inserted {
                        self.publishCodexCostCatchUpActivity(
                            status: nextStatus,
                            context: context,
                            phase: .paused,
                            pauseReason: .noProgress)
                        CodexBarLog.logger(LogCategories.tokenCost).warning(
                            "Codex cost catch-up stopped because a bounded pass made no progress")
                        return
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
        guard let current = self.tokenSnapshotPublicationForCurrentProviderConfig(for: .codex)?.snapshot,
              current.historyCoverageIsEstablished
        else { return }
        let publicationRevision = self.tokenSnapshotPublicationRevision(for: .codex)
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
                } else if cached.currentDayIsFullyVerified {
                    Self.codexCostSnapshotOverlayingVerifiedCurrentDay(
                        cached.snapshot,
                        onto: current,
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
                  snapshot.historyCoverageIsEstablished,
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

    private func publishStableCodexCostCatchUpSnapshot(
        context: CodexCostCatchUpContext) async throws -> CostUsageFetcher.CodexScanCatchUpStatus
    {
        let now = Date()
        let publicationRevision = self.tokenSnapshotPublicationRevision(for: .codex)
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

    private func codexCostCatchUpContextIsCurrent(_ context: CodexCostCatchUpContext) -> Bool {
        !Task.isCancelled
            && self.codexCostCatchUpToken == context.token
            && self.settings.providerConfigRevision(for: .codex) == context.providerConfigRevision
            && self.settings.costUsageSettingsRevision == context.costUsageSettingsRevision
            && self.settings.costUsageHistoryDays == context.historyDays
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
        self.codexCostCatchUpActivity = CodexCostCatchUpActivity(
            phase: phase,
            mode: self.codexCostCatchUpMode,
            processedBytes: status.processedBytes,
            totalBytes: status.totalBytes,
            completedFiles: status.completedFiles,
            totalFiles: status.totalFiles,
            pauseReason: pauseReason,
            staleSnapshotUpdatedAt: status.staleSnapshotUpdatedAt)
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
