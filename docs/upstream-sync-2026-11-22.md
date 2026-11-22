# QuotaKit upstream integration — 2026-11-22

Reviewed `c94b855f308370c503c9f4caad9f1ca4e2151444..a26ca57b518667a659d69524c473af2735069612`
against QuotaKit base `f43ccc22dca530175c4a53ab45612dc5ea89b3f5`.
The range contains five linear commits.

| Upstream commit | Classification | Evidence |
| --- | --- | --- |
| `e9a5b27997bfe48087679f48c8fb0273ceafeab0` | Adapted | Record settled unavailable analytics in the existing scoped Mac spend publication. Preserve QuotaKit's separate confirmed-empty path, dashboard fingerprints, and Codex ledger retention. Cover failed, missing, forced and changed-scope refreshes with in-memory fixtures. |
| `5dd48cab770a326691b25a124d37ffee12c5f7ac` | Rejected | Edits the upstream 0.85.0 release changelog and its upstream-only CPU measurement. QuotaKit records the adopted behavior in its own changelog. |
| `dc0b43db54ba002c3d6e07c96cd13a83d0635915` | Rejected | Publishes the upstream 0.85.0 Sparkle feed. QuotaKit maintains its own feed. |
| `850a3e231e9a80ce2f299eeaf260f09d04b5a5c0` | Rejected | Fixes a large GitHub Contents API request in an upstream-only Python publisher. QuotaKit generates its appcast locally and publishes it through Git in `Scripts/release.sh`. |
| `a26ca57b518667a659d69524c473af2735069612` | Rejected | Opens upstream 0.85.1 development and changes upstream version and build numbers. |

A balance-only result replaces stale spend with a scoped, unavailable publication.
Repeated results leave the recovery revision unchanged. A later spend snapshot advances the
revision again. The provider catalog, credential selection, mobile wire format, and release
settings retain their existing contracts.
