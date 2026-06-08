---
summary: "Homebrew Cask release steps for QuotaKit (Sparkle-disabled builds)."
read_when:
  - Publishing a QuotaKit release via Homebrew
  - Updating the Homebrew tap cask definition
---

# QuotaKit Homebrew Release Playbook

Homebrew is for the UI app via Cask. When installed via Homebrew, QuotaKit disables Sparkle and shows an "update via brew" hint in About.

## Prereqs
- Homebrew installed.
- Access to the tap repo: `../homebrew-tap`.

## 1) Release QuotaKit normally
Follow `docs/RELEASING.md` to publish `QuotaKit-macos-universal-<version>.zip` to GitHub Releases.

## 2) Let the Release CLI workflow update the tap
After the GitHub release is published, `.github/workflows/release-cli.yml` builds the standalone CLI assets and dispatches the configured Homebrew tap's `update-formula.yml`. That tap workflow updates both:
- `Casks/quotakit.rb` for the app zip.
- `Formula/quotakit.rb` for the standalone CLI tarballs.

If dispatch fails or is rate-limited, update the files manually.

## 2a) Manual cask update
In `../homebrew-tap`, update the cask at `Casks/quotakit.rb`:
- `url` points at the GitHub release asset: `.../releases/download/v<version>/QuotaKit-macos-universal-<version>.zip`
- Update `sha256` to match that zip.
- Keep `depends_on arch: :arm64` and `depends_on macos: ">= :sonoma"` (QuotaKit is macOS 14+).

## 2b) Manual formula update
In `../homebrew-tap`, update the formula at `Formula/quotakit.rb`:
- `url` points at the GitHub release assets:
  - macOS: `.../releases/download/v<version>/QuotaKitCLI-v<version>-macos-arm64.tar.gz`
  - macOS: `.../releases/download/v<version>/QuotaKitCLI-v<version>-macos-x86_64.tar.gz`
  - Linux: `.../releases/download/v<version>/QuotaKitCLI-v<version>-linux-aarch64.tar.gz`
  - Linux: `.../releases/download/v<version>/QuotaKitCLI-v<version>-linux-x86_64.tar.gz`
- Update all `sha256` values to match those tarballs.

## 3) Verify install
```sh
brew uninstall --cask quotakit || true
brew tap <owner>/<tap>
brew install --cask <owner>/<tap>/quotakit
open -a QuotaKit
```

## 4) Push tap changes
Commit + push in the tap repo.
