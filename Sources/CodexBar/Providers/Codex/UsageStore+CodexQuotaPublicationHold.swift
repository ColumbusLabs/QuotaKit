import Foundation

extension UsageStore {
    var codexQuotaPublicationHoldMessage: String? {
        guard let activeID = self.settings.codexVisibleAccountProjection.activeVisibleAccountID,
              let row = self.codexAccountSnapshots.first(where: { $0.id == activeID })
        else { return nil }
        return Self.codexQuotaPublicationHoldMessage(evidence: row.weeklyBoundaryEvidence)
    }

    static func codexQuotaPublicationHoldMessage(evidence: CodexWeeklyBoundaryEvidence?) -> String? {
        guard let reason = evidence?.holdReason else { return nil }
        switch reason {
        case .candidateCreated, .minimumDelay:
            return "Confirming a quota update. Showing the last accepted reading."
        case .retiredBoundary:
            return "An older quota cycle was ignored. Showing the last accepted reading."
        default:
            return "Quota update could not be confirmed. Showing the last accepted reading."
        }
    }
}
