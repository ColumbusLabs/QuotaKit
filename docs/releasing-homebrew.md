---
summary: "Current QuotaKit Homebrew distribution status."
read_when:
  - Considering a QuotaKit Homebrew release
  - Troubleshooting a Homebrew-managed QuotaKit installation
---

# QuotaKit Homebrew Distribution

QuotaKit does not currently publish a Homebrew tap, cask, or formula. Do not use
`steipete/tap/quotakit` for QuotaKit releases or updates; that tap belongs to the
upstream project and has no QuotaKit cask.

Mac releases use the signed GitHub assets and Sparkle appcast described in
[RELEASING.md](RELEASING.md). The standalone CLI is available in the Mac app
bundle; no standalone public CLI release artifact is currently published. See
[cli.md](cli.md).

The app still recognizes a bundle linked from a Homebrew Caskroom and disables
Sparkle for that installation, leaving installation ownership with Homebrew.
Its About pane reports that updates are managed by Homebrew, without offering an
update command. If Columbus Labs establishes a supported tap in the future,
update the release workflow and this document against the actual tap before
adding an in-app update path.

The upstream manual command card, copy-confirmation control and one-click updater
all target `steipete/tap/codexbar`. These changes are intentionally excluded from
QuotaKit while there is no supported QuotaKit cask. The managed-install notice
remains available; no guessed cask command or upstream upgrade is offered.
