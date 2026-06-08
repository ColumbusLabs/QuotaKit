# Release Checklist

Use this checklist before publishing QuotaKit releases.

## Public Identity

- [ ] Product copy says QuotaKit.
- [ ] Company copy says Columbus Labs.
- [ ] Download/setup links point to `https://columbus-labs.com/quotakit/mac`.
- [ ] GitHub release links point to `ColumbusLabs/QuotaKit`.
- [ ] Appcast links point to `ColumbusLabs/QuotaKit`.

## iOS

- [ ] `CodexBarMobile/project.yml` build numbers are bumped when needed.
- [ ] `cd CodexBarMobile && xcodegen generate` has been run after project changes.
- [ ] `CodexBarMobile/CHANGELOG.md` is updated.
- [ ] In-app release notes are updated when user-facing behavior changes.
- [ ] `./Scripts/lint.sh lint` passes.
- [ ] iOS simulator build passes.

## Mac

- [ ] `.mac-release.env` points to Columbus Labs release settings.
- [ ] Appcast entries use QuotaKit artifact names.
- [ ] `Scripts/verify-cloudkit-schema.sh` passes for `iCloud.com.columbuslabs.quotakit` Production.
- [ ] Signed/notarized artifacts are verified before publication.

## Release Gate

- [ ] `https://columbus-labs.com/quotakit/mac` returns a working 2xx/3xx response.
- [ ] GitHub release assets exist before appcast publication.
- [ ] Any `QUOTAKIT_SKIP_CLOUDKIT_SCHEMA_VERIFY=1` bypass is documented with the manual CloudKit Dashboard verification that replaced it.
