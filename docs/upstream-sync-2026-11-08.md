# Upstream integration, November 8, 2026

The reviewed steipete/CodexBar range is `5e5275b4f7f30a736f8c58d5374a3fff693962de..7447bc77c2497323d9c41e40164ce705533493c8`. It contains ten linear commits. QuotaKit started from `3b8cc8dfafc3bde6568e20a89348a2b18fa70d1a`. [Issue #275](https://github.com/ColumbusLabs/QuotaKit/issues/275) records verification and closeout.

| Upstream commit | Disposition | QuotaKit result |
| --- | --- | --- |
| `9a91cb3f8` | Superseded by `c727c08a2` | The upstream owner withdrew the cross-machine Claude and Pi/OMP CLI collector and its shared transport changes. |
| `1e5150ba0` | Adapted | Share identical Claude quota event storage in memory across reporting windows while preserving each report's cache validation. |
| `0dc741ac0` | Adapted | Use controlled deadlines for plugin transport fixtures while preserving production deadlines and cancellation behavior. |
| `d9ccde113` | Rejected | Upstream 0.84.1 release bookkeeping. Relevant product changes have their own dispositions. |
| `28c23d9af` | Adapted | Reuse existing Spend Dashboard provider marks in QuotaKit share cards and check all six light-card identity slots. |
| `e66b0d698` | Rejected | Upstream release changelog entry for the share-card fix. |
| `c727c08a2` | Accounted with `9a91cb3f8` | Preserve the existing QuotaKit Codex SSH subtotal path and parser fingerprint. The upstream revert removes the entire feature introduced in this range. |
| `39091637d` | Adapted | Report invalid explicit CLI provider selections while retaining QuotaKit's supported selection forms and config defaults. |
| `879c51141` | Adapted | Surface provider-owned ElevenLabs setup guidance through the existing CLI metadata and localization pipeline. |
| `7447bc77c` | Rejected | Upstream release changelog credit edits. Source provenance remains in this ledger. |

QuotaKit’s scanner audit requires a new Claude artifact generation for the change to report publication. Claude rebuilds its v23 cache from transcripts and preserves existing artifacts and memos on disk. The report wire format and Vertex AI generation stay the same.

The integration keeps QuotaKit's 113-provider catalog and existing Mac and iPhone contracts. The cursor tracks the reviewed range. Shipped upstream provenance remains v0.69.0.

Hosted CI uses checksum-verified downloads through the GitHub Releases API when preparing the existing lint, XcodeGen, and Sparkle pins. The same release URLs remain available as fallbacks. Sparkle prefetch uses the runner’s local SwiftPM cache, and the regular build still verifies the pinned dependency.
