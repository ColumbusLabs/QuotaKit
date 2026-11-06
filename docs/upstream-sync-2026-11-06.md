# Upstream source integration for November 6, 2026

Hosted qualification and merge evidence belong to [issue #270](https://github.com/ColumbusLabs/QuotaKit/issues/270).

Pinned range `6f72afa7b378f4b2325afe71421946ebabb821b6..20ada8abf0e4e2267aaa8c7cc9cf891cdf866838` contains 45 linear commits. The monitor cursor tracks reviewed source. The shipped upstream version and sync date stay at v0.69.0 and October 5, 2026.

| Upstream commit | Disposition | QuotaKit integration |
| --- | --- | --- |
| `f4cef507e42deb7d88dd424dcec6d111a9461ea4` | Adapted | Reject malformed cost-day arguments while preserving the configured local time zone. |
| `7fcddb5f9eb3208a158d5444b4661d6a075b4aba` | Adapted | Reject nonrepresentable hook watcher intervals before converting to a duration. |
| `fa583088865ed716f337a345b5614886cdc0ea76` | Adapted | Detect Cursor CSV layouts from the header and retain QuotaKit date-window filtering. |
| `2f741a4330a9330442397a90210dc53598128883` | Adapted | Scope fleet fallback to Codex and retain provider-owned identities. Test remote fallback and deduplication. |
| `748b4dff09fbb25a55dd05a9204187389859b0e6` | Adopted | Retry transient formatter and linter downloads using the existing verified pins. |
| `36698c56625cd85afc6ee7bf5c5c5d95368c3c6f` | Adapted | Synchronize optional plugin request fixtures with deterministic admission/deadline seams. Keep the existing PR #269 admission and cancellation contracts. |
| `78374117aa707ace7615384bf4aa3bfad21e760c` | Adapted | Expose the native NeuralWatt prepaid balance through provider cost. |
| `a20e95e6966071dd75d3b9c4c23dacf189dfcee5` | Adapted | Present Synthetic weekly plan credits without dropping the existing other quotas. Check weekly-only widget identity on iPhone. |
| `9faf0c7c9dc695b502b54247e05ea83ae3ad085c` | Adapted | Reuse bounded Bedrock cost reports by credential fingerprint, region, endpoint, and date range. Preserve explicit refresh and unknown cost behavior. Include the shared expiring-cache dependency from upstream c46e90701. |
| `79d207d1f936f0972901e567a2510d71dcb5d1ff` | Adapted | Expose a Claude dashboard warning code when the model breakdown is unavailable, without forwarding diagnostic notice text. |
| `1d590434fa46742bf16dc73c69ff1c7ea1fed459` | Adapted | Hide provider sorting when the Settings sidebar is closed. |
| `f47299f4becfd1994f3fe4b901038b38fb1ee1a1` | Adapted | Include localized pane titles in Settings search and retain the Mobile pane. |
| `bbf7c89f0c434f948fba2964c3d5f41579f07758` | Adapted | Use the system picker for Settings choices. |
| `5e50176ddcbc2815d857f83e74b327a8a060c7ed` | Adapted | Use tabular digits in usage and cost values. |
| `4d3c360aee6f0b4728bbc1fd943d417dd83f7232` | Adapted | Dim retained usage on failed refresh using QuotaKit’s existing presentation model. |
| `1ebab5e468dbc438d93dfdd6e05cb3d8243683ec` | Adapted | Preserve plus signs in Kiro CLI plan names. |
| `929c4fe2df6fbe28160a8edebc8fd234413f4be5` | Adapted | Recover Kiro usage when the saved profile is missing. |
| `8685b9324ec7da94047796f0f46fa3931b02a1c3` | Adapted | Return empty OpenCode Go history when no installation exists. Preserve authenticated missing-database behavior. |
| `eaaebcc7b9ce246153930ef68122b257208970c9` | Adapted | Require an elapsed Grok weekly boundary before reset celebration. Retain Codex correction handling. |
| `b22cdc2fd7b840390a8a31cbc5710acd6ea49216` | Adapted | Use TypeSafe overview JSON, path-eligible cookies, scoped cache ownership, and the existing locale inventory. |
| `a96e58f3019707a4f80131dd78b37b634e5c8d6a` | Adapted | Keep Claude’s omitted five-hour quota out of the session lane, preserve warning state, and display measured weekly/model/scoped windows. Preserve QuotaKit’s all-model scoped fallback. |
| `a106bf661204a96d072abe5cb80b07faf3ca9524` | Adapted | Resolve browser profile display names for Langdock without changing saved profile IDs or how storage is discovered. |
| `5ea7d006a07226cc531c3f55ae0d3445b00e6713` | Adapted | Omit stale supplemental dashboard data from the CLI. |
| `c37b29d52c1671e4a315eaa7294efcbbba5b3b98` | Adapted | Clarify status-item hosting evidence while retaining QuotaKit’s bounded and redacted diagnostics. |
| `c512c897b335cea182d98812e1970b37c1b12356` | Adapted | Label menu layout windows from their provider and report protected CLI installs with QuotaKit support links. |
| `4037ac316dbd0a6a349759da11b5ff3fd4545f86` | Adapted | Keep measured zero-cost Bedrock days and wait for Claude quota redraws before reading visible values. Exclude usage-insights percentages. |
| `e051aa059b0942de90ca679d563cda0f036e8969` | Adapted | Avoid identical retention metadata writes. Preserve the read that supplies QuotaKit’s verified-ledger publication metadata and retain source-aware archive checks. |
| `32c58efb1c7b5425e0db4c16598dcf6a1baa0f08` | Adapted | Prune expired CLI serve cache variants on refresh completion. |
| `7b3a51ad294b107397acb580a787088a7393b165` | Adapted | Release retired plugin runtimes before idle watchdog expiry. |
| `ea41440edc568350be9e058c4fd598e672aa028c` | Adapted | Reduce OpenCode Go history memory while preserving per-day cost and token evidence. |
| `458afc6017c4b2f5f97615653ce2999de3551673` | Adapted | Avoid unused Spend Dashboard projections through QuotaKit’s asynchronous publication ownership model. |
| `1ce556012450b2224abe58f2f6259426269c474d` | Adopted | Stream Cursor CSV input to reduce parsing memory. |
| `a55183c0ce2cde51b76dcfda2850e89f74b2a03c` | Adopted | Read a symlinked Claude projects root while retaining scoped configuration and nested-link traversal limits. Advance the fork’s Claude parser artifact epoch so old results are rescanned. |
| `95560897c629440582908316e333b57c996369c4` | Adapted | Release closed share previews. |
| `7e51f65933af5f9be03387dfc6f876420259a82c` | Adapted | Aggregate Grok local tokens by turn in usage.json. |
| `24132dbb10a8a8f78d34f6b593f5dfc4e8be1fe5` | Adapted | Allow a matching manual User-Agent for WorkBuddy manual cookies through the existing provider config and manifest. |
| `fbfd08c907c4d45ebf9fdc2229da58b44505c602` | Adapted | Avoid scheduling menu bar countdowns for hidden reset tokens using QuotaKit’s layout visibility semantics. |
| `b9ba2da9afdaa5f6f0b7feeff3b6c5f5ae71be50` | Adapted | Avoid applying static status icons twice. |
| `49ccb08a17dae1ffdf8528135d2209e1e87fc6eb` | Adapted with linked deferral | Sweep disposable WebKit disk and memory caches. Defer full managed-account store deletion to [#271](https://github.com/ColumbusLabs/QuotaKit/issues/271) until account recovery and live refreshes are serialized with retirement. |
| `556b359bef8cc7a8ed700d440a9efd547537097f` | Adapted | Validate Claude Platform sessions from stdin through the provider plugin before publishing the private config update. |
| `a24ec707610ab6383df1dcdc19c194883228b942` | Adapted | Reuse eligible bundled plugin runtimes across refreshes without bypassing credential scope or request teardown. |
| `18f74e039c3154f7a59955c4390ddf5cb6cf2ecc` | Adapted | Cache the Antigravity agy version by executable identity in QuotaKit’s scoped resolver. |
| `a692e7a9ffea46204d9cfc998df7bdc149e6edf9` | Adapted | Reuse a storage-free Alibaba HTTP session. |
| `fa985b7dfaec2822779ede7b5e65ab3417fd0ed2` | Adapted | Reuse a storage-free Replicate HTTP session in the fork’s current fetch path. |
| `20ada8abf0e4e2267aaa8c7cc9cf891cdf866838` | Adapted | Share the storage-free Antigravity identity connection pool across scoped requests. |

Upstream changelog hunks are accounted for as upstream release bookkeeping. QuotaKit keeps its own unreleased notes. The provider IDs, appcast, signing, release settings, build numbers, and CloudKit schema are preserved.

Verification uses independent source review and GitHub CI on the reviewed PR head. The iPhone fixture qualifies the weekly quota presentation for Claude and Synthetic against the legacy primary field and dynamic window identity.
