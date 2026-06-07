---
summary: "QuotaKit quick start: Columbus Labs product boundary, inherited internals, and common commands."
read_when:
  - Onboarding to QuotaKit development
  - Checking which public repo identity should be used
---

# QuotaKit Quick Start

QuotaKit is the Columbus Labs product in this repository. The repository preserves upstream CodexBar history and still has inherited internal target names, but public product copy, releases, support links, and setup flows should use QuotaKit / Columbus Labs.

## Product Boundary

- Product: QuotaKit
- Company: Columbus Labs
- Repository: `https://github.com/ColumbusLabs/QuotaKit`
- Setup page: `https://columbus-labs.com/quotakit/mac`
- Mac bundle ID: `com.columbuslabs.quotakit.mac`
- iOS bundle ID: `com.columbuslabs.quotakit.ios`
- CloudKit container: `iCloud.com.columbuslabs.quotakit`

## Key Areas

| Path | Purpose |
|------|---------|
| `AGENTS.md` | Current development workflow |
| `CodexBarMobile/` | iOS app and XcodeGen project |
| `Shared/` | Shared sync layer |
| `Sources/` | Mac app and provider internals |
| `.mac-release.env` | QuotaKit Mac release defaults |
| `version.env` | Current Mac/mobile/upstream version alignment |

## Common Commands

```bash
./Scripts/lint.sh lint

cd CodexBarMobile
xcodegen generate
xcodebuild -project CodexBarMobile.xcodeproj \
  -scheme CodexBarMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

Use `jj` for commits:

```bash
jj status
jj describe -m "message"
jj bookmark set main -r @
jj git push --bookmark main
```

## Upstream History

Upstream references are valid in credits, inherited implementation notes, and sync planning. They should not be used for QuotaKit install, support, release, appcast, or public product links.
