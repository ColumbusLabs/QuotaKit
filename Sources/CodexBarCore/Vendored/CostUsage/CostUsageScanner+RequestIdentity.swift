import Foundation

extension CostUsageScanner {
    static func codexUsageRowKey(
        sessionId: String?,
        fileIdentity: String? = nil,
        row: CodexUsageRow) -> String
    {
        if let responseID = row.responseID {
            return self.codexResponseKey(scope: sessionId ?? fileIdentity ?? "", responseID: responseID)
        }
        return [
            sessionId.map { "session:\($0)" } ?? "file:\(fileIdentity ?? "")",
            row.turnID ?? "",
            row.eventIndex.map(String.init) ?? "",
            row.day,
            row.model,
            String(row.input),
            String(row.cached),
            String(row.output),
        ].joined(separator: "\u{1F}")
    }

    static func uniqueCodexRows(
        rows: [CodexUsageRow],
        sessionId: String?,
        fileIdentity: String,
        state: inout CodexScanState) -> [CodexUsageRow]
    {
        var unique: [CodexUsageRow] = []
        var acceptedKeys = Set<String>()
        for row in rows {
            let key = Self.codexCrossFileRowKey(sessionId: sessionId, fileIdentity: fileIdentity, row: row)
            let unseen = row.responseID == nil
                ? !state.seenCodexUsageRowKeys.contains(key)
                : !acceptedKeys.contains(key)
                && (state.retainCandidateResponseDuplicates || !state.seenCodexUsageRowKeys.contains(key))
            if unseen {
                unique.append(state.committedCodexResponseRows[key].map {
                    let canonical = (row.timestampUnixMs ?? .max) < ($0.timestampUnixMs ?? .max) ? row : $0
                    return Self.codexRequestRowPreservingLocalIdentity(row, canonical: canonical, additional: $0)
                } ?? row)
                acceptedKeys.insert(key)
            }
        }
        state.seenCodexUsageRowKeys.formUnion(acceptedKeys)
        return unique
    }

    static func rememberCodexRows(
        _ rows: [CodexUsageRow],
        sessionId: String?,
        fileIdentity: String,
        state: inout CodexScanState)
    {
        for row in rows {
            state.seenCodexUsageRowKeys.insert(self.codexCrossFileRowKey(
                sessionId: sessionId,
                fileIdentity: fileIdentity,
                row: row))
        }
    }

    /// Preserve the canonical response's accounting evidence while keeping this page's local row index.
    private static func codexRequestRowPreservingLocalIdentity(
        _ row: CodexUsageRow,
        canonical: CodexUsageRow,
        additional: CodexUsageRow? = nil,
        responseID: String? = nil,
        mirrorKeys: [String] = []) -> CodexUsageRow
    {
        let candidates = [canonical] + (additional.map { [$0] } ?? []) + [row]
        let price = candidates.first {
            $0.model == canonical.model && $0.input == canonical.input
                && $0.cached == canonical.cached && $0.output == canonical.output
                && ($0.knownCostNanos != nil || $0.unpricedTokens != nil || $0.pricingMode == "priority"
                    || ($0.pricingModel != nil && $0.pricingModel != $0.model))
        } ?? canonical
        return CodexUsageRow(
            day: canonical.day,
            model: canonical.model,
            rawModel: canonical.rawModel,
            turnID: canonical.turnID,
            eventIndex: row.eventIndex,
            timestampUnixMs: canonical.timestampUnixMs,
            input: canonical.input,
            cached: canonical.cached,
            output: canonical.output,
            reasoning: canonical.reasoning,
            knownCostNanos: price.knownCostNanos,
            unpricedTokens: price.unpricedTokens,
            pricingModel: price.pricingModel,
            pricingMode: price.pricingMode,
            responseID: responseID ?? row.responseID,
            requestMirrorKeys: Array(Set(candidates.flatMap { $0.requestMirrorKeys ?? [] } + mirrorKeys)).sorted())
    }

    /// Carry aliases learned from adjacent legacy observations with the response's owned row.
    static func codexRowsWithLedgerMirrorAliases(
        _ rows: [CodexUsageRow],
        ledger: CodexRequestLedgerState?) -> [CodexUsageRow]
    {
        var mirrors: [String: [String]] = [:]
        for (key, responseID) in ledger?.mirroredResponses ?? [:] {
            mirrors[responseID, default: []].append(key)
        }
        return rows.map { row in
            guard let responseID = row.responseID, let keys = mirrors[responseID] else { return row }
            return Self.codexRequestRowPreservingLocalIdentity(row, canonical: row, mirrorKeys: keys)
        }
    }

    /// A source replay may produce legacy rows for requests whose typed owners were transferred here.
    /// Restore identity only onto observed rows; never merge unobserved rows from the old generation.
    static func codexRowsRetainingRequestOwnership(
        _ rows: [CodexUsageRow],
        ownedRows: [CodexUsageRow]) -> [CodexUsageRow]
    {
        var responses: [String: CodexUsageRow] = [:]
        var mirrors: [String: Set<String>] = [:]
        for row in ownedRows {
            guard let responseID = row.responseID else { continue }
            responses[responseID] = row
            for key in row.requestMirrorKeys ?? [] {
                mirrors[key, default: []].insert(responseID)
            }
        }
        return rows.map { row in
            let matchingIDs = row.responseID.map { Set([$0]) } ?? Set((row.requestMirrorKeys ?? [])
                .flatMap { mirrors[$0] ?? [] })
            guard matchingIDs.count == 1, let responseID = matchingIDs.first,
                  let canonical = responses[responseID],
                  row.model == canonical.model, row.input == canonical.input,
                  row.cached == canonical.cached, row.output == canonical.output,
                  row.reasoning == canonical.reasoning
            else { return row }
            let earlierTypedRow = row.responseID != nil
                && (row.timestampUnixMs ?? .max) < (canonical.timestampUnixMs ?? .max)
            return Self.codexRequestRowPreservingLocalIdentity(
                row,
                canonical: earlierTypedRow ? row : canonical,
                additional: canonical,
                responseID: responseID)
        }
    }

    /// Reconcile committed siblings and new pages before their aggregate updates share one transaction.
    static func reconcileCodexRequestMirrors(cache: inout CostUsageCache, context: CodexFileScanContext) {
        let paths = cache.files.keys.filter {
            cache.files[$0]?.hasCurrentCodexParser == true
                && cache.files[$0]?.codexScanComplete == true
                && cache.files[$0]?.hasPendingCodexReplacementScan != true
        }.sorted()
        var aliases: [String: String] = [:]
        var owned: [String: (path: String, index: Int)] = [:]
        var replacements: [String: [CodexUsageRow]] = [:]
        var removals: [String: Set<Int>] = [:]
        let retainedRequestOwners = Set((cache.codexHistoryHydrationRetries ?? [:]).values
            .flatMap { $0.requestOwnerPaths ?? [] })
        let missingRequestOwners = retainedRequestOwners.filter { !FileManager.default.fileExists(atPath: $0) }
        func row(at location: (path: String, index: Int)) -> CodexUsageRow {
            (replacements[location.path] ?? cache.files[location.path]?.codexRows ?? [])[location.index]
        }
        func retainPricing(from source: CodexUsageRow, at location: (path: String, index: Int)) {
            let target = row(at: location)
            guard target.model == source.model, target.input == source.input,
                  target.cached == source.cached, target.output == source.output,
                  target.knownCostNanos == nil, target.unpricedTokens == nil,
                  source.knownCostNanos != nil || source.unpricedTokens != nil || source.pricingMode == "priority"
                  || (source.pricingModel != nil && source.pricingModel != source.model)
            else { return }
            var targets = replacements[location.path] ?? cache.files[location.path]?.codexRows ?? []
            targets[location.index].knownCostNanos = source.knownCostNanos
            targets[location.index].unpricedTokens = source.unpricedTokens
            targets[location.index].pricingModel = source.pricingModel
            targets[location.index].pricingMode = source.pricingMode
            replacements[location.path] = targets
        }
        for path in paths {
            guard let file = cache.files[path] else { continue }
            let scope = file.sessionId ?? path
            let sourceRows = replacements[path] ?? file.codexRows ?? []
            let aliasedRows = Self.codexRowsWithLedgerMirrorAliases(sourceRows, ledger: file.codexRequestLedgerState)
            if aliasedRows != sourceRows { replacements[path] = aliasedRows }
            for (snapshot, responseID) in file.codexRequestLedgerState?.mirroredResponses ?? [:] {
                aliases[scope + "\u{1F}" + snapshot] = Self.codexResponseKey(scope: scope, responseID: responseID)
            }
            for (index, candidate) in aliasedRows.enumerated() where candidate.responseID != nil {
                let key = Self.codexUsageRowKey(sessionId: file.sessionId, fileIdentity: path, row: candidate)
                // Canonical rows carry aliases from earlier sibling slices even when the original
                // owner is now rowless or outside the current hydration cohort.
                for snapshot in candidate.requestMirrorKeys ?? [] {
                    aliases[scope + "\u{1F}" + snapshot] = key
                }
                let location = (path: path, index: index)
                guard let previous = owned[key] else { owned[key] = location; continue }
                let previousRow = row(at: previous)
                // Keep a response anchor in the actively reconciled page so later sibling slices
                // can resolve mirrors without rehydrating every previously visited owner.
                let candidateAnchor = context.requestReconciliationCandidatePaths.contains(path)
                let previousAnchor = context.requestReconciliationCandidatePaths.contains(previous.path)
                let earlierCandidate = (candidate.timestampUnixMs ?? .max, path, index)
                    < (previousRow.timestampUnixMs ?? .max, previous.path, previous.index)
                let candidateMissing = missingRequestOwners.contains(path)
                let previousMissing = missingRequestOwners.contains(previous.path)
                let candidateWins = candidateMissing != previousMissing ? !candidateMissing
                    : (candidateAnchor != previousAnchor ? candidateAnchor : earlierCandidate)
                let winner = candidateWins ? location : previous
                let loser = candidateWins ? previous : location
                let canonical = earlierCandidate ? candidate : previousRow
                var targets = replacements[winner.path] ?? cache.files[winner.path]?.codexRows ?? []
                targets[winner.index] = Self.codexRequestRowPreservingLocalIdentity(
                    row(at: winner), canonical: canonical, additional: row(at: loser))
                replacements[winner.path] = targets
                cache.files[winner.path]?.codexRequestLedgerState = Self.codexLedgerRetainingPromotedRow(
                    targets[winner.index], state: cache.files[winner.path]?.codexRequestLedgerState)
                retainPricing(from: row(at: loser), at: winner)
                removals[loser.path, default: []].insert(loser.index)
                owned[key] = winner
            }
        }
        for path in paths {
            guard let file = cache.files[path] else { continue }
            let scope = file.sessionId ?? path
            for (index, candidate) in (file.codexRows ?? []).enumerated() where candidate.responseID == nil {
                guard let match = (candidate.requestMirrorKeys ?? []).compactMap({ aliases[scope + "\u{1F}" + $0] })
                    .compactMap({ owned[$0] }).first else { continue }
                if retainedRequestOwners.contains(match.path),
                   context.requestReconciliationCandidatePaths.contains(path)
                   || (missingRequestOwners.contains(match.path) && FileManager.default.fileExists(atPath: path))
                {
                    let canonical = row(at: match)
                    let promoted = Self.codexRequestRowPreservingLocalIdentity(
                        candidate,
                        canonical: canonical,
                        responseID: canonical.responseID)
                    var targets = replacements[path] ?? cache.files[path]?.codexRows ?? []
                    targets[index] = promoted
                    replacements[path] = targets
                    removals[match.path, default: []].insert(match.index)
                    let key = Self.codexUsageRowKey(sessionId: file.sessionId, fileIdentity: path, row: promoted)
                    owned[key] = (path, index)
                    for snapshot in promoted.requestMirrorKeys ?? [] {
                        aliases[scope + "\u{1F}" + snapshot] = key
                    }
                    let promotedLedgerState = Self.codexLedgerRetainingPromotedRow(
                        promoted,
                        state: cache.files[path]?.codexRequestLedgerState)
                    cache.files[path]?.codexRequestLedgerState = promotedLedgerState
                } else {
                    removals[path, default: []].insert(index)
                    retainPricing(from: candidate, at: match)
                }
            }
        }
        for path in Set(replacements.keys).union(removals.keys) {
            guard let old = cache.files[path] else { continue }
            let rows = (replacements[path] ?? old.codexRows ?? []).enumerated().compactMap { index, row in
                removals[path]?.contains(index) == true ? nil : row
            }
            let allDays = Array(old.days.keys) + (old.codexRows ?? []).map(\.day) + rows.map(\.day)
            let updated = Self.codexFileUsageByFilteringRows(
                old,
                rows: rows,
                context: context,
                rangeOverride: CostUsageDayRange(coveringDayKeys: allDays, calendar: context.range.calendar))
            Self.applyFileDays(cache: &cache, fileDays: old.days, sign: -1)
            cache.files[path] = updated
            Self.applyFileDays(cache: &cache, fileDays: updated.days, sign: 1)
        }
    }

    static func codexLedgerRetainingPromotedRow(
        _ row: CodexUsageRow,
        state: CodexRequestLedgerState?) -> CodexRequestLedgerState?
    {
        guard let responseID = row.responseID else { return state }
        var ledger = state ?? CodexRequestLedgerState()
        ledger.responseIDs.insert(responseID)
        if let eventIndex = row.eventIndex {
            ledger.legacyRowIndices = ledger.legacyRowIndices.filter { $0.value != eventIndex }
            if ledger.pendingLegacyRowIndex == eventIndex { ledger.clearPendingMirrors() }
        }
        ledger.rememberMirrors(row.requestMirrorKeys ?? [], responseID: responseID)
        return ledger
    }

    /// Preserve the removed owner's canonical date/pricing until surviving source pages rebuild.
    static func deferMissingCodexRequestOwner(path: String, cache: inout CostUsageCache) -> Bool {
        guard let owner = cache.files[path], !owner.days.isEmpty,
              let sessionID = owner.sessionId,
              owner.codexRequestReconciliation != nil || owner.codexTypedResponseIdentity == true
        else { return false }
        let siblings = cache.files.keys.filter {
            $0 != path && cache.files[$0]?.sessionId == sessionID && FileManager.default.fileExists(atPath: $0)
        }
        guard !siblings.isEmpty else { return false }
        var retries = cache.codexHistoryHydrationRetries ?? [:]
        // Existing recovery owns the full source cohort; keep its bounded visit progress intact.
        if retries.values.contains(where: { $0.requestOwnerPaths?.contains(path) == true }) { return true }
        for sibling in siblings {
            let retry = CodexHistoryHydrationRetry(
                retainedPaths: [path, sibling],
                forceFullRescan: true,
                requestOwnerPaths: [path])
            if var existing = retries[sibling] {
                existing.merge(retry)
                retries[sibling] = existing
            } else {
                retries[sibling] = retry
            }
        }
        cache.codexHistoryHydrationRetries = retries
        cache.codexScanCatchUpPending = true
        return true
    }

    static func completeCodexRequestOwnerRetries(
        processedPaths: Set<String>,
        retries: inout [String: CodexHistoryHydrationRetry],
        cache: inout CostUsageCache) -> Set<String>
    {
        var completedOwners = Set<String>()
        var completedMissingTargets = Set<String>()
        for target in processedPaths {
            guard var retry = retries[target], let owners = retry.requestOwnerPaths else { continue }
            let missingSource = !FileManager.default.fileExists(atPath: target)
            if !missingSource, let usage = cache.files[target] {
                guard usage.codexScanComplete == true, usage.hasCurrentCodexParser,
                      !usage.hasPendingCodexReplacementScan else { continue }
            }
            if !missingSource, cache.files[target]?.hasPendingCodexScanWork == true {
                // Source replay is complete; subsequent passes only hydrate the remaining siblings.
                retry.forceFullRescan = false
                retries[target] = retry
            } else {
                completedOwners.formUnion(owners)
                // A target with its own contribution still needs the ordinary owner-recovery path.
                if missingSource, cache.files[target]?.days.isEmpty == true {
                    completedMissingTargets.insert(target)
                }
                retries.removeValue(forKey: target)
            }
        }
        // Generic fork/history retries also protect complete canonical baselines.
        let retainedOwners = Set(retries.values.flatMap(\.retainedPaths))
        var retiredOwners = Set<String>()
        for owner in completedOwners.union(completedMissingTargets).subtracting(retainedOwners) {
            guard !FileManager.default.fileExists(atPath: owner) else { continue }
            Self.dropCachedCodexFile(path: owner, cached: cache.files[owner], cache: &cache)
            retiredOwners.insert(owner)
        }
        return retiredOwners
    }

    private static func codexResponseKey(scope: String, responseID: String) -> String {
        [scope, "response", responseID].joined(separator: "\u{1F}")
    }

    private static func codexCrossFileRowKey(
        sessionId: String?,
        fileIdentity: String,
        row: CodexUsageRow) -> String
    {
        // Page-local event indices restart; timestamps distinguish new requests from archived copies.
        let key = self.codexUsageRowKey(sessionId: sessionId, fileIdentity: fileIdentity, row: row)
        return row.responseID == nil ? key + "\u{1F}" + (row.timestampUnixMs.map(String.init) ?? "") : key
    }
}
