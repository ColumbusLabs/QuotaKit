
- **Status**: superseded — Build 52 shipped this design's zone-split form (state and locale only). Build 53 layers a `UNNotificationServiceExtension` on top to add the provider name as the title; see [006-push-provider-nse.md](006-push-provider-nse.md) for the current design and [005-push-provider-alternatives.md](005-push-provider-alternatives.md) for the 14 alternatives evaluated and rejected.
- **Created**: 2026-04-08
- **Supersedes**: [003-push-notifications.md](003-push-notifications.md)

## Implementation note (final form, Build 52, 2026-04-13)

Builds 42–50 iterated on this design. Build 52 is the stable final form; below is what actually shipped and why it diverges from the original design in two ways.

### Divergence 1 — state by zone, not by predicate
- **Original plan** (below): one zone, two `CKQuerySubscription`s filtered by `state == "depleted"` / `"restored"`.
- **Shipped**: two zones (`QuotaDepletedZone` / `QuotaRestoredZone`), each with a `CKRecordZoneSubscription`. Mac picks the destination zone based on state.
- **Reason**: A/B testing across Builds 42–48 confirmed that `CKQuerySubscription` saves without error but never persists on this CloudKit container. `CKRecordZoneSubscription` does persist, but has no predicate support — so state differentiation moved from predicate to zone.

### Divergence 2 — localization on iOS, not via CloudKit args
- **Original plan** (below): subscription uses `titleLocalizationKey` + `titleLocalizationArgs = ["providerName"]`; CloudKit pulls the `providerName` field from the record at push time and substitutes it into the `%@` template; iOS resolves the template against the iPhone's locale.
- **Build 50 tried this with `["providerName"]`** (a field long-present in the Production schema since Build 48). On-device verification showed `allSubscriptions()` returned only the legacy `device-snapshot-changes` sub — the two new quota subs silently didn't persist. **Same failure mode as Build 49 (commit `65960ac8`), which had also used args.**
- **Definitive learning**: any subscription carrying `titleLocalizationArgs` / `alertLocalizationArgs` is silently dropped by CloudKit on this container, regardless of which field the args reference. Production-deployed vs undeployed field doesn't matter.
- **Shipped in Build 52**: no args. Each subscription's `alertBody` is a **static, locale-resolved** string, chosen at subscription-creation time via `String(localized: "Push.QuotaDepleted.body")` / `"Push.QuotaRestored.body"` against the iPhone's current locale. CloudKit delivers that literal string verbatim. Locale changes propagate on next app launch because the `"already correct"` check compares the stored body against a freshly-resolved `String(localized: …)`, mismatches on locale change, and recreates the sub.

### What this means for future work
- Any design that depends on the subscription reading record fields (Plan A-style pass-through) is **not viable on this container**.
- iOS-side `String(localized:)` at sub-creation time is the replacement pattern for anything where the discriminator is known statically at sub-creation (e.g. zone-specific state).
- If Mac needs to push *dynamic* per-record text to iOS later (e.g. provider name embedded in the notification body), a `UNNotificationServiceExtension` on iOS is the architectural escape hatch, not CloudKit args.

The rest of this document describes the original design and is kept for historical reference.








> "If you don't set any of the **alertBody, soundName, or shouldBadge** properties, CloudKit sends the push notification using a lower priority and doesn't display any content to the user."




> "Set this property's value to have the system display the specified string when it receives the corresponding push notification."



> "A regular push notification notifies the user by displaying a message, making a sound, or badging the application icon, and they show up in Notification Center and on the device's Lock Screen."




```
var titleLocalizationArgs: [CKRecord.FieldKey]? { get set }
```

> "This property is an array of field names that CloudKit uses to extract the corresponding values from the record that triggers the push notification. The values must be strings, numbers, or dates. Don't specify keys that use other value types. CloudKit may truncate strings with a length greater than 100 characters when it adds them to a notification's payload."

> "If you use `%@` for your substitution variables, CloudKit replaces those variables by traversing the array in order. If you use variables of the form `%n$@`, where `n` is an integer, `n` represents the index..."





> "Your application doesn't need to request the user's explicit permission to receive silent notifications. However, because regular push notifications are visible to the user, applications need to ask the user for permission."

1. `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])`
2. `UIApplication.shared.registerForRemoteNotifications()`




```objc
subscription.zoneID = recordZone.zoneID;
```








```
SyncCoordinator.writeQuotaTransition(provider:state:)
    ↓
CloudKit private DB / DeviceSnapshotsZone / QuotaTransition record
    ↓ CKQuerySubscription with predicate (state="depleted") fires
APNs Production
    ↓ (alert payload with titleLocalizationKey + alertLocalizationArgs from record)
iPhone NotificationCenter
```

### Record schema：`QuotaTransition`


|---|---|---|---|




#### Subscription 1: depleted

```swift
let subscription = CKQuerySubscription(
    recordType: "QuotaTransition",
    predicate: NSPredicate(format: "state == %@", "depleted"),
    subscriptionID: "quota-transition-depleted",
    options: [.firesOnRecordCreation])
subscription.zoneID = customZone.zoneID

let info = CKSubscription.NotificationInfo()
info.titleLocalizationKey = "Push.QuotaDepleted.title"  // "%@"
info.titleLocalizationArgs = ["providerName"]
info.alertLocalizationKey = "Push.QuotaDepleted.body"    // "Session depleted"
info.alertLocalizationArgs = []
subscription.notificationInfo = info
```

#### Subscription 2: restored


### Localization keys


| key | en | ja | zh-Hans | zh-Hant |
|---|---|---|---|---|
| `Push.QuotaDepleted.title` | `%@` | `%@` | `%@` | `%@` |
| `Push.QuotaRestored.title` | `%@` | `%@` | `%@` | `%@` |


> **Codex**
> Session depleted


> **Codex**

































|---|---|---|


- [Apple `CKSubscription.NotificationInfo`](https://developer.apple.com/documentation/cloudkit/cksubscription/notificationinfo-swift.class)
- [Apple `alertBody` doc](https://developer.apple.com/documentation/cloudkit/cksubscription/notificationinfo-swift.class/alertbody)
- [Apple `shouldSendContentAvailable` doc](https://developer.apple.com/documentation/cloudkit/cksubscription/notificationinfo-swift.class/shouldsendcontentavailable)
- [Apple `titleLocalizationArgs` doc](https://developer.apple.com/documentation/cloudkit/cksubscription/notificationinfo-swift.class/titlelocalizationargs)
- [Apple `CKQuerySubscription`](https://developer.apple.com/documentation/cloudkit/ckquerysubscription) (zoneID example)
- [Apple `CKNotification`](https://developer.apple.com/documentation/cloudkit/cknotification)
- [Apple Local and Remote Notification Programming Guide](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/)
- [Hacking with Swift CKQuerySubscription tutorial](https://www.hackingwithswift.com/read/33/8/delivering-notifications-with-cloudkit-push-messages-ckquerysubscription)
- [fluffy.es CloudKit push notification tutorial](https://fluffy.es/push-notification-cloudkit/)
- [Cocoacasts: Five Reasons CloudKit Notifications Are Not Arriving](https://cocoacasts.com/five-reasons-cloudkit-notifications-are-not-arriving)
- [Filip Němeček: How to setup CloudKit subscription](https://nemecek.be/blog/31/how-to-setup-cloudkit-subscription-to-get-notified-for-changes)
- [`apple/sample-cloudkit-privatedb-sync`](https://github.com/apple/sample-cloudkit-privatedb-sync)
