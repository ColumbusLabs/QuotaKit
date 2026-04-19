# 008 · iOS 数据架构重构

- Status: `ready`
- Date: 2026-04-18
- Author: Architect (Claude)
- Related task: [Todoist 6gJW92VFqrcPVHG2](todoist://task?id=6gJW92VFqrcPVHG2)

## Context

当前 iOS 从 CloudKit 拿到多设备 snapshots 后，所有合并/重算都在内存里完成，无缓存无 DB。直接架构暴露两个紧迫问题：

1. **CloudKit 单 record 1MB 硬限制**。Mac 端 `SyncCoordinator` 每次变化就把一个设备的所有 provider 序列化成单个 `DeviceSnapshot.payload` JSON blob 推上去。随着用户累积数据，这个 blob 逼近并将突破 1MB。**上游 Mac 已发布很久，任何老用户装上 iOS 开始 sync 就可能踩爆。**
2. **SwiftUI body 里重算**。`UtilizationAggregateView.model` / `CostDashboardInsights.init` / `CostShareCardView.displayProviders` 等几处大型 O(N·M) 计算在每次 render 都跑 —— 包括 chart hover 状态变化。

次要的（可感知但不紧急）：
3. 冷启动 2-5 秒空白（等 CloudKit 返回）
4. merge 在 `@MainActor` 上跑

## 现状实测（关键数字）

| 指标 | 实测值 | 来源 |
|---|---|---|
| CKRecord 类型 | `DeviceSnapshot` | `Shared/iCloud/CloudConstants.swift:11` |
| Payload 结构 | **单个 JSON blob**，含所有 provider | `CloudSyncManager.swift:262` |
| 单条 utilization entry JSON | **90 bytes**（ISO8601 时间 + Double + 可选 ISO8601） | `UsageSnapshot.swift:131-141` 实测 JSONEncoder |
| 单条 SyncDailyPoint JSON | **198 bytes**（含 2 model + 1 service breakdown） | `UsageSnapshot.swift` |
| 每 series 条目 cap | **730 条**（= 约 1 个月小时级） | `SyncCoordinator.swift:268` |
| 每 provider 30 天上限 | **~203 KB**（3 series × 730 × 90 + 30 天 cost 6 KB + metadata 500B） | 计算 |
| 10 provider 设备 | **~2 MB** ← 已经破 1MB 限制 | 计算 |
| CKRecord 硬限制 | **1 MB** | Apple |
| 版本标记 | **无 schemaVersion**；靠 `decodeIfPresent` + legacy key 向后兼容 | `UsageSnapshot.swift:268-279` |
| 写入触发 | **响应式**（`withObservationTracking` → UsageStore 改动就推） | `SyncCoordinator.swift:42-54` |
| 冲突处理 | fetch-then-create + serverRecordChanged 单次重试 | `CloudSyncManager.swift:226-300` |
| iOS 合并 key | `"{providerID}|{accountEmail ?? ""}"` | `CloudSyncReader.swift:84` |
| Utilization dedup | **按小时桶平均** `usedPercent`，保留最新 reset | `CloudSyncReader.swift:268-313` |
| Cost 合并 | **local 类 provider（Claude/Codex/VertexAI）求和**；account 类取 lastUpdated 最新 | `CloudSyncReader.swift:132-209` |

**结论**：任务描述中「10 providers × 30 天 ≈ 1MB」偏乐观。实测是 **2MB**，730 entries/series 的 cap 是决定性因素。**老用户 + 10 provider 的场景现在随时会触发 CKError.serverRejectedRequest（record too large）。**

## 视图层 Hotspots（从 Agent 2）

| 位置 | 每次 render 代价 | 触发 | 修复 |
|---|---|---|---|
| `Views/UtilizationAggregateView.swift:16-18` `model` computed | 200-400 ops | 每次 body render（含 hover）| `@State` 缓存 + providers hash 失效 |
| `Views/CostShareCardView.swift:321-331` displayProviders 重算 | 120+ ops | 30 个 bar 每个都重算 | 顶层缓存一次传下去 |
| `ContentView.swift:782-841` `CostDashboardInsights.init` | 150+ ops | Cost tab 每次 render | `@State` + snapshot id 失效 |
| `Views/UtilizationHistoryView.swift:48-50` buildPeriodPoints | 100+ ops | series 切换 + render | `@State` + `.onChange` |
| `Views/ProviderDetailView.swift:157` axis formatter | 30+ ops | 每次 chart render | 预算 axisValues 到 `@State` |

## 设计决策（待用户确认）

### D1. CloudKit 拆 record 策略

| 方案 | 优点 | 缺点 |
|---|---|---|
| **A1. 按 (device, provider) 拆**（推荐）| 简单；每条 record 最大 ~203 KB 远低于 1MB；per-provider 更新粒度更细；iOS merge 直接按新 key 跑 | Mac 端要改：一次 push 变 N 次；需要 batch 写 |
| A2. 保持单 record 但用 CKAsset 装 payload | schema 变化最小；1GB 上限完全没压力 | 多一次 asset fetch round-trip；iOS 冷启动更慢；调试难 |
| A3. payload 走 gzip | 最小改动，能压 60-70% | **治标不治本**：10 provider 仍可能踩限；未来继续加 provider/series 又要改 |

**推荐 A1**。A3 是止损不是解药；A2 调试和性能都劣化。

### D2. 迁移 / 向后兼容（修订：必须保证任意版本组合都 work）

**4 种版本组合兼容矩阵**：

| # | Mac | iOS | 数据流 | 要求 |
|---|---|---|---|---|
| 1 | 老（0.20.0 legacy）| 老（1.2.x legacy）| 现状 | ✅ 今天 work |
| 2 | 老 | 新 | iOS 读 legacy → import SwiftData → 本地持久化（不享增量 sync 但功能全）| iOS 1.3.0 必须支持读 legacy |
| 3 | **新 0.21.0** | **老 1.2.x** | 如果 Mac 只写新 record 则老 iOS 盲 | **Mac 0.21.0+ 必须继续写 legacy（双写）** |
| 4 | 新 | 新 | 最优：per-provider + change token + SwiftData | — |

**第 3 种是陷阱**：用户先装 Mac 0.21 但没装 iOS 1.3.0 → 老 iOS 就从云端拿不到数据。**Mac 必须双写至少 6 个版本**。

**迁移策略**：

**Mac 版本号规则**：保持 `0.20` 主版本前缀（跟上游 v0.20 对齐），通过 minor 递增承载本次 refactor。

**Mac 0.20.1 ~ 0.20.6（双写过渡期，6 个 minor 版本 / 约 6 个月）**：
- 继续写 legacy `DeviceSnapshot` 到 `DeviceSnapshotsZone`
- 同时写新 `DeviceProviderSnapshot/{deviceID}:{providerID}` 到 `DeviceProvidersZone`

**iOS 1.3.0+**：
- 先查 `DeviceProvidersZone` 的新 record。有 → 增量 sync（change token）。无 → fallback 读 legacy 一次性 import 到 SwiftData，后续每次启动仍查新 zone（期待某次升级后 Mac 写了新格式就自动切换）
- 维护**两个 CKServerChangeToken**（每个 zone 一个），两条增量路径并行

**Mac 停写 legacy（0.20.7+）条件（至少满足两个）**：
1. Mac 0.20.1 发布 ≥ 6 个月
2. App Store Connect 监控的 iOS 1.2.x 活跃比 < 5%
3. 停写前 2 个 Mac 版本（0.20.5/0.20.6）发版 notes 预告「从 0.20.7 开始 legacy 停写」

**iOS 移除 legacy fallback（1.5.0）**：
- Mac 0.20.7+ 已成主流后
- iOS 1.3.0 ~ 1.4.x 均保留 legacy fallback（任何时候老 Mac 用户都能 fallback）
- 1.5.0 才移除

**CloudKit 存储开销**：双写期间单设备 CK 用量约 4MB（legacy 2MB + 新 per-provider ~2MB），远低于用户 iCloud 配额（默认 5GB 起），可忽略。Mac 发版 notes 提一下「过渡期 iCloud 用量略增，稳定后恢复」。

### D3. Mac 端是否要改？

**是。** 拆 record 必须 Mac 端改写入逻辑。iOS 是只读消费者，无法单方面解决上传端 1MB 限制。

Mac 改动范围：
- `Sources/CodexBar/Sync/SyncCoordinator.swift` `pushCurrentSnapshot()`：从「推 1 条」变「推 N 条（per provider）」 + 保留一条「legacy 单 record」双写
- `Shared/iCloud/CloudSyncManager.swift`：新增 `pushProviderSnapshot(deviceID:providerID:payload:)` 方法；batch modify
- `Shared/Models/UsageSnapshot.swift`：新增 `ProviderUsageEnvelope`（单 provider payload 的顶层结构）

**注**：这违反我们「只改 iOS」的一贯原则，但此次是唯一出路。用户需明确批准动 Mac。

### D4. View 层缓存

全部用 `@State` + 失效 key 的模式，零 CloudKit 依赖，可独立于 D1-D3 先发。实施:
- `providers.map(\.providerID).joined()` 作为 aggregate 缓存 key
- `snapshot.syncTimestamp` 作为 cost insights 缓存 key
- `selectedSeriesIndex + active.identity` 作为 period points 缓存 key

### D5. 本地冷启动缓存

App Group container（`group.com.o1xhack.codexbar`）下放一个 `last-merged-snapshot.json` 文件：
- App 启动瞬间读这个文件显示
- CloudKit fetch 回来后覆盖 + 重写文件
- 容量可控（merged snapshot 比 raw 小，典型 <500KB）

## 推荐架构 · 最终形态

```
┌─── Mac (CodexBar 0.21+) ───┐
│  UsageStore 变化             │
│    ↓                         │
│  SyncCoordinator             │
│    ├─ 按 provider 拆 payload │
│    ├─ pushLegacyDeviceSnap() │  ← 过渡期双写
│    └─ pushProviderSnap×N()   │  ← 新主路径
└─────────────┬────────────────┘
              ↓
┌─── CloudKit Private DB ──────┐
│  DeviceSnapshot/{deviceID}   │  ← legacy, 过渡期保留
│  DeviceProviderSnapshot/     │
│    {deviceID}:{providerID}   │  ← 新主路径, N 条/设备
└─────────────┬────────────────┘
              ↓
┌─── iPhone ──────────────────┐
│  CloudSyncReader             │
│    1. 先读 DeviceProviderSnap│
│    2. fallback DeviceSnapshot│
│    3. mergeSnapshots() ← @MainActor 外│
│    ↓                         │
│  SyncedUsageData (@Observable)│
│    ↓                         │
│  本地落盘 → App Group JSON    │
│    ↓                         │
│  Views with @State 缓存      │
│    - UtilizationAggregate    │
│    - CostDashboardInsights   │
│    - CostShareCardView       │
│    - UtilizationHistoryView  │
└──────────────────────────────┘
```

## 实施阶段（建议顺序）

| Phase | 范围 | 依赖 | 预估 |
|---|---|---|---|
| **P1 · View @State 缓存** | 只改 iOS Views/。5 个 hotspot 全部走 @State + identity 失效 | 无 | 1-1.5 天 |
| **P2 · App Group 本地缓存** | 只改 iOS。SyncedUsageData 启动时从 JSON 读、CloudKit 回来后写回 | 无 | 1 天 |
| **P3 · CloudKit 拆 record + 双写**（重头戏）| Mac 端 SyncCoordinator + CloudSyncManager；iOS CloudSyncReader 读新+fallback 旧；Shared 模型新增 envelope | P1/P2 可并行，P3 独立 | 3-4 天 |
| **P4 · Mac 停写 legacy**（过渡期后）| Mac 端只写新格式；iOS 保留 fallback 读但默认走新格式 | P3 发布 + N 个 Mac release 后 | 0.5 天 |

**P1 + P2 可以立刻做不用等 P3 设计确认**；P3 需要你明确批准动 Mac 端后才能启动。

## 风险登记

| # | 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|---|
| R1 | P3 双写期间 iOS 读到新/旧数据不一致 | 中 | 中 | iOS 按 provider 合并时以 timestamp 新者优先；测试覆盖 |
| R2 | Mac 端 batch modify 超时（一次推 10 record）| 低 | 低 | CKModifyRecordsOperation 默认可承载；失败单条重试 |
| R3 | CloudKit schema 变化需要 Production 部署 | 中 | 中 | 新 record type 自动建，但要首次真机验证 indexing 无报错 |
| R4 | 老 Mac 用户升级延迟，iOS 新版本读不到新格式 fallback 失败 | 低 | 中 | P3 发版前强制 fallback 路径 100% 覆盖老 schema |
| R5 | P1 @State 缓存失效 key 选错导致 stale display | 低 | 低 | 单测 + 手动点测 hover / switch provider / refresh 场景 |

## 需要你确认的 5 个决策点

1. **D1 选 A1（按 provider 拆 record）？**
2. **D2 选 B1（过渡期双写）？**
3. **D3 明确授权动 Mac 端代码（本次例外，拆 record 无法只在 iOS 改）？**
4. **实施顺序**：P1 + P2 先上，P3 等你确认 D1/D2/D3 后再起，对吧？
5. **P3 完成后打算发哪个版本？** 建议 iOS 1.3.0 + Mac 0.21（跟上游下一版对齐），但要你点头。

确认这 5 点后我立刻从 P1 开工。

## 相关数字（开发期备查）

- Mac 当前 utilization cap: 730 entries/series（`SyncCoordinator.swift:268`）
- Mac cost daily points cap: ~30 条/provider
- CloudKit CKRecord 硬限制: 1 MB
- iOS 主线程渲染预算: 16 ms/frame (60 fps)
- App Group container ID: `group.com.o1xhack.codexbar`（`Scripts/package_app.sh:142`）
- CloudKit container: `iCloud.com.o1xhack.codexbar` Production

## 关键文件索引

| 文件 | 本次会改？ |
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
| `Sources/CodexBar/Sync/SyncCoordinator.swift` | P3（Mac 端）|
