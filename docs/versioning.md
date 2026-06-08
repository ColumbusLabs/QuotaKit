# QuotaKit Versioning

QuotaKit currently tracks three version lanes.

## Mac

`version.env` contains:

- `MARKETING_VERSION`: Mac app version.
- `BUILD_NUMBER`: Mac build number.
- `MOBILE_VERSION`: paired iOS companion version.
- `UPSTREAM_VERSION`: last upstream CodexBar version shipped to users.
- `UPSTREAM_SYNC_DATE`: date that shipped upstream alignment was last confirmed.
- `UPSTREAM_MONITOR_BASE`: last upstream CodexBar commit already merged or reviewed for the daily monitor.

`UPSTREAM_VERSION` is release-facing and should only advance after users can get
the corresponding QuotaKit release. `UPSTREAM_MONITOR_BASE` is workflow-facing
and should advance when an upstream sync PR lands, so the daily monitor only
reopens issues for newly-arrived Pete upstream commits.

The Mac release tag for Columbus Labs releases is:

```text
v{MARKETING_VERSION}
```

Release artifacts should use the names configured in `.mac-release.env`, for example:

```text
QuotaKit-macos-universal-{MARKETING_VERSION}.zip
QuotaKit-macos-universal-{MARKETING_VERSION}.dSYM.zip
```

## iOS

`CodexBarMobile/project.yml` contains:

- `MARKETING_VERSION`: user-facing iOS version.
- `CURRENT_PROJECT_VERSION`: iOS build number.

Increment every `CURRENT_PROJECT_VERSION` before pushing an iOS release change, then regenerate the Xcode project:

```bash
cd CodexBarMobile
xcodegen generate
```

## Appcast

QuotaKit's appcast is:

```text
https://raw.githubusercontent.com/ColumbusLabs/QuotaKit/main/appcast.xml
```

Do not publish QuotaKit appcast entries that point to inherited GitHub release assets.
