import CloudKit
import CodexBarSync
import Foundation
import UserNotifications

/// `UNNotificationServiceExtension` that rewrites the incoming CloudKit push to
/// include the `providerName` from the triggering `QuotaTransition` record.
///
/// ### Why this exists
///
/// CloudKit subscription push payloads on our private-DB custom-zone setup can
/// carry a static locale-resolved body (Build 52's `String(localized:)`), but
/// they **cannot** carry per-record values. `titleLocalizationArgs` /
/// `alertLocalizationArgs` are silently dropped by CloudKit on this container,
/// and `desiredKeys` on a `CKRecordZoneSubscription` throws "cannot add
/// additionalFields to this subscription type" — so the subscription cannot
/// embed `providerName` in the push itself.
///
/// iOS invokes this extension before the notification is shown when the push
/// has `mutable-content: 1` (set by the subscription's `shouldSendMutableContent
/// = true`). We parse `CKRecordZoneNotification` out of the push, fetch the
/// latest `QuotaTransition` record in that zone, read `providerName`, and use
/// it as the notification title. The existing locale-resolved body from the
/// subscription is preserved — our only job is to prepend provider identity.
///
/// ### Failure tolerance
///
/// The extension has roughly 30 seconds before iOS delivers whatever content
/// we've mutated. If the CloudKit fetch fails, times out, or the payload isn't
/// a recognised zone notification, we deliver the **original** push content
/// unchanged — which is still the Build 52 state-specific localized body.
/// No regression from Build 52's user experience under extension failure.
///
/// ### Concurrency
///
/// `UNNotificationServiceExtension` is single-instance per push (Apple
/// guarantee), so the mutable state below is not actually shared across
/// concurrent invocations. We use `nonisolated(unsafe)` to acknowledge that
/// guarantee to Swift 6's strict checker without forcing the whole class into
/// `@MainActor` — the system invokes our overrides on a private dispatch
/// queue and may call `serviceExtensionTimeWillExpire()` from a different
/// thread than `didReceive(...)`.
final class NotificationService: UNNotificationServiceExtension {

    /// Wraps the system-provided callback so it can survive a Swift 6 closure
    /// capture into a `Task`. The system promises the handler is callable from
    /// any thread, so the `@unchecked Sendable` is sound in practice.
    private struct ContentHandlerBox: @unchecked Sendable {
        let call: (UNNotificationContent) -> Void
    }

    /// Wraps the mutable content for the same reason — `UNMutableNotificationContent`
    /// is a class without `Sendable` conformance in the iOS 17 SDK.
    private struct ContentBox: @unchecked Sendable {
        let value: UNMutableNotificationContent
    }

    /// Single-delivery latch. `UNNotificationServiceExtension` requires the
    /// content handler to be invoked **at most once** — invoking it twice is
    /// undefined behaviour. The fetch `Task` and `serviceExtensionTimeWillExpire`
    /// can race (the system cancels in-flight work but `fetchLatestProviderName`
    /// catches `CancellationError` and returns `nil`, so the task continues to
    /// the handler call after cancellation). This latch makes whichever path
    /// reaches the handler first the winner; the loser becomes a no-op.
    private final class DeliveryLatch: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false

        func tryFire() -> Bool {
            self.lock.lock()
            defer { self.lock.unlock() }
            guard !self.fired else { return false }
            self.fired = true
            return true
        }
    }

    private nonisolated(unsafe) var pendingHandler: ContentHandlerBox?
    private nonisolated(unsafe) var pendingContent: UNMutableNotificationContent?
    private nonisolated(unsafe) var fetchTask: Task<Void, Never>?
    private nonisolated(unsafe) var deliveryLatch: DeliveryLatch?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard let best = request.content.mutableCopy()
            as? UNMutableNotificationContent
        else {
            contentHandler(request.content)
            return
        }

        let handlerBox = ContentHandlerBox(call: contentHandler)
        let latch = DeliveryLatch()
        self.pendingHandler = handlerBox
        self.pendingContent = best
        self.deliveryLatch = latch

        guard let zoneID = QuotaZoneNotificationParser.extractQuotaZoneID(
            from: request.content.userInfo)
        else {
            // Not one of our quota zone notifications — deliver unchanged.
            if latch.tryFire() {
                handlerBox.call(best)
            }
            return
        }

        let contentBox = ContentBox(value: best)
        self.fetchTask = Self.makeFetchTask(
            zoneID: zoneID,
            handler: handlerBox,
            content: contentBox,
            latch: latch)
    }

    /// Spawns the CloudKit fetch + content rewrite as a `Task`. Pulled out of
    /// `didReceive(...)` so the closure captures only function-local Sendable
    /// values — Swift 6's region-based isolation checker can't reason about a
    /// `Task` created inside a `nonisolated(unsafe)` method that captures
    /// `self`'s mutable state, but a free function with Sendable args sidesteps
    /// the issue.
    private static func makeFetchTask(
        zoneID: CKRecordZone.ID,
        handler: ContentHandlerBox,
        content: ContentBox,
        latch: DeliveryLatch) -> Task<Void, Never>
    {
        return Task {
            // iOS 1.6.0 / Mac 0.25.2 — for warning-state zones we fetch
            // the latest record's recordName (encodes window + threshold)
            // and rewrite both title AND body. For depleted/restored we
            // keep the Build 54+ behavior (title rewrite only).
            let parsed = QuotaZoneNotificationParser.parseQuotaZoneName(zoneID.zoneName)
            if parsed?.state == .warning {
                let info = await Self.fetchLatestWarningInfo(in: zoneID)
                if let info {
                    content.value.title = info.providerName
                    content.value.body = Self.formatWarningBody(
                        providerName: info.providerName,
                        window: info.window,
                        threshold: info.threshold)
                }
            } else {
                let providerName = await Self.fetchLatestProviderName(in: zoneID)
                if let providerName, !providerName.isEmpty {
                    content.value.title = providerName
                }
            }
            if latch.tryFire() {
                handler.call(content.value)
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        self.fetchTask?.cancel()
        if let handler = self.pendingHandler,
           let content = self.pendingContent,
           let latch = self.deliveryLatch,
           latch.tryFire()
        {
            handler.call(content)
        }
    }

    // MARK: - CloudKit fetch

    /// Returns the most recent `QuotaTransition` record's `providerName` in the
    /// given zone, or `nil` if the fetch fails or returns nothing useful.
    ///
    /// We use a server-side `transitionAt` descending sort + `resultsLimit: 1`,
    /// so the zone size doesn't affect correctness — even after a year of
    /// accumulated records the newest one comes back first. `transitionAt` is
    /// a `Date` field which CloudKit auto-infers as Sortable when records were
    /// first written (Build 48). If the field is somehow not Sortable in the
    /// deployed Production schema, the query throws and we return `nil`,
    /// which makes the extension fall back to delivering the Build 52 body
    /// without a provider title — no regression.
    static func fetchLatestProviderName(
        in zoneID: CKRecordZone.ID) async -> String?
    {
        let container = CKContainer(identifier: CloudSyncConstants.containerIdentifier)
        let query = CKQuery(
            recordType: CloudSyncConstants.quotaTransitionRecordType,
            predicate: NSPredicate(value: true))
        query.sortDescriptors = [
            NSSortDescriptor(key: "transitionAt", ascending: false),
        ]
        do {
            let (matchResults, _) = try await container.privateCloudDatabase.records(
                matching: query,
                inZoneWith: zoneID,
                desiredKeys: ["providerName"],
                resultsLimit: 1)
            guard let first = matchResults.first else { return nil }
            let record = try first.1.get()
            return record["providerName"] as? String
        } catch {
            return nil
        }
    }

    /// iOS 1.6.0 / Mac 0.25.2 — fetches the latest warning record and
    /// parses its `recordName` to extract the crossed threshold and
    /// affected window so the push body can show specifics.
    /// `recordName` format documented at
    /// `CloudSyncManager.writeQuotaWarningTransition`.
    ///
    /// Returns `nil` when the fetch fails or the recordName format
    /// doesn't parse — the caller then falls back to the static
    /// subscription alertBody (the generic "[Provider] usage warning"),
    /// which still gives the user an actionable signal. No regression
    /// vs not having NSE enrichment at all.
    static func fetchLatestWarningInfo(
        in zoneID: CKRecordZone.ID
    ) async -> (providerName: String, window: String, threshold: Int)? {
        let container = CKContainer(identifier: CloudSyncConstants.containerIdentifier)
        let query = CKQuery(
            recordType: CloudSyncConstants.quotaTransitionRecordType,
            predicate: NSPredicate(value: true))
        query.sortDescriptors = [
            NSSortDescriptor(key: "transitionAt", ascending: false),
        ]
        do {
            let (matchResults, _) = try await container.privateCloudDatabase.records(
                matching: query,
                inZoneWith: zoneID,
                desiredKeys: ["providerName"],
                resultsLimit: 1)
            guard let first = matchResults.first else { return nil }
            let record = try first.1.get()
            guard let providerName = record["providerName"] as? String else { return nil }
            guard let parsed = QuotaZoneNotificationParser.parseWarningRecordName(
                record.recordID.recordName)
            else {
                // Unparseable recordName — preserve provider title at least.
                return (providerName, "", 0)
            }
            return (providerName, parsed.window, parsed.threshold)
        } catch {
            return nil
        }
    }

    /// Builds the push body for a warning notification. Localized
    /// templates handle the 4 supported languages; the threshold and
    /// window are formatted via `%lld` + `%@`. The window string is
    /// localized via a small lookup so "session" / "weekly" become
    /// "Session" / "Weekly" / "会话" / "週間" etc.
    static func formatWarningBody(
        providerName: String, window: String, threshold: Int
    ) -> String {
        let windowLabel = self.localizedWindowLabel(window)
        let template = String(localized: "Push.QuotaWarning.detailBody")
        // %1$@ providerName · %2$@ windowLabel · %3$lld threshold
        return String(format: template, providerName, windowLabel, threshold)
    }

    private static func localizedWindowLabel(_ window: String) -> String {
        switch window {
        case "session": return String(localized: "Push.QuotaWarning.window.session")
        case "weekly":  return String(localized: "Push.QuotaWarning.window.weekly")
        default:        return window
        }
    }
}
