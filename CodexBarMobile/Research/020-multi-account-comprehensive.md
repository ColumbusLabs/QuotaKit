
**Status**: Round 1 — In Progress
**Started**: 2026-05-02

---




---


|-------|------|------|------|


|---|------|----------|------------|------|

---




|------|----------|----------|------------------------|










```swift
public struct ProviderUsageSnapshot: Sendable, Codable, Hashable {

    /// Stable identifier for accounts that may not have a known email.
    /// For Codex managed accounts, this is `"codex-account-{uuid-prefix-8}"`.
    /// `nil` for legacy single-account providers and old Mac builds.
    /// iOS uses this when `accountEmail == nil` to disambiguate per-account
    /// records, falling back to `accountEmail` for old Mac builds (forward-compat)
    /// and to legacy per-device bucket for old iOS reads (back-compat via
    /// `Codable` default-decode).
    public var accountIdentifier: String?
}
```


|-----------|-------------------------------|---------------------|



```swift
// Sources/CodexBar/Sync/SyncCoordinator.swift

func pushCurrentSnapshot() async {
    // ...
    var providerSnapshots: [ProviderUsageSnapshot] = []

    for provider in enabledProviders {
        // NEW: provider-specific multi-account emit
        let perAccountSnapshots = self.collectMultiAccountSnapshots(for: provider)
        if !perAccountSnapshots.isEmpty {
            providerSnapshots.append(contentsOf: perAccountSnapshots)
        } else {
            // Existing single-snapshot path
            providerSnapshots.append(makeFromActiveSnapshot(provider))
        }
    }
    // ...
}

/// Returns one ProviderUsageSnapshot per known account for providers that
/// support multi-account. Returns empty array for single-account providers
/// or when no per-account data is available — caller falls back to
/// `store.snapshots[provider]`.
private func collectMultiAccountSnapshots(
    for provider: UsageProvider
) -> [ProviderUsageSnapshot] {
    switch provider {
    case .codex:
        return collectCodexAccounts() // R1
    case .claude, .zai, .cursor, .opencode, .opencodego,
         .factory, .minimax, .augment, .ollama, .abacus, .mistral:
        return collectTokenBasedAccounts(for: provider) // R2
    default:
        return []
    }
}
```

#### Codex per-account emit (R1)

```swift
private func collectCodexAccounts() -> [ProviderUsageSnapshot] {
    guard let reconciliation = self.store.codexReconciliationSnapshot else {
        return []
    }
    let storedAccounts = reconciliation.storedAccounts
    guard storedAccounts.count >= 2 else {
        return [] // Single-account → fall back to active snapshot path
    }
    return storedAccounts.compactMap { account in
        // Each ManagedCodexAccount → ProviderUsageSnapshot
        // accountEmail: account.accountEmail (may be nil)
        // accountIdentifier: "codex-account-\(String(account.id.uuidString.prefix(8)))"
        // primary/secondary/tertiary/cost/budget: from account-scoped snapshot
        //   (need to find Mac-side accessor — likely `accountSnapshots[.codex]`
        //    keyed by account.id, or refresh side effect)
        makeProviderUsageSnapshot(forCodexAccount: account, ...)
    }
}
```










|---------|------|---------------------|------|
| `CostUsageScanner.loadDailyReport` | `Options(codexSessionsRoot: URL?)` | ✅ | `CostUsageScanner.swift:14-33` |
| `CodexHomeScope.scopedEnvironment` | `codexHome:` | ✅ | `CodexBarCore` |
| `UsageFetcher(environment:)` | env dict | ✅ | `ProviderRegistry` |


```
Sources/CodexBar/Sync/
```

- Input: `ManagedCodexAccount` + base `UsageStore` env
- Output: `ProviderUsageSnapshot` (accountEmail / accountIdentifier / rate / cost / identity)

```swift
// In pushCurrentSnapshot()
for provider in enabledProviders {
    if provider == .codex,
       let stored = self.store.codexReconciliationSnapshot?.storedAccounts,
       stored.count >= 2 {
        let perAccountSnapshots = await fetchCodexPerAccount(stored: stored)
        providerSnapshots.append(contentsOf: perAccountSnapshots)
    } else {
        providerSnapshots.append(makeFromActiveSnapshot(provider))
    }
}

private func fetchCodexPerAccount(stored: [ManagedCodexAccount])
    async -> [ProviderUsageSnapshot]
{
    await withTaskGroup(of: ProviderUsageSnapshot?.self) { group in
        for account in stored {
            group.addTask {
                await SyncCodexAccountFetcher.fetchSnapshot(
                    for: account,
                    baseEnvironment: ProcessInfo.processInfo.environment)
            }
        }
        var results: [ProviderUsageSnapshot] = []
        for await snapshot in group {
            if let snapshot { results.append(snapshot) }
        }
        return results
    }
}
```














  - record + retrieve single account
  - cached snapshots exclude active
  - record replaces existing entry
  - purge stale accounts removes unreferenced
  - purge with empty living wipes provider
  - cross-provider isolation (R2 readiness)
  - reset clears all providers
  - excluding never-seen account returns all (cold-start path)



- ⏳ R1.5 build + test pass → R1 closure trigger


- lint pass



---


**11 provider**: Claude / z.ai / Cursor / OpenCode / OpenCodeGo / Factory / MiniMax / Augment / Ollama / Abacus / Mistral













|------|-----------------|-------------------|

---




|------|------------------|------------------|------------------|------------------|

---






|------|----------|













---



---





|------|------|------|



  - `off_peak`
  - `off_peak_peak_in`
  - `peak_ends_in`


- iOS xcstrings：lint i18n audit 'all locales translated' ✅



- ✅ `./Scripts/lint.sh lint` 0 violations across 820 files；i18n audit 'all locales translated'





---


**Target**: iOS 1.6.0 (upgrades from 1.5.3 series)
**Mac dependency**: 0.25.1-mobile.1.5.3 (released 2026-05-13)






|----------|-------|-----|----------|




### R7.2 QuotaProviderList 27 → 38 (S2)









### R7.4 Quota warning markers + push (S4 — 1.6.0, Mac 0.25.2)




```
  └── session: QuotaWarningWindowConfig?  { thresholds: [Int]?, enabled: Bool? }
  └── weekly: QuotaWarningWindowConfig?

settings.quotaWarningEnabled(provider:, window:)         per-provider override
settings.quotaWarningThresholds(provider:, window:)      per-provider override

  → sessionQuotaNotifier.postQuotaWarning(event:, provider:)
```


```swift
public struct SyncQuotaWarningConfig: Codable, Sendable, Equatable {
    public let sessionEnabled: Bool?
    public let weeklyThresholds: [Int]?
    public let weeklyEnabled: Bool?
}
```

```swift
public let quotaWarnings: SyncQuotaWarningConfig?  // decodeIfPresent
```




- Fields: providerID, providerName, window (session/weekly), threshold, currentRemaining, transitionAt, deviceID



- 38 providers × 3 states (depleted / restored / warning) = 114 subscriptions

**iOS NSE** (Notification Service Extension):


|------|------------|------------|-------------|-------|

- G1 wire `decodeIfPresent` additive
- G8 NSE @objc observers nonisolated


**Wire (Shared/)**:

**Mac**:
- [ ] Mac 0.25.2 / BUILD_NUMBER 62 / sparkle 62.1.6.0

**iOS**:
- [ ] iOS 1.6.0 build 121

**Tests**:
- [ ] `SyncQuotaWarningConfigTests` Codable round-trip

### R7.5 Claude peak-hours iOS indicator (S5, P2)







- `.test` TLD email
- `_mock_simple_<provider>` recordName





1. Mac: `CODEXBAR_MOCK_PROVIDERS=1 open /Applications/CodexBar.app`



### R7.9 In-app release notes + xcstrings (S9)



- `project.yml` MARKETING_VERSION 1.5.3 → 1.6.0; CURRENT_PROJECT_VERSION 119 → 120
- `version.env` MOBILE_VERSION 1.5.3 → 1.6.0




|------|------|------|

---




---


| Date | Round | Note |
|------|-------|------|
