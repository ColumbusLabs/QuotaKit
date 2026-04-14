import CodexBarCore
import CodexBarSync
import Foundation

/// Protocol that wraps the `QuotaTransition` CloudKit record write so it can be
/// mocked in unit tests, mirroring the existing `SessionQuotaNotifying` pattern.
@MainActor
protocol QuotaTransitionWriting: AnyObject {
    func write(transition: SessionQuotaTransition, provider: UsageProvider)
}

/// Writes `QuotaTransition` records to CloudKit so iOS receives a visible alert push
/// via the existing `CKQuerySubscription` (configured in iOS app).
///
/// This is the **server-side decided notification** path: Mac just persists the fact
/// of the transition; CloudKit + APNs deliver the visible push directly to iPhone
/// without requiring the iOS app to wake up. Replaces the failed silent-push design.
///
/// ### Debounce
///
/// To avoid spamming iPhone when the same provider's quota oscillates near the
/// threshold, writes are debounced per `(provider, state)` key with a 5-minute
/// window. The most recent write within that window wins; earlier ones inside the
/// window are dropped client-side.
///
/// ### Idempotency
///
/// Record names are derived deterministically from `(deviceID, provider, state, hourBucket)`,
/// so two writes within the same hour for the same `(provider, state)` from the same
/// Mac collapse to a single CloudKit record (an update, not a duplicate insert). The
/// subscription's `firesOnRecordCreation` only fires on the first record of that hour,
/// so the user sees at most one push per hour for the same `(provider, state)` per Mac.
@MainActor
final class QuotaTransitionWriter: QuotaTransitionWriting {
    private let logger = CodexBarLog.logger(LogCategories.sessionQuotaNotifications)

    /// Tracks the last successful write per `(provider, state)` to enforce a debounce.
    private var lastWriteByKey: [String: Date] = [:]

    /// Minimum interval between two writes for the same `(provider, state)`.
    private let debounceInterval: TimeInterval = 5 * 60

    init() {}

    func write(transition: SessionQuotaTransition, provider: UsageProvider) {
        guard transition != .none else { return }

        let stateString = stateString(for: transition)
        let providerName = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
        let key = "\(provider.rawValue)|\(stateString)"
        let now = Date()

        if let lastWrite = self.lastWriteByKey[key],
           now.timeIntervalSince(lastWrite) < self.debounceInterval
        {
            self.logger.debug(
                "QuotaTransition write debounced: provider=\(provider.rawValue) state=\(stateString)")
            return
        }

        // Note: do NOT update `lastWriteByKey` here. Updating it before the async
        // CloudKit write completes would suppress legitimate retry attempts when the
        // initial write fails (network blip / auth glitch). The timestamp is only set
        // after the write succeeds, so failed writes don't start the debounce window.

        // No notification text is written to the record: state is encoded in the
        // zone (QuotaDepletedZone / QuotaRestoredZone) and iOS subscriptions carry
        // static `Push.QuotaDepleted.*` / `Push.QuotaRestored.*` localization keys
        // with `titleLocalizationArgs = ["providerName"]`, so each iPhone
        // substitutes the localized text for its own locale.

        Task { [providerName, stateString] in
            let result = await CloudSyncManager.shared.writeQuotaTransition(
                providerName: providerName,
                providerID: provider.rawValue,
                state: stateString,
                transitionAt: now)
            if result.succeeded {
                self.lastWriteByKey[key] = now
                self.logger.info(
                    "QuotaTransition record written: provider=\(provider.rawValue) state=\(stateString)")
            } else {
                self.logger.error(
                    "QuotaTransition record write failed: \(result.message ?? "unknown")")
            }
        }
    }
}

private func stateString(for transition: SessionQuotaTransition) -> String {
    switch transition {
    case .depleted: return "depleted"
    case .restored: return "restored"
    case .none: return "none"
    }
}
