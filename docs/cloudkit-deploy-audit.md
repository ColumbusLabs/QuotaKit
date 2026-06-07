# CloudKit Production Deploy Audit

QuotaKit release builds use CloudKit Production.

## Container

- Production container: `iCloud.com.columbuslabs.quotakit`
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

## Audit Commands

```bash
LAST_TAG=$(gh release list --repo ColumbusLabs/QuotaKit --limit 5 --json tagName,isDraft \
  | python3 -c 'import json,sys; rows=[r for r in json.load(sys.stdin) if not r["isDraft"]]; print(rows[0]["tagName"] if rows else "")')

git diff "$LAST_TAG"..HEAD 2>&1 \
  | grep -E "^\\+.*(recordType|CKRecordZone\\(|addIndex|querySchema|CKContainer|providerPayloadVersion|CKQuerySubscription|CKRecordZoneSubscription|encodingVersion)" || true

git diff "$LAST_TAG"..HEAD -- Shared/iCloud/CloudConstants.swift
git diff "$LAST_TAG"..HEAD -- Shared/Models/UsageSnapshot.swift \
  | grep -E "^\\+.*public let|^-.*public let" || true
```

If there is no previous Columbus Labs release tag yet, compare against the last known release baseline in `version.env` and inspect the same paths manually.
