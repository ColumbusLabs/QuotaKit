---
summary: "QuotaKit update integration: Sparkle and release flow."
read_when:
  - Touching Sparkle settings, feed URL, or keys
  - Generating or troubleshooting the Sparkle appcast
  - Validating update toggles or updater UI
---

# Sparkle integration

- Framework: Sparkle 2.8.1 via SwiftPM.
- Updater: `SPUStandardUpdaterController` owned by `AppDelegate` (see `Sources/CodexBar/CodexbarApp.swift:1`).
- Feed: `SUFeedURL` in Info.plist points to GitHub Releases appcast (`appcast.xml`).
- Key: `SUPublicEDKey` set to `AGCY8w5vHirVfGGDGc8Szc5iuOqupZSh9pMj/Qs67XI=`. Keep the Ed25519 private key safe; use it when generating the appcast.
- UI: auto-check toggle (About) enables auto-downloads; a staged update remains owned by Sparkle and a manual check reopens its install UI. The menu shows the staged reminder or a manual update check and running version.
- LSUIElement: works; updater window will show when checking. App is non-sandboxed.
- Channels: stable vs beta are served from the same appcast. Beta items are tagged with `sparkle:channel="beta"`; About → Update Channel controls `allowedChannels`.

## Build number scheme (fork)

The fork uses a composite `CFBundleVersion` to track both the upstream build
number and the mobile companion version independently:

```
CFBundleVersion = {BUILD_NUMBER}.{MOBILE_VERSION}
                    53          . 1.1.0
```

- `BUILD_NUMBER` (from `version.env`) stays in sync with the upstream base build.
- `MOBILE_VERSION` (from `version.env`) is the iOS companion version.
- `package_app.sh` joins them as `${BUILD_NUMBER}.${MOBILE_VERSION}`.

Sparkle's `SUStandardVersionComparator` compares dot-separated components
numerically, so this scheme handles all update scenarios correctly:

| Installed | Appcast | Detected? | Scenario |
|-----------|---------|-----------|----------|
| `53` | `53.1.0.0` | Yes | Upstream-only user → fork build |
| `53.1.0.0` | `53.1.1.0` | Yes | Mobile version bump (same upstream base) |
| `53.1.1.0` | `54` | Yes | Upstream build bump |
| `53.1.1.0` | `54.1.1.0` | Yes | Both bumped |

This avoids build-number collisions when merging from upstream, since the
upstream's plain `53` and the fork's `53.1.1.0` occupy different version
spaces.

## Release flow
1) Build & notarize as usual (`./Scripts/sign-and-notarize.sh`), producing notarized `QuotaKit-macos-universal-<ver>.zip`.
2) Generate appcast entry with Sparkle `generate_appcast` using the Ed25519 private key; HTML release notes come from `CHANGELOG.md` via `Scripts/changelog-to-html.sh`. For beta releases: set `SPARKLE_CHANNEL=beta` to tag the entry.
3) Upload `appcast.xml` + zip to GitHub Releases (feed URL stays stable).
4) Tag/release.

## Notes
- HTML release notes are embedded in the appcast entry; the Sparkle update dialog should show formatted bullets (not raw tags).
- If you change the feed host or key, update Info.plist (`SUFeedURL`, `SUPublicEDKey`) and bump the app.
- Auto-check toggle is persisted via Sparkle; manual “Check for Updates…” is available in About and the menu.
- QuotaKit disables Sparkle when it detects a Homebrew Cask installation. No QuotaKit Homebrew tap is currently published, so the app does not offer a Homebrew update check or command. Unsigned builds also have no updater.
