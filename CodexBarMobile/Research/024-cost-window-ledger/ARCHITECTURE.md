

```swift
// CodexBarMobile/CodexBarMobile/Storage/CostLedgerModels.swift (NEW)

@Model
final class DailyCostPoint {
    var deviceID: String
    var providerID: String
    var accountEmail: String?  // nil → "_" sentinel
    var dayKey: String        // "YYYY-MM-DD" UTC

    var costUSD: Double
    var totalTokens: Int
    var isEstimated: Bool?

    // - standardCostUSD / priorityCostUSD / standardTokens / priorityTokens(gap A)
    var modelBreakdownsData: Data?
    var serviceBreakdownsData: Data?

    var lastUpdated: Date

    init(deviceID: String, providerID: String, dayKey: String,
         costUSD: Double, totalTokens: Int, isEstimated: Bool?,
         modelBreakdownsData: Data?, serviceBreakdownsData: Data?,
         lastUpdated: Date)
    { ... }
}
```



```
┌──────────────────────────────────────────────────────────────────┐
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  SwiftDataBridge.upsertProvider(snapshot, deviceID)              │
│  └─ if cwlEnabled:                                               │
│      CostLedgerService.upsertFromSnapshot(snapshot, deviceID)    │
│      for each day in costSummary.daily:                          │
│          query DailyCostPoint where (deviceID, providerID,       │
│                                       dayKey) == ...             │
│          if existing != nil && existing.lastUpdated >= new:      │
│          else:                                                   │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  CostDashboardInsights / CostShareService / ProviderDetailView   │
│  if cwlEnabled:                                                  │
│      CostLedgerService.aggregate(windowDays: N)                  │
│      → CostLedgerAggregation                                     │
│        ├─ totalCostUSD                                           │
│        ├─ providerRollups: [providerID: rollup]                  │
│        ├─ dailyPoints: [SyncDailyPoint]                          │
│        └─ modelMix: [SyncCostBreakdown]                          │
│  else:                                                           │
└──────────────────────────────────────────────────────────────────┘
```


```swift
// CodexBarMobile/CodexBarMobile/Storage/CostLedgerService.swift (NEW)

@MainActor
struct CostLedgerService {
    let modelContext: ModelContext

    func aggregate(windowDays: Int) async -> CostLedgerAggregation

    func aggregateProvider(
        providerID: String,
        windowDays: Int) async -> CostLedgerProviderRollup

    func diagnostics() -> CostLedgerDiagnostics

    func clearAll() throws

    func seedFromExistingBlobs(
        _ snapshots: [ProviderSnapshotRecord]) async throws

    func upsertFromSnapshot(
        _ snapshot: ProviderUsageSnapshot,
        deviceID: String) async
}

struct CostLedgerAggregation {
    let providerRollups: [String: CostLedgerProviderRollup]
    let totalCostUSD: Double
    let totalTokens: Int
    let activeDayCount: Int
}

struct CostLedgerProviderRollup {
    let providerID: String
    let totalCostUSD: Double
    let totalTokens: Int
    let dailyPoints: [SyncDailyPoint]
    let modelBreakdowns: [SyncCostBreakdown]
}

struct CostLedgerDiagnostics {
    let deviceCount: Int
    let providerCount: Int
    let dayCount: Int
    let earliestDayKey: String?
    let latestWriteAt: Date?
    let estimatedBytes: Int
}
```







```
                     │
                     ▼
         ┌────────────────────────────┐
         │ seedFromExistingBlobs      │
         └────────────────────────────┘
                     │
                     │
            decode costSummaryData
                     │
        for day in costSummary.daily:
            upsert DailyCostPoint
                     │
            ┌────────┴────────┐
            ▼                 ▼
         │                   │
```



|---|---|---|
| `Models/MobileDisplayPreferences.swift` | +AppStorage:`cwlEnabled` / `cwlWindowDays`(7/30/90/365) | P4 |
