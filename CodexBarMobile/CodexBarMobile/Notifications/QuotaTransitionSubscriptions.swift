import CloudKit
import CodexBarSync
import Foundation

/// Sets up the two `CKQuerySubscription`s that turn `QuotaTransition` records into
/// visible alert pushes on this device. See `Research/004-alert-push-cloudkit.md`.
///
/// Why two subscriptions: each subscription's `notificationInfo` (and therefore the
/// `alertLocalizationKey`) is fixed at subscription-creation time. To get a different
/// localized message for "depleted" vs "restored", we create one subscription per state
/// with a `state == "X"` predicate.
///
/// **Self-healing pattern**: every call queries the server for the actual subscription
/// state and only takes the minimum action to converge — same approach we landed on
/// after Codex review for the previous CloudKit work. A stale local UserDefaults flag
/// can drift from the real server state across iCloud account switches and dashboard
/// resets, leaving silent push silently broken; trusting the server costs one extra
/// fetch per launch.
@MainActor
final class QuotaTransitionSubscriptions {
    static let shared = QuotaTransitionSubscriptions()

    private let containerIdentifier = CloudSyncConstants.containerIdentifier
    private let customZoneName = CloudSyncConstants.customZoneName
    private let recordType = CloudSyncConstants.quotaTransitionRecordType

    private init() {}

    /// Configures both subscriptions if needed. Idempotent and safe to call on every
    /// launch and on every `CKAccountChangedNotification`.
    func setupIfNeeded() async {
        let diag = await PushSetupDiagnostic.shared
        let container = CKContainer(identifier: containerIdentifier)
        // Use PUBLIC database — private database subscriptions save without error
        // but never persist or fire push. All working tutorials use public DB.
        let database = container.publicCloudDatabase
        // Public database uses the default zone only — no custom zone needed.
        await diag.recordZone("✓ public DB (no custom zone needed)")

        // Configure both subscriptions independently.
        await self.configureSubscription(
            database: database,
            subscriptionID: CloudSyncConstants.quotaTransitionDepletedSubscriptionID,
            stateValue: "depleted",
            titleLocalizationKey: "Push.QuotaDepleted.title",
            alertLocalizationKey: "Push.QuotaDepleted.body",
            diagLabel: "depleted")

        await self.configureSubscription(
            database: database,
            subscriptionID: CloudSyncConstants.quotaTransitionRestoredSubscriptionID,
            stateValue: "restored",
            titleLocalizationKey: "Push.QuotaRestored.title",
            alertLocalizationKey: "Push.QuotaRestored.body",
            diagLabel: "restored")

        // Step 3: refresh the subscription list from iOS's own perspective
        await diag.refreshSubscriptionList()
    }

    // MARK: - Internals

    /// Creates or repairs a single subscription. Strategy:
    ///
    /// 1. Try to fetch the existing subscription by ID.
    /// 2. If it's already a `CKQuerySubscription` with the right zone, record type,
    ///    predicate, options, AND notification info, no-op.
    /// 3. Otherwise (wrong type / wrong zone / wrong predicate / wrong options /
    ///    wrong alert keys / wrong title args / wrong sound), delete and recreate.
    /// 4. On any non-`unknownItem` fetch error (network, transient CloudKit), abort
    ///    and try again next launch — never destructively modify on transient failures.
    private func configureSubscription(
        database: CKDatabase,
        subscriptionID: String,
        stateValue: String,
        titleLocalizationKey: String,
        alertLocalizationKey: String,
        diagLabel: String) async
    {
        let diag = await PushSetupDiagnostic.shared

        // Step 1: fetch existing
        let existing: CKSubscription?
        do {
            existing = try await database.subscription(for: subscriptionID)
        } catch let error as CKError where error.code == .unknownItem {
            existing = nil
        } catch {
            let msg = "subscription(for:\(subscriptionID)) failed: \(error.localizedDescription)"
            print("[CodexBar Push v2] \(msg) — will retry next launch")
            if diagLabel == "depleted" {
                await diag.recordDepletedSub("✗ fetch failed: \(error.localizedDescription)")
            } else {
                await diag.recordRestoredSub("✗ fetch failed: \(error.localizedDescription)")
            }
            await diag.recordError(msg)
            return
        }

        // Step 2: build the desired (canonical) subscription up front, then
        // structurally compare every field that matters. We deliberately recreate
        // on ANY mismatch — predicate / options / args / sound — because a stale
        // subscription with the same ID but wrong filter will misroute pushes.
        let desiredPredicate = NSPredicate(format: "state == %@", stateValue)
        let desiredOptions: CKQuerySubscription.Options =
            [.firesOnRecordCreation, .firesOnRecordUpdate]
        let desiredTitleArgs = ["providerName"]
        let desiredSoundName = "default"

        if let existingQuery = existing as? CKQuerySubscription,
           Self.matches(
               existing: existingQuery,
               recordType: self.recordType,
               predicate: desiredPredicate,
               options: desiredOptions,
               titleLocalizationKey: titleLocalizationKey,
               titleLocalizationArgs: desiredTitleArgs,
               alertLocalizationKey: alertLocalizationKey,
               soundName: desiredSoundName)
        {
            let msg = "✓ already correct"
            print("[CodexBar Push v2] Subscription \(subscriptionID) \(msg)")
            if diagLabel == "depleted" {
                await diag.recordDepletedSub(msg)
            } else {
                await diag.recordRestoredSub(msg)
            }
            return
        }

        // Step 3: delete the wrong one (if any), then create fresh
        if existing != nil {
            do {
                try await database.deleteSubscription(withID: subscriptionID)
                print("[CodexBar Push v2] Deleted stale subscription \(subscriptionID)")
            } catch {
                print("[CodexBar Push v2] Failed to delete stale subscription " +
                    "\(subscriptionID): \(error.localizedDescription) — continuing")
            }
        }

        // QuotaTransition records live in the DEFAULT zone. All working examples of
        // CKQuerySubscription + alertBody use default zone. Custom zone + alert push
        // appears unsupported (subscription saves but push never fires).
        let subscription = CKQuerySubscription(
            recordType: self.recordType,
            predicate: desiredPredicate,
            subscriptionID: subscriptionID,
            options: desiredOptions)
        // Note: do NOT set subscription.zoneID — default zone is intentional.

        let info = CKSubscription.NotificationInfo()
        // Set alertBody as a static fallback — CloudKit's internal priority logic may
        // only check alertBody (not alertLocalizationKey) to decide visible vs silent.
        // iOS prefers the localization key when present, falls back to alertBody.
        info.alertBody = stateValue == "depleted"
            ? "Session quota depleted"
            : "Session quota restored"
        info.titleLocalizationKey = titleLocalizationKey
        info.titleLocalizationArgs = desiredTitleArgs
        info.alertLocalizationKey = alertLocalizationKey
        info.soundName = desiredSoundName
        info.shouldBadge = true
        subscription.notificationInfo = info

        do {
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
            let msg = "✓ created (state=\(stateValue))"
            print("[CodexBar Push v2] Created subscription \(subscriptionID) \(msg)")
            if diagLabel == "depleted" {
                await diag.recordDepletedSub(msg)
            } else {
                await diag.recordRestoredSub(msg)
            }
        } catch {
            let msg = "✗ create failed: \(error.localizedDescription)"
            print("[CodexBar Push v2] \(msg)")
            if diagLabel == "depleted" {
                await diag.recordDepletedSub(msg)
            } else {
                await diag.recordRestoredSub(msg)
            }
            await diag.recordError(msg)
        }
    }

    /// Returns true iff the existing subscription's structurally observable state
    /// matches the desired configuration. Compares every field that affects either
    /// CloudKit's filter logic (recordType, zoneID, predicate, options) or the user-
    /// visible push (localization keys/args, sound). `predicate.predicateFormat` is a
    /// stable canonical string representation suitable for equality checks.
    private static func matches(
        existing: CKQuerySubscription,
        recordType: String,
        predicate: NSPredicate,
        options: CKQuerySubscription.Options,
        titleLocalizationKey: String,
        titleLocalizationArgs: [String],
        alertLocalizationKey: String,
        soundName: String) -> Bool
    {
        guard existing.recordType == recordType,
              existing.zoneID == nil,
              existing.predicate.predicateFormat == predicate.predicateFormat,
              existing.querySubscriptionOptions == options
        else { return false }

        guard let info = existing.notificationInfo else { return false }
        guard info.alertBody != nil,
              info.titleLocalizationKey == titleLocalizationKey,
              info.titleLocalizationArgs == titleLocalizationArgs,
              info.alertLocalizationKey == alertLocalizationKey,
              info.soundName == soundName
        else { return false }

        return true
    }
}
