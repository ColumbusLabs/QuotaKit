# Review Findings Fix Bundle

Status: `done`
Date: 2026-06-09

## Scope

This bundle closes the validated review findings from the QuotaKit rebrand and iOS sync freshness pass:

- Provider tint parity now treats Mac `ProviderDescriptor` colors as canonical, with a script audit to catch mobile drift.
- Known duplicate or near-duplicate colors were separated before parity was enforced.
- The iOS palette now matches exact normalized provider aliases instead of broad substrings, so short names such as `amp` cannot color unrelated future providers.
- Very dark and very light provider swatches adapt at render time for iOS light/dark readability while raw values remain exact for parity tests.
- Sync freshness chips preserve their visible status text for VoiceOver and use a widening timeline cadence as the displayed age gets older.
- The customer branding audit now scans mobile Swift and `.xcstrings` values, and allowlisting is applied to each forbidden-token occurrence instead of an entire line.

## Decisions

- Keep raw palette values in sync with Mac descriptors and apply iOS appearance adaptation only in `ProviderColorPalette.color(for:)`.
- Keep `ProviderColorPalette.rawColor(for:)` internal so tests and the parity audit can assert exact RGB values without depending on rendered SwiftUI color behavior.
- Allow explicit upstream MIT attribution wording, but keep generic customer-facing `CodexBar` copy blocked.
- Keep internal target/module/storage names allowlisted only in narrow source contexts.

## Verification

- `python3 Scripts/audit_customer_branding.py`
- `python3 Scripts/audit_provider_palette.py`
- `./Scripts/lint.sh audit-customer-branding`
- `./Scripts/lint.sh audit-i18n`
- `./Scripts/lint.sh audit-provider-palette`
- `swift test --filter ProviderRegistryTests`
- `xcodebuild -project CodexBarMobile/CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skip-testing:CodexBarMobileUITests CODE_SIGNING_ALLOWED=NO test`
- `xcodebuild -project CodexBarMobile/CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO build`
