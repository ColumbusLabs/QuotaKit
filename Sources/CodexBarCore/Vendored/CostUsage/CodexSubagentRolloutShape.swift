import Foundation

extension CostUsageScanner {
    enum CodexSubagentCounterSemantics: Equatable {
        case independent
        case copiedPrefix
    }

    /// Subagent source is lineage evidence, not counter semantics. The first session metadata
    /// owns leaf identity; only embedded metadata proves that this rollout copied an ancestor
    /// prefix. Do not restore a blanket "all subagents are independent/inherited" rule.
    struct CodexSubagentRolloutShape {
        let counterSemantics: CodexSubagentCounterSemantics
        let ownedSuffix: CodexSubagentOwnedSuffix?
        let inferredParentSessionID: String?

        struct CodexSubagentOwnedSuffix {
            let startLineIndex: Int
            let rawTotalsBaseline: CostUsageCodexTotals
        }

        struct Observation {
            let lineIndex: Int
            let kind: Kind

            enum Kind {
                case sessionMetadata(id: String?)
                case turnContext
                case interAgentCommunication(triggerTurn: Bool)
                case tokenCount(total: CostUsageCodexTotals?, last: CostUsageCodexTotals?)
            }
        }

        static func classify(
            leafSessionID: String?,
            observedSessionIDs: [String?]) -> Self
        {
            let normalizedLeafID = Self.normalizedSessionID(leafSessionID)

            let hasEmbeddedAncestor: Bool = if let normalizedLeafID {
                observedSessionIDs.contains { Self.normalizedSessionID($0) != normalizedLeafID }
            } else {
                observedSessionIDs.count > 1 || observedSessionIDs.contains { Self.normalizedSessionID($0) != nil }
            }
            let distinctAncestorIDs = Set(observedSessionIDs
                .compactMap(Self.normalizedSessionID)
                .filter { normalizedLeafID == nil || $0 != normalizedLeafID })
            let inferredParentSessionID = distinctAncestorIDs.count == 1 ? distinctAncestorIDs.first : nil

            return Self(
                counterSemantics: hasEmbeddedAncestor ? .copiedPrefix : .independent,
                ownedSuffix: nil,
                inferredParentSessionID: inferredParentSessionID)
        }

        static func classify(
            leafSessionID: String?,
            observations: [Observation]) -> Self
        {
            let metadataIDs = observations.reduce(into: [String?]()) { result, observation in
                guard case let .sessionMetadata(id) = observation.kind else { return }
                result.append(id)
            }
            let metadataShape = Self.classify(
                leafSessionID: leafSessionID,
                observedSessionIDs: metadataIDs)
            guard metadataShape.counterSemantics == .copiedPrefix else { return metadataShape }

            let normalizedLeafID = Self.normalizedSessionID(leafSessionID)
            var lastRawTotals: CostUsageCodexTotals?
            var pendingTurnContext: (lineIndex: Int, baseline: CostUsageCodexTotals)?
            var ownedSuffix: CodexSubagentOwnedSuffix?
            var inspectedOwnedSuffixFirstTotal = false
            var observedAuthoritativeMetadata = false

            for observation in observations {
                switch observation.kind {
                case let .sessionMetadata(id):
                    let normalizedID = Self.normalizedSessionID(id)
                    let isEmbeddedAncestor: Bool = if !observedAuthoritativeMetadata {
                        false
                    } else if let normalizedLeafID {
                        normalizedID != normalizedLeafID
                    } else {
                        true
                    }
                    observedAuthoritativeMetadata = true
                    if isEmbeddedAncestor {
                        // A later ancestor meta proves that any earlier candidate boundary was replay.
                        ownedSuffix = nil
                        inspectedOwnedSuffixFirstTotal = false
                    }
                    pendingTurnContext = nil

                case .turnContext:
                    pendingTurnContext = lastRawTotals.map { (observation.lineIndex, $0) }

                case let .interAgentCommunication(triggerTurn):
                    if ownedSuffix == nil,
                       triggerTurn,
                       let pendingTurnContext,
                       observation.lineIndex == pendingTurnContext.lineIndex + 1
                    {
                        ownedSuffix = Self.CodexSubagentOwnedSuffix(
                            startLineIndex: pendingTurnContext.lineIndex,
                            rawTotalsBaseline: pendingTurnContext.baseline)
                        inspectedOwnedSuffixFirstTotal = false
                    }
                    pendingTurnContext = nil

                case let .tokenCount(total, last):
                    if !inspectedOwnedSuffixFirstTotal,
                       let suffix = ownedSuffix,
                       let total
                    {
                        inspectedOwnedSuffixFirstTotal = true
                        if let last,
                           Self.totalsEqual(total, last),
                           !Self.totalsAtLeast(total, suffix.rawTotalsBaseline)
                        {
                            // Some future protocol may copy history and then restart its counter.
                            // Require both a strong boundary and total==last reset evidence.
                            ownedSuffix = Self.CodexSubagentOwnedSuffix(
                                startLineIndex: suffix.startLineIndex,
                                rawTotalsBaseline: .init(input: 0, cached: 0, output: 0))
                        }
                    }
                    if let total {
                        lastRawTotals = total
                    }
                    pendingTurnContext = nil
                }
            }

            return Self(
                counterSemantics: .copiedPrefix,
                ownedSuffix: ownedSuffix,
                inferredParentSessionID: metadataShape.inferredParentSessionID)
        }

        static func sameConcreteSessionID(_ lhs: String?, _ rhs: String?) -> Bool {
            guard let lhs = normalizedSessionID(lhs),
                  let rhs = normalizedSessionID(rhs)
            else { return false }
            return lhs == rhs
        }

        private static func totalsEqual(_ lhs: CostUsageCodexTotals, _ rhs: CostUsageCodexTotals) -> Bool {
            lhs.input == rhs.input && lhs.cached == rhs.cached && lhs.output == rhs.output
        }

        private static func totalsAtLeast(_ lhs: CostUsageCodexTotals, _ rhs: CostUsageCodexTotals) -> Bool {
            lhs.input >= rhs.input && lhs.cached >= rhs.cached && lhs.output >= rhs.output
        }

        private static func normalizedSessionID(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
