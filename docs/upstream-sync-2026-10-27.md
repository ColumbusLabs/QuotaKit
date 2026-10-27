# Upstream integration — 2026-10-27

Implementation and independent source review are complete. Hosted qualification and merge status are recorded in the authoritative issue receipt below. A source change is complete only when that receipt confirms exact-head CI and merge.

Pinned upstream range: `d34fbb47afe73f81dd591bae28a60f72c39a9fe4..5f93dc3068b3bee3f8753f3772614cc2949c335d`. QuotaKit origin base: `d3e329a838f16a8031c15f2216ab13e8525cd8ca`. Tracking and authoritative delivery receipt: [issue #264](https://github.com/ColumbusLabs/QuotaKit/issues/264).

21 reachable commits: 17 adopted/adapted product and source-organization intents, one merge wrapper and three release-only rejections. No superseded or deferred applicable work. Exclude upstream changelog/release bookkeeping hunks throughout. No wholesale upstream merge.

| Upstream commit | Decision | Intent and treatment |
| --- | --- | --- |
| `aa029218d82e7086cc787fcb3d56ea24d0798edc` | adapted | feat(plugins): allow detail rows to show a pace marker (#4776) |
| `7141477080ff9bc096066af4f2a51c0782bd071e` | adapted | fix(workbuddy): keep the reset on the paid subscription cycle (#4767) |
| `3d29637240bd27fe6ef3fe75969dfe6fb383239d` | adapted | fix(workbuddy): use the official brand mark (#4768) |
| `2e8ea50081c1ce38a9b3e4e770477cdad121fc93` | adapted | fix(traecn): distinguish the usage gauge from the credits breakdown (#4780) |
| `c3d8ca5d7a82cce0d3bfdc5771bf86352a753c12` | adapted | feat(plugins): choose the window behind the menu-bar percentage (#4784) |
| `77914457d3bfe4124122174dfdd307c2699ed5b6` | adapted | fix(opencodego): fetch server quotas with the active CLI login (#4771) |
| `0aa34100b7a7ea397bcbf14eaab388d3f32aa4a1` | adapted | fix(settings): hide the undetected version row for web-only Cursor and Raycast (#4779) |
| `da9aa49b28c2ee3ba542769e5c1b8314aeda0cc2` | adapted | fix(updates): separate automatic installs from automatic checks (#4778) |
| `914204f4022eb8c38785460a1635e08df9bfc75a` | adapted | feat(cost): track OpenCode local history in the cost store (#4786) |
| `6070b29a1a5d51193a634dc1b0a14a67c39d0ccc` | adapted | feat(settings): fade the provider order undo banner (#4760) |
| `f078b60708de13c79cefd413310562f09ef14a89` | adapted | fix(cursor): read encrypted Cursor app tokens (#4790) |
| `c6d07f61da5631095bc20113b8dd650e29e5d6c8` | adapted | feat(commandcode): manage saved subscription sessions (#4774) |
| `3d00b1a7de9564068c09e2ef6e17558f0bc3b173` | adapted | feat(codex): pace the fixed 30-day Free plan window (#4766) |
| `9f026e037c1ec792527221d1b43a54030075a28f` | adapted | feat(cli): add config set-cookie and clear-credential (#4765) |
| `5de59e196f065c9f6d0e8da98f11d61a170eb9df` | adapted | feat(kimi): break monthly Total down into Kimi Code and other features (#4759) |
| `dad8c7ee87f42d3ae5d80eaecfce53aad7d72df2` | adapted | refactor(app): move provider-owned files into provider folders (#4762) |
| `c86bf6232bb5c6f61b17566f31dc00c3046c5cd6` | adapted | refactor(app): group shared app sources into folders (#4762) |
| `f8f8b04e5cd780f9bd7ef06a91995d702a130434` | merge wrapper | No independent intent beyond dad8c7ee and c86bf623; inspect merge tree. |
| `7749f7b94ae8f1b84b9ffb2046643cec810f4078` | rejected | Upstream release/version/appcast bookkeeping; QuotaKit owns releases. |
| `a3d8eae9c5233d2a185702ceab3f96dc6fe3fb09` | rejected | Upstream release/version/appcast bookkeeping; QuotaKit owns releases. |
| `5f93dc3068b3bee3f8753f3772614cc2949c335d` | rejected | Upstream release/version/appcast bookkeeping; QuotaKit owns releases. |

## Fork adaptations and verification

- Retain all 110 provider identifiers/order and generated manifests. Preserve QuotaKit by Columbus Labs identity, private config/cache paths, Sparkle feed/key, packaging/signing, App Groups/CloudKit/StoreKit/recovery and notification contracts. No version/build/shipped-upstream metadata changes; only the reviewed cursor advances after qualification.
- OpenCode history is an explicit opt-in. QuotaKit has newer native verified-day/baseline/session and pricing evidence, so isolate OpenCode source storage and merge recorded summaries at the report boundary. Never contaminate native provenance or include scoped/alternate Codex homes. OpenCode recorded history stays on this Mac; iPhone cost sync retains the native-only verified projection. Source-bearing snapshots bypass the native proof-only optimization so changed recorded amounts are published. Review fresh/cached/background report parity, source checkpoint atomicity, retention and disabled/scoped behavior.
- Preserve prompt-free Safe Storage reads through QuotaKit ACL preflight and KeychainNoUIQuery. Keep host-only Alibaba cookie scoping, active OpenCode login owner binding, stale credential rejection, and CLI writes confined to explicitly requested config fields. Test with synthetic stores/fixtures only.
- Plugin pace is backward Codable compatible; per-plugin window choices reuse existing persisted layout keys and deterministic fallback. User plugins remain outside mobile sync; no plugin wire schema change.
- Sanitize Kimi's two numeric breakdown rows through the existing optional shared detail model and localize them on iPhone. Match WorkBuddy's existing mobile icon asset to the upstream brand mark. Verify CommandCode saved-account fan-out with synthetic identities and secret-free envelopes. No provider/window identifiers or wire schema changes.
- Automatic update checks and automatic installs have separate preferences; preserve a user's saved Sparkle install choice on launch and Settings appearance. QuotaKit feed, signature key, update ownership and unavailable Homebrew/unsigned behavior remain intact. Packaging source adds the upstream default only; no packaging, installation or distribution is executed.
- Adopt upstream source grouping by moving each QuotaKit file's own contents, never replacing them with upstream blobs. Rebase live source/test/tooling paths and architecture anchors while retaining QuotaKit-specific guard enforcement. The merge wrapper has the exact second-parent tree. Six moved-only upstream paths do not exist in this fork (CodexAccountSwitcherLabeling/View, UsageStore+OpenAISubscriptionMetadata, MenuCardView+ProviderDetailVisibility, PersistentRefreshRowMetrics, UsageStore+SessionQuotaTransition); no stale types are reintroduced. Upstream’s absent site-localization helper is represented by QuotaKit’s existing localization gates.
- Qualification requires independent adversarial auth, desktop and cost review plus final exact-head hosted lint, full Mac shards/plugin engines, compatibility/widget build, Linux CLI and applicable iOS/shared/Lite checks. No routine local Swift/Xcode build/test/lint suites or real account/credential/cookie/Keychain/CloudKit probes. Cheap source/whitespace checks only locally.
- Live repository visibility is PUBLIC; ordinary PR/main CI uses standard GitHub-hosted macOS/Ubuntu runners, restore-only caches and no artifact/cache uploads. Recheck before each trigger. No paid runners, paid settings, spending cap or storage cap changes. [GitHub billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

The linked issue's delivery receipt must identify exact reviewed head, hosted run, independent review, merge commit and post-merge cursor/tail. A working-tree cursor or passing earlier head is not completion.
