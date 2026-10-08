# Claude subscription dates

Status: implemented; hosted Mac/iOS verification pending.

QuotaKit adopts upstream optional billing enrichment only after rechecking the same Claude account and organization. Quota fetches survive missing, malformed, slow, and cross-owner subscription responses. Existing manual or automatically cached web credentials may enrich a successful fetch; cookie source Off does not. No new credential discovery or writes are introduced.

The existing `ProviderUsageSnapshot.providerDetails` contract carries allowlisted Subscription rows. `Renews` and `Plan expires` values are either a strict UTC civil `yyyy-MM-dd` value or an ISO timestamp with milliseconds. The phone formats civil dates in UTC so a time-zone offset cannot shift the calendar day; timestamps retain local-date behavior. CloudKit record IDs, account linkage, widget snapshots, and the SwiftData schema stay unchanged. Explicit empty detail arrays clear prior billing information; legacy missing detail payloads remain readable.

Regression coverage: ClaudeSubscriptionMetadataTests and ClaudeSubscriptionCLITests (parser, owner revalidation, cancellation/deadline/source Off); SyncCoordinatorClaudeSubscriptionTests (allowlisted precision and clearing); ClaudeSubscriptionSyncTests (wire compatibility, local date presentation, multi-device clearing, and existing persistent detail storage). Verification belongs to hosted CI; no live accounts, credential prompts, CloudKit writes, installation, or release execution.
