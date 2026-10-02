# Upstream integration — 2026-10-02

Pinned upstream range: `2e4633073aa8e2bbb06c5563e02e61e44370c92f..acc22cacf12e99142233af0dd9d300d8f438a619` — 110 DAG commits: 62 non-merges and 48 merges.
QuotaKit base: `f89f0c46b638be0698eac45423a5a273991ae1eb`.
Tracking issue: [#221](https://github.com/ColumbusLabs/QuotaKit/issues/221).

## Design and fork contracts

Adopt the full useful provider and Mac behavior as one QuotaKit-native integration. New Muse (muse.ai) remains distinct from Meta Muse Code. Antigravity scoped credentials, config compare-and-swap, Codex executable discovery, cost-cache persistence, notifications, and CloudSync receive independent adversarial source review. Hosted CI owns lint, builds, Mac/portable tests and iOS verification.

- Preserve QuotaKit/Columbus Labs identity, config and cache paths, bundle IDs, CloudKit containers/zones, App Groups, entitlements, signing, updater/appcast and release ownership.
- Preserve every existing provider identifier and mobile/shared payload contract while adding MuseAI through the repository catalog and mobile adaptation. The full registry grows from 87 to 88 IDs; the quota-notification subset grows from 71 to 72 (216 subscriptions).
- Retain guarded external Codex/Claude auth ownership, QuotaKit process-group cleanup, rolling PTY output, stale-refresh guards, recovery receipts and cache compatibility.
- Preserve `UPSTREAM_VERSION` and all marketing/build values. Only the reviewed cursor/date advance after the complete batch qualifies for merge. No binary distribution or live credentials/CloudKit operations.
- Upstream live proof logs, screenshots and release-only changelog/version/appcast material are evidence or upstream publication assets; they are not imported as QuotaKit product state. Relevant behavior is documented in QuotaKit-native Unreleased notes and provider docs. Generated files use repository-owned generators and the fork's final source inputs.

## Commit accounting

Each row accounts for the exact commit. Adapted chains include their intermediate tests and dependency intent; explicitly superseded intermediates are named. Merge re-resolution inspection found 12 behavior/generated resolutions, 20 changelog-only resolutions and 16 merges without a resolution delta. Product introduced by merge parents is accounted in its corresponding rows, never discarded merely because the merge has no independent delta. No applicable slice is silently hidden behind the cursor.

| Commit | Disposition | Representation or reason |
| --- | --- | --- |
| `6b706a67d024de4d4f30df9d2e4e66c48e014ef5` | Adapted | Selected-account Antigravity print fallback; final verified scoped-session chain. |
| `e0172ea2efe543f5db5600207452593938ab458d` | Superseded | Superseded by 70be213f9: live proof artifacts removed from the product tree. |
| `066d5daf68c9a2fd7409fb492ae5e7384bb39fff` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `35dd747a9e5abab54462a62c93eb253183fc5c38` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `6cfaad64409bd4861cf1e60f7b454ebd4461560c` | Superseded | Superseded by 5becbf61e: unverified quota fallback intentionally removed. |
| `8053da9e37b7f7a743b35d49e7190cbd03b07666` | Adapted | Private credential staging through existing CredentialFileWriter. |
| `70be213f976d7b87ab6b87bcdead772d6cdf31bc` | Adapted | Proof-artifact cleanup retained; no real account evidence imported. |
| `5becbf61e28bca75faa28ca3f824e9fec5ceaecc` | Adapted | Only verified scoped quota can publish. |
| `7c4018f595d5353a6f13d4012e7e55e38ea83c52` | Adapted | Verify selected identity using the effective access token. |
| `3731502b1eb83396739ef2b8101eb1bf5aa0f076` | Adapted | Token-only saved scoped credentials supported. |
| `5e895efd955eb53391fd14967d5325279d5b3949` | Adapted | Verified selected-account token refresh writeback. |
| `c0cd3092a1aec8515cdc91164d0c6928d8154573` | Adapted | MuseAI provider, plugin, settings and catalog adapted through final 46501f4dd. |
| `d4caae94a69d74f75d121be544f8d1d255a1f004` | Adapted | Existing QuotaKit uninstall isolation retained; 6698bf4ab adds registered-app fixtures. |
| `b9f0bfa9dcfb6b062d11e3d867e42d00a8c726dd` | Adapted | Saved-account stale token writeback regression fixtures. |
| `77051eac6f113dd657963f2eeda361599d48fe93` | Adapted | Config advisory lock and credential compare-and-swap prevent mid-run reauthorization overwrite. |
| `f2db790e533c0636737b9e61f8bcacb976738cc2` | Adapted | Measured quota presentation applied through final 6f36e66f0. |
| `758ddc16bb9d8ab06dc9a02e90e85989b3912660` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `057d41a919428f78c3c07351081509ee42542297` | Adapted | Scoped agy descendant cleanup retained with owned process groups. |
| `d9444c907527dfdde08ee2f08d30463cec60f21d` | Adapted | Workspace-trust support reconciled with e9a3f6534/709ff569c/94984614a. |
| `e9a3f6534ad48b5f8c6c528109d24fa7da9536aa` | Adapted | Trust only the dedicated, validated probe directory. |
| `709ff569c21bce69b9bd73f2806067d03cb62c6c` | Adapted | Preserve legacy prompt behavior while handling dedicated workspace prompt. |
| `9cbaedbc5c7ee7bdd6f0833f9e864b5cfbf8d3fe` | Superseded | Superseded by 12d9f8cb4 final inline swap path and help placement. |
| `6c070c72731e1b85495ec75123e6ef80bd9c54c1` | Adapted | Default-off reset notifications completed by account-scoped c3f8b95de. |
| `97391d5cd2d84405ff779db83d1f4765e92cdc34` | Superseded | Superseded by cb7e8a6d3 and 3ce4da881 hardened executable/resource lookup. |
| `cb7e8a6d35ac18eba273dacb15046f81a74b7643` | Adapted | Symlink-aware helper lookup represented by final 3ce4da881. |
| `88a91f3b3cdd2cce2f5aca4372c8952d0a1937c0` | Adapted merge resolution | MuseAI catalog/architecture resolution adapted; QuotaKit site identity retained. |
| `b73d0046f1a9f416aba39cf51dce2c7d17685e3b` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `51150bc5c3f330ce462b2b13c1d8c30dec113c26` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `1d7f20576275174546948785b4e554915bf01ece` | Rejected | Rejected: upstream release-section bookkeeping; QuotaKit Unreleased product wording used. |
| `88dddafe7706ca4501e24d83a39e222532b8f36b` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `73e7378949b1b566b22fc965d1e20252c2b08175` | Adapted | Deleted-binary agent visibility while preserving QuotaKit app-server trust. |
| `ca051cfa55dc921a4490d48522f1cab0add8ee77` | Rejected | Rejected: upstream release-only changelog entry; behavior documented in QuotaKit Unreleased. |
| `89229b37ed7e1ef0064a39ba86d6f42a1e5de9cf` | Adapted | OpenCode Console workspace migration with final shared parser. |
| `781646d41b6597481b2ca71c435e0e11d32dc7db` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `4b3c65917d074ea2dce4ffcea37b635fa2287d03` | Adapted | Console reset timestamps support fractional and ordinary ISO8601. |
| `45557db2931bc57b172da22bfaf0ef461d7dcc70` | Adapted | Correct Antigravity protobuf usage field mapping and synthetic fixtures. |
| `bd0ebc0db32b73f27b4de16e347952b0dc7b45e3` | Adapted | Schema byte allowance per database with final 9401fceaa reconciliation. |
| `7d0de656d41ada94557820fca467966c7448a87e` | Adapted | Initial npm discovery represented by final 3299979c8/d2a6360f3/5ca83845f/9d8d110b5 chain. |
| `796f679a50ae30229ae96c7093c2f08d20b3a637` | Adapted merge resolution | Scoped Antigravity/config-lock dependency resolution adapted. |
| `d9f3aed901b1b9c8efc4075f89a3e5b5ea301e91` | Adapted | Consecutive verified token writes advance the expected saved credential. |
| `c40987f52e4f5c523f252cd140ab220f9e076a99` | Adapted | Reuse parsed Antigravity usage for local pricing. |
| `3299979c830d2d4eb40fb45fd78d39945519ad27` | Adapted | Validate npm payload layouts and preserve healthy discovery fallbacks. |
| `4a350f05fc214a9f00a1241669b9ef28b68f0588` | Adapted | Deleted-executable scanner fixtures adapted to QuotaKit process-identity seams. |
| `6698bf4ab6ec5aa9523cde529bcff40ef70ef01e` | Adapted merge resolution | Registered browser fixture resolution adapted. |
| `9401fceaa5bf7f86a5b2f5abbcb13038036db6f2` | Adapted merge resolution | Antigravity shared per-database schema allowance resolution adapted. |
| `12d9f8cb448a4ad8dd4baab778eae46baa979536` | Adapted merge resolution | Inline swap path and help under enabled toggle adapted. |
| `3ce4da881d58fc457e3a5bb945321a040bcd46ed` | Adapted merge resolution | Absolute executable/bundle discovery resolution adapted, including sanitized Git worktree subprocess environment; fork ownership and paths preserved. |
| `4d1b834ab28736a913a328d6cd51f9765b922f46` | Adapted | Shared Console parsing with compatible OpenCode snapshot APIs. |
| `94984614a6ea0076b0850c6f019020f160d8f01d` | Adapted | Safe PTY trust prompt and measured quota handling with QuotaKit probe ownership. |
| `bceeda738603cc3d75cda5153bbdba3475f83837` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `878de79359985d1504fd4d51c04d4f01dbd1d10a` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `44238e40068ddd8493b8134ddddbeb9165d22ee2` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `725322dfeb762b42d10b50acd351267a15ab9f38` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `63e858b2ab9cac55281ce49f80f7c92873be74a6` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `6464e2aafaf7f91c4f09c58d09eb709fe1babdad` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `d2a6360f3b3c6f564510454df863a48f979fc5ff` | Adapted | Assess payload selected by the launch Node runtime without evaluating launcher code. |
| `274122036e2cc02dbdcf1c1150b95853f29eae91` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `d9a2add9acab6c495b855dfcd758397c7274f681` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `6f36e66f0636c070fed378cc13fdaf3c5524bc89` | Adapted merge resolution | Shared measured quota presentation resolution adapted across menu and CLI. |
| `53a366fbf296f8caffe8de2bdcbd551c3aa85bde` | Adapted | Preserve locator rejection at RPC and PTY launch boundaries. |
| `ff783487655d5f5e17adc4eead702b7d7a7b8461` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `c3f8b95de53a2e8114df88f240310fb58e962950` | Adapted merge resolution | Account-scoped persisted reset receipt resolution adapted to existing Mac/iPhone notification ownership. |
| `8135eb284ab714833ea8554fd066710beb5e0731` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `b2acac575f80bdec2e6844bb2ddb0b2cad96b4c6` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `b5734fac34de2f1144e8d47c9126fef853173b1d` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `75a5cae05effe00771a58960a2cd34077962d2ea` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `949cac4e88b5aa6f12ba52bef9112fab2b3e9901` | Adapted | Deleted CloudKit record recovery and capability-gated registration with QuotaKit fleet identity. |
| `9930e06d4fc4d5ffb1fa4c7238981c64e13d978e` | Adapted | Controlled hooks sleep/process lifetime fixtures; preserve live config-disable behavior. |
| `705a588307b0ee8acedc8733b5200afe653b2391` | Adapted | Claude isolated quota probes, direct fallback and CLI recovery. |
| `c07379c5b139d0ad3534879a750c5984e6919eb1` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `627130e34ed5c9025716cd1e34b466d61b0c1269` | Adapted | Adaptive activity from rollout timestamps within consent/power/budget constraints. |
| `ce2991eb43021197df709fa4dbf0f4710bf569c7` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `d964d4ed444d9e4adf0104fc1187ae3ed68f0854` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `5ca83845f5de9436f11889bd72c644d8fe0f44b3` | Adapted | Absolute Node runtime discovery and NODE_OPTIONS rejection. |
| `ca32251b4192a7701ac0cfabad1dad18b1763a19` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `bfbc6a6de0b8d3c6ea608afc116a349c67f4e69a` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `15c172594e98f7d6bb3c3415b7da99037ec787b7` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `6f7aba6a1cb115a01e8aead79835dec485886741` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `5208d2465f53b08ce31562942d9852a329880206` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `065f4a53bb19e03f97dfec02a1093ed85d372672` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `5334d0cc9ef0e7abcaf48521fc3cd8e60dc4ac17` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `67e836cb4429943f1c18e3348ce9e6d1bfdc6dc3` | Adapted | Scoped-only measured Claude quota before spend fallback. |
| `4367a701cc34f646a155f51bbcc71aa60333d721` | Adapted | Reuse one decoder per Codex cache read pass. |
| `944dbe4eb6673e34fae6a35b4544023d820eca76` | Adapted | Skip Claude pricing for rows outside the padded reporting window. |
| `7dbc1e595abdc44a947bfc80d9391b4d099348d0` | Adapted merge resolution | Parser hash resolution superseded by final QuotaKit regeneration; parent product work retained. |
| `2d099c9d0f7a6e12398e6d1acb62525a5945418c` | Adapted | Generated artifact adapted: regenerate from final QuotaKit producer sources. |
| `0dd8363ad47ee4d35dc5a8b22f5b796e8f64181b` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `961d041c69804146d5ac60e4fa2893dd8b8c2901` | Accounted merge | Parent slices accounted; reject upstream changelog/release reconciliation only. |
| `f46a125af227254ac14de591968bce88d9fcc0f5` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `e069bff233c1e359118524a0fc8a37d730edeacc` | Adapted | Cursor credential/session mapping, stable provider menu order and Pi cache/Bedrock costs. |
| `d066665deb3ddc563e676f0fd796813d9279fd91` | Adapted | Atomic fetched-record/settings/bookkeeping apply with cancellation and generation guards. |
| `a011813409699e5d6713b937fbbc64c8c6e1a6bf` | Adapted | Controlled CLI serve deadline fixture instead of wall-clock speed assertion. |
| `ba5e89eb4ed8e8f40eef8806921bd01032e5b1d9` | Adapted | Controlled provider/cookie/widget/process fixtures; stronger existing Keychain memo tests retained. |
| `2266b60ce2e1fd55659e404d6c9971787f5baaaa` | Adapted | Controlled provider and CLI deadline/response fixtures. |
| `17c454f9f30335fd12d3613f8a4bf949b99158fd` | Adapted merge resolution | Launch environment preservation combined with sanitized PATH. |
| `59152732182b4600bb78221da9b6b437d2154608` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `9d8d110b5dbcd730e647726ff69d573abbce2fc0` | Adapted merge resolution | Caller launch environment propagated through provider locator and PTY; cold GUI capture ordering additionally repaired. |
| `9413e98c16f995d55de49e05f9e03ae6e311b5bc` | Adapted | Dynamic running-code requirement validation with static fallback and retained safe handles. |
| `9a0b958224bb217c46d48dc85c827891d8f127ed` | Adapted | Exact Claude/Vertex encoded fragment reuse preserving fork cache wrapper and recovery. |
| `3239175f6a43aff35a52abc9072f8eca69444a7d` | Adapted | SweetCookieKit 0.5.4 pinned dependency plus applicable importer cache regression. |
| `28611afaa07bdbdec9a8a1f3c5cc514b9cb0dec6` | Accounted merge | Parent slices accounted; no independent resolution delta. |
| `b5435c75a285f5571664f39c741c9c203e745160` | Adapted | Archived orphan forks settle scheduling while retaining unmetered buffered usage and incomplete coverage. |
| `170606517e8457e005d8cac0cb95f7b62bce11c4` | Adapted | Isolated Claude cache test state and producer-compatible fixtures. |
| `6ccd9f2f27011c94e22ed173e98c1b19cf22b1ad` | Adapted | Deterministic SQLite work counters and Antigravity deadline clock fixtures. |
| `3457fb5538689dbe9b6dcdfbfed7c122dd0587ef` | Adapted | Shared RPC sleep injection and controlled PTY/teardown fixtures; different existing Python readiness API retained. |
| `119cc242bf451770da7b288c9732d4e71c9217da` | Adapted | Task-scoped cost-store test hooks and matching tests. |
| `0ac27e8f78801cb893b31e220fce8589241f4c3c` | Adapted | Descriptor-bound Gatekeeper verdict memo only under full host enforcement. |
| `46501f4ddfa5faf43deee30a82d2e405e1b430e8` | Adapted merge resolution | Final MuseAI subscription catalog/plugin/mobile/widget integration adapted. |
| `d44acaa693a985bc4b4aa221c56745081b74e7c4` | Adapted | Opaque synthetic rejected MuseAI session fixtures. |
| `acc22cacf12e99142233af0dd9d300d8f438a619` | Accounted merge | Parent slices accounted; no independent resolution delta. |

## Fork adaptations resolved during review

- Claude restoration now delivers the pending Mac notification when an unverified OAuth owner prevents detector persistence; it preserves the existing single iPhone push. Every menu metric ignores synthetic quota placeholders while retaining measured fallback windows.
- MuseAI uses the complete native cookie-plugin support chain behind its generated registration, rather than a catalog-only addition. Existing `muse` remains a separate provider.
- Codex orphan settlement retains missing-parent dependencies and unmetered buffers. Previous reports cannot certify an overlapping unresolved range; disjoint reports remain usable. Full-ledger publication and compact status reads enforce the same distinction.

## Verification and delivery

Independent source review and final diff checks precede hosted checks on the reviewed PR head. All applicable required hosted checks must pass before merge; no prior-head check is credited for changed source. Local Swift/Xcode build/test, live provider probes, cookie import, Keychain UI, packaging and app relaunch are intentionally omitted.

The source review found and repaired a cold GUI npm-discovery ordering problem: login PATH must be captured before provider preflight, while a rejected locator must still terminate implicit discovery. A synthetic injected capture/locator fixture covers the final behavior. CloudSync source review cleared the atomic apply/recovery adaptation with QuotaKit container/zone and retry safeguards retained. Independent Claude cache review checked exact encoded-byte reuse, artifact-wrapper preservation and reporting-range pricing without unresolved findings. Orphan-fork adaptation explicitly separates settled scheduling from complete accounting: missing-parent evidence and buffered usage survive, overlapping reports remain incomplete, and restored parents reopen dependency checks.

Before workflow-triggering actions, live visibility was public and all relevant runner/matrix labels were standard GitHub-hosted runners. The personal account's live billing UI showed GitHub Free, a $0 Actions budget and Stop usage enabled. Public Actions usage is discounted under [GitHub's billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions). Cache usage was 10,558,981,180 bytes, below the documented 10 GiB default; the paid cache-limit endpoint required a valid payment method, so the configured cap was not directly readable. No budget, payment method, storage limit or workflow gate was changed. The dependency update naturally changes existing cache keys; no extra caches or artifacts are introduced by this integration.

Static verification passed: whitespace diff, generated provider manifests (88 IDs), and regenerated parser hash `fbe994be4ecef112`. The predecessor `91aceec74bae13b6` remains compatible, with migration coverage for retained rows, snapshots, buffers, discovery and cursors. Marketing/build values, entitlements, updater and workflows remain unchanged.

The first hosted run exposed missing shared OpenCode date helpers, the additive MuseAI account-identity case, a Claude locator closure signature, a Pi return statement and formatting differences. These were repaired with parser/identity fixtures and independent source review; final hosted verification remains the merge gate.

Final source/CI and merge evidence is recorded on the PR and in automation memory after delivery.
