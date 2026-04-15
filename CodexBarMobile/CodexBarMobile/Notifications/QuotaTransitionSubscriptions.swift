import CloudKit
import CodexBarSync
import Foundation

/// Sets up one `CKRecordZoneSubscription` per `(provider, state)` pair so every
/// incoming CloudKit push already carries the provider's name in its body text.
///
/// ### Why one subscription per provider instead of one per state (Build 54+)
///
/// Build 53 tried to inject the provider name into the notification via a
/// `UNNotificationServiceExtension` woken by `shouldSendMutableContent = true`.
/// On-device verification showed iPhones still displayed the default "CodexBar"
/// title — the extension didn't wake, most likely because this CloudKit
/// container silently strips the `shouldSendMutableContent` flag the same way
/// it strips `titleLocalizationArgs` / `alertLocalizationArgs`.
///
/// Rather than bet again on a CloudKit feature this container mishandles, we
/// fall all the way back to the mechanism Build 48 / 52 proved persists
/// reliably — a plain `CKRecordZoneSubscription` with a static `alertBody` —
/// and scale it horizontally: one subscription per `(provider, state)` pair,
/// with the provider's display name baked directly into each subscription's
/// `alertBody` at setup time using `String(format:)` against a localized
/// template. The iPhone's locale is resolved at subscription-setup time, so
/// each iPhone sees its own language without any server-side substitution.
///
/// ### What shows up on the iPhone
///
/// - **Title**: iOS default (the app name "CodexBar"). We can't override it
///   reliably on this container — the extension-based approach failed.
/// - **Body**: e.g. "Codex 的会话额度已耗尽" on a Chinese iPhone, "Codex session
///   depleted" on an English iPhone. Baked into the subscription at setup.
///
/// ### Scale
///
/// `QuotaProviderList.providers.count × 2` subscriptions (≈ 46 today) created
/// in a single batched `modifySubscriptions(saving:deleting:)` call on first
/// launch. Subsequent launches diff the server state against the expected
/// config and only save the subs whose `alertBody` has drifted (e.g. locale
/// change, new display name, new provider in the list). CloudKit Private DB
/// has no practical subscription limit for a single user at this scale.
@MainActor
final class QuotaTransitionSubscriptions {
    static let shared = QuotaTransitionSubscriptions()

    private let containerIdentifier = CloudSyncConstants.containerIdentifier
    private let recordType = CloudSyncConstants.quotaTransitionRecordType

    /// Closures are used for `localizedAlertBody` so `String(localized:)`
    /// re-resolves against the iPhone's **current** locale on every call,
    /// instead of the locale that was active when `configs` was populated.
    /// That's what lets a locale change trigger a sub recreate on next launch
    /// (the stored body no longer matches the expected body).
    private struct SubConfig {
        let zoneName: String
        let subscriptionID: String
        let localizedAlertBody: () -> String
    }

    /// Builds the full `(provider × state)` matrix of desired subscriptions.
    private func makeConfigs() -> [SubConfig] {
        var configs: [SubConfig] = []
        for provider in QuotaProviderList.providers {
            configs.append(SubConfig(
                zoneName: QuotaProviderList.quotaZoneName(
                    providerID: provider.id, state: "depleted"),
                subscriptionID: "quota-\(provider.id)-depleted-sub",
                localizedAlertBody: {
                    let template = String(localized: "Push.QuotaDepleted.bodyWithProvider")
                    return String(format: template, provider.displayName)
                }))
            configs.append(SubConfig(
                zoneName: QuotaProviderList.quotaZoneName(
                    providerID: provider.id, state: "restored"),
                subscriptionID: "quota-\(provider.id)-restored-sub",
                localizedAlertBody: {
                    let template = String(localized: "Push.QuotaRestored.bodyWithProvider")
                    return String(format: template, provider.displayName)
                }))
        }
        return configs
    }

    /// Subscription IDs to delete on upgrade. Covers Build 42–49
    /// (single zone-level sub) and Build 52–53 (state-level subs; provider
    /// was expected to come from localization args or the now-disabled
    /// service extension).
    private let legacySubscriptionIDs: [CKSubscription.ID] = [
        CloudSyncConstants.quotaTransitionLegacySubscriptionID,
        CloudSyncConstants.quotaTransitionDepletedSubscriptionID,
        CloudSyncConstants.quotaTransitionRestoredSubscriptionID,
    ]

    private init() {}

    /// Configures the `(provider, state)` subscription matrix and cleans up
    /// legacy subscriptions from older builds. Idempotent — safe to call on
    /// every launch and on every `CKAccountChangedNotification`.
    func setupIfNeeded() async {
        let diag = await PushSetupDiagnostic.shared
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase

        // Step 0: clean up legacy subs. Safe to no-op if they don't exist.
        for legacyID in self.legacySubscriptionIDs {
            _ = try? await database.deleteSubscription(withID: legacyID)
        }

        let configs = self.makeConfigs()

        // Step 1: batch create all zones in one round-trip. CloudKit treats
        // saving an existing zone as a no-op, so this is idempotent.
        let zones = configs.map { CKRecordZone(zoneName: $0.zoneName) }
        do {
            _ = try await database.modifyRecordZones(saving: zones, deleting: [])
            await diag.recordZone("✓ \(zones.count) quota zones ensured")
        } catch {
            let msg = "✗ quota zones batch create failed: \(error.localizedDescription)"
            print("[CodexBar Push v6] \(msg)")
            await diag.recordZone(msg)
            await diag.recordError(msg)
            // Keep going — individual zone creates may succeed implicitly when
            // the subscription save references them.
        }

        // Step 2: diff server state vs expected configs.
        let existing: [CKSubscription]
        do {
            existing = try await database.allSubscriptions()
        } catch {
            let msg = "✗ allSubscriptions failed: \(error.localizedDescription)"
            print("[CodexBar Push v6] \(msg)")
            await diag.recordError(msg)
            await diag.refreshSubscriptionList()
            return
        }

        var subsToSave: [CKSubscription] = []
        var alreadyCorrect = 0
        for config in configs {
            let expectedBody = config.localizedAlertBody()
            let zoneID = CKRecordZone.ID(
                zoneName: config.zoneName, ownerName: CKCurrentUserDefaultName)
            if let zoneSub = existing.first(where: {
                $0.subscriptionID == config.subscriptionID
            }) as? CKRecordZoneSubscription,
               zoneSub.zoneID == zoneID,
               zoneSub.recordType == recordType,
               let info = zoneSub.notificationInfo,
               info.alertBody == expectedBody,
               (info.titleLocalizationArgs ?? []).isEmpty,
               (info.alertLocalizationArgs ?? []).isEmpty
            {
                alreadyCorrect += 1
                continue
            }

            // Either missing or drifted — queue for save. CloudKit treats save
            // with an existing subscriptionID as an overwrite.
            let sub = CKRecordZoneSubscription(
                zoneID: zoneID, subscriptionID: config.subscriptionID)
            sub.recordType = self.recordType
            let info = CKSubscription.NotificationInfo()
            info.alertBody = expectedBody
            info.soundName = "default"
            sub.notificationInfo = info
            subsToSave.append(sub)
        }

        let summaryPrefix = "✓ \(configs.count) subs desired, "
            + "\(alreadyCorrect) already correct, "
            + "\(subsToSave.count) to save"
        print("[CodexBar Push v6] \(summaryPrefix)")
        await diag.recordDepletedSub(summaryPrefix)
        await diag.recordRestoredSub("")

        // Step 3: batch save the drifted subs.
        if !subsToSave.isEmpty {
            do {
                _ = try await database.modifySubscriptions(
                    saving: subsToSave, deleting: [])
                let msg = "✓ saved \(subsToSave.count) subs"
                print("[CodexBar Push v6] \(msg)")
                await diag.recordDepletedSub(summaryPrefix + " — " + msg)
            } catch {
                let msg = "✗ sub batch save failed: \(error.localizedDescription)"
                print("[CodexBar Push v6] \(msg)")
                await diag.recordError(msg)
            }
        }

        await diag.refreshSubscriptionList()
    }

    /// Runs a persistence test on a bare `CKRecordZoneSubscription` in the
    /// first provider's depleted zone. Representative of the real subs since
    /// all of them share the same subscription type + alertBody-only payload.
    func runPersistenceTest() async -> String {
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        let testID = "ios-persistence-test"
        guard let firstProvider = QuotaProviderList.providers.first else {
            return "✗ no providers configured"
        }
        let zoneName = QuotaProviderList.quotaZoneName(
            providerID: firstProvider.id, state: "depleted")
        let zoneID = CKRecordZone.ID(
            zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

        do {
            try await self.ensureZoneExists(database: database, zoneID: zoneID)
        } catch {
            return "✗ zone creation failed: \(error.localizedDescription)"
        }

        // Always clean up on exit
        defer {
            Task { try? await database.deleteSubscription(withID: testID) }
        }

        do {
            _ = try? await database.deleteSubscription(withID: testID)
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
    }
}
