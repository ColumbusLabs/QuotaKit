# Upstream integration — 2026-10-03

## Pinned range and scope

- QuotaKit origin/main: `a66066c7384a6cf1df99f442f55d05d1b5c940e5`.
- Reviewed upstream base: `acc22cacf12e99142233af0dd9d300d8f438a619`.
- Pinned upstream head: `917ae1465d984710817f8010a824612f74b1a6f9`.
- 67 reachable commits. Product behavior is adopted or adapted through final coherent chains; upstream release bookkeeping is excluded.

Preserve QuotaKit identity, all existing provider IDs, credential ownership, persisted cache and mobile/shared contracts, CloudKit/App Groups, updater/appcast/signing, versions and build numbers. LithosAI is a spend/balance surface; it must not acquire quota/reset subscriptions. No release, binary distribution, live credentials, Keychain UI, browser-cookie import, or live CloudKit writes.

## Verification and free CI boundary

Hosted CI owns automated tests, lint, builds and iOS simulator validation. Local work is source inspection and cheap static checks only. Independent range accounting and adversarial review are required before merge.

Live GitHub visibility is PUBLIC. The only branch/PR-triggered workflow is CI; it uses standard `ubuntu-24.04`, `ubuntu-24.04-arm`, `macos-26` and `macos-15` runners, no reusable workflows or larger runners. Release workflows require release/tag/manual events; the monitor requires schedule/manual events. No such event is requested. Official GitHub billing rules confirm standard hosted execution for public repositories is free: https://docs.github.com/en/billing/concepts/product-billing/github-actions.

Live ColumbusLabs billing UI shows the Actions product budget at $0, $0 spent and Stop usage Yes. No settings changed. Cache storage was 9,338,167,680 bytes; removed only two caches belonging to verified merged PR #222 with no active workflow runs, leaving 6,645,800,910 bytes (<10 GiB). Root dependency/cache keys are unchanged; the widget pin follows the existing SweetCookieKit 0.5.4 root pin. Existing CI uploads an iOS result bundle only on failure; no additional uploads or storage limits are introduced.

## Commit accounting

67 commits: 30 adapted, 3 superseded, 6 rejected, 28 accounted merge. No applicable slice is deferred. Every merge was inspected with `git show --remerge-diff`; eight contain independent product resolutions adopted through their final chains. Generated catalog/plugin files use repository-owned generation; QuotaKit’s existing site-catalog and llms checks cover its native card/guide topology rather than importing the upstream generator’s incompatible HTML/social schema and hard-coded upstream links. The CLI icon generator also fills the previously omitted, already-registered MuseAI icon while adding LithosAI; no provider is removed. Upstream release/social publication assets are omitted.

| Commit | Disposition | Representation or reason |
| --- | --- | --- |
| `dbdd465b4cc7b059cb18f1146fda586a73d865e5` | Adapted | Antigravity Hub request identity through final shared-client resolution 51eb3b0e8. |
| `9ed0d96a0f9a887cdd79eef35aa77aba0e05806f` | Adapted | Linux Hub user agent platform through shared-client resolution 51eb3b0e8; portable CLI remains supported. |
| `ff35cc2edc31e8e7ce0a3ec59c8539b28469cb98` | Adapted | Saved project names and stable path identity through cached-load refresh 7202ef3b1. |
| `f5fcf05d6e78972c2b17409fec63b047a0fc44c2` | Superseded | Presentation helper split superseded by in-place metadata overlay in 7202ef3b1; no temporary helper file retained. |
| `0953733615b929805e8c86ac58d5d1f94284bd3b` | Adapted | Status publication generation guards through final hook/background safeguards e4dcc4869. |
| `b71dc6a9dc26c866aa65160941d92685c4975f99` | Superseded | Temporary upstream proof log deleted by e4dcc4869; synthetic production-seam regression retained in the status chain. |
| `43c1e338eaee58f0ec5e9282b0eebc0a8e97a2a1` | Adapted | Pi one-hour cache-write subset through strict shared-reader validation 26ee8be34 and formula-version invalidation. |
| `51eb3b0e82e5b221b0933c0eafae5a31bc49722f` | Adapted | Meaningful merge resolution: common Hub identity covers shared/selected quota summaries, fallback, onboarding and refresh. |
| `2cfa63250079b96b00a0da10358001e676cee19d` | Accounted merge | Parent product chains accounted; no independent resolution delta. |
| `cd244a0f03ff3b33a3b4800e1ae1e184b3059eb5` | Adapted | LithosAI provider and scoped host-only cookie header echo; QuotaKit Mac/mobile catalog, settings, widgets and spend-only contracts adapted. |
| `637947ac14ac827cc07d0d5d4805683d0a8dd322` | Rejected | Upstream 0.71.0 release/changelog/version state belongs to upstream release ownership. |
| `9260f2fe413ddcca37cec21f443fc327d20ee999` | Rejected | Upstream shipped-release changelog bookkeeping. |
| `76b212b445493fddd8311a09b1057cd71ce385a2` | Adapted | Previously shared widget colors follow provider menu accents; distinct widget colors and user overrides preserved. |
| `f5835e3e1cb3ad0d6d5a47dcecf09c9adc694987` | Adapted | Opt-in synthetic widget rendering fixture; no live rendering or app launch during integration. |
| `98d84b8a06957e193a9a8e58b40590736c94bf70` | Adapted | Widget SweetCookieKit pin aligned to existing root 0.5.4; fork workspace origin hash preserved. |
| `c676f3ac296b16d7e6af41443c22f2b32bfa813a` | Adapted | Empty token-history no-write equivalence through lock-safe final 39c8e9bb1; real nonempty history clearing remains a write. |
| `51282630656f65b04e6863cc140564186030a699` | Adapted | Parsed Claude window certification survives pricing replacement through final a66157f4b. |
| `d4813eeba03bbf1add170f3c8a2047c34ddaad7d` | Adapted | Certified Codex decoded baselines retained across metadata-only saves through final 061dcea9a. |
| `cb5f0cbe88615a441272c6f9e44675bf594a3fa3` | Rejected | Upstream public appcast/release publication; QuotaKit appcast remains unchanged. |
| `c40bec29a7c1471d935c1de549d04e9f77878310` | Rejected | Upstream version and development-release bookkeeping. |
| `29ae87e252317523c76955551fc23251e81cf2a5` | Adapted | Offline root/widget package pin parity checker and synthetic CI tests; no dependency resolver or build run locally. |
| `b1943758c729f8e7f45ee2620f7c9650abf7807c` | Adapted | Grok scans restricted to session roots through final 73f4b119a including empty-summary publication. |
| `cab1ded6756e0f7d4bac633ea639a39630ddd528` | Accounted merge | Parent product chains accounted; no independent resolution delta. |
| `39c8e9bb18c8d735422ced70ffe56d6f54d8f9ca` | Adapted | Meaningful merge resolution: normalize empty vs unloaded token history only with zero persisted rows; lock-safe persistence and regression hooks. |
| `e4dcc48696dba8b6c19c8cf08ff9f3c0f2a27fd3` | Adapted | Complete status hook/background publication safeguards and synthetic overlap tests; upstream proof artifact omitted. |
| `7551fa98d91a94c68c78cd58199d4160c7cead4a` | Adapted | Long inline dashboard headings wrap; menu recycling/selection coverage and QuotaKit UI documentation. |
| `695520423e8d379d0ebcca161317778a06d487c1` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `5955c9f5af42392fc669b1c819200a305ef143a3` | Adapted | Palette regression/render tests and documentation follow final shared accent policy. |
| `061dcea9a1e292e3108749932039d695feeda183` | Adapted | Meaningful merge resolution: certify only own metadata writes under writer lock; preserve external change detection, pending catch-up and post-commit invalidation. |
| `a66157f4bed78a082f73c0326eb7a42b773378ef` | Adapted | Meaningful merge resolution: keep transcript-window certificate while stale pricing stamps force reprice; QuotaKit Claude producer advanced from 15 to 16 for cache invalidation. |
| `26ee8be3425481f04725a7b936ba9003bff99db9` | Adapted | Meaningful merge resolution: strict first-present alias reader for Pi/OMP one-hour subset, shared cost-model fixtures and reprice version. |
| `dc291de9edab97f8f7bd707bdfdbda312f8605c8` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `a5415cd0881c9d087f59dea2a87772b76c541db5` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `9f51abdabd2de99395ec15f2a8d3aebd15dc06f1` | Accounted merge | Parent product chains accounted; no independent resolution delta. |
| `047983e4a1b756987591d546a4d4c0292c4640d7` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `c2be4ec1ffe4fb5ab6b92f51dc6f5c6998e98039` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `2148d5401243d20506d983ee4b76963b61914b5c` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `7dedb5bdac765bbe7f63371eee5848a848496196` | Accounted merge | Parent product chains accounted; no independent resolution delta. |
| `618cb44a90d293e3061e2c08c1518874691dc228` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `896255a024223ba774285a4fc3ec74cb6ecc676e` | Adapted | CommandCode bare manual session-token normalization with synthetic validation and no-secret diagnostics. |
| `8a954aa5f4010d2426fbebb171547b83eb02e7eb` | Accounted merge | Parent product chains accounted; no independent resolution delta. |
| `97a55f52d0be4a5c346ad26392be803b73bc8b33` | Accounted merge | Parent product chains accounted; no independent resolution delta. |
| `7ae191a3e3aaabad6d8e4df432aa574cb340932c` | Accounted merge | Parent product chains accounted; no independent resolution delta. |
| `6091f7405488cbc3e4b340bbd11099a965bab0f5` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `9f0749e1e890f0fdeaa50d84e9697c758d8823b7` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `5c7735f8afa8d7ab2480766e1316ad16bb7aeb67` | Accounted merge | Parent product chains accounted; no independent resolution delta. |
| `73f4b119a9f84a2e92256dd033519fc0a4f6a9c5` | Adapted | Meaningful merge resolution: bounded Grok direct-session scan, ignore nested artifact sessions, preserve empty cost summaries and publication regression coverage. |
| `20daa80634683ffef787f38d5faade118f6d852d` | Adapted | Fresh exact Codex weekly quota can confirm without historical inventory, retaining identity/plan/time/positive inventory checks. |
| `09e03d62c7304859732001a0a1258121b6a0900b` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `7202ef3b1a22aaca1804cc90e99bb2c569a79528` | Adapted | Meaningful merge resolution: one bounded read-only project-name lookup per SQLite home on fresh and cached loads; names remain presentation-only and are omitted from widget wire summaries. |
| `fcba379d0e431378947c2a1abde03fc6ff8a613a` | Superseded | Mid-week-start workaround superseded by complete weekly cadence 2274cf3b5; trials and invalid/missing reset dates remain unpaced. |
| `935b4c53b8cdcaa124a362d7db608c22ef4e80d5` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `0ee0c3adbe1ceffd8d7272e65c5c05245b5fb2c5` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `d35992ad0c86317f9eee8f6d8852e42f2f24c731` | Accounted merge | Parent product chains accounted; no independent resolution delta. |
| `50ce15d2b1ad526356475f2ce1d7001e9812443e` | Adapted | Controlled process/OpenCodeGo/account fixtures and production test seams replace timing assertions while preserving cleanup behavior. |
| `c8faf7233be5eeee7a79aaff75fdb96458d55f6a` | Rejected | Upstream changelog-conflict-only bookkeeping; QuotaKit-native Unreleased product notes written separately. |
| `839f31ed7c8e000538f0526ddb86ee706022038c` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `cad03a93b70df05bd1cf36155166575922c29bc0` | Adapted | Per-test SettingsStore defaults isolate persistence/account/window test fixtures. |
| `4489d919cd13f5079b52b8632809a8c73392fad1` | Accounted merge | Parent product chains accounted; no independent resolution delta. |
| `2274cf3b57d8b1c2e9f4a46efaff3c4124f54284` | Adapted | Meaningful merge resolution: paid Grok Bot reset uses full seven-day cadence regardless of period start; monthly/trial semantics remain unchanged. |
| `89cbd4654352b170caa52ecbf28ac791cd979a45` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `a53a6fe19e62cbeded0bc06a316c2ff1a80cf228` | Adapted | Supported automatic browser-source metadata and translated guidance; QuotaKit naming and consent behavior retained. |
| `d9b340cd2b448ffb10c672a18d172a89efa7b645` | Accounted merge | Parent product chains accounted; only upstream changelog conflict resolution, omitted. |
| `83560bf6072d8e17b6fe5e549d357ee2f2b40cd5` | Accounted merge | Parent product chains accounted; no independent resolution delta. |
| `b04864bb5dd3bf0dc1b0ea842ab7f4e1a48550ad` | Accounted merge | Parent product chains accounted; no independent resolution delta. |
| `78ce03aacfe05694cda9dedd72e5c159f048c3b6` | Accounted merge | Parent product chains accounted; no independent resolution delta. |
| `917ae1465d984710817f8010a824612f74b1a6f9` | Rejected | Upstream 0.71.1 release-changelog bookkeeping. |

## Fork adaptations

- LithosAI appends the 89th catalog entry. All 88 prior IDs remain; the quota-alert subset stays at 72 providers and 216 subscriptions. Its prepaid balance is excluded from used/limit budgets and spend summaries while sanitized details sync to iPhone.
- Cookie policy lives in QuotaKit’s existing manifest type. Header echo retains strict URL-scoped cookie records, opaque session handles, access gating and no-UI credential reads.
- Codex empty-history/baseline persistence is implemented in the fork’s receipt-based Codex cache/baseline/read seams, with synthetic store regressions rather than importing incompatible upstream store/test topology.
- Mac widget accents follow the final upstream behavior; CommandCode’s distinct black widget, burn-down/confetti colors and the independent iOS widget palette remain preserved.
- Saved project names are presentation-only; stable filesystem paths remain grouping identities and personal project names stay out of widget wire summaries.
- Versions/builds, shipped UPSTREAM_VERSION, appcast, updater, signing, entitlements, CloudKit and App Groups are unchanged. Only the reviewed-head cursor and sync date advance.

## Pre-PR review

Source review and independent adversarial review resolved the cache-certificate and plugin-test issues; no substantive findings remain. Cheap whitespace and script syntax checks pass. Synthetic fixtures cover redirects/cookie authority, concurrent cache writers and triggers, pricing races, stable project identity/privacy, status ordering, reset inventories, process timing and LithosAI mobile balance contracts. Mac palette assertions use QuotaKit’s accepted 16-provider audit rather than upstream’s incompatible 36-provider proposal table. The opt-in Cursor tile fixture uses QUOTAKIT_WIDGET_PROOF_DIR and is not invoked. Hosted exact-head CI is the pending merge gate; no local Swift/Xcode tests, builds, app launch, packaging or live accounts were used.
