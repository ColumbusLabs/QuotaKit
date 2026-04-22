# iOS 1.3.0 · T5 · Codex 多账号卡片 UI 精修 — 调研

**Status:** ready
**Date:** 2026-04-21
**Branch:** refactor-1.3.0
**Scope:** `ProviderUsageView` subtitle + `ProviderListView` ForEach identity; no Mac changes in Branch A; optional Mac follow-up in Branch B.

## Summary

Build 23's `CloudSyncReader.mergeSnapshots` already keys providers by `providerID|accountEmail`, so two Codex accounts on the same Mac-pair produce two `ProviderUsageSnapshot` entries. The UI is unprepared in **two** ways: (1) `ProviderListView` still uses `ForEach(... id: \.providerID)` which collides on duplicate IDs, and (2) `ProviderUsageView`'s header already shows email + plan but has no multi-card disambiguation intent. Workspace name is *not* on the sync contract — Mac's `ProviderIdentitySnapshot` carries only `accountEmail` + `loginMethod` (plan string). For T5 we ship **Branch A (iOS-only)**: fix the ForEach identity bug, add an index/ordinal fallback when `accountEmail == nil`, and leave Branch B (adding `workspaceName` to the shared model + Mac push) as an opt-in follow-up gated on a Mac 0.20.3 release window.

## Current state

### iOS merge logic

`CodexBarMobile/CodexBarMobile/iCloud/CloudSyncReader.swift:127-148` — `mergeSnapshots`:

```swift
let key = "\(provider.providerID)|\(provider.accountEmail ?? "")"
providersByKey[key, default: []].append(provider)
```

- Groups per-device `ProviderUsageSnapshot` entries by `providerID + accountEmail`.
- Same key → merge (take latest for identity/status/rate, sum cost for `localCostProviders = ["claude", "codex", "vertexai"]`, dedup utilization by hour).
- Different key → preserved as separate `ProviderUsageSnapshot` in the merged output, even though both have `providerID == "codex"`.
- Empty string is used as the nil-email fallback key. Different-email-vs-nil cards stay separate; two nil-email cards with different `providerID` stay separate; but **two nil-email cards with the same `providerID` collapse** onto each other via `"codex|"`. That is a real merge collision and the tests (`CloudKitMergeTests.swift:143-153`) only assert the nil-vs-email case, not nil-vs-nil.

### iOS card rendering

`CodexBarMobile/CodexBarMobile/Views/ProviderUsageView.swift:64-105` — `providerHeader`:

- Line 67-70: big provider name (e.g., "Codex") — identical for every Codex card.
- Line 80-89: `accountEmail` row with person icon (already exists; respects `hidePersonalInfo` redactor).
- Line 91-98: `loginMethod` as a capsule chip (e.g., "Pro", "Business") — this is the OpenAI plan string, **not** a workspace.
- Line 101-103: relative `lastUpdated` timestamp.

In single-card scenarios the email already appears, so "clean single-card UI = subtitle suppressed" per the T5 brief is actually slightly aspirational: email is already rendered for any non-nil email. The T5 goal translates to: **make sure each duplicate-ID card carries *something* unique when stacked, even when email is nil**.

`CodexBarMobile/CodexBarMobile/ContentView.swift:174` — list site:

```swift
ForEach(self.snapshot.providers, id: \.providerID) { provider in
    NavigationLink { ProviderDetailView(provider: provider) } label: {
        ProviderUsageView(provider: provider)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("provider-card-\(provider.providerID)")
}
```

Bug: `ForEach` identity is `providerID`. When two Codex snapshots are handed in, SwiftUI treats them as the same identity and collapses them to one view instance. `accessibilityIdentifier` on line 181 also collides (two elements with `"provider-card-codex"`). This is the **actual** reason T5's visible rendering today shows only one card even though `mergeSnapshots` emits two — the ForEach dedups them in view-land after the model already split them.

### Shared identity contract

`CodexBarMobile/Shared/Models/UsageSnapshot.swift:157-226` — `ProviderUsageSnapshot`:

Relevant identity fields on the wire:
- `providerID: String` (line 158)
- `providerName: String` (line 159)
- `accountEmail: String?` (line 164)
- `loginMethod: String?` (line 165)
- No `workspaceName`, no `workspaceLabel`, no `accountDisplayName`, no `organization`. `accountOrganization` exists in Mac's `ProviderIdentitySnapshot` (`Sources/CodexBarCore/UsageFetcher.swift:25`) but is **not** mapped into `ProviderUsageSnapshot` by `SyncCoordinator` (see below), so it does not leave Mac.

Decode path at line 218-219 is `decodeIfPresent` — adding a new optional string field is wire-backward-compat.

### Upstream Mac identity model

Codex account data on Mac lives in several layers; only a tiny fraction makes it onto the sync wire:

| Layer | File:line | Carries workspace? |
|---|---|---|
| `ManagedCodexAccount` (persisted account store) | `Sources/CodexBarCore/CodexManagedAccounts.swift:3-34` | ✅ `workspaceLabel: String?`, `workspaceAccountID: String?` |
| `ObservedSystemCodexAccount` (live CLI probe) | `Sources/CodexBarCore/Providers/Codex/CodexSystemAccountObserver.swift:3-25` | ✅ `workspaceLabel: String?` |
| `CodexVisibleAccount` (UI ribbon in menu bar) | `Sources/CodexBar/CodexAccountReconciliation.swift:4-63` | ✅ `workspaceLabel` + `displayName = "\(email) — \(workspaceLabel)"` |
| `CodexIdentity` (routing key) | `Sources/CodexBarCore/Providers/Codex/CodexIdentity.swift:3-9` | ❌ only `providerAccount(id)` / `emailOnly(normalizedEmail)` / `unresolved` |
| `CodexReconciledState` (post-reconcile snapshot) | `Sources/CodexBarCore/Providers/Codex/CodexReconciledState.swift:3-19` | ❌ fields `session/weekly/identity/updatedAt` only |
| `CodexConsumerProjection` (menu-bar presentation) | `Sources/CodexBar/Providers/Codex/CodexConsumerProjection.swift:89-156` | ❌ no workspace accessor |
| `ProviderIdentitySnapshot` (on `UsageSnapshot.identity`) | `Sources/CodexBarCore/UsageFetcher.swift:22-48` | ❌ `providerID / accountEmail / accountOrganization / loginMethod` — **no workspace**, and `accountOrganization` is currently always nil for Codex per `CodexReconciledState.oauthIdentity` (line 72-81 of CodexReconciledState.swift) |

Upshot: workspace label is a **first-class concept inside the Mac app**, but the reconciled `UsageSnapshot` flowing from `UsageStore` → `SyncCoordinator` has already stripped it down to email + plan.

### What actually leaves Mac via SyncCoordinator

`Sources/CodexBar/Sync/SyncCoordinator.swift:148-162`:

```swift
let providerSnapshot = ProviderUsageSnapshot(
    providerID: provider.rawValue,
    providerName: meta?.displayName ?? provider.rawValue.capitalized,
    primary: primaryWindow,
    secondary: secondaryWindow,
    accountEmail: snapshot?.identity?.accountEmail,
    loginMethod: snapshot?.identity?.loginMethod,
    ...
)
```

Only `accountEmail` and `loginMethod` (plan string) go on the wire. And because `UsageStore.snapshots` is keyed by `UsageProvider` (singleton per provider, not per-account), **a single Mac only ever pushes the *active* Codex account at a time** — multi-card on iOS today arises from either (a) Mac-A and Mac-B having different active Codex accounts, or (b) a single Mac switching active account and leaving the prior account's per-device row on CloudKit (stored by key `{deviceID}|{providerID}|{accountEmail}` per `Storage/SwiftDataSchema.swift:58`). Scenario (b) is the steady-state path that makes the T5 brief's "2+ Codex cards on one Mac's payload" feasible.

This also means **Branch B would not just need a workspace field — it would need Mac's `SyncCoordinator` to iterate managed accounts and push one `ProviderUsageSnapshot` per account per cycle**. That is a meaningful Mac-side refactor well beyond "add a string field". For this reason T5 ships Branch A now.

## Design

### Subtitle selection rule

```
// View-layer, per card, given the merged snapshot's provider list:
let sameIDCards = mergedProviders.filter { $0.providerID == card.providerID }
let index = sameIDCards.firstIndex { $0 === card /* value-type eq */ }

if sameIDCards.count < 2:
    // Single card for this providerID — keep the clean header the UI already has.
    subtitle = nil

else:
    // Disambiguate.
    subtitle = card.accountEmail
            ?? card.loginMethod            // Pro / Business can distinguish in some setups
            ?? workspaceNameIfAvailable    // Branch B only
            ?? "\(providerName) \(index + 1)"  // generic "Codex 2", localized
```

Keep the existing header layout. Subtitle slot reuses the accountEmail row when present, or replaces it when nil-email forces a fallback. Important: `loginMethod` alone is *not* guaranteed disambiguating (two Pro accounts share a loginMethod), so we only promote it when email is nil AND no other source is available, and even then we still append the ordinal to keep uniqueness.

### Changes needed

#### Branch A — iOS-only (ship now, Mac unchanged)

1. **`CodexBarMobile/CodexBarMobile/ContentView.swift:174`** — fix ForEach identity:
   ```swift
   ForEach(self.snapshot.providers, id: \.cardIdentityKey) { provider in
       ...
       .accessibilityIdentifier("provider-card-\(provider.cardIdentityKey)")
   }
   ```
   Add a computed helper on `ProviderUsageSnapshot` (extension in iOS target, not Shared):
   ```swift
   var cardIdentityKey: String {
       "\(providerID)|\(accountEmail ?? "")"
   }
   ```
   Matches `mergeSnapshots`'s bucket key so ForEach identity aligns with the merger. Two nil-email providers with the same ID still collide here — that's fine because `mergeSnapshots` already merges them into one entry (see merge-collision note above; we treat nil-email as "the one unattributed account" intentionally).

2. **`CodexBarMobile/CodexBarMobile/Views/ProviderUsageView.swift`** — add ordinal context. Signature grows one optional parameter:
   ```swift
   struct ProviderUsageView: View {
       let provider: ProviderUsageSnapshot
       /// 1-based position among cards sharing the same providerID. nil when this
       /// is the only card for that providerID (clean single-card UI).
       let duplicateOrdinal: Int?
       ...
   }
   ```
   Call site computes from the siblings list (Step 1 already has them):
   ```swift
   let codexCount = snapshot.providers.count { $0.providerID == provider.providerID }
   let ordinal = codexCount > 1
       ? snapshot.providers.filter { $0.providerID == provider.providerID }
             .firstIndex(where: { $0.cardIdentityKey == provider.cardIdentityKey }).map { $0 + 1 }
       : nil
   ProviderUsageView(provider: provider, duplicateOrdinal: ordinal)
   ```

3. **Subtitle renderer inside `providerHeader`** — replace the current email/plan HStack (lines 80-99) with a small helper that selects per the rule:
   ```swift
   @ViewBuilder
   private var accountSubtitle: some View {
       HStack(spacing: 8) {
           if let line = self.subtitleLine() {
               HStack(spacing: 4) {
                   Image(systemName: "person.circle.fill").font(.caption)
                   Text(line).font(.subheadline)
               }
               .foregroundStyle(.secondary)
           }
           if let plan = self.provider.loginMethod {
               // Plan chip stays, independent of email/workspace disambiguation.
               Text(MobilePersonalInfoRedactor.redactEmails(in: plan, isEnabled: self.hidePersonalInfo) ?? plan)
                   .font(.caption).fontWeight(.medium)
                   .padding(.horizontal, 8).padding(.vertical, 3)
                   .background(.quaternary, in: Capsule())
           }
       }
   }

   private func subtitleLine() -> String? {
       if let email = self.provider.accountEmail, !email.isEmpty {
           return MobilePersonalInfoRedactor.redactEmail(email, isEnabled: self.hidePersonalInfo)
       }
       // email is nil. Only show ordinal fallback when we're one of multiple cards
       // with the same providerID — otherwise leave it blank (unattributed but singular).
       if let ordinal = self.duplicateOrdinal {
           return "\(self.provider.providerName) \(ordinal)"  // "Codex 2"
       }
       return nil
   }
   ```

4. **Localization** — add `"Codex %lld"`-style string key (or reuse `"\(providerName) \(index)"`) across 4 languages (`Localizable.xcstrings`). Since `providerName` is already human-readable upstream ("Codex" / "Claude") and is device-authored, we just need the ordinal concatenation to be localized (RTL languages, digit rendering). Simplest is a format key `"account-ordinal"` = `"%@ %lld"`.

5. **No change to `CloudSyncReader.mergeSnapshots`.** Its key semantics are already correct for Branch A. The comment at line 125 (`→ keep both (different accounts)`) accurately describes current behavior.

6. **No change to `Shared/Models/UsageSnapshot.swift`, no change to `SyncCoordinator.swift`.**

#### Branch B — add real workspace attribution (defer, pair with Mac 0.20.3)

Only pursue when we're willing to ship a coordinated Mac release. Changes:

1. **`CodexBarMobile/Shared/Models/UsageSnapshot.swift`** — add `public let workspaceName: String?` to `ProviderUsageSnapshot`, wire through designated initializer + `CodingKeys` + `decodeIfPresent` (same pattern as `accountEmail` at line 218). Default to nil for backward compat: old iOS builds decoding a new payload with `workspaceName` via `decodeIfPresent` → nil, fine; old Mac pushing payload without `workspaceName` → iOS decode → nil, fine.

2. **`Sources/CodexBar/Sync/SyncCoordinator.swift`** — two sub-options:

   - **B1 (minimal):** extend the current single-snapshot-per-provider push to read `store.settings.codexAccountReconciliationSnapshot.activeStoredAccount?.workspaceLabel` when the Codex `activeSource` is `.managedAccount`, pass it as `workspaceName` on the `ProviderUsageSnapshot`. Multi-account cards still only arise from Mac-A-vs-Mac-B, not from a single Mac. Small change.

   - **B2 (full multi-account):** iterate `storedAccounts + liveSystemAccount` via `CodexVisibleAccountProjection`, run a per-account Codex refresh (or reuse cached per-account `UsageSnapshot`s), push N `ProviderUsageSnapshot` entries with the same `providerID = "codex"` and distinct `accountEmail`/`workspaceName`. Requires touching `UsageStore`'s single-snapshot-per-provider assumption. Large change — explicitly out of scope here.

   We'd take B1 for an initial Mac 0.20.3 follow-up.

3. **iOS subtitle fallback chain** becomes `email ?? workspaceName ?? "Codex N"`, with workspaceName also used when email IS present but workspaceName is more informative for managed-workspace accounts (debatable — avoid this initially; keep email-first for privacy parity with the rest of the app).

Call-out: **Branch B introduces a "Mac old / iOS new" window** where iOS is on 1.3.0 but Mac users haven't upgraded to 0.20.3 — iOS just sees `workspaceName == nil` and falls back to the ordinal. No crash, no ugliness. This is the same pattern we used for T3's PerplexityCreditSummary.

**Reality check for this research:** Branch B is not required to close T5. T5 brief says "workspace name > generic" — workspace name doesn't exist on the wire today, so "generic" is the live fallback. T5 can ship Branch A and note Branch B as a later polish.

### iOS rendering sketch

Single-card case (unchanged visual):
```
┌─────────────────────────────────────┐
│ Codex                          ⚠︎   │
│ 👤 alice@example.com   [ Pro ]      │
│ 3 min ago                           │
└─────────────────────────────────────┘
```

Two-card case, both emails present:
```
┌─────────────────────────────────────┐
│ Codex                               │
│ 👤 alice@personal.com   [ Pro ]     │
│ 3 min ago                           │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ Codex                               │
│ 👤 bob@work.com    [ Business ]     │
│ 5 min ago                           │
└─────────────────────────────────────┘
```

Two-card case, one nil email:
```
┌─────────────────────────────────────┐
│ Codex                               │
│ 👤 alice@example.com    [ Pro ]     │
│ 3 min ago                           │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ Codex                               │
│ 👤 Codex 2       [ free ]           │
│ 7 min ago                           │
└─────────────────────────────────────┘
```

Two-card case, both nil email (Branch A falls back to ordinal):
```
┌─────────────────────────────────────┐
│ Codex                               │
│ 👤 Codex 1                          │
│ 3 min ago                           │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ Codex                               │
│ 👤 Codex 2                          │
│ 9 min ago                           │
└─────────────────────────────────────┘
```
(Caveat: the underlying `mergeSnapshots` still collapses two nil-email same-ID entries to one. In practice this case is unreachable from the merger today; T5 tests will still cover it via synthetic input to guard against future regressions in the merger.)

## Unit test matrix

New file: `CodexBarMobile/CodexBarMobileTests/ProviderUsageViewIdentityTests.swift` (or extend `CloudKitMergeTests.swift` for the merge-level, and add a new suite for the view-level derivation helper).

**Merge-level** (extends `CloudKitMergeTests.swift`):

| # | Setup | Expected |
|---|---|---|
| M1 | 2 devices, Codex on each with **distinct emails** | 2 providers, both `providerID == "codex"`, emails preserved |
| M2 | 1 device, 2 Codex entries with nil email (synthetic — today's Mac can't produce this but future multi-account Mac push could) | 1 provider (collapsed). Guard-rail test; pin behavior. |
| M3 | 2 devices, Codex: one email + one nil | 2 providers |
| M4 | 3 cards: two with emails, one with nil | 3 providers, all preserved |

**View-helper** (new suite covering the pure subtitle selector):

Extract a pure func `ProviderUsageView.Subtitle.select(provider:, siblingCountWithSameProviderID:, ordinal:)` so we don't need SwiftUI hosting:

| # | Input | Expected |
|---|---|---|
| V1 | email="a@b.com", siblings=1 | email shown (hidePersonalInfo off) |
| V2 | email="a@b.com", siblings=1, hidePersonalInfo=on | redacted placeholder |
| V3 | email="a@b.com", siblings=2, ordinal=1 | email shown (email wins over ordinal) |
| V4 | email=nil, siblings=1 | nil (clean single-card UI; ordinal suppressed) |
| V5 | email=nil, siblings=2, ordinal=2 | `"Codex 2"` |
| V6 | email=nil, loginMethod="Pro", siblings=1 | nil (plan alone doesn't become subtitle text — stays on the chip) |
| V7 | email=nil, loginMethod="Pro", siblings=2, ordinal=1 | `"Codex 1"` (ordinal still wins — see design note) |
| V8 | provider.providerName="Codex", email=nil, siblings=3, ordinal=2, locale=ja | localized `"Codex 2"` format holds |

**List-identity** (SwiftUI ViewInspector or manual driver not practical; assert through the key computation):

| # | Input | Expected |
|---|---|---|
| L1 | providers=[codex@a, codex@b] | `Set(cardIdentityKey)` has 2 distinct values |
| L2 | providers=[codex@nil, claude@x] | 2 distinct keys |
| L3 | providers=[codex@nil, codex@"a@b.com"] | 2 distinct keys |

## Files touched

### Branch A (ship with T5)
- `CodexBarMobile/CodexBarMobile/Views/ProviderUsageView.swift` — add `duplicateOrdinal` init parameter, rewrite `providerHeader` subtitle HStack, add pure `subtitleLine` helper.
- `CodexBarMobile/CodexBarMobile/ContentView.swift:174-182` — switch ForEach id + accessibility id to use `cardIdentityKey`; compute and pass `duplicateOrdinal`.
- `CodexBarMobile/CodexBarMobile/Views/ProviderUsageView.swift` (or a small extension file) — add `ProviderUsageSnapshot.cardIdentityKey` computed var (iOS app target only; do NOT modify the Shared model).
- `CodexBarMobile/CodexBarMobile/Localizable.xcstrings` — add `"%@ %lld"` format key used for the ordinal fallback across en/zh-Hans/zh-Hant/ja.
- `CodexBarMobile/CodexBarMobile/Preview Content/PreviewData.swift` — add a second Codex provider fixture (`codexSecondaryProvider` with different email; optionally a `codexUnlabeledProvider` with `accountEmail = nil`) to power a new `#Preview("Codex · 2 accounts")` in `ProviderUsageView.swift`.
- `CodexBarMobile/CodexBarMobileTests/CloudKitMergeTests.swift` — append M1–M4.
- `CodexBarMobile/CodexBarMobileTests/ProviderUsageViewIdentityTests.swift` (new) — V1–V8, L1–L3.

### Branch B (deferred, Mac-coordinated)
- `CodexBarMobile/Shared/Models/UsageSnapshot.swift` — add `workspaceName: String?`.
- `Sources/CodexBar/Sync/SyncCoordinator.swift` — map workspace from reconciliation snapshot.
- Mac release + ASC coordination required.

## Effort estimate

- **Branch A:** ~3 hours. Mechanical: identity helper + ForEach id fix + view helper refactor + tests + preview + 4-lang strings. No Mac changes, no schema bump, no wire change.
- **Branch B (on top of A):** ~4–6 additional hours, mostly Mac: plumb `workspaceLabel` through `CodexReconciledState` or fetch directly from the reconciliation snapshot in `SyncCoordinator`, add shared model field, regen mock fixtures, cross-version matrix testing. Plus a Mac release (TestFlight-equivalent process for the Mac app, which is not our project's usual cadence).

## Risks / open questions

1. **Merge collision for two-nil-email Codex cards.** `mergeSnapshots` keys nil as `""`, so two different accounts that both failed to resolve an email merge into one. Today this is almost unreachable (single Mac pushes one active Codex). Branch B's full multi-account Mac push would hit it. Recommended fix for Branch B: extend the merge key with `providerAccountID` when available, or fall back to `deviceID` suffix as a last resort. Out of scope for T5 A.
2. **`ForEach` identity stability.** When a user switches active Codex account on Mac, a card's `cardIdentityKey` changes (different email), which SwiftUI sees as card removed + card inserted. That's visually correct (animated card swap), but any per-card `@State` in `ProviderUsageView` would reset. Today the view has no meaningful state, so safe.
3. **accessibilityIdentifier uniqueness.** Currently `"provider-card-codex"` is used by a UI test (search for this string in `CodexBarMobileUITests`). Changing to `"provider-card-codex|a@b.com"` could break it — need to grep UI tests before the rename. **TODO for Developer:** verify `grep -r "provider-card-" CodexBarMobile/` and update any assertions.
4. **Privacy redactor on the ordinal fallback.** `"Codex 2"` contains no PII, so `hidePersonalInfo` has no effect. Don't accidentally route it through `redactEmail`. The design above already keeps them separate.
5. **Localization of "Codex 2".** Some languages expect a different order (e.g., Japanese might want "2番目のCodex"). Using `"%@ %lld"` format leaves this translatable, but QA should review zh-Hans/zh-Hant/ja once.
6. **Mac 0.20.2 ghost-provider filter.** `SyncCoordinator.isGhostProvider` (line 264) skips providers with no signal + no email. Two-card scenarios assume both cards carry at least one of: rate window, cost, error, or email. Multi-account where one account is entirely dormant → that one is filtered on the Mac side and never reaches iOS. Fine; document this as expected.
7. **View-helper test placement.** Pure subtitle selector lives on `ProviderUsageView`. Extracting a nested `enum Subtitle { static func select(...) }` keeps it testable without SwiftUI hosting — recommended over ViewInspector to avoid a test-only dependency.
