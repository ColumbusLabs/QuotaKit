import Foundation

extension CostUsageScanner {
    /// These immutable phase values hold inline cache/parser results on the heap, so
    /// their return storage does not accumulate across nested inherited-parent lookups.
    private final class CodexRescanPlan {
        let cached: CostUsageFileUsage?
        let migratedCached: CostUsageFileUsage?
        let parsed: CodexParseResult
        let replacementWasPending: Bool
        let parserRevisionNeedsReplacement: Bool
        let replacementGeneration: Bool
        let replacementPending: Bool
        let scanComplete: Bool
        let usageDays: [String: [String: [Int]]]
        let sourcePricing: [CodexSourcePricingKey: CodexPricingEvidence]?
        let sourceAnchor: CostUsageCodexTokenIndexAnchor?
        let stageParsedRows: Bool

        init(
            cached: CostUsageFileUsage?,
            migratedCached: CostUsageFileUsage?,
            parsed: CodexParseResult,
            replacementWasPending: Bool,
            parserRevisionNeedsReplacement: Bool,
            replacementGeneration: Bool,
            replacementPending: Bool,
            scanComplete: Bool,
            usageDays: [String: [String: [Int]]],
            sourcePricing: [CodexSourcePricingKey: CodexPricingEvidence]?,
            sourceAnchor: CostUsageCodexTokenIndexAnchor?,
            stageParsedRows: Bool)
        {
            self.cached = cached
            self.migratedCached = migratedCached
            self.parsed = parsed
            self.replacementWasPending = replacementWasPending
            self.parserRevisionNeedsReplacement = parserRevisionNeedsReplacement
            self.replacementGeneration = replacementGeneration
            self.replacementPending = replacementPending
            self.scanComplete = scanComplete
            self.usageDays = usageDays
            self.sourcePricing = sourcePricing
            self.sourceAnchor = sourceAnchor
            self.stageParsedRows = stageParsedRows
        }
    }

    private final class CodexRescanPreparation {
        let migratedCached: CostUsageFileUsage?
        let sourcePricing: [CodexSourcePricingKey: CodexPricingEvidence]?
        let sourceAnchor: CostUsageCodexTokenIndexAnchor?
        let parserRevisionNeedsReplacement: Bool
        let stageParsedRows: Bool

        init(
            migratedCached: CostUsageFileUsage?,
            sourcePricing: [CodexSourcePricingKey: CodexPricingEvidence]?,
            sourceAnchor: CostUsageCodexTokenIndexAnchor?,
            parserRevisionNeedsReplacement: Bool,
            stageParsedRows: Bool)
        {
            self.migratedCached = migratedCached
            self.sourcePricing = sourcePricing
            self.sourceAnchor = sourceAnchor
            self.parserRevisionNeedsReplacement = parserRevisionNeedsReplacement
            self.stageParsedRows = stageParsedRows
        }
    }

    private final class CodexRescanMaterialized {
        let usage: CostUsageFileUsage
        let session: CodexScannedSession
        let rows: [CodexUsageRow]

        init(usage: CostUsageFileUsage, session: CodexScannedSession, rows: [CodexUsageRow]) {
            self.usage = usage
            self.session = session
            self.rows = rows
        }
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
        if plan.replacementGeneration,
           !plan.replacementPending,
           Self.dropStaleCodexSessionAliases(
               currentSession: plan.parsed.codexSession,
               currentHasTypedResponseIdentity: plan.parsed.requestLedgerState?.hasTypedResponseIdentity == true
                   || input.cached?.codexTypedResponseIdentity == true,
               currentFile: (
                   path: input.metadata.path,
                   mtimeUnixMs: input.metadata.mtimeUnixMs,
                   size: input.metadata.size),
               cache: &cache)
        {
            return
        }
        if !plan.replacementPending, let cached = plan.cached {
            Self.applyFileDays(cache: &cache, fileDays: cached.days, sign: -1)
        }
        guard let materialized = try Self.materializeCodexRescan(
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
        // Preparation and assembly copy large cached usage values. Finish those phases
        // outside the parser's call frame so inherited-baseline callbacks have stack room.
        let preparation = Self.prepareCodexRescan(input: input, context: context)
        let parsed = try Self.parseCodexReplacement(
            input: input,
            context: context,
            includeInitialBufferedTokenSnapshots: input.cached?.codexReplacementScanPending == true
                && !preparation.stageParsedRows,
            maxBytesToRead: maxBytesToRead)
        return Self.makeCodexRescanPlan(
            input: input,
            context: context,
            preparation: preparation,
            parsed: parsed)
    }

    private static func prepareCodexRescan(
        input: CodexFileScanInput,
        context: CodexFileScanContext) -> CodexRescanPreparation
    {
        let cached = input.cached
        let recoveringSourceRows = context.sourceRowRecoveryPathKeys.contains(Self.codexPathKey(input.fileURL))
            || Self.codexFileNeedsSourceRowRecovery(cached, context: context)
        var sourcePricing = Self.codexSourcePricingForScan(
            cached: cached,
            metadata: input.metadata,
            range: context.range,
            recoveringSourceRows: recoveringSourceRows)
        if context.dropDeferredCodexRows { sourcePricing = nil }
        let sourceAnchor = Self.codexSourcePricingAnchor(
            cached: cached, recoveringSourceRows: recoveringSourceRows)
        // Older rows may combine events split by the corrected parser or include inherited
        // subagent history. A replacement must never merge those rows back into the new ledger.
        let parserRevisionNeedsReplacement = cached?.hasCurrentCodexParser == false
        let stageParsedRows = parserRevisionNeedsReplacement || sourcePricing != nil
            || cached?.codexStagedRecoveryRows != nil
        let migratedCached = context.dropDeferredCodexRows
            ? nil : cached.map {
                sourcePricing == nil ? Self.codexFileUsageWithPricingMetadata($0, context: context) : $0
            }
        return CodexRescanPreparation(
            migratedCached: migratedCached,
            sourcePricing: sourcePricing,
            sourceAnchor: sourceAnchor,
            parserRevisionNeedsReplacement: parserRevisionNeedsReplacement,
            stageParsedRows: stageParsedRows)
    }

    private static func codexReplacementResumeOffset(input: CodexFileScanInput) -> Int64? {
        guard let cached = input.cached,
              cached.codexReplacementScanPending == true,
              // A complete subagent replacement can change attribution when appended lineage
              // metadata arrives, so restart it from byte zero and keep the per-refresh bound
              // effective. Once that bounded cold start is itself partial, its staged prefix
              // is safe to resume; ordinary unresolved-fork buffers are append-safe.
              cached.codexScanComplete == false
              || cached.codexBufferedSubagentLines?.isEmpty != false,
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
        return parsedBytes
    }

    private static func parseCodexReplacement(
        input: CodexFileScanInput,
        context: CodexFileScanContext,
        includeInitialBufferedTokenSnapshots: Bool,
        maxBytesToRead: Int64?) throws -> CodexParseResult
    {
        let resumeOffset = Self.codexReplacementResumeOffset(input: input)
        let stagedUsage = resumeOffset == nil ? nil : input.cached
        return try Self.parseCodexFileCancellable(
            fileURL: input.fileURL,
            range: context.range,
            startOffset: resumeOffset ?? 0,
            initialModel: stagedUsage?.lastModel,
            initialSessionID: stagedUsage?.sessionId,
            initialTotals: stagedUsage?.lastCountedTotals,
            initialRawTotalsBaseline: stagedUsage?.lastRawTotalsBaseline,
            initialRawTotalsWatermark: stagedUsage?.lastRawTotalsWatermark,
            initialSeenRawTotals: stagedUsage?.seenRawTotals ?? [],
            initialHasDivergentTotals: stagedUsage?.hasDivergentTotals ?? false,
            initialHasInterleavedTotals: stagedUsage?.hasInterleavedTotals ?? false,
            initialCodexTurnID: stagedUsage?.lastCodexTurnID,
            // Replacement rows are always indexed from zero. The previously committed rows are
            // not part of this generation and must never affect the replay's event indexes.
            initialCodexUsageRowIndex: stagedUsage?.codexNextUsageRowIndex ?? 0,
            initialLastAcceptedTokenTimestampUnixMs: stagedUsage?.codexSession?.latestAcceptedUsageUnixMs,
            initialBufferedSubagentLines: stagedUsage?.codexBufferedSubagentLines,
            initialBufferedUnresolvedForkLines: stagedUsage?.codexBufferedUnresolvedForkLines,
            includeInitialBufferedTokenSnapshots: includeInitialBufferedTokenSnapshots,
            initialJSONLResumeState: stagedUsage?.codexJSONLResumeState,
            initialForkAccountingState: stagedUsage?.codexForkAccountingState,
            initialRequestLedgerState: stagedUsage?.codexRequestLedgerState,
            initialRequestLedgerRows: stagedUsage?.codexStagedRecoveryRows ?? [],
            maxBytesToRead: maxBytesToRead,
            shouldStopReading: context.scanBudget.map { budget in
                { bytesRead in budget.shouldYield(additionalBytes: bytesRead) }
            },
            inheritedTotalsResolver: context.resources.inheritedResolver.inheritedTotals(for:atOrBefore:),
            checkCancellation: context.checkCancellation)
    }

    private static func makeCodexRescanPlan(
        input: CodexFileScanInput,
        context: CodexFileScanContext,
        preparation: CodexRescanPreparation,
        parsed: CodexParseResult) -> CodexRescanPlan
    {
        let cached = input.cached
        let replacementWasPending = cached?.codexReplacementScanPending == true
        let sourceScanComplete = parsed.parsedBytes >= input.metadata.size && parsed.jsonlResumeState == nil
        let hasReplayBuffer = parsed.bufferedSubagentLines != nil
            || parsed.bufferedUnresolvedForkLines != nil
        // A bounded reread of committed rows must stage its new generation. Otherwise a partial
        // prefix can be published with the old rows, then appended a second time on resume.
        // Retain that prefix until the complete generation atomically replaces the committed one.
        let replacementGeneration = replacementWasPending || preparation.stageParsedRows || hasReplayBuffer
            || sourceScanComplete || cached?.codexRows?.isEmpty == false
            || cached?.codexTokenSnapshots?.isEmpty == false || cached?.days.isEmpty == false
        // Unresolved lineage is still staged work. Do not replace a committed subagent ledger
        // with an empty/partial replay while its parent snapshots are unavailable.
        let replacementPending = replacementGeneration && (!sourceScanComplete || hasReplayBuffer)
        let scanComplete = sourceScanComplete
        // A pending replacement retains the committed aggregate contribution in memory. The
        // staged parser state is persisted separately and is invisible to report aggregation.
        let retainedCommittedDays = context.dropDeferredCodexRows
            ? [:]
            : Self.fileDaysOutsideScanWindow(preparation.migratedCached?.days ?? [:], range: context.range)
        let usageDays = replacementPending
            ? cached?.days ?? retainedCommittedDays
            : retainedCommittedDays
        return CodexRescanPlan(
            cached: cached,
            migratedCached: preparation.migratedCached,
            parsed: parsed,
            replacementWasPending: replacementWasPending,
            parserRevisionNeedsReplacement: preparation.parserRevisionNeedsReplacement,
            replacementGeneration: replacementGeneration,
            replacementPending: replacementPending,
            scanComplete: scanComplete,
            usageDays: usageDays,
            sourcePricing: preparation.sourcePricing,
            sourceAnchor: preparation.sourceAnchor,
            stageParsedRows: preparation.stageParsedRows)
    }

    private static func codexRescanSessionMetadata(
        cached: CostUsageFileUsage?,
        parsed: CodexParseResult) -> CostUsageCodexSessionMetadata
    {
        let cachedSessionMetadata = cached?.codexSession ?? CostUsageCodexSessionMetadata(
            sessionId: cached?.sessionId,
            forkedFromId: cached?.forkedFromId,
            cwd: nil,
            title: nil,
            startedAtUnixMs: nil,
            latestActivityUnixMs: nil)
        return cachedSessionMetadata.merging(parsed.codexSession)
    }

    private static func codexRescanRowsRetainingRequestOwnership(
        input: CodexFileScanInput,
        context: CodexFileScanContext,
        rows: [CodexUsageRow],
        sessionID: String?,
        sourcePricing: [CodexSourcePricingKey: CodexPricingEvidence]?) -> [CodexUsageRow]
    {
        guard !context.dropDeferredCodexRows, sourcePricing == nil,
              let cached = input.cached, cached.hasCurrentCodexParser,
              cached.sessionId == sessionID, cached.codexScanFileId == input.metadata.fileId,
              let anchor = cached.codexTokenIndexAnchor,
              codexTokenIndexAnchorMatches(anchor, fileURL: input.fileURL, metadata: input.metadata)
        else { return rows }
        return Self.codexRowsRetainingRequestOwnership(
            rows,
            ownedRows: Self.codexRowsWithLedgerMirrorAliases(
                cached.codexRows ?? [], ledger: cached.codexRequestLedgerState))
    }

    private static func materializeCodexRescan(
        plan: CodexRescanPlan,
        input: CodexFileScanInput,
        context: CodexFileScanContext,
        state: inout CodexScanState) throws -> CodexRescanMaterialized?
    {
        let parsed = plan.parsed
        let migratedCached = plan.migratedCached
        let parsedCodexSession = Self.codexRescanSessionMetadata(cached: input.cached, parsed: parsed)
        let sessionId = parsedCodexSession.sessionId ?? parsed.sessionId ?? input.cached?.sessionId
        let projectPath = parsed.projectPath ?? input.cached?.projectPath
        let canonicalProjectPath = parsed.projectPath.map {
            context.resources.projectPathResolver.canonicalProjectPath(for: $0)
        } ?? input.cached?.canonicalProjectPath ?? context.resources.projectPathResolver
            .canonicalProjectPath(for: projectPath)
        let stagedRows = (plan.replacementWasPending ? input.cached?.codexStagedRecoveryRows ?? [] : []).filter {
            $0.eventIndex.map { !parsed.replacedLegacyRowIndices.contains($0) } ?? true
        }
        let sourceSessionID = parsed.sessionId ?? input.cached?.sessionId
        let sourcePricing = input.cached?.sessionId != nil && parsed.sessionId != nil
            && parsed.sessionId != input.cached?.sessionId ? [:] : plan.sourcePricing
        var pendingPricing = Self.codexRescanPendingPricing(
            migratedCached: migratedCached,
            metadata: input.metadata,
            sessionId: sourceSessionID,
            preserveCachedRows: sourcePricing == nil && !plan.parserRevisionNeedsReplacement)
        let ownershipRows = Self.codexRescanRowsRetainingRequestOwnership(
            input: input, context: context, rows: parsed.rows, sessionID: sourceSessionID, sourcePricing: sourcePricing)
        let classifiedNewRows = Self.codexRowsWithRetainedPricing(
            ownershipRows,
            source: (sourcePricing, parsed, plan.sourceAnchor?.indexedBytes),
            pendingPricing: &pendingPricing,
            sessionId: sourceSessionID,
            priorityTurns: context.resources.priorityTurns)
        let recoveredStagedRows = Self.codexRowsRecoveringLedgerPricing(
            stagedRows,
            pricing: sourcePricing,
            ledgerLegacyKeys: parsed.ledgerLegacyPricingKeys,
            priorityTurns: context.resources.priorityTurns)
        let replayedRows = recoveredStagedRows + classifiedNewRows
        let replayedSnapshots = plan.replacementWasPending
            ? Self.mergingCodexTokenSnapshots(input.cached?.codexStagedRecoverySnapshots ?? [], parsed.tokenSnapshots)
            : parsed.tokenSnapshots
        let uniqueRows = Self.uniqueCodexRows(
            rows: replayedRows,
            sessionId: sessionId,
            fileIdentity: input.metadata.path,
            state: &state)
        // Source-boundary and pending pricing are applied before deduplication so invalidated
        // historical evidence cannot reprice a replacement generation.
        let classifiedRows = uniqueRows
        let requestLedgerState = classifiedRows.reduce(parsed.requestLedgerState) { ledger, row in
            Self.codexLedgerRetainingPromotedRow(row, state: ledger)
        }
        context.workRecorder?.record(processed: uniqueRows.count, repriced: uniqueRows.count)
        let usageDays = plan.usageDays
        let duplicateWithoutUniqueUsage = plan.scanComplete
            && !plan.replacementPending
            && sessionId.map { state.contributingSessionIds.contains($0) } == true
            && uniqueRows.isEmpty
            && usageDays.isEmpty
            && parsed.bufferedSubagentLines == nil
            && parsed.bufferedUnresolvedForkLines == nil
        let accounting = Self.codexRescanAccounting(
            plan: plan,
            context: context,
            uniqueRows: classifiedRows,
            sessionId: sessionId)
        var usage = try Self.makeFileUsage(
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
                hasResolvedForkBaseline: parsed.forkBaselineResolved,
                inheritedResolver: context.resources.inheritedResolver),
            projectPath: projectPath,
            canonicalProjectPath: canonicalProjectPath,
            codexSession: parsedCodexSession.isEmpty ? nil : parsedCodexSession,
            codexCostNanos: plan.replacementPending
                ? migratedCached?.codexCostNanos
                : Self.mergeCostMaps(
                    accounting.costBaseline,
                    Self.codexCostNanos(rows: classifiedRows, range: context.range)),
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
                : Self.mergeCodexTurnIDs(accounting.turnIDBaseline, rows: classifiedRows),
            // Do not merge replayed rows with the committed generation. Pending passes need no
            // event rows; completion receives the full replay from the parser and replaces them.
            codexRows: plan.replacementPending
                ? nil
                : Self.codexRowsWithPricingMetadata(
                    accounting.persistedRows,
                    priorityTurns: context.resources.priorityTurns),
            codexTokenSnapshots: replayedSnapshots,
            codexTokenCheckpoints: plan.replacementPending
                ? nil
                : Self.codexTokenCheckpoints(for: replayedSnapshots),
            codexTokenTimestampsMonotonic: plan.replacementPending
                ? migratedCached?.codexTokenTimestampsMonotonic
                : Self.codexTokenTimestampsAreMonotonic(
                    replayedSnapshots,
                    checkCancellation: context.checkCancellation,
                    workRecorder: context.workRecorder),
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
            // Keep the old marker until the full replacement commits. A resumed bounded pass
            // must still discard superseded rows outside its current report window.
            codexParserRevision: plan.replacementPending && plan.parserRevisionNeedsReplacement
                ? input.cached?.codexParserRevision
                : CostUsageFileUsage.currentCodexParserRevision,
            codexJSONLResumeState: parsed.jsonlResumeState,
            codexForkAccountingState: parsed.forkAccountingState,
            codexRequestLedgerState: requestLedgerState,
            codexBufferedSubagentLines: parsed.bufferedSubagentLines,
            codexBufferedUnresolvedForkLines: parsed.bufferedUnresolvedForkLines)
            .refreshingCodexWorkspaceUsageFingerprint()
        usage.codexNextUsageRowIndex = parsed.nextUsageRowIndex
        Self.retainCodexSourcePricing(&usage, pricing: sourcePricing, anchor: plan.sourceAnchor)
        usage.codexPendingPricing = pendingPricing.isEmpty
            || (usage.codexScanComplete == true && !usage.hasBufferedCodexForkRetryLines) ? nil : pendingPricing
        usage.codexStagedRecoveryRows = plan.replacementPending ? uniqueRows : nil
        usage.codexStagedRecoverySnapshots = plan.replacementPending
            ? replayedSnapshots : nil
        if duplicateWithoutUniqueUsage, parsed.requestLedgerState?.hasTypedResponseIdentity != true,
           !parsed.rows.isEmpty || !Self.isCompleteEmptyCodexFragment(usage)
        {
            return nil
        }
        let session = CodexScannedSession(
            id: sessionId,
            days: plan.replacementPending ? [:] : accounting.usageDays)
        return CodexRescanMaterialized(
            usage: usage,
            session: session,
            rows: plan.replacementPending ? [] : classifiedRows)
    }
}
