# QuotaKit upstream integration — 2026-10-14

Pinned full range: `f66d18fc6fbb85c7df056bdeef56992de0619038..052ded4136dd3e2daa39edb59d33236fcb9c6be6`.
Source base: `1457ca2ea8f3aac179888c44a6e244bbcffc0793`.

The prior 62-commit checkpoint is accounted in [the Oct 13 ledger](upstream-sync-2026-10-13.md). The additional 23 commits below are linear, with no merge resolutions. The combined range contains 85 DAG commits: 51 nonmerge and 34 merge. Final classification is 51 adopted/adapted, 17 concrete exclusions, 16 empty merge wrappers and one named supersession. No applicable slice is deferred.

## Additional commit ledger

| Commit | Subject | Classification and evidence |
| --- | --- | --- |
| `f3d237304` | feat(claude): make credits, resets and plan dates independently selectable (#4484) | Adapted independent Claude credits/reset/plan visibility with compatible preference migration and sync. |
| `d6171aeb8` | feat(cursor): add short menu bar tags for lanes and Grok Bot (#4481) | Adapted Cursor lane/Grok Bot short menu tags; preserve full accessibility labels and graphical bars. Tags follow actual QuotaKit Total/Auto/API labels and saved-layout overrides rather than mislabeling Auto/API as Cursor/Third Party. |
| `664311fc8` | ci: build and test macOS with Xcode 27 only (#4497) | Rejected Xcode-27-only CI/cache-lane migration: QuotaKit requires its pinned Xcode 26.3 compatibility/mobile gates and verified standard free runners. Vision availability skips target that unused runner; existing required OCR assertions remain. |
| `5fdb2c79f` | test(claude): isolate OAuth cache tests from the shared test store (#4500) | Adapted isolated Claude OAuth test-store fixtures without accessing live credentials. |
| `d74a0f9f1` | fix(sessions): preserve macOS CLI sessions with app paths in prompts (#4474) | Adapted macOS app-path CLI-session attribution and bounded process fixture readiness. Retain the fork desktop-only app-server predicate on structured executable arguments so CLI app servers cannot relabel unknown file-only sessions. |
| `bab8d5dd2` | fix(jetbrains): read quota from JbaiQuota and Junie log records (#4457) | Adapted JbaiQuota/Junie JetBrains log parsing with synthetic fixtures. |
| `1228e9fa9` | fix(devin): use the official hexagon mark for the provider icon (#4458) | Adapted official Devin icon across Mac/mobile/CLI owned resources. |
| `84059f7f7` | fix(cookies): explain Files & Folders denial instead of Sign in (#4482) | Adapted precise Files & Folders denial guidance while retaining consent/no-UI boundaries. |
| `961220823` | feat(commandcode): fetch usage with an API key (#4462) | Adapted CommandCode API-key usage source while preserving browser/manual policies and configuration compatibility. |
| `0aef66c73` | feat(cookies): import cookies from all supported browsers for every provider (#4498) | Adapted shared supported-browser traversal across the complete eligible catalog; preserve lazy validation, scoped profiles and denial cooldown. |
| `b3d6ffb3f` | fix(spend): retain every bounded Codex account result (#4466) | Adapted every bounded Codex account result, preserving account ownership and partial progress. |
| `8ec603346` | fix(cli): mark incomplete project cost reports (#4472) | Adapted explicit incomplete CLI project cost reports. |
| `5a40ac439` | feat(openai): live tokens-per-minute usage with org limits (#4495) | Adapted OpenAI live 1-minute throughput, credential-scoped manual limits, project context and Mac UI; three-state compatible token-account/fleet sync. |
| `8b2ef4216` | test: fix two Xcode 27 CI flakes (#4505) | Adopted PTY output-ready teardown and nonblocking process-fixture exit release; assertions retained. |
| `0fbebbb42` | feat(providers): add Parallel credit balance (#4479) | Adapted default-disabled balance-only Parallel provider; append-only registry/mobile billing contracts. |
| `910dc82e7` | fix(parallel): use the shared browser order (#4508) | Adapted Parallel shared browser order, inseparable from provider and all-browser discovery. |
| `848096328` | fix(spend): keep native Codex details and tabs stable across replaced totals (#4467) | Adapted native Codex detail/tab retention across replacement totals; preserve certainty and scope. |
| `2e19c9276` | fix(claude): give spend-only accounts a meter, pace and UTC monthly reset (#4480) | Adapted Claude spend-only meters, pace and UTC month reset; genuine monthly financial limit semantics retained. |
| `ed3c650e1` | chore(release): prepare 0.75.0 | Rejected upstream 0.75.0 version/build/release-changelog bookkeeping. |
| `4668969c8` | docs: update appcast for 0.75.0 | Rejected upstream appcast publication; QuotaKit owns its release feed. |
| `3bfbf4a51` | chore: start 0.75.1 development | Rejected upstream 0.75.1 version/build/changelog bookkeeping. |
| `6964f7036` | docs(readme): rename the KDE integration to CodexBar AgentView (#4502) | Adapted AgentView name/link in explicit upstream community provenance. |
| `052ded413` | docs(readme): add the Notify! CodexBar companion (#4504) | Adapted Notify! upstream companion documentation; QuotaKit compatibility is explicitly unverified. |

## Fork contracts and verification

Keep the complete provider registry, existing identifiers/order, shared mobile payloads, CloudKit record types, secrets and three-state sync compatibility. Public branding and all release/build/signing/appcast inputs remain QuotaKit-owned. New balance providers are billing-only, never synthetic quota widgets or transition alerts. OpenCode Go retains QuotaKit’s mint tint on Mac and iPhone: upstream blue predates this range, and the fork’s existing palette/distinctness tests require the coordinated mint identity.

The Oct 13 storage uncertainty is resolved by removing ordinary CI storage writes: the optional failed iOS `.xcresult` upload becomes a bounded textual job summary, and dependency caches are restored without uploading new caches. Test commands, assertions, runners, matrices, path gates and the aggregate gate are unchanged. The Xcode 26.3 compatibility job allows 60 minutes instead of 30: hosted run 38555173123 completed its cold Swift test build after 28 minutes, then hit GitHub’s explicit job-timeout annotation during the required widget build. Both build checks remain required. The full `xcodebuild` log remains available; full downloadable failure bundles and refreshed cache uploads are the deliberate diagnostic/performance tradeoff. Release workflows are untouched. [GitHub billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions) confirm public standard-hosted execution is free and logs/summaries do not count toward artifact storage.

Source review and cheap static checks only run locally. Existing hosted Mac, compatibility/widget, Linux and shared/iOS gates must pass on the final independently reviewed head before merge. No live provider accounts, credentials, cookies, Keychain UI, CloudKit writes, local automated Swift/Xcode tests/builds, app relaunch or binary distribution are allowed.

Runtime qualification repairs append Parallel’s stable AppIntent selector case without enabling balance-only widgets, and use an inline interactive-only cookie-policy fixture because LongCat is native in QuotaKit rather than a bundled JS plugin. The latter now explicitly enables the cookie-jar gate under test; forbidden discovery/profile/network callbacks and missing-credential assertions remain. Independent source review found no remaining issue in these repairs.

Hosted runtime fixtures also follow the shared supported-browser catalog, Claude calendar-month pacing and financial meter, QuotaKit’s bounded 365-day CLI label, asynchronous dashboard-model completion, and exact SQLite replacement timestamps. MiMo retries inject the lazy candidate path with a never-read trailing session. Hyper API-only mode skips browser-cookie resolution, and dashboard fixtures follow its HTML team route. Cursor’s shared presentation labels now reflect persisted Auto/API layouts before short tags are selected. New providers retain the upstream violet/neutral accents on both platforms; five explicit palette overlaps extend the existing pair-specific exceptions without changing the general separation threshold.

## Qualification

In progress. No passing CI or merge is claimed by this ledger checkpoint. The primary local-only user commit remains preserved.
