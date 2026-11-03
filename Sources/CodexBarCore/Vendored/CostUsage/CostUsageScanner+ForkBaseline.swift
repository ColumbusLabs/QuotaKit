import Foundation

extension CostUsageScanner {
    /// A replacement prefix owns one inherited baseline. Validate it before admission,
    /// so a changed ancestor restarts both accounting and the charged source-byte range.
    static func prepareCodexReplacementForkResume(
        fileURL: URL,
        metadata: CodexFileMetadata,
        context: CodexFileScanContext,
        cache: inout CostUsageCache) throws -> Bool
    {
        let input = CodexFileScanInput(fileURL: fileURL, metadata: metadata, cached: cache.files[metadata.path])
        guard var cached = input.cached,
              cached.codexReplacementScanPending == true,
              cached.codexForkAccountingState != nil,
              cached.forkBaselineDependencyKey != Self.codexForkDependencyNotRequiredKey,
              Self.codexReplacementResumeOffset(input: input) != nil,
              let parentID = cached.forkedFromId
        else { return true }
        guard let current = try context.resources.inheritedResolver.currentDependencyKey(for: parentID)
        else { return false }
        guard current != cached.forkBaselineDependencyKey else { return true }

        // These fields belong to the uncommitted replacement only. Its committed rows,
        // snapshots, prices, and aggregate contribution remain intact until replay completes.
        cached.parsedBytes = 0
        cached.codexScanComplete = false
        cached.codexJSONLResumeState = nil
        cached.codexTokenIndexAnchor = nil
        cached.codexForkAccountingState = nil
        cached.forkBaselineDependencyKey = nil
        cached.codexStagedRecoveryRows = nil
        cached.codexStagedRecoverySnapshots = nil
        cached.codexBufferedUnresolvedForkLines = nil
        cached.codexHasBufferedUnresolvedForkLines = nil
        cache.files[metadata.path] = cached
        context.resources.inheritedResolver.updateCachedUsage(fileURL: fileURL, usage: cached)
        return true
    }

    static func codexResumedReplacementForkDependencyKey(
        input: CodexFileScanInput,
        context: CodexFileScanContext) throws -> String?
    {
        guard codexReplacementResumeOffset(input: input) != nil,
              let cached = input.cached,
              try canResumeCodexForkAccounting(cached, context: context)
        else { return nil }
        return cached.forkBaselineDependencyKey
    }

    static func codexBufferedForkWaitsForParent(
        _ cached: CostUsageFileUsage?,
        inheritedResolver: CodexInheritedTotalsResolver) throws -> Bool
    {
        guard let cached,
              let parentID = cached.forkedFromId,
              let buffered = cached.codexBufferedUnresolvedForkLines,
              let forkTimestamp = buffered.compactMap({ line -> String? in
                  guard case let .sessionMeta(metadata) = line.line else { return nil }
                  return metadata.forkTimestamp
              }).first,
              case .unresolved = try inheritedResolver.inheritedTotals(for: parentID, atOrBefore: forkTimestamp)
        else { return false }
        return inheritedResolver.dependencyKeyUsed(for: parentID).map(Self.codexDependencyIsMissing) != true
    }

    static func codexBufferedForkHasMetadata(_ cached: CostUsageFileUsage) -> Bool {
        ((cached.codexBufferedUnresolvedForkLines ?? []) + (cached.codexBufferedSubagentLines ?? []))
            .contains { buffered in
                if case .sessionMeta = buffered.line { return true }
                return false
            }
    }

    static func codexBufferedSnapshotsNeedRecovery(
        cached: CostUsageFileUsage,
        isBufferedForkResume: Bool) -> Bool
    {
        guard isBufferedForkResume else { return false }
        let indexedOffsets = Set((cached.codexTokenSnapshots ?? []).compactMap(\.endOffset))
        let bufferedLines = (cached.codexBufferedUnresolvedForkLines ?? [])
            + (cached.codexBufferedSubagentLines ?? [])
        return bufferedLines.contains { buffered in
            guard case let .tokenCount(record) = buffered.line,
                  record.last != nil || record.total != nil
            else { return false }
            guard let endOffset = buffered.endOffset else { return true }
            return !indexedOffsets.contains(endOffset)
        }
    }

    /// Replays any compact fork buffer without reading JSONL when the indexed file is unchanged.
    /// This remains safe for subagents because no appended lineage can change their classification.
    static func isValidatedSameSizeBufferedCodexForkRetry(
        metadata: CodexFileMetadata,
        cached: CostUsageFileUsage) -> Bool
    {
        let startOffset = cached.parsedBytes ?? cached.size
        guard cached.forkedFromId != nil,
              cached.hasBufferedCodexForkRetryLines,
              cached.codexScanComplete != false,
              cached.codexJSONLResumeState == nil,
              cached.codexScanFileId == metadata.fileId,
              startOffset > 0,
              startOffset == metadata.size,
              cached.codexTokenIndexAnchor?.indexedBytes == startOffset
        else { return false }
        return cached.codexTokenIndexAnchor.map {
            Self.codexTokenIndexAnchorMatches(
                $0,
                fileURL: URL(fileURLWithPath: metadata.path),
                metadata: metadata)
        } == true
    }

    /// Reuses compact ordinary-fork events for a validated appended suffix.
    /// Appended subagent buffers still require a full rescan because later lineage can change attribution.
    static func isAppendSafeBufferedCodexForkResume(
        metadata: CodexFileMetadata,
        cached: CostUsageFileUsage) -> Bool
    {
        let startOffset = cached.parsedBytes ?? cached.size
        guard cached.codexScanComplete != false,
              cached.forkedFromId != nil,
              cached.codexBufferedSubagentLines?.isEmpty != false,
              cached.codexBufferedUnresolvedForkLines?.isEmpty == false,
              cached.codexJSONLResumeState == nil,
              cached.codexScanFileId != nil,
              cached.codexScanFileId == metadata.fileId,
              startOffset > 0,
              startOffset <= metadata.size,
              cached.codexTokenIndexAnchor?.indexedBytes == startOffset
        else { return false }
        return cached.codexTokenIndexAnchor.map {
            Self.codexTokenIndexAnchorMatches(
                $0,
                fileURL: URL(fileURLWithPath: metadata.path),
                metadata: metadata)
        } == true
    }

    static func codexForkBaselineDependencyKey(
        parentSessionId: String?,
        dependsOnParentTotals: Bool,
        hasResolvedForkBaseline: Bool = true,
        inheritedResolver: CodexInheritedTotalsResolver) -> String?
    {
        guard let parentSessionId else { return nil }
        guard dependsOnParentTotals else { return Self.codexForkDependencyNotRequiredKey }
        let dependencyKey = inheritedResolver.dependencyKeyUsed(for: parentSessionId)
        // Exhausted discovery is stable dependency evidence even though no accounting
        // baseline exists. Deferred discovery and changing parents still retain nil.
        guard hasResolvedForkBaseline || dependencyKey.map(Self.codexDependencyIsMissing) == true
        else { return nil }
        return dependencyKey
    }

    static func mergingCodexTokenSnapshots(
        _ cached: [CostUsageCodexTokenSnapshot],
        _ replayed: [CostUsageCodexTokenSnapshot]) -> [CostUsageCodexTokenSnapshot]
    {
        var seenOffsets: Set<Int64> = []
        return (cached + replayed)
            .sorted { ($0.endOffset ?? .max) < ($1.endOffset ?? .max) }
            .filter { snapshot in
                guard let offset = snapshot.endOffset else { return true }
                return seenOffsets.insert(offset).inserted
            }
    }
}
