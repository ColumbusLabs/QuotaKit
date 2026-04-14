import CloudKit
import CodexBarSync
import Foundation

/// Sets up two `CKRecordZoneSubscription`s (one per state-specific zone) to receive
/// visible, locale-aware alert push notifications when Mac writes a `QuotaTransition`
/// record.
///
/// **Why CKRecordZoneSubscription, not CKQuerySubscription:**
/// A/B testing confirmed that CKQuerySubscription saves without error but never
/// persists on this CloudKit container (`allSubscriptions()` returns empty
/// immediately after a successful save). CKRecordZoneSubscription DOES persist —
/// the old `device-snapshot-changes` subscription proves this.
///
/// **Why two zones instead of one zone + state predicate:**
/// CKRecordZoneSubscription does not support NSPredicate, so the `state`
/// differentiation is encoded in the **zone choice** instead: Mac writes depleted
/// records to `QuotaDepletedZone` and restored records to `QuotaRestoredZone`.
/// Each zone carries its own subscription with a state-specific, locale-resolved
/// `alertBody` — the zone split is what lets iOS pre-pick the right text per state
/// at subscription-creation time.
///
/// **How notification text works (Build 51+):**
/// Each subscription's `alertBody` is resolved at creation time via
/// `String(localized: "Push.QuotaDepleted.body")` / `"Push.QuotaRestored.body"`,
/// which bakes the iPhone's current locale's text into the subscription payload.
/// CloudKit then delivers that literal string as the push body. No subscription
/// args, no server-side localization — the subscription stores a concrete
/// locale-specific string chosen by iOS when it registered the subscription.
///
/// **Why no `titleLocalizationArgs` / `alertLocalizationArgs` (historical):**
/// Build 49 (commit `65960ac8`) and Build 50 both proved that **any subscription
/// carrying args is silently dropped by CloudKit on this container**, regardless
/// of whether the referenced field is in the Production schema. Build 50 tried
/// `args = ["providerName"]` — `providerName` has been in the Production schema
/// since Build 48, but the args-carrying sub still didn't persist
/// (`allSubscriptions()` returned only `device-snapshot-changes` after save).
/// We therefore build the final text on iOS at sub-creation and skip args
/// entirely. Locale updates propagate naturally: the `"already correct"` check
/// compares on the current-locale `alertBody`, so a locale change forces
/// delete + recreate with the new text on next launch.
@MainActor
final class QuotaTransitionSubscriptions {
    static let shared = QuotaTransitionSubscriptions()

    private let containerIdentifier = CloudSyncConstants.containerIdentifier
    private let recordType = CloudSyncConstants.quotaTransitionRecordType

    /// One config per state-specific zone. Adding a third state (e.g. "warning")
    /// only requires a new entry here + the matching zone on Mac + a Localizable key.
    ///
    /// `localizedAlertBody` is a closure so each call resolves against the iPhone's
    /// **current** locale — not the locale that was active when this array was
    /// initialised. That's how a locale change picks up the new text on the next
    /// `setupIfNeeded()` run.
    private struct SubConfig {
        let zoneName: String
        let subscriptionID: String
        let localizedAlertBody: () -> String
    }

    private let configs: [SubConfig] = [
        SubConfig(
            zoneName: CloudSyncConstants.quotaDepletedZoneName,
            subscriptionID: CloudSyncConstants.quotaTransitionDepletedSubscriptionID,
            localizedAlertBody: { String(localized: "Push.QuotaDepleted.body") }),
        SubConfig(
            zoneName: CloudSyncConstants.quotaRestoredZoneName,
            subscriptionID: CloudSyncConstants.quotaTransitionRestoredSubscriptionID,
            localizedAlertBody: { String(localized: "Push.QuotaRestored.body") }),
    ]

    private init() {}

    /// Configures both state-specific subscriptions if needed, and deletes the
    /// Build 42–49 legacy single-sub (`quota-transition-zone-sub`) on upgrade.
    /// Idempotent and safe to call on every launch and on every
    /// `CKAccountChangedNotification`.
    func setupIfNeeded() async {
        let diag = await PushSetupDiagnostic.shared
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase

        // Step 0: clean up the Build 42–49 legacy single-sub if present. Mac no
        // longer writes to its zone, so it would never fire, but we remove it to
        // keep `allSubscriptions()` tidy.
        try? await database.deleteSubscription(
            withID: CloudSyncConstants.quotaTransitionLegacySubscriptionID)

        // Step 1–2: for each state-specific config, ensure zone + subscription.
        for config in configs {
            await self.setup(config: config, database: database, diag: diag)
        }

        // Step 3: refresh subscription list from iOS perspective
        await diag.refreshSubscriptionList()
    }

    private func setup(
        config: SubConfig, database: CKDatabase, diag: PushSetupDiagnostic) async
    {
        let zoneID = CKRecordZone.ID(
            zoneName: config.zoneName, ownerName: CKCurrentUserDefaultName)

        // Ensure zone exists
        do {
            try await self.ensureZoneExists(database: database, zoneID: zoneID)
            await diag.recordZone("✓ \(config.zoneName) exists")
        } catch {
            let msg = "✗ ensureZoneExists(\(config.zoneName)) failed: " +
                "\(error.localizedDescription)"
            print("[CodexBar Push v5] \(msg)")
            await diag.recordZone(msg)
            await diag.recordError(msg)
            return
        }

        // Configure the subscription
        do {
            let created = try await self.configureSubscription(
                database: database, zoneID: zoneID, config: config)
            let msg = "✓ \(config.subscriptionID) " +
                (created ? "created" : "already correct")
            print("[CodexBar Push v5] \(msg)")
            await self.report(msg: msg, config: config, diag: diag)
        } catch {
            let msg = "✗ \(config.subscriptionID) setup failed: " +
                "\(error.localizedDescription)"
            print("[CodexBar Push v5] \(msg)")
            await self.report(msg: msg, config: config, diag: diag)
            await diag.recordError(msg)
        }
    }

    private func report(
        msg: String, config: SubConfig, diag: PushSetupDiagnostic) async
    {
        if config.subscriptionID
            == CloudSyncConstants.quotaTransitionDepletedSubscriptionID
        {
            await diag.recordDepletedSub(msg)
        } else {
            await diag.recordRestoredSub(msg)
        }
    }

    /// Runs a persistence test on a bare CKRecordZoneSubscription in the depleted
    /// zone. Returns a human-readable result. Representative of both real subs
    /// since they share the same subscription type and zone pattern.
    func runPersistenceTest() async -> String {
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        let testID = "ios-persistence-test"
        let zoneID = CKRecordZone.ID(
            zoneName: CloudSyncConstants.quotaDepletedZoneName,
            ownerName: CKCurrentUserDefaultName)

        do {
            try await self.ensureZoneExists(database: database, zoneID: zoneID)
        } catch {
            return "✗ zone creation failed: \(error.localizedDescription)"
        }

        // Create — always clean up on exit regardless of success/failure
        defer {
            Task { try? await database.deleteSubscription(withID: testID) }
        }

        do {
            try? await database.deleteSubscription(withID: testID)
            let sub = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: testID)
            sub.recordType = recordType
            let info = CKSubscription.NotificationInfo()
            info.alertBody = "Persistence test"
            info.soundName = "default"
            sub.notificationInfo = info
            _ = try await database.modifySubscriptions(saving: [sub], deleting: [])
        } catch {
            return "✗ save failed: \(error.localizedDescription)"
        }

        // Verify
        let persisted: Bool
        do {
            let all = try await database.allSubscriptions()
            persisted = all.contains(where: { $0.subscriptionID == testID })
        } catch {
            return "✗ allSubscriptions failed: \(error.localizedDescription)"
        }

        return persisted
            ? "✓ CKRecordZoneSubscription persists from iOS!"
            : "✗ NOT FOUND after save — same issue as CKQuerySubscription"
    }

    // MARK: - Internals

    private func ensureZoneExists(
        database: CKDatabase, zoneID: CKRecordZone.ID) async throws
    {
        do {
            _ = try await database.recordZone(for: zoneID)
            return
        } catch let error as CKError where error.code == .zoneNotFound {
            // Fall through to create
        }
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
        print("[CodexBar Push v5] Created zone: \(zoneID.zoneName)")
    }

    /// Creates or repairs the subscription for a given config. Returns true if
    /// created, false if already correct (no-op).
    private func configureSubscription(
        database: CKDatabase, zoneID: CKRecordZone.ID, config: SubConfig)
        async throws -> Bool
    {
        // Fetch existing
        let existing: CKSubscription?
        do {
            existing = try await database.subscription(for: config.subscriptionID)
        } catch let error as CKError where error.code == .unknownItem {
            existing = nil
        }
        // Other errors propagate (don't destructively modify on transient failures)

        // Resolve the alert body against iPhone's current locale. We compare the
        // existing sub's stored string against this freshly-resolved one, so a
        // locale change naturally triggers recreate.
        let expectedBody = config.localizedAlertBody()

        // Check if already correct. Match zoneID, recordType, and the
        // locale-resolved alertBody. NO localization args on the sub — args are
        // silently dropped by CloudKit on this container (Build 49 and Build 50
        // both proved this). An existing sub carrying args (shipped Build 50)
        // will fail this check and get replaced.
        if let zoneSub = existing as? CKRecordZoneSubscription,
           zoneSub.zoneID == zoneID,
           zoneSub.recordType == recordType,
           let info = zoneSub.notificationInfo,
           info.alertBody == expectedBody,
           (info.titleLocalizationArgs ?? []).isEmpty,
           (info.alertLocalizationArgs ?? []).isEmpty
        {
            return false // already correct
        }

        // Delete stale subscription if exists
        if existing != nil {
            try? await database.deleteSubscription(withID: config.subscriptionID)
        }

        // Create a new CKRecordZoneSubscription with a **static** alertBody that
        // is already locale-resolved. CloudKit delivers this literal string as
        // the push body — no server-side substitution, no args. See class comment
        // for why args aren't viable on this container.
        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID, subscriptionID: config.subscriptionID)
        subscription.recordType = recordType

        let info = CKSubscription.NotificationInfo()
        info.alertBody = expectedBody
        info.soundName = "default"
        subscription.notificationInfo = info

        _ = try await database.modifySubscriptions(
            saving: [subscription], deleting: [])
        return true
    }
}
