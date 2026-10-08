# Claude subscription dates

Status: done.

QuotaKit adopts upstream optional billing enrichment only after rechecking the same Claude account and organization. Quota fetches survive missing, malformed, slow, and cross-owner subscription responses. Existing manual or automatically cached web credentials may enrich a successful fetch; cookie source Off does not. No new credential discovery or writes are introduced.

The existing `ProviderUsageSnapshot.providerDetails` contract carries allowlisted Subscription rows. `Renews` and `Plan expires` values are either a strict UTC civil `yyyy-MM-dd` value or an ISO timestamp with milliseconds. The phone formats civil dates in UTC so a time-zone offset cannot shift the calendar day; timestamps retain local-date behavior. CloudKit record IDs, account linkage, widget snapshots, and the SwiftData schema stay unchanged. Explicit empty detail arrays clear prior billing information; legacy missing detail payloads remain readable.

Regression coverage: ClaudeSubscriptionMetadataTests and ClaudeSubscriptionCLITests (parser, owner revalidation, cancellation/deadline/source Off); SyncCoordinatorClaudeSubscriptionTests (allowlisted precision and clearing); ClaudeSubscriptionSyncTests (wire compatibility, local date presentation, multi-device clearing, and existing persistent detail storage). Verification belongs to hosted CI; no live accounts, credential prompts, CloudKit writes, installation, or release execution.

Hosted verification: CI run [37762280331](https://github.com/ColumbusLabs/QuotaKit/actions/runs/37762280331) on `3fb07eb9e9e97cc8d19bdf226078f6932cb205ae` passed these Mac regression suites and the iOS suite (642 Swift Testing cases, 174 XCTest cases, and four UI tests). Unrelated provider integration failures from that run are repaired separately; the integration PR still requires all applicable checks on its final reviewed head before merge.
