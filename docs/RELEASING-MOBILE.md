---
summary: "QuotaKit Mac and iOS release pointers."
read_when:
  - Preparing a QuotaKit Mac release
  - Preparing an iOS TestFlight/App Store upload
  - Checking appcast or GitHub release ownership
---

# QuotaKit Release Guide

QuotaKit releases are owned by Columbus Labs.

## Public Release Targets

- Repository: `ColumbusLabs/QuotaKit`
- Setup page: `https://columbus-labs.com/quotakit/mac`
- Appcast: `https://raw.githubusercontent.com/ColumbusLabs/QuotaKit/main/appcast.xml`
- Release artifacts: use the `QuotaKit` names configured in `.mac-release.env`

## Mac Release Defaults

Read `.mac-release.env` before packaging. It defines the QuotaKit app name, bundle ID, release repo, appcast URL, download URL prefix, and artifact naming rules.

The first Columbus Labs Mac release must use a Columbus Labs Sparkle signing key. Do not reuse inherited private keys or publish to inherited GitHub release feeds.

## iOS Release Defaults

The iOS app uses `CodexBarMobile/project.yml` for `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.

Before a pushed iOS release change:

1. Increment every `CURRENT_PROJECT_VERSION`.
2. Run `cd CodexBarMobile && xcodegen generate`.
3. Run `./Scripts/lint.sh lint`.
4. Run the full iPhone simulator test command in `AGENTS.md`.
5. Archive/upload with `./Scripts/ios_testflight_xcode.sh`.

## Headless TestFlight Contract

QuotaKit's canonical TestFlight lane is the `xcodebuild` CLI script above.
The Xcode GUI is not part of this workflow, and the script requires App Store
Connect API-key authentication instead of falling back to an account stored in
Xcode. Validate the machine without generating the project or creating an
archive:

```bash
./Scripts/ios_testflight_xcode.sh --preflight-only
```

The preflight prints the selected Xcode build, developer directory, system and
shell `rsync` versions, verifies all three App Store Connect key inputs, and
proves the installed Apple Distribution private key by signing a disposable
binary. If the signing probe reports a locked Keychain, run the exact
`security unlock-keychain ...` command it prints in Terminal and retry. Opening
Xcode is appropriate only when the distribution certificate/private-key pair
is genuinely absent.

A locked or unavailable paired iPhone is non-blocking for a generic iOS
archive. Messages such as `The device is passcode protected` or failures to
start `com.apple.mobile.notification_proxy` are device-discovery noise; do not
unlock the phone, change the generic destination, or open Xcode to work around
them. The archive target remains `generic/platform=iOS`.

The export step intentionally pins `PATH=/usr/bin:/bin:/usr/sbin:/sbin` so
Xcode cannot mix Apple's `/usr/bin/rsync` with an incompatible Homebrew rsync
server.

### Retest the clang workaround after Xcode upgrades

The current wrapper removes `-v` only from Xcode's `-E -dM ... /dev/null`
compiler-identification probe. The release script records the Xcode build on
which that workaround was verified and warns when the active build changes.
After an Xcode upgrade:

1. Run `./Scripts/ios_testflight_xcode.sh --preflight-only` and review the tool versions.
2. Prove the normal wrapper path with `./Scripts/ios_testflight_xcode.sh --skip-lint --archive-only`.
3. Test native clang without uploading:

   ```bash
   QUOTAKIT_DISABLE_CLANG_PROBE_WORKAROUND=1 \
     ./Scripts/ios_testflight_xcode.sh --skip-lint --archive-only
   ```

4. If native `xcodebuild` archives reliably, remove the wrapper, its build
   marker, and the corresponding regression assertions. If it hangs, stop the
   archive and retain the workaround for that Xcode build.

## CloudKit

All release builds must use CloudKit Production for `iCloud.com.columbuslabs.quotakit`.

Before a Mac release, review `docs/cloudkit-deploy-audit.md` to decide whether CloudKit schema changes need a Production deploy.

## Safety Checks

- Confirm GitHub release drafts are on `ColumbusLabs/QuotaKit`.
- Confirm appcast entries point at `ColumbusLabs/QuotaKit` release assets.
- Confirm public setup links point at `https://columbus-labs.com/quotakit/mac`.
- Confirm no release script is targeting inherited repos.
