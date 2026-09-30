# Upstream numeric and Mac presentation boundaries

Status: done — implemented and locally verified; hosted CI and merge pending

## Scope and design

Continue from tested cost/provider source `997988ae699569a923a6dd473d9bca227935394d`
against final reviewed upstream `25bba9b7fd9ce83c33053958f7366e23b2dc8a82`.
This bounded follow-on covers Mac/Core numeric row 466, structured balance rows
789/801, recorder localization row 334 and cookie-picker localization row 315.
No release is prepared.

- Preserve ordinary numeric rounding and formatting. Omit only invalid projections
  when non-finite values, integer conversion or derived arithmetic exceed their
  supported range. Keep Amp's QuotaKit sync payload, independent credits and valid
  explicit subscription periods. LongCat and reset countdown bounds already exist.
- Select structured balance amounts through provider metadata so TypeSafe and
  OpenRouter use the appropriate shared resolver without adding a provider-name
  switch. Preserve other metrics and prefix formatting.
- Observe KeyboardShortcuts recorder placeholder changes and restore localized
  copy when needed. Remove delayed timing repair and detach observers cleanly when
  the representable is dismantled or reattached.
- Cookie-picker providers supply explicit localized Auto/Manual/Off values. Shared
  UI selects those values without parsing English phrases; preserve dynamic copy,
  Keychain-disabled behavior and all 23 Mac locales.

## Source applicability decisions

- Homebrew rows 386/459/687 target upstream's `steipete/tap/codexbar` cask.
  QuotaKit's documented release lane publishes no tap/cask/formula, so these
  command/copy/updater affordances are excluded while the managed-install notice
  is retained. Existing merge row704 remains excluded.
- Plugin tabs (242) are implemented, including scoped refresh and placement.
  Retain the documented omitted-field `topLevel: false` default; upstream row838's
  default-on change would move existing enabled plugin cards. This is an explicit
  placement policy, not a security or permission boundary.

## Verification and closeout

Use synthetic Mac and portable numeric boundary fixtures, existing menu-layout
model tests and focused recorder lifecycle checks. Avoid status-bar construction,
live providers, browser import and Keychain access. Run only affected tests and
format/lint checks; share the required hosted CI cycle with the preceding tested
source where practical.

Credit rows only after tested source is committed. Preserve all historical ledger
columns, product/build versions and the monitor cursor. Mark done after implemented
behavior is verified, then merge and remove covered refs after exact-head proof.

## Local verification results

- Combined focused check: 199 Mac tests in 10 suites plus 8 portable numeric
  tests. Compile repairs migrated existing popup tests to the typed subtitle API
  and used an ordinary if/else for checked pass arithmetic.
- After correcting the fractional credit fixture to preserve `2.50/10 credits`
  and retaining the existing OpenRouter architecture justification, all 47
  affected Mac numeric/architecture tests and 8 portable numeric tests passed.
  The other eight Mac suites passed in the combined run and were not rerun.
- Independent numeric/balance/recorder and cookie-localization reviews found no
  remaining actionable issue. Signed-zero formatting preserves `0/0 credits`.
- Scoped SwiftFormat/strict SwiftLint, all 23 locale catalogs, diff checks and
  generated parser-hash check passed. Hash remains `7607317f30850961`.
- No full local suite, live provider/browser/Keychain probe, product release or
  version/build/cursor advance ran. Required combined hosted CI is next.

## Final card-context reconciliation

The residual row315 audit confirmed live/settings contexts are represented without
requiring a construction refactor. The shared account-capable input now forwards
the selected snapshot's confidence and explicit account history/reset observations
(the latter completes an omitted helper route from row451). Claude itself permits
estimated pace, so confidence isolation is exercised using OpenCode Go's differing
estimated/exact eligibility rather than claiming a Claude-specific effect.

Six focused card-context/quota-window tests passed. They verify account confidence
is independent of live confidence, nil/identityless cards do not borrow reset
history, explicit history selections work, and rendering does not mutate history.
Scoped SwiftFormat and strict SwiftLint passed for both affected files.

The ClaudeSwap route was separately checked against upstream row451. The adapter
stores its latest external slot measurements, without collecting plan-history
samples or proving a slot-to-OAuth history owner. A matching email or active slot
therefore cannot authorize reading OAuth history. Synthetic real-projection card
fixtures for both active and inactive slots preserve their own reset and return
no unrelated history, without changing buckets or their revision. The focused
UsageStoreMenuCardModelTests run passed (three tests, two parameterized). Adding
external slot history collection would be a separate feature; the upstream
account-owned reset resolver is represented without inventing an owner mapping.
