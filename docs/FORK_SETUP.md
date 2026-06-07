---
summary: "QuotaKit repository ownership, remotes, and upstream sync policy."
read_when:
  - Setting up remotes
  - Syncing inherited upstream changes
  - Checking product ownership boundaries
---

# Repository Setup

QuotaKit is maintained by Columbus Labs in `ColumbusLabs/QuotaKit`.

The repository preserves upstream history, but current releases, setup links,
bundle identifiers, iCloud containers, support links, and public copy are owned by
Columbus Labs.

## Remotes

Expected local remotes:

```bash
git remote -v
```

- `origin`: `https://github.com/ColumbusLabs/QuotaKit.git`
- `upstream`: `https://github.com/steipete/CodexBar.git` when upstream sync work is needed

Do not push QuotaKit product changes to `upstream`.

## Upstream Sync Policy

Sync upstream changes selectively. Prioritize:

- Provider bug fixes
- Parser improvements
- Performance improvements
- Security and packaging fixes
- New provider support that fits QuotaKit's privacy and sync model

Review carefully before accepting:

- Release automation changes
- Bundle identifier changes
- Appcast or Sparkle changes
- iCloud or CloudKit changes
- Broad refactors touching provider auth, keychain, browser-cookie import, or sync

## Public Product Boundary

Use QuotaKit / Columbus Labs for:

- README and docs
- GitHub metadata
- Release notes and appcast entries
- Setup, support, and download links
- User-facing app copy

Use upstream names only for:

- Provenance and credit
- Internal target names that still exist in the codebase
- Upstream sync planning and review notes
