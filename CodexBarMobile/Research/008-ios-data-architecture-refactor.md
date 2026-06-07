
- Status: `ready`
- Date: 2026-04-18
- Author: Architect (Claude)
- Related task: [Todoist 6gJW92VFqrcPVHG2](todoist://task?id=6gJW92VFqrcPVHG2)

## Context





|---|---|---|



|---|---|---|---|



|---|---|---|




|---|---|---|---|---|





**iOS 1.3.0+**：













```
┌─── Mac (CodexBar 0.21+) ───┐
│    ↓                         │
│  SyncCoordinator             │
└─────────────┬────────────────┘
              ↓
┌─── CloudKit Private DB ──────┐
│  DeviceProviderSnapshot/     │
└─────────────┬────────────────┘
              ↓
┌─── iPhone ──────────────────┐
│  CloudSyncReader             │
│    2. fallback DeviceSnapshot│
│    ↓                         │
│  SyncedUsageData (@Observable)│
│    ↓                         │
│    ↓                         │
│    - UtilizationAggregate    │
│    - CostDashboardInsights   │
│    - CostShareCardView       │
│    - UtilizationHistoryView  │
└──────────────────────────────┘
```


|---|---|---|---|



|---|---|---|---|---|





- App Group container ID: `group.com.columbuslabs.quotakit.mac`（`Scripts/package_app.sh:142`）
- CloudKit container: `iCloud.com.columbuslabs.quotakit.mac` Production


|---|---|
| `CodexBarMobile/CodexBarMobile/Models/SyncedUsageData.swift` | P2 |
| `CodexBarMobile/CodexBarMobile/iCloud/CloudSyncReader.swift` | P3 |
| `CodexBarMobile/CodexBarMobile/Views/UtilizationAggregateView.swift` | P1 |
| `CodexBarMobile/CodexBarMobile/Views/UtilizationHistoryView.swift` | P1 |
| `CodexBarMobile/CodexBarMobile/Views/CostShareCardView.swift` | P1 |
| `CodexBarMobile/CodexBarMobile/Views/ProviderDetailView.swift` | P1 |
| `CodexBarMobile/CodexBarMobile/ContentView.swift` (CostDashboardInsights) | P1 |
| `Shared/Models/UsageSnapshot.swift` | P3 |
| `Shared/iCloud/CloudSyncManager.swift` | P3 |
| `Shared/iCloud/CloudConstants.swift` | P3 |
