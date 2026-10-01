# Upstream integration — 2026-10-01

Reviewed range: `5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f..2ef5bb6305dda4570d8d080f348cf76a45a392bd`.
QuotaKit base: `5aa81f8d958d97d7f780c1408aa6b7f3ea779eba`.

The range has seven commits, including five merges. The monitor reports only the two non-merge contributor commits, so it understates the integration history.

| Commit | Disposition | Evidence and resulting behavior |
| --- | --- | --- |
| `503e980f7f895e24e26a4de1a717fd40683201bc` | Adapted through `740d49ff` | README community KDE link, explicitly attributed to upstream CodexBar's CLI; no claim of QuotaKit compatibility or installer ownership. |
| `1d854173aef832299925c759f256c1d5e8eb32f8` | Superseded by `5cb303014` | Initial Gemini-specific hook replaced by the shared fallback; its contributor parser regressions are retained in the final tests. |
| `5cb303014a2902c5814607dd8db2d18eda845d58` | Adapted | Resolution merge replaces the hook with shared automatic/average and requested-lane fallback. Production change and both test files match upstream intent; QuotaKit resolver's existing fork behavior stays intact. Gemini docs imported unchanged. Upstream release-number bookkeeping omitted; QuotaKit Unreleased note records the behavior. |
| `740d49ff0d8b18eb0b6fcb49127aaf025e8345bd` | Adapted | Contributor merge retains the link; its upstream release-number changelog note is omitted. |
| `b97544275275351998f02fef4dc2b091b50affdb` | Accounted by adapted `5cb303014` | Merge of the final shared fallback tree; no additional product change relative to that parent. |
| `03d8e367f353d231eb1b571e6c4b16efeb9d69f8` | Accounted by both adapted slices | Synchronization merge brings the already-accounted fallback onto the documentation branch, with no distinct unported behavior. |
| `2ef5bb6305dda4570d8d080f348cf76a45a392bd` | Accounted by adapted `740d49ff` | Final documentation merge; no additional behavior beyond the community link and excluded upstream release bookkeeping. |

No eligible slice is deferred. All code and test intent in the final range is represented. No generated files change.

## Fork contracts

Tertiary quota is selected only after the existing preferred primary/secondary lanes. Two-window averages, exhausted-first selection, provider resolvers and explicit lane orders retain precedence. Spend and combined metrics do not acquire invented quota lanes. Gemini Flash Lite-only API and parser fixtures cover remaining and exhausted quota.

Provider catalog, identifiers, manifests, persistence, mobile/shared wire models, CloudKit, notifications, entitlements, packaging, updater and release ownership remain unchanged. Public wording remains QuotaKit / Columbus Labs; the community project's CodexBar name is explicit provenance. Build/version values and shipped `UPSTREAM_VERSION` remain unchanged. The monitor cursor and review date move only with this integration's merge.

## Verification and delivery gates

- Local source review and `git diff --check`; independent adversarial source review found no actionable defects.
- Hosted CI owns lint, Mac Swift tests, Xcode compatibility build and portable Linux checks on the exact PR head. Repository gates require the full Mac shards for these paths. iOS path gate has no changed shared/mobile contract to validate and skips the simulator job.
- No local Swift/Xcode build or test, app launch, real credentials, Keychain UI, browser-cookie import, live CloudKit write or binary distribution.
- Before workflow-triggering actions: live repository is public; every CI matrix runner is a standard GitHub-hosted runner (`macos-26`, `macos-15`, `ubuntu-24.04`, `ubuntu-24.04-arm`), with no reusable workflow or larger runner. GitHub's current billing rules make their public-repository execution free.
- Live account billing UI confirms GitHub Free and an Actions product budget of $0 with Stop usage enabled. Existing cache usage is 10,558,981,180 bytes, below the included 10 GiB; dependency/cache keys are unchanged. This change triggers no artifact upload because the iOS job is skipped. No paid settings or limits are changed.
