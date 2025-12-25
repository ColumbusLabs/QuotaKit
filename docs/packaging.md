---
summary: "Packaging, signing, and bundled CLI notes."
read_when:
  - Packaging/signing builds
  - Updating bundle layout or CLI bundling
---

# Packaging & signing

## Scripts
- `Scripts/package_app.sh`: builds arm64, writes `CodexBar.app`, seeds Sparkle keys/feed.
- `Scripts/sign-and-notarize.sh`: signs, notarizes, staples, zips.
- `Scripts/make_appcast.sh`: generates Sparkle appcast and embeds HTML release notes.
- `Scripts/changelog-to-html.sh`: converts the per-version changelog section to HTML for Sparkle.

## Bundle contents
- `CodexBarWidget.appex` bundled with app-group entitlements.
- `CodexBarCLI` copied to `CodexBar.app/Contents/Helpers/` for symlinking.

## Releases
- Full checklist in `docs/RELEASING.md`.

See also: `docs/sparkle.md`.
