---
summary: "QuotaKit upstream sync strategy for inherited CodexBar history."
read_when:
  - Planning upstream sync work
  - Reviewing inherited changes
  - Preparing upstream contributions
---

# Upstream Strategy

QuotaKit is a Columbus Labs product fork that preserves upstream history from
`steipete/CodexBar`.

The goal is to keep useful upstream provider, parser, performance, and security
work flowing into QuotaKit while protecting the Columbus Labs product boundary.

## Remotes

- `origin`: `https://github.com/ColumbusLabs/QuotaKit.git`
- `upstream`: `https://github.com/steipete/CodexBar.git`

Use `origin` for QuotaKit work. Use `upstream` only for review, sync, or
contribution work.

## What To Sync

Prefer syncing:

- Provider bug fixes
- Parser improvements
- Security fixes
- Performance improvements
- Packaging and notarization hardening
- New providers that match QuotaKit's privacy and sync model

Review carefully before syncing:

- Release automation
- Appcast or Sparkle behavior
- Bundle identifiers and entitlements
- CloudKit schema or container changes
- Keychain, browser-cookie, or OAuth changes
- Broad UI or architecture refactors

## What Stays QuotaKit-Owned

- Public branding and product copy
- GitHub Releases and appcast entries
- Bundle identifiers
- CloudKit containers
- StoreKit products
- iPhone setup and handoff flows
- Columbus Labs support links

## Workflow

```bash
git fetch upstream
git log --oneline main..upstream/main --no-merges
git diff --stat main..upstream/main
```

Review candidate commits individually. Prefer small cherry-picks or carefully
scoped merges over broad unreviewed syncs.

After any sync, run the normal QuotaKit checks:

```bash
./Scripts/lint.sh lint
swift build
```

For iOS-affecting syncs, also run the iOS simulator build from `AGENTS.md`.

## Contribution Policy

Contribute changes upstream when they are general, product-neutral, and useful to
the original project. Keep QuotaKit-specific product, release, and sync decisions
in this repository.
