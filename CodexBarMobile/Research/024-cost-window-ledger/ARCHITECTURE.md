# CWL — 架构

## 新 SwiftData 表

```swift
// CodexBarMobile/CodexBarMobile/Storage/CostLedgerModels.swift (NEW)

@Model
final class DailyCostPoint {
    // Composite uniqueness 由 upsert 逻辑保证(SwiftData 当前无 native composite UNIQUE)。
    var deviceID: String
    var providerID: String
    var dayKey: String        // "YYYY-MM-DD" UTC

    var costUSD: Double
    var totalTokens: Int
    var isEstimated: Bool?

    // 编码后的 [SyncCostBreakdown](Shared/Models 的)。保留:
    // - isEstimated(P5 估算 badge)
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

- 注册方式:追加到 `CodexBarSwiftDataSchema.models`(`CodexBarMobile/CodexBarMobile/Storage/SwiftDataSchema.swift` 末尾)。当前 schema **未引入 `VersionedSchema` / `SchemaMigrationPlan`** —— `ModelContainerFactory` 的注释明确说 "Future phases must revisit this once real migrations exist",且现策略是 init 失败 → 删了重建(数据是 CloudKit 缓存,可重新拉)。
- 迁移类型:**lightweight(SwiftData 自动)**。同 schema 内新增 entity 不需要 `MigrationPlan`,SwiftData 会在打开旧 store 时自动 add 新表。Round 1 / P1 验证这一点(T16)。如未来需要"改字段"或"重命名"才引入正式 versioned schema —— 那是另一项工作。

## 数据流

```
┌──────────────────────────────────────────────────────────────────┐
│  CloudKit per-provider record(Mac 推送)                         │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  CloudSyncReader 解码 ProviderUsageSnapshot                      │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  SwiftDataBridge.upsertProvider(snapshot, deviceID)              │
│  ├─ 写 blob 路径:existing.costSummaryData = costSummaryData     │
│  │   [现状不变,CWL OFF / fallback 都走这条]                     │
│  └─ if cwlEnabled:                                               │
│      CostLedgerService.upsertFromSnapshot(snapshot, deviceID)    │
│      for each day in costSummary.daily:                          │
│          query DailyCostPoint where (deviceID, providerID,       │
│                                       dayKey) == ...             │
│          if existing != nil && existing.lastUpdated >= new:      │
│              skip(保护已有更新的数据)                            │
│          else:                                                   │
│              覆盖 / 插入                                         │
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
│      读 blob 路径(CostUsageTokenSnapshot)—— 现状不变            │
└──────────────────────────────────────────────────────────────────┘
```

## CostLedgerService(新)

```swift
// CodexBarMobile/CodexBarMobile/Storage/CostLedgerService.swift (NEW)

@MainActor
struct CostLedgerService {
    let modelContext: ModelContext

    /// 聚合一段窗口。跨设备 merge:同 (providerID, dayKey) 取 max lastUpdated。
    /// 不阻塞主线程 —— 大量记录时走 background Task + ModelActor。
    func aggregate(windowDays: Int) async -> CostLedgerAggregation

    /// 单 provider 的窗口聚合(per-provider detail view 用)。
    func aggregateProvider(
        providerID: String,
        windowDays: Int) async -> CostLedgerProviderRollup

    /// 诊断:多少 device / provider / day / 最早一天 / 最近写入 / 估算存储。
    func diagnostics() -> CostLedgerDiagnostics

    /// 显式清空(用户操作)。仅删 DailyCostPoint。blob 不动。
    func clearAll() throws

    /// 老 blob → seed 新 ledger。一次性。失败 → 抛错(调用方负责回退)。
    func seedFromExistingBlobs(
        _ snapshots: [ProviderSnapshotRecord]) async throws

    /// Writer 入口(SwiftDataBridge 调)。
    func upsertFromSnapshot(
        _ snapshot: ProviderUsageSnapshot,
        deviceID: String) async
}

struct CostLedgerAggregation {
    let providerRollups: [String: CostLedgerProviderRollup]
    let totalCostUSD: Double
    let totalTokens: Int
    let activeDayCount: Int
    let dailyPoints: [SyncDailyPoint]    // 聚合后的(可喂 chart)
    let modelMix: [SyncCostBreakdown]    // 跨 provider 模型聚合
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

## 多设备 merge(CWL ON 路径)

**写入端**(per-device,简单):每条 `DailyCostPoint` 带 `deviceID`,同 `(deviceID, providerID, dayKey)` 视为同一条;不同 device 即使同 dayKey 各自一条。

**读取端**(aggregate 内):
1. 按 `(providerID, dayKey)` group 所有 ledger 行。
2. 同组里取 `lastUpdated` 最大那条 —— 即"最新设备 / 最新更新"赢。
3. 这条作为该 (providerID, dayKey) 的真相,加进汇总。

这跟现有 `CloudSyncReader.mergeSnapshots` 的"内存 merge"等价,只是从"每次都重算 / 全 blob 比较"变成"在 ledger 表上 SQL aggregate"。

**CWL OFF 路径** 走原 `mergeSnapshots` 不变,保留作为 fallback。

## 向后兼容(Migration)

```
              [用户首次开 CWL]
                     │
                     ▼
         ┌────────────────────────────┐
         │ seedFromExistingBlobs      │
         │ (Settings 显示 spinner)    │
         └────────────────────────────┘
                     │
            遍历 ProviderSnapshotRecord
                     │
            decode costSummaryData
                     │
        for day in costSummary.daily:
            upsert DailyCostPoint
                     │
            ┌────────┴────────┐
            ▼                 ▼
         成功               失败
         │                   │
    设置 cwlEnabled       报错 + 关 CWL
    = true                 + 回退到 blob 路径
                           + 提示用户("ledger 初始化失败,
                              已暂时关闭,可在 Settings 重试")
```

- seed 是**一次性**,完成后所有后续 CloudKit 同步都直接走 writer 上面的 dual-write(blob + ledger)路径。
- 关 CWL:ledger 表保留(下次开还能用)。
- 显式清空:删 ledger 全部行,blob 不动。

## 接入点(改哪些现有文件)

| 文件 | 改动 | Phase |
|---|---|---|
| `Storage/CostLedgerModels.swift` | **新增**:`@Model DailyCostPoint` | P1 |
| `Storage/SwiftDataSchema.swift` | 追加 `DailyCostPoint.self` 到 `CodexBarSwiftDataSchema.models` 数组(无 versioned schema,lightweight migration) | P1 |
| `Storage/CostLedgerService.swift` | **新增**:聚合 + seed + 清空 + 诊断 + writer 入口 | P2 / P3 / P6 |
| `Storage/SwiftDataBridge.swift` | `upsertProvider` 末尾,if CWL ON → `CostLedgerService.upsertFromSnapshot` | P2 |
| `iCloud/CloudSyncReader.swift` | CWL ON 时 reader 走 ledger;OFF 路径(`mergeSnapshots`)不动 | P5 |
| `Models/MobileDisplayPreferences.swift` | +AppStorage:`cwlEnabled` / `cwlWindowDays`(7/30/90/365) | P4 |
| `ContentView.swift` 的 `CostDashboardInsights` | init 加 `windowDays:` 参数;CWL ON 时数据源换成 `CostLedgerService` | P4 |
| `Models/CostShareService.swift` | period 计算 if CWL ON → 走 ledger,OFF → 原路径 | P4 |
| `Views/ProviderDetailView.swift` | per-provider cost 卡用 `aggregateProvider` | P4 |
| `ContentView.swift` 的 `CostSettingsView`(~2578) | +CWL 开关 + 窗口 Picker + 清空 + 诊断面板 | P4 |
| `Localizable.xcstrings` | 新字符串 4 语 | P4 |

## envelope 不动

`Shared/Models/UsageSnapshot.swift` 是 wire 格式,**不许碰**。CWL 读的是同样的 `SyncCostSummary.daily[]`,只是 iOS 端"保留累积而不替换"。

改了 envelope = 改了 Mac 推送格式 → 旧 iOS / 旧 Mac 兼容性炸 + 可能要 CloudKit production deploy。
