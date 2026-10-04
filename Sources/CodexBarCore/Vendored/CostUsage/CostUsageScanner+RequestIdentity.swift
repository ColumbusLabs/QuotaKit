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
        _ row: CodexUsageRow, canonical: CodexUsageRow, additional: CodexUsageRow? = nil) -> CodexUsageRow
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
            responseID: row.responseID,
            requestMirrorKeys: Array(Set(candidates.flatMap { $0.requestMirrorKeys ?? [] })).sorted())
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
            for (snapshot, responseID) in file.codexRequestLedgerState?.mirroredResponses ?? [:] {
                aliases[scope + "\u{1F}" + snapshot] = Self.codexResponseKey(scope: scope, responseID: responseID)
            }
            for (index, candidate) in (file.codexRows ?? []).enumerated() where candidate.responseID != nil {
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
                let candidateWins = candidateAnchor != previousAnchor ? candidateAnchor : earlierCandidate
                let winner = candidateWins ? location : previous
                let loser = candidateWins ? previous : location
                let canonical = earlierCandidate ? candidate : previousRow
                var targets = replacements[winner.path] ?? cache.files[winner.path]?.codexRows ?? []
                targets[winner.index] = Self.codexRequestRowPreservingLocalIdentity(
                    row(at: winner), canonical: canonical, additional: row(at: loser))
                replacements[winner.path] = targets
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
                removals[path, default: []].insert(index)
                retainPricing(from: candidate, at: match)
            }
        }
        for path in Set(replacements.keys).union(removals.keys) {
            guard let old = cache.files[path] else { continue }
            let rows = (replacements[path] ?? old.codexRows ?? []).enumerated().compactMap { index, row in
                removals[path]?.contains(index) == true ? nil : row
            }
            let allDays = Array(old.days.keys) + (old.codexRows ?? []).map(\.day) + rows.map(\.day)
            let updated = Self.codexFileUsageByFilteringRows(
                old, rows: rows, context: context,
                rangeOverride: CostUsageDayRange(coveringDayKeys: allDays, calendar: context.range.calendar))
            Self.applyFileDays(cache: &cache, fileDays: old.days, sign: -1)
            cache.files[path] = updated
            Self.applyFileDays(cache: &cache, fileDays: updated.days, sign: 1)
        }
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
