# 007: Per-provider subscriptions with provider-name-baked `alertBody` (shipped design)

- **Status**: done — shipped in Build 54 (2026-04-14), verified on real iPhone the same day with a genuine Claude quota depleted → restored cycle.
- **Supersedes**: [006-push-provider-nse.md](006-push-provider-nse.md) (Build 53 `UNNotificationServiceExtension` approach that didn't wake on this container).
- **Siblings**: [005-push-provider-alternatives.md](005-push-provider-alternatives.md) (the 15 candidate architectures). This design is the evolution of alternative #4 in that list ("per-(provider,state) zones"), scaled to the full provider set.

## What this design ships

iPhone push for a Mac→iOS quota transition displays:
- **Title**: `CodexBar` (iOS default — cannot be reliably overridden on this container without a `UNNotificationServiceExtension`, and the extension-based Build 53 approach did not fire).
- **Sound**: default.

All three fields resolved at **subscription creation time on iPhone** and shipped to CloudKit as literal strings — no server-side substitution, no service extension, no `titleLocalizationArgs`, no `desiredKeys`.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Phase A — iPhone app launch (once per app start / locale change)│
└──────────────────────────────────────────────────────────────────┘

  QuotaTransitionSubscriptions.setupIfNeeded()
    ┌─→ for each provider in QuotaProviderList.providers  (23)
    │     for each state in ["depleted", "restored"]      (2)
    │       zoneName  = QuotaProviderList.quotaZoneName(providerID:, state:)
    │                 = "Quota-{providerID}-{state}Zone"
    │       subID     = "quota-{providerID}-{state}-sub"
    │       template  = String(localized: "Push.Quota{State}.bodyWithProvider")
    │                 = iPhone-locale-specific "%@ xxx" from Localizable.xcstrings
    │       alertBody = String(format: template, displayName)
    │                 = already-final locale-specific "{Provider} xxx"
    │       build CKRecordZoneSubscription with that alertBody
    │
    └─→ single batched modifyRecordZones(saving: [46 zones])
    └─→ single batched modifySubscriptions(saving: [drifted subs only])

  Server state after this: 46 subscriptions, each with a pre-baked alertBody.

┌──────────────────────────────────────────────────────────────────┐
│  Phase B — Mac detects a quota transition (runtime, per event)   │
└──────────────────────────────────────────────────────────────────┘

  Mac SessionQuotaNotifier.post(transition: .depleted, provider: .claude)
    ↓
  QuotaTransitionWriter.write(transition: .depleted, provider: .claude)
    ↓
  CloudSyncManager.writeQuotaTransition(
      providerID: "claude", state: "depleted", ...)
    ↓
  zoneName = QuotaProviderList.quotaZoneName(...) = "Quota-claude-depletedZone"
  save record {providerName, providerID, state, transitionAt, deviceID} into that zone
    ↓
  CloudKit server:
    sees record creation in Quota-claude-depletedZone
    finds the matching CKRecordZoneSubscription
    packages it into an APNs alert push
    ↓
```

The zone name is the **single join point** between Mac and iPhone. Both ends independently compute the same string via `QuotaProviderList.quotaZoneName(...)`. No text flows from Mac to iPhone at push time.

## Why this design (reasoning recap)

- **Build 49 / 50 / 51** established that this CloudKit container silently drops subscriptions that carry `titleLocalizationArgs` / `alertLocalizationArgs` referencing record fields — regardless of whether the referenced field is deployed in Production schema.
- **Build 53** tried to escape via `UNNotificationServiceExtension` woken by `shouldSendMutableContent = true`. On-device verification showed the extension never fired. The leading hypothesis is that this container silently strips the `shouldSendMutableContent` flag too, the same way it strips args.
- **Build 48 / 52** proved that the plain `CKRecordZoneSubscription` + static `alertBody` combination persists and delivers reliably on this container.
- **Build 54** commits fully to that proven mechanism and scales it horizontally — one subscription per `(provider, state)` pair. The provider name goes into the `alertBody` at subscription creation time via `String(format:)`, eliminating any runtime dependency on CloudKit features that this container mishandles.

## Cost and scale

| Dimension | Value | Notes |
|---|---|---|
| Providers tracked | 23 (as of 2026-04-14) | From `UsageProvider.allCases` on Mac; mirrored by `QuotaProviderList.providers` on iOS |
| States | 2 (`depleted`, `restored`) | |
| Subscriptions per user | 46 | 23 × 2 |
| Zones per user | 46 | Same structure; zone = subscription target |
| CloudKit round-trips on **first** app launch | 3 | `allSubscriptions` + `modifyRecordZones(46 saves)` + `modifySubscriptions(46 saves)` |
| CloudKit round-trips on **returning** app launch (no drift) | 1 | `allSubscriptions` only |
| CloudKit round-trips on **locale change** | 3 | `allSubscriptions` + `modifyRecordZones(noop, idempotent)` + `modifySubscriptions(46 saves with re-baked body)` |
| CloudKit zone quota (Private DB) | Hundreds per user | 46 is well under any practical limit |
| Adding a new provider | Bump `QuotaProviderList` in an iOS release | Mac side automatically routes to the new zone via `UsageProvider.rawValue` |

## Files touched in Build 54

| File | Role |
|---|---|
| `Shared/Notifications/QuotaProviderList.swift` | **NEW** — the 23-provider list + `quotaZoneName(providerID:state:)` shared between Mac and iOS |
| `Shared/iCloud/CloudSyncManager.swift` | `writeQuotaTransition` routes via `QuotaProviderList.quotaZoneName(...)` instead of the Build 52 two-zone split |
| `CodexBarMobile/CodexBarMobile/Notifications/QuotaTransitionSubscriptions.swift` | Rewrite: iterate 23 × 2, bake `alertBody` via `String(format:)`, batch save, delete legacy subs |
| `CodexBarMobile/CodexBarMobile/Localizable.xcstrings` | New keys `Push.QuotaDepleted.bodyWithProvider` + `Push.QuotaRestored.bodyWithProvider` (4 languages) |
| `CodexBarMobile/CodexBarMobile/ContentView.swift` | Release notes bullet updated to describe the message-body behaviour |
| `CodexBarMobile/project.yml` + `.xcodeproj/project.pbxproj` | Bump `CURRENT_PROJECT_VERSION` 53→54, wire `QuotaProviderList.swift` into the Shared framework |
| `CodexBarMobile/CHANGELOG.md` | Build 54 entry |

## Kept but dormant

- `CodexBarMobile/CodexBarMobilePushExtension/` — the `UNNotificationServiceExtension` target from Build 53 remains compiled into the app bundle but is never woken because subscriptions no longer set `shouldSendMutableContent`. Retained as a future-revival hook in case a future iOS release fixes whatever this container mishandles.
- `Shared/Notifications/QuotaZoneNotificationParser.swift` + its 7 unit tests — used only by the dormant extension. Low maintenance cost, kept together with the target.

## Known limitations

- **Title stays as the iOS default "CodexBar"**. Overriding the title at push time requires the extension path, which this container does not support. The body includes the provider, so information is preserved — the title just doesn't distinguish providers at a glance.
- **Adding a new provider upstream requires an iOS release** to append to `QuotaProviderList`. This is a trade-off of the hardcoded-list approach; in return we avoid the complexity + latency of dynamic provider discovery.
- **Provider display name drift**: `QuotaProviderList` mirrors Mac's `ProviderDescriptor.metadata.displayName` at the time of the iOS release. If Mac renames a provider (rare), iOS will show the stale name until the next iOS release ships.

## Real-device verification (2026-04-14)

User ran out of Claude session quota naturally on Mac, received a real iPhone push:
- Title: `CodexBar`
- Body: matched the localized Build 54 template with provider name baked in

…then the quota restored and the paired restore push also arrived correctly. No DEV button, no test push — a real production transition. End-to-end validated.

## Future work (optional, not scheduled)

- **Re-try NSE** on a future iOS release once Apple or CloudKit resolves the `shouldSendMutableContent` behaviour on this container (diagnostic: compare `allSubscriptions()` output against `CloudKit Console → Subscriptions tab` with "Act As" on the test account).
- **Move display names out of the hardcoded list** into a CloudKit record that Mac writes once per known provider, so adding a new provider on Mac is picked up by iOS without a release. Trade-off: an extra round-trip on iOS app launch.
