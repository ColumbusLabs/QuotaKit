# CWL — 设计

## 问题

Mac 的 cost 扫描受 `historyDays`(1–365,默认 30)限制。Mac 每次只推过去 N 天 `daily[]`,iOS 当前在 `SwiftDataBridge.swift:~173` 是 **整块 blob 覆盖**:

```swift
existing.costSummaryData = costSummaryData   // ← REPLACE,不 merge
```

结果:即使 iOS 一直在同步,过去 Mac 窗口外的数据(iOS 之前接收过的旧 daily 点)在下一次同步时被覆盖丢失。用户没法在 iOS 端选 > Mac 当前 historyDays 的窗口。

## A vs B 决策

| 维度 | A — clamp | B — ledger |
|---|---|---|
| 改动量 | ~50 行 | ~150–250 行 + SwiftData 迁移 |
| Mac 改动 | 无 | 无 |
| 窗口上限 | Mac 当前 historyDays | 原则上无限(实际 = iOS 累积时长) |
| Mac 改窗口的影响 | iOS 跟着变 | iOS 不受影响 |
| 全新装 iOS 用户 | 立即可用 | 只能 ≤ Mac 当前窗口(ledger 刚建,无历史) |
| Mac 停用一段时间后 | iOS 同步窗口对应变短 | iOS 持有的累积仍可用 |
| 存储增长 | 0(blob 替换) | ledger 表逐日增长(40 providers × 365 days ≈ 14k 行,小) |
| 多设备复杂度 | 现有内存 merge 不变 | 改成 "per-device 累积 + 渲染时跨设备聚合" |

**决策:B**。A 直接做完反而是浪费 —— 用户的核心诉求是"iOS 独立于 Mac 控制窗口",A 的 clamp 没解决这个;B 一次性彻底解决。

## CWL 语义

per-device, per-provider, per-day 的 append + dedupe ledger。每条记录:

```swift
DailyCostPoint(
    deviceID: String,         // 哪台 Mac 推的(来自 SyncedUsageSnapshot.deviceID)
    providerID: String,       // 哪个 provider
    dayKey: String,           // "YYYY-MM-DD" UTC,跟 SyncDailyPoint.dayKey 一致
    costUSD: Double,
    totalTokens: Int,
    isEstimated: Bool?,       // 保留 P5 isEstimated 标记
    modelBreakdownsData: Data?,  // 编码后的 [SyncCostBreakdown],保留 isEstimated /
                                 //   standardCostUSD / priorityCostUSD(gap A 标快拆分)
    serviceBreakdownsData: Data?,
    lastUpdated: Date         // Mac 推送时该日数据的最后更新时间
)
```

**Unique key**:`(deviceID, providerID, dayKey)`。同 key 收到新数据 → 以最新 `lastUpdated` 为准覆盖。

## 关键设计决策

1. **per-device 累积,不在写入时跨设备 merge**。多设备 merge 推到 reader 层(渲染时按 `(providerID, dayKey)` group,取各设备里 latest `lastUpdated`)。
   - 写入简单,不会跨设备误覆盖。
   - 用户切设备 / 加设备 / 删设备时,历史归属清晰。
   - 诊断面板能查"哪台设备贡献了哪些天的数据"。

2. **保留现有 blob 写入路径不动**(`SwiftDataBridge.swift:~173`)。CWL ON 时 ledger 是新真相源;OFF 时仍走 blob。开关切换无需迁移、可回滚。

3. **老用户升级 = 首次开 CWL = 自动 seed**。`seedFromExistingBlobs` 把现有所有 `ProviderSnapshotRecord.costSummaryData` blob 解码,逐 day upsert 进 ledger 作为初始历史。失败 → 关 CWL 回 blob 路径,不丢用户数据。

4. **CWL 默认 OFF**。用户在 Settings 显式开启。开启后看到一段说明:"接下来 iOS 会累积成本历史,可选择比 Mac 更长的窗口。当前已积 N 天"。

5. **清空**:Settings 提供"清空 CWL ledger"显式按钮(二次确认对话框)。仅删 ledger 表内容,blob 不动,其他 iOS 数据不动。

6. **诊断面板**:Settings 显示:多少 device / 多少 provider / 多少 day / 最早一天 / 最近写入时间 / 估算存储大小。

7. **`isEstimated` / 标快拆分**:从老 blob seed 时 **保留**(可能影响 UI 渲染的 estimated badge / Codex Std·Fast 子行)。

## 权衡(Trade-offs)

| 场景 | 行为 | 注释 |
|---|---|---|
| 全新装 iOS 用户 | ledger 刚建,只能看 ≤ Mac 当前窗口 | UI 显式说明"接下来会累积" |
| 用户长期不用 iOS / Mac | ledger 不增长但不丢 | 不主动 GC |
| Mac 卸载某 provider | 该 provider 的旧 daily 点在 ledger 里保留 | 用户仍能查历史 |
| 用户换 Mac(新 deviceID) | ledger 多一组 `(newDeviceID, ...)` 记录 | reader 渲染时跨设备聚合,新旧设备数据一起算 |
| 用户清空 ledger | 历史全删 | 显式确认,不可恢复 |
| ledger 表过大(> 100k 行) | 当前不限制 | 见 README Q4 |

## 风险 + 应对

- **R1 — 迁移期间数据丢失** → seed 步骤完成前不切换 reader 路径;失败回退到 blob。
- **R2 — 多设备 merge 重写引入 bug** → 保留旧 `CloudSyncReader.mergeSnapshots` 作为 CWL OFF fallback;ON 路径独立测试。
- **R3 — ledger 写入阻塞主线程** → SwiftData background context + Task。
- **R4 — 破坏 build 140 cap+Others** → 每轮 CR 必须 check build 140 在 CWL ON / OFF 都对(回归测试 T7 + T14)。
- **R5 — CWL 与现有 `CostShareService` 的 7d/30d period 选项冲突** → period 计算 if CWL ON 走 ledger,OFF 走原路径。详见 ARCHITECTURE.md。

## 与现有功能的关系

- **build 140 cap+Others**:CWL 不影响渲染逻辑,只换数据源。`contributionSection` / `budgetSection` / `UtilizationAggregateView` 全部继续用 top-5 + Others + drill-down。
- **gap A Codex Std/Fast 拆分**:`DailyCostPoint.modelBreakdownsData` 保留 `standardCostUSD` / `priorityCostUSD` 字段,iOS 渲染逻辑不动。
- **gap F historyDays 标签**:CWL ON 时显示的 "N Days" 来自 iOS Picker 选择(而非 Mac historyDays);OFF 时仍读 Mac historyDays。
- **mock injection**:Mac mock 推送的 daily 数据进 ledger 跟真实数据走同样路径,测试可用。
