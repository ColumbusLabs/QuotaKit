import CodexBarSync
import Foundation

/// Detects session quota transitions (depleted / restored) by comparing successive snapshots.
/// Mirrors the Mac-side `SessionQuotaNotificationLogic` thresholds.
final class SessionQuotaMonitor: Sendable {

    /// A provider is considered depleted when remainingPercent ≤ 0.0001 (i.e. 0.0001%).
    /// Matches Mac-side `SessionQuotaNotificationLogic.depletedThreshold` exactly (both use 0-100 scale).
    static let depletedThreshold: Double = 0.0001

    private static let storageKey = "sessionQuotaMonitor.lastKnownRemaining"

    enum Transition: Equatable {
        case none
        case depleted
        case restored
    }

    struct ProviderTransition: Equatable {
        let providerID: String
        let providerName: String
        let transition: Transition
    }

    /// Compares `newSnapshot` against persisted state, returns any transitions, and persists the new state.
    func detectTransitions(in snapshot: SyncedUsageSnapshot) -> [ProviderTransition] {
        let previous = Self.loadPreviousState()
        var results: [ProviderTransition] = []
        var newState: [String: Double] = [:]

        for provider in snapshot.providers {
            // Prefer the 5-hour session window (windowMinutes == 300) for stable
            // comparison. Falls back to the first available window if no session
            // window exists (matches Mac-side primary window selection).
            let sessionWindow = provider.allRateWindows.first(where: { $0.windowMinutes == 300 })
                ?? provider.allRateWindows.first
            guard let sessionWindow else { continue }
            let remaining = sessionWindow.remainingPercent // 0…100 scale, same as Mac side

            // Use providerID|accountEmail as key to distinguish multiple accounts of the same provider
            let stateKey = "\(provider.providerID)|\(provider.accountEmail ?? "")"
            newState[stateKey] = remaining

            let previousRemaining = previous[stateKey]
            let transition = Self.transition(previousRemaining: previousRemaining, currentRemaining: remaining)

            if transition != .none {
                results.append(ProviderTransition(
                    providerID: provider.providerID,
                    providerName: provider.providerName,
                    transition: transition))
            }
        }

        Self.savePreviousState(newState)
        return results
    }

    // MARK: - Logic (mirrors Mac SessionQuotaNotificationLogic)

    private static func transition(previousRemaining: Double?, currentRemaining: Double) -> Transition {
        let isDepleted = currentRemaining <= depletedThreshold

        guard let previousRemaining else {
            // First observation: notify if already depleted (matches Mac startup behavior)
            return isDepleted ? .depleted : .none
        }

        let wasDepleted = previousRemaining <= depletedThreshold

        if !wasDepleted, isDepleted { return .depleted }
        if wasDepleted, !isDepleted { return .restored }
        return .none
    }

    // MARK: - Persistence

    private static func loadPreviousState() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
    }

    private static func savePreviousState(_ state: [String: Double]) {
        UserDefaults.standard.set(state, forKey: storageKey)
    }
}
