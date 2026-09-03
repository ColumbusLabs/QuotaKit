import Foundation

extension CostUsageScanner {
    private struct CodexRescanPlan {
        let cached: CostUsageFileUsage?
        let migratedCached: CostUsageFileUsage?
        let parsed: CodexParseResult
        let replacementWasPending: Bool
        let replacementGeneration: Bool
        let replacementPending: Bool
        let scanComplete: Bool
        let usageDays: [String: [String: [Int]]]
    }

    private struct CodexRescanMaterialized {
        let usage: CostUsageFileUsage
        let session: CodexScannedSession
        let rows: [CodexUsageRow]
    }

    private struct CodexRescanAccounting {
        let usageDays: [String: [String: [Int]]]
        let costBaseline: [String: [String: Int64]]?
        let standardTokenBaseline: [String: [String: Int]]?
        let priorityTokenBaseline: [String: [String: Int]]?
        let turnIDBaseline: [String]?
        let persistedRows: [CodexUsageRow]
        let standardTokens: [String: [String: Int]]?
        let priorityTokens: [String: [String: Int]]?
    }

    static func rescanCodexFile(
        input: CodexFileScanInput,
        context: CodexFileScanContext,
        cache: inout CostUsageCache,
        state: inout CodexScanState,
        maxBytesToRead: Int64? = nil) throws
    {
        let plan = try Self.codexRescanPlan(
            input: input,
            context: context,
            maxBytesToRead: maxBytesToRead)
        if !plan.replacementPending, let cached = plan.cached {
            Self.applyFileDays(cache: &cache, fileDays: cached.days, sign: -1)
        }
        guard let materialized = Self.materializeCodexRescan(
            plan: plan,
            input: input,
            context: context,
            state: &state)
        else {
            cache.files.removeValue(forKey: input.metadata.path)
            return
        }
        cache.files[input.metadata.path] = materialized.usage
        if !plan.replacementPending {
            Self.applyFileDays(
                cache: &cache,
                fileDays: materialized.usage.days,
                sign: 1)
        }
        Self.rememberScannedCodexFile(
            input: input,
            session: materialized.session,
            rows: materialized.rows,
            context: context,
            state: &state)
    }

    private static func codexRescanAccounting(
        plan: CodexRescanPlan,
        context: CodexFileScanContext,
        uniqueRows: [CodexUsageRow],
        sessionId: String?) -> CodexRescanAccounting
    {
        var usageDays = plan.usageDays
        if !plan.replacementPending {
            Self.mergeFileDays(
                existing: &usageDays,
                delta: Self.codexFileDays(rows: uniqueRows))
        }
        let modeTokens = Self.codexModeTokenMaps(
            rows: uniqueRows,
            range: context.range,
            priorityTurns: context.resources.priorityTurns)
        let cachedRowsOutsideScanWindow = (plan.migratedCached?.codexRows ?? []).filter {
            !CostUsageDayRange.isInRange(
                dayKey: $0.day,
                since: context.range.scanSinceKey,
                until: context.range.scanUntilKey)
        }
        let costBaseline: [String: [String: Int64]]?
        let standardTokenBaseline: [String: [String: Int]]?
        let priorityTokenBaseline: [String: [String: Int]]?
        let turnIDBaseline: [String]?
        let persistedRows: [CodexUsageRow]
        if plan.replacementPending {
            costBaseline = plan.migratedCached?.codexCostNanos
            standardTokenBaseline = plan.migratedCached?.codexStandardTokens
            priorityTokenBaseline = plan.migratedCached?.codexPriorityTokens
            turnIDBaseline = plan.migratedCached?.codexTurnIDs
            persistedRows = []
        } else if plan.replacementGeneration {
            costBaseline = Self.costMapOutsideScanWindow(
                plan.migratedCached?.codexCostNanos,
                range: context.range)
            standardTokenBaseline = Self.intMapOutsideScanWindow(
                plan.migratedCached?.codexStandardTokens,
                range: context.range)
            priorityTokenBaseline = Self.intMapOutsideScanWindow(
                plan.migratedCached?.codexPriorityTokens,
                range: context.range)
            turnIDBaseline = Self.codexTurnIDs(rows: cachedRowsOutsideScanWindow)
            persistedRows = Self.mergeCodexRows(
                cachedRowsOutsideScanWindow,
                rows: uniqueRows,
                sessionId: sessionId) ?? []
        } else {
            costBaseline = context.dropDeferredCodexRows
                ? nil
                : Self.costMapOutsideScanWindow(
                    plan.migratedCached?.codexCostNanos,
                    range: context.range)
            standardTokenBaseline = context.dropDeferredCodexRows
                ? nil
                : Self.intMapOutsideScanWindow(
                    plan.migratedCached?.codexStandardTokens,
                    range: context.range)
            priorityTokenBaseline = context.dropDeferredCodexRows
                ? nil
                : Self.intMapOutsideScanWindow(
                    plan.migratedCached?.codexPriorityTokens,
                    range: context.range)
            turnIDBaseline = context.dropDeferredCodexRows
                ? nil
                : plan.migratedCached?.codexTurnIDs
            persistedRows = context.dropDeferredCodexRows
                ? uniqueRows
                : Self.mergeCodexRows(
                    plan.migratedCached?.codexRows,
                    rows: uniqueRows,
                    sessionId: sessionId) ?? []
        }
        return CodexRescanAccounting(
            usageDays: usageDays,
            costBaseline: costBaseline,
            standardTokenBaseline: standardTokenBaseline,
            priorityTokenBaseline: priorityTokenBaseline,
            turnIDBaseline: turnIDBaseline,
            persistedRows: persistedRows,
            standardTokens: modeTokens.standard,
            priorityTokens: modeTokens.priority)
    }

    private static func codexRescanPlan(
        input: CodexFileScanInput,
        context: CodexFileScanContext,
        maxBytesToRead: Int64?) throws -> CodexRescanPlan
    {
        try context.checkCancellation?()
        let cached = input.cached
        let migratedCached = cached.map { Self.codexFileUsageWithPricingMetadata($0, context: context) }
        let replacementWasPending = cached?.codexReplacementScanPending == true
        let replacementResume: (offset: Int64, usage: CostUsageFileUsage)? = {
            guard replacementWasPending,
                  let cached,
                  let parsedBytes = cached.parsedBytes,
                  parsedBytes > 0,
                  parsedBytes <= input.metadata.size,
                  cached.codexScanFileId == input.metadata.fileId,
                  cached.codexTokenIndexAnchor.map({
                      Self.codexTokenIndexAnchorMatches(
                          $0,
                          fileURL: input.fileURL,
                          metadata: input.metadata)
                  }) == true,
                  cached.codexJSONLResumeState?.offset == nil
                  || cached.codexJSONLResumeState?.offset == parsedBytes
            else { return nil }
            return (parsedBytes, cached)
        }()
        let startOffset = replacementResume?.offset ?? 0
        let stagedUsage = replacementResume?.usage
        let parsed = try Self.parseCodexFileCancellable(
            fileURL: input.fileURL,
            range: context.range,
            startOffset: startOffset,
            initialModel: stagedUsage?.lastModel,
            initialTotals: stagedUsage?.lastCountedTotals,
            initialRawTotalsBaseline: stagedUsage?.lastRawTotalsBaseline,
            initialRawTotalsWatermark: stagedUsage?.lastRawTotalsWatermark,
            initialSeenRawTotals: stagedUsage?.seenRawTotals ?? [],
            initialHasDivergentTotals: stagedUsage?.hasDivergentTotals ?? false,
            initialHasInterleavedTotals: stagedUsage?.hasInterleavedTotals ?? false,
            initialCodexTurnID: stagedUsage?.lastCodexTurnID,
            // Replacement rows are always indexed from zero. The previously committed rows are
            // not part of this generation and must never affect the replay's event indexes.
            initialCodexUsageRowIndex: 0,
            initialLastAcceptedTokenTimestampUnixMs: stagedUsage?.codexSession?.latestAcceptedUsageUnixMs,
            initialBufferedSubagentLines: stagedUsage?.codexBufferedSubagentLines,
            initialBufferedUnresolvedForkLines: stagedUsage?.codexBufferedUnresolvedForkLines,
            includeInitialBufferedTokenSnapshots: replacementWasPending,
            initialJSONLResumeState: stagedUsage?.codexJSONLResumeState,
            maxBytesToRead: maxBytesToRead,
            shouldStopReading: context.scanBudget.map { budget in
                { bytesRead in budget.shouldYield(additionalBytes: bytesRead) }
            },
            inheritedTotalsResolver: context.resources.inheritedResolver.inheritedTotals(for:atOrBefore:),
            checkCancellation: context.checkCancellation)
        let sourceScanComplete = parsed.parsedBytes >= input.metadata.size && parsed.jsonlResumeState == nil
        let hasReplayBuffer = parsed.bufferedSubagentLines != nil
            || parsed.bufferedUnresolvedForkLines != nil
        // Only a replayable lineage prefix needs staged replacement. Ordinary bounded rescans
        // retain the established partial-resume accounting until append can continue them. A
        // complete pass is replacement-shaped even without buffers so stale rows are removed.
        let replacementGeneration = replacementWasPending || hasReplayBuffer || sourceScanComplete
        // Unresolved lineage is still staged work. Do not replace a committed subagent ledger
        // with an empty/partial replay while its parent snapshots are unavailable.
        let replacementPending = replacementGeneration && (!sourceScanComplete || hasReplayBuffer)
        let scanComplete = sourceScanComplete && !replacementPending
        // A pending replacement retains the committed aggregate contribution in memory. The
        // staged parser state is persisted separately and is invisible to report aggregation.
        let retainedCommittedDays = context.dropDeferredCodexRows
            ? [:]
            : Self.fileDaysOutsideScanWindow(migratedCached?.days ?? [:], range: context.range)
        let usageDays = replacementPending
            ? cached?.days ?? retainedCommittedDays
            : retainedCommittedDays
        return CodexRescanPlan(
            cached: cached,
            migratedCached: migratedCached,
            parsed: parsed,
            replacementWasPending: replacementWasPending,
            replacementGeneration: replacementGeneration,
            replacementPending: replacementPending,
            scanComplete: scanComplete,
            usageDays: usageDays)
    }

    private static func materializeCodexRescan(
        plan: CodexRescanPlan,
        input: CodexFileScanInput,
        context: CodexFileScanContext,
        state: inout CodexScanState) -> CodexRescanMaterialized?
    {
        let parsed = plan.parsed
        let migratedCached = plan.migratedCached
        let parsedCodexSession: CostUsageCodexSessionMetadata
        let cachedSessionMetadata = input.cached?.codexSession ?? CostUsageCodexSessionMetadata(
            sessionId: input.cached?.sessionId,
            forkedFromId: input.cached?.forkedFromId,
            cwd: nil,
            title: nil,
            startedAtUnixMs: nil,
            latestActivityUnixMs: nil)
        parsedCodexSession = cachedSessionMetadata.merging(parsed.codexSession)
        let sessionId = parsedCodexSession.sessionId ?? parsed.sessionId ?? input.cached?.sessionId
        let projectPath = parsed.projectPath ?? input.cached?.projectPath
        let canonicalProjectPath = parsed.projectPath.map {
            context.resources.projectPathResolver.canonicalProjectPath(for: $0)
        } ?? input.cached?.canonicalProjectPath ?? context.resources.projectPathResolver
            .canonicalProjectPath(for: projectPath)
        let uniqueRows = Self.uniqueCodexRows(
            rows: parsed.rows,
            sessionId: sessionId,
            fileIdentity: input.metadata.path,
            state: &state)
        context.workRecorder?.record(processed: uniqueRows.count, repriced: uniqueRows.count)
        let usageDays = plan.usageDays
        if !plan.replacementGeneration,
           let sessionId,
           state.contributingSessionIds.contains(sessionId),
           uniqueRows.isEmpty,
           usageDays.isEmpty,
           parsed.bufferedSubagentLines == nil,
           parsed.bufferedUnresolvedForkLines == nil
        {
            return nil
        }
        let accounting = Self.codexRescanAccounting(
            plan: plan,
            context: context,
            uniqueRows: uniqueRows,
            sessionId: sessionId)
        let usage = Self.makeFileUsage(
            mtimeUnixMs: input.metadata.mtimeUnixMs,
            size: input.metadata.size,
            days: accounting.usageDays,
            parsedBytes: parsed.parsedBytes,
            lastModel: parsed.lastModel,
            lastTotals: parsed.lastTotals,
            lastCountedTotals: parsed.lastCountedTotals,
            lastRawTotalsBaseline: parsed.lastRawTotalsBaseline,
            lastRawTotalsWatermark: parsed.lastRawTotalsWatermark,
            seenRawTotals: parsed.seenRawTotals,
            hasDivergentTotals: parsed.hasDivergentTotals,
            hasInterleavedTotals: parsed.hasInterleavedTotals,
            lastCodexTurnID: parsed.lastCodexTurnID,
            sessionId: sessionId,
            forkedFromId: parsedCodexSession.forkedFromId ?? parsed.forkedFromId,
            forkBaselineDependencyKey: Self.codexForkBaselineDependencyKey(
                parentSessionId: parsed.forkedFromId,
                dependsOnParentTotals: parsed.dependsOnParentTotals,
                inheritedResolver: context.resources.inheritedResolver),
            projectPath: projectPath,
            canonicalProjectPath: canonicalProjectPath,
            codexSession: parsedCodexSession.isEmpty ? nil : parsedCodexSession,
            codexCostNanos: plan.replacementPending
                ? migratedCached?.codexCostNanos
                : Self.mergeCostMaps(
                    accounting.costBaseline,
                    Self.codexCostNanos(rows: uniqueRows, range: context.range)),
            codexPrioritySurchargeNanos: nil,
            codexStandardCostNanos: nil,
            codexPriorityCostNanos: nil,
            codexStandardTokens: plan.replacementPending
                ? migratedCached?.codexStandardTokens
                : Self.mergeIntMaps(accounting.standardTokenBaseline, accounting.standardTokens),
            codexPriorityTokens: plan.replacementPending
                ? migratedCached?.codexPriorityTokens
                : Self.mergeIntMaps(accounting.priorityTokenBaseline, accounting.priorityTokens),
            codexTurnIDs: plan.replacementPending
                ? migratedCached?.codexTurnIDs
                : Self.mergeCodexTurnIDs(accounting.turnIDBaseline, rows: uniqueRows),
            // Do not merge replayed rows with the committed generation. Pending passes need no
            // event rows; completion receives the full replay from the parser and replaces them.
            codexRows: plan.replacementPending
                ? nil
                : Self.codexRowsWithPricingMetadata(
                    accounting.persistedRows,
                    priorityTurns: context.resources.priorityTurns),
            codexTokenSnapshots: plan.replacementPending ? nil : parsed.tokenSnapshots,
            codexTokenCheckpoints: plan.replacementPending
                ? nil
                : Self.codexTokenCheckpoints(for: parsed.tokenSnapshots),
            codexTokenTimestampsMonotonic: plan.replacementPending
                ? migratedCached?.codexTokenTimestampsMonotonic
                : Self.codexTokenTimestampsAreMonotonic(parsed.tokenSnapshots),
            codexTokenIndexAnchor: Self.codexTokenIndexAnchor(
                fileURL: input.fileURL,
                indexedBytes: parsed.parsedBytes),
            codexScanFileId: input.metadata.fileId,
            codexScanTargetSize: input.metadata.size,
            codexScanComplete: plan.scanComplete,
            // `false` is a transient completion signal consumed by persistence; it is cleared
            // from the durable scan state after the replacement transaction commits.
            codexReplacementScanPending: plan.replacementGeneration
                ? plan.replacementPending
                : nil,
            codexJSONLResumeState: parsed.jsonlResumeState,
            codexBufferedSubagentLines: parsed.bufferedSubagentLines,
            codexBufferedUnresolvedForkLines: parsed.bufferedUnresolvedForkLines)
            .refreshingCodexWorkspaceUsageFingerprint()
        let session = CodexScannedSession(
            id: sessionId,
            days: plan.replacementPending ? [:] : accounting.usageDays)
        return CodexRescanMaterialized(usage: usage, session: session, rows: plan.replacementPending ? [] : uniqueRows)
    }
}
