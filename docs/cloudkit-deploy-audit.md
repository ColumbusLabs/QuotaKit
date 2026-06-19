# CloudKit Production Deploy Audit

QuotaKit release builds use CloudKit Production.

## Container

- Production container: `iCloud.com.columbuslabs.quotakit`
- Apple Developer team: `78PXX669LQ`
- Mac entitlement: `com.apple.developer.icloud-container-environment = Production`
- iOS entitlement: `com.apple.developer.icloud-container-environment = Production`

## When A Schema Deploy Is Needed

Deploy CloudKit schema changes to Production when a release adds or changes:

- CKRecord types
- CKRecord fields used by queries, sorting, or indexes
- Queryable, sortable, or searchable indexes
- CKRecordZone definitions
- CKQuerySubscription or CKRecordZoneSubscription predicates for new fields or record types

Payload-only JSON changes inside opaque `Data` blobs usually do not require a CloudKit schema deploy.

## Required Production Schema

Mac-to-iOS sync depends on these Production record types in
`iCloud.com.columbuslabs.quotakit`:

- `DeviceSnapshot`: `deviceName`, `deviceID`, `appVersion`, `syncTimestamp`, `payload`
- `DeviceProviderSnapshot`: `deviceID`, `deviceName`, `providerID`, `providerName`, `accountEmail`, `lastUpdated`, `encodingVersion`, `payload`
- `DeviceStatus`: `deviceID`, `deviceName`, `appVersion`, `syncTimestamp`, `encodingVersion`, `payload`
- `ProviderAccountLinkage`: `providerID`, `linkedIdentifiers`, `confirmedAt`, `confirmedFromDeviceID`, `unmerge`
- `QuotaTransition`: `providerName`, `providerID`, `state`, `transitionAt`, `deviceID`, `accountEmail`

`DeviceProviderSnapshot.deviceID` must be queryable because the Mac startup
reconcile queries provider records for the current device.

`DeviceSnapshot.recordName`, `DeviceProviderSnapshot.recordName`,
`DeviceStatus.recordName`, and `ProviderAccountLinkage.recordName` must also be
queryable. iOS full-refresh
paths issue whole-record-type CloudKit queries for those records, and
Production rejects those reads with `Field 'recordName' is not marked
queryable` when the built-in record-name index is missing. CloudKit Dashboard
labels the field `recordName`; schema exports may represent the same index as
`___recordID`.

If a release build shows `Cannot create new type DeviceSnapshot in production
schema`, Production schema has not been deployed. Open CloudKit Dashboard,
select `iCloud.com.columbuslabs.quotakit`, and use **Schema -> Deploy Schema
Changes to Production** before publishing another Mac release.

## Audit Commands

```bash
Scripts/verify-cloudkit-schema.sh

LAST_TAG=$(gh release list --repo ColumbusLabs/QuotaKit --limit 5 --json tagName,isDraft \
  | python3 -c 'import json,sys; rows=[r for r in json.load(sys.stdin) if not r["isDraft"]]; print(rows[0]["tagName"] if rows else "")')

git diff "$LAST_TAG"..HEAD 2>&1 \
  | grep -E "^\\+.*(recordType|CKRecordZone\\(|addIndex|querySchema|CKContainer|providerPayloadVersion|CKQuerySubscription|CKRecordZoneSubscription|encodingVersion)" || true

git diff "$LAST_TAG"..HEAD -- Shared/iCloud/CloudConstants.swift
git diff "$LAST_TAG"..HEAD -- Shared/Models/UsageSnapshot.swift \
  | grep -E "^\\+.*public let|^-.*public let" || true
```

If there is no previous Columbus Labs release tag yet, compare against the last known release baseline in `version.env` and inspect the same paths manually.

`Scripts/verify-cloudkit-schema.sh` is read-only. It requires a CloudKit
Management Token saved with `xcrun cktool save-token "<token>" --type
management`, saved through the secure interactive prompt with `xcrun cktool
save-token --type management`, or provided through cktool's supported token mechanisms. Mac release
phase 1 runs this verifier automatically. To bypass it for a documented
emergency release only, set `QUOTAKIT_SKIP_CLOUDKIT_SCHEMA_VERIFY=1`.
