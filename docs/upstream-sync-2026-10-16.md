# QuotaKit upstream integration — 2026-10-16

Frozen reviewed range: `a49c61c30bb829c89460a95294fc09c5dab22221..f50cd6cee4db4e96e4823a51f74eb462a56bbb66`.
QuotaKit source base: `0234b7076f36ce12501c2879be9b5b4d01567ccb`.
Tracking issue: [#248](https://github.com/ColumbusLabs/QuotaKit/issues/248).

All 33 commits are linear: 25 product/test intents and one widget-recovery documentation commit are adapted; six release-only commits and one inapplicable updater commit are rejected. There are no merge wrappers, superseded patches or applicable deferred slices. Each commit's paths, full patch and dependency relationships are inspected. No wholesale upstream merge is used.

| Commit | Classification | Upstream intent |
| --- | --- | --- |
| `0bedb9924678a14814190996724ca59dd85d75ea` | Adapted | fix(helmcode): import Cloud sessions scoped to the API host (#4492) |
| `74f64b62b5d38b9cea59107d15799d69563eb38a` | Adapted | test(plugins): wait for watchdog release with a deadline (#4541) |
| `a8eb7b8c4cd4ed00f8483831a78a9f4368145c79` | Adapted | fix(pty): keep buffered output when commands exit quickly (#4543) |
| `27e9b9a08f171ee0ca9d1659e87e9d5d52fe9bee` | Adapted | fix(settings): never overwrite an unreadable config (#4509) |
| `85f38b8c2bd36ac26291d572335a2408efb62ddd` | Rejected: upstream release bookkeeping only | chore(release): prepare 0.76.0 |
| `2d8b1409a1649dce60f3610ebe4eab52b92545de` | Rejected: upstream release bookkeeping only | docs: update appcast for 0.76.0 |
| `506db610b8b761b817830bc8080bf4e667a76acb` | Rejected: upstream release bookkeeping only | chore: start 0.76.1 development |
| `df024f935a684ced2e616171ad0f1c096c42c077` | Adapted | fix(dock): stop rescanning windows on every update pass (#4524) |
| `bbbd6f9234721eba4678267293e539139b003bec` | Adapted | fix(qwen): treat an empty Team summary as no Team subscription (#4527) |
| `72f47e23c8e872d720f35fc36a272b3f17f855c8` | Adapted | fix(claude): open Platform usage for default accounts (#4503) |
| `0c760f9ba25a4bb586123c6a8cb0f4721a364972` | Adapted | fix(opencodego): read OpenCode v2 session history for local cost (#4526) |
| `d679e809605be313be38876bb167afbb2661e9fe` | Adapted | fix(confetti): let the reset confetti finish (#4536) |
| `12b192ff25df954b2f926bd68d6019c9699b832f` | Adapted | fix(menubar): dim monochrome stacked titles on inactive displays (#4547) |
| `d846ceb47f3151df6caa88cd9aa61b17cb7185aa` | Adapted | fix(widgets): keep Antigravity window resets in usage rows (#4529) |
| `fdb38ac8b50cfa5b843b57e5f1cabbce575d5069` | Adapted | fix(cookies): keep per-browser permission guidance (#4528) |
| `2022e6934ae9c937cf9a4d1d7444d931d1c551c2` | Adapted | fix(codex): drop rejected browser cookies from the account store (#4514) |
| `b8b295bccd012b3b05c5792ee55fcac1f8fce3ab` | Rejected: no supported QuotaKit Homebrew cask/updater | fix(updates): recover Homebrew upgrades after a failed refresh (#4520) |
| `487436df295ee71e08769490dfa27fa930566231` | Adapted | perf(cost): bound Codex thread titles read from the state database (#4550) |
| `68005e3c12543e825a3f45f3ec4f9104897b17fa` | Rejected: upstream release bookkeeping only | docs(changelog): move post-0.76.0 entries out of the released section |
| `b585bc330f517a2cb38e5b45855c12179522e050` | Adapted | test: keep local test runs out of the developer cost cache (#4551) |
| `8a11b66458614048bef0f9635f72d4838b89d63a` | Adapted | perf(cost): speed up native history marker searches (#4552) |
| `bd57aa3aaa90ddc95e527fb125c1bc6260579122` | Adapted | fix(forecast): keep session forecasts after reset corrections (#4540) |
| `f748e3b9daa14e144b5bf9bc9ffe653f42d32c51` | Adapted | feat(settings): offer 6 work days for weekly pace (#4548) |
| `959b868094f8c380377b065c5911fb59872d9b9f` | Adapted | fix(claude): release sleep inhibitors left by passive probes (#4544) |
| `48f648e51406f072b4528ea14b44e6eaa5915487` | Adapted | test: keep settings fixtures out of the SweetCookieKit Keychain gate (#4558) |
| `ffe39e702b96efc0456137b9d737a3b928c5bef3` | Adapted | docs(widgets): document post-update extension recovery (#4569) |
| `f43f19fc01d9246c6d955ab1e46c4689844d172f` | Adapted | fix(widgets): keep provider details in widget snapshots (#4555) |
| `e20070829d5ede8aa22ac5b0ca3864e9af0a903e` | Adapted | feat(claude): import cookies from the Claude desktop app (#4539) |
| `218a7e7b380a150e9098744a3b2d688960e8fa86` | Adapted | feat(settings): add back/forward navigation and a native header (#4475) |
| `08e15ffd0d44d310054d530a9b507f6390c7e7d7` | Adapted | feat(menu-bar): rank Auto quotas by depletion risk (#4491) |
| `448d05c52fcbad2d74c0b98abcb5e69589af1b30` | Rejected: upstream release bookkeeping only | docs(changelog): restore 0.76.1 entries dropped by a section rewrite |
| `7e60198d7bb31b03a703bd04481011a59e8eb808` | Rejected: upstream release bookkeeping only | docs(changelog): match the released 0.76.0 section to its tag |
| `f50cd6cee4db4e96e4823a51f74eb462a56bbb66` | Adapted | fix(antigravity): avoid incorrect OAuth Free labels (#4571) |

## Fork adaptations and boundaries

- Keep QuotaKit / Columbus Labs identity, configuration and Application Support paths, full 104-provider catalog and IDs, mobile/shared sync wire contracts, CloudKit/App Group/notification identities, StoreKit behavior and recovery safeguards.
- Do not import upstream changelog release sections, version/build/date changes, tags or appcast entries. `UPSTREAM_VERSION=v0.69.0` and `UPSTREAM_SYNC_DATE=2026-10-05` remain release provenance; all Mac/iOS build numbers, release ownership, entitlements, signing and binary delivery remain unchanged.
- Claude desktop cookie import is explicit opt-in and provider-scoped; preserve QuotaKit consent and background no-UI policy. Adopt its coherent SweetCookieKit 0.5.8 dependency in both root/widget locks and pinned acknowledgements. The license text and digest are unchanged in upstream's pinned notice inventory.
- Preserve strict source-owner/history boundaries and recovery paths when adapting unreadable-config writes, rejected-cookie invalidation and browser-specific permission guidance.
- Mac widget snapshots retain QuotaKit's additive quota slots, actual reset/window semantics and shared/mobile contracts while adopting provider detail preservation. Antigravity labels do not invent a Free plan from insufficient OAuth evidence.
- Unrelated array-subscript formatting in the marker-search patch is excluded; existing implementations remain unchanged.
- Native-history marker performance changes preserve parsing semantics and accept the actual preceding QuotaKit producer hash as a compatible cache predecessor. Regenerate the repository-owned parser fingerprint; do not copy upstream cache hashes.
- Adapt test-private-home isolation to QuotaKit's current native/direct harness; retain exact discovery/runtime inventories, timeouts, containment, cancellation and retry gates. Discovery, serial groups/retries and shell wrappers also set private `CODEX_HOME` and remove inherited `CODEX_SQLITE_HOME`, matching the existing direct runner so explicit history-path overrides cannot escape the temporary home. Upstream's absent alternative test wrappers are represented by QuotaKit's existing entrypoints.
- `b8b295bcc` targets an owning upstream Homebrew cask and updater absent from QuotaKit. `docs/releasing-homebrew.md` and `docs/RELEASING.md` explicitly establish no supported QuotaKit cask or Homebrew release lane; `makeUpdaterController` intentionally reports managed-install ownership. Importing the upstream cask updater would target the wrong product. Preserve that policy, with no guessed cask or new release lane.
- Widget troubleshooting uses QuotaKit bundle/process names and separates snapshot/reload requests from installed WidgetKit execution. Historical upstream reports are evidence of a workaround, not proof of QuotaKit runtime behavior.

## Verification and cost

This broad credential/config/runtime/UI batch requires independent adversarial source review and applicable exact-head hosted gates, including iOS when shared/mobile-consumed data changes. Locally use source inspection, `git diff --check`, pinned write-mode formatting where needed and documented generation only. Do not run local Swift/Xcode tests/builds/lint suites, packaging, installation, relaunch, provider probes, credentials, Keychain UI, live browser cookies or CloudKit operations.

Before workflow-triggering actions, recheck live PUBLIC visibility and complete workflow/job/matrix inventory. Current tracked PR/main jobs use standard macOS/Ubuntu hosted labels, restore-only caches and no artifact uploads or cache saves; no reusable, larger or custom runners are triggered. The historical diagnostic workflow triggers only its separate diagnostic branch. Existing cache bytes are 9,839,485,195, below the included 10 GiB. Billing UI shows $0 billable Actions usage and 0.2/0.5 GB included storage; raw historical artifact inventory is 1,464,092,523 bytes and is not newly uploaded or expanded by this batch. Existing stop-usage settings are preserved. [GitHub billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions) confirm free standard public runner execution and always-billable larger runners. No paid usage/settings or extra uploads are authorized.

The identical-tree preceding main CI run `38742480574` failed a StatusMenuTests timeout, including its isolated retry. Its isolated log records 178 passing cases totaling 105.934 seconds plus startup/fixture overhead before the 120-second suite deadline; the last announced case is not proof of a case-specific hang. This is baseline duration evidence, not passing qualification or permission to relax a gate. The current reviewed source must pass required CI on its exact PR head before merge.

Implementation covers all classified intents. Independent review and exact-head CI/merge receipts are maintained on the tracking issue. Candidate cursor advancement to the reviewed head becomes effective on main only after all adopted work passes qualification and merges.

Twenty-four architecture-test anchors were moved only after exact old/new source equality was established; occurrence fingerprints, scanner behavior, tolerances and waiver rules remain intact. Final hosted source checks must qualify the complete diff.

The initial hosted lint gate identified the cache-helper file length limit and one test closure syntax violation. Extract the exact byte-marker helper into its own source file, preserving its implementation, then regenerate the parser hash; retain the actual preceding QuotaKit cache producer. The test uses the existing named-override closure pattern. No lint limit or test gate is relaxed.

The initial hosted Mac test build identified two fixture API mismatches: the missing browser-detection clock and access to the internal fully injected initializer through a normal Core import. Tests now supply a fixed clock and use a testable Core import, retaining synthetic application/profile callbacks rather than broadening production API visibility or consulting installed browser state. Production targets had no corresponding compile error; final hosted qualification remains required.

Hosted runtime qualification found three fixture adaptations: Auto's no-forecast fallback now expects the most-used 70% lane while explicit lane/average assertions remain exact; the widget detail fixture explicitly enables its seeded Claude/Codex providers; synthetic Claude process captures receive the existing task-local explicit CLI capability. Production enabled-provider and background-access guards remain intact.

The cached-title CPU test reported 58.34 ms against its existing 50 ms budget. Source comparison traces its fixed fixture and complete cache-hit call path: the changed template-image construction and quota ranking are outside the timed loop. No performance threshold or assertion is changed; the final reviewed head must still pass this gate.

The repeated menu deadline is addressed by a source-equivalent partition of its 184 test declarations across three nested suites. Their parent retains recursive serialization and credential-fixture scoping; the harness selects complete nested suite paths with quote-aware slash parsing. All original method signatures, argument annotations and bodies are retained across 15 files. The 120-second deadlines, complete runtime/discovery equality, containment and bounded retry gates remain unchanged. A combined group can still use the existing isolated-selection retry; each smaller leaf has a separate bounded deadline. Apple's [Swift Testing parallelization contract](https://developer.apple.com/documentation/Testing/Parallelization) establishes recursive serialization, and `CodexCredentialFixtures.isRecursive` preserves per-case fixture inheritance. Hosted discovery/filtering must qualify the final source.

Independent review identified the affected-test lane's existing parent-suite request. Parent requests now expand to discovered descendants using complete path components, retaining unknown-name and sibling-prefix rejection. A discovered ancestor with direct tests retains its existing whole-subtree selection and suppresses overlapping child selections, preventing duplicate execution. Mock coverage includes quoted slashes, nested filters, parent expansion, overlap and malformed identifiers.
