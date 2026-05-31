# 025 — v0.31.0 上游同步 · 设计文档

**Status:** ready · **Date:** 2026-05-30 · 配套 [00 总体](00-overview.md) / [02 开发](02-development.md) / [03 测试](03-testing.md)
**最终版本：** Mac `0.31.0.1`(BUILD 73.1) · iOS `1.10.0`(BUILD 145+) · tag `v0.31.0-mobile.1.10.0` · **完成定义(DONE G1–G10) → [00 总体 ⭐ 节](00-overview.md)**

本文档定稿：每个上游特性在 iOS 上**怎么落**——走哪条同步路径、要不要新增结构、iOS 怎么渲染、要哪些本地化与 mock。

---

## 1. 架构回顾：三条同步路径

我们 fork 的同步层（`Shared/`，Mac 与 iOS 符号链接共用）是**版本化叠加 envelope**：

```
Mac UsageSnapshot (上游内部模型, Sources/CodexBarCore/)
   │  SyncCoordinator.buildProviderUsageSnapshot()   ← fork-owned bridge
   ▼
ProviderUsageSnapshot (Shared/Models/UsageSnapshot.swift)   ← wire 模型
   │  ProviderUsageEnvelope 包一层设备元数据
   ▼  JSON(ISO8601) → zlib(PayloadCompression)
CKRecord "DeviceProviderSnapshot".payload (blob)  in zone "DeviceProvidersZone"
   ▼  CloudKit push (CKRecordZoneSubscription)
iOS CloudSyncReader → SnapshotCache → SwiftData → ProviderUsageView/卡片
```

新数据落地有三条路径：

| 路径 | 机制 | 兼容性 | 适用 |
|---|---|---|---|
| **A 通用 lane** | 进入 `ProviderUsageSnapshot.rateWindows: [SyncRateWindow]`（动态数组）。Mac bridge `line 545` 已无条件把 `snapshot.extraRateWindows` 全量塞入；iOS `ProviderUsageView.swift:53` 用 `ForEach(allRateWindows.enumerated())` 渲染任意条数 | 天然 | 任意"多一条具名配额条" |
| **B 数值修复** | 上游纠正值经**已存在**字段（`SyncRateWindow.windowMinutes`、`claudeExtraUsage`、`budget`、`alibabaTokenPlan` 等）流过 | 天然 | 合并即生效，无 fork 改动 |
| **C 新 envelope 块** | 在 `ProviderUsageSnapshot` 加一个 optional `SyncXxx?` 字段（`decodeIfPresent`，**不 bump `providerPayloadVersion`**）；bridge 加 `mapXxx`；iOS 加专属卡片 | additive，前后兼容 | 通用 lane 装不下的富结构 |

**为什么 additive optional 就够（前后兼容的根）：**
- **前向**（新 Mac → 旧 iOS）：旧解码器不认识新 JSON key，直接忽略。
- **后向**（旧 Mac → 新 iOS）：新解码器 `decodeIfPresent` 取到 `nil`，回退通用渲染。

`Shared/iCloud/CloudConstants.swift` 的 `providerPayloadVersion = 1` 仅在**载荷格式本身**变（压缩算法/envelope 形状）时才 bump。**本次全是 additive optional 字段，不 bump。**

---

## 2. 逐特性设计决策

### 2.1 DeepSeek web-session 用量+成本 —— 路径 C（本次唯一新增块）

**上游来源**（v0.30.0 #1166）：
- 核心新字段 `UsageSnapshot.deepseekUsage: DeepSeekUsageSummary?`（`Sources/CodexBarCore/UsageFetcher.swift:90`，**瞬态**，不持久化）。
- 新结构 `DeepSeekUsageSummary`（`Providers/DeepSeek/DeepSeekUsageCostParser.swift:180`）：
  `todayTokens: Int` · `currentMonthTokens: Int` · `todayCost: Double?` · `currentMonthCost: Double?` · `requestCount: Int` · `currentMonthRequestCount: Int` · `topModel: String?` · `categoryBreakdown: [DeepSeekCategoryBreakdown]` · `daily: [DeepSeekDailyUsage]` · `currency: String` · `updatedAt: Date`。
- 子类型：`DeepSeekCategoryBreakdown(category, tokens, cost?)`、`DeepSeekUsageCategory{ promptCacheHitToken, promptCacheMissToken, responseToken, request }`、`DeepSeekDailyUsage(date, totalTokens, cost?, requestCount)`。
- DeepSeek 现状：已是 iOS 注册 provider（`Shared/Notifications/QuotaProviderList.swift:82`、`ProviderColorPalette` 有品牌色），但 iOS **无专属卡**，余额（`DeepSeekUsageSnapshot.totalBalance/...`）此前未在 iOS 充分呈现 → 本次顺手补齐。

**决策：** 新增 envelope 块 `SyncDeepSeekUsage`，承载**新用量/成本 + 既有余额**，iOS 新增 `DeepSeekUsageCard`（仿 `DeepgramUsageCard` / `MiniMaxBillingCard`）。

**新结构（放 `Shared/Models/V030Snapshots.swift`）：**
```swift
public struct SyncDeepSeekUsage: Codable, Sendable, Equatable {
    // web-session 用量/成本（v0.30.0 #1166）
    public let todayTokens: Int
    public let monthTokens: Int
    public let todayCost: Double?
    public let monthCost: Double?
    public let todayRequests: Int
    public let monthRequests: Int
    public let topModel: String?
    public let currency: String
    // 既有余额（顺手补齐 parity，可空）
    public let totalBalanceUSD: Double?
    public let grantedBalanceUSD: Double?
    public let toppedUpBalanceUSD: Double?
    // 30 天日序列（给迷你柱图，可空数组）
    public let daily: [SyncDeepSeekDaily]
    public let updatedAt: Date
}
public struct SyncDeepSeekDaily: Codable, Sendable, Equatable {
    public let dayKey: String        // "yyyy-MM-dd"
    public let totalTokens: Int
    public let cost: Double?
    public let requestCount: Int
}
```
- `categoryBreakdown`（cache hit/miss/response）**本期不进 wire**：信息密度低、占载荷，先不传；若后续要可再 additive 加。这是"与现有架构基本契合、暂缓细节"的取舍，非放弃整特性。
- 所有数值字段除两个 `Int` 计数外尽量 optional，老 payload / free-tier 静默降级。

### 2.2 Codex Spark 两条 lane —— 路径 A（自动透传，零 schema）

**上游来源**（v0.31.0 #1195/#1201）：经 **`extraRateWindows`** 暴露——
- OAuth 路径：`CodexReconciledState.extraRateWindows`（解析 `CodexUsageResponse.additional_rate_limits`）。
- Web dashboard 路径：`OpenAIDashboardSnapshot.extraRateWindows`。
- 两条具名 lane：`id:"codex-spark"` title `"Codex Spark 5-hour"`、`id:"codex-spark-weekly"` title `"Codex Spark Weekly"`。

**决策：零 fork schema 改动。** bridge `SyncCoordinator.swift:545` 的 `for extra in snapshot?.extraRateWindows ?? []` 无条件把它们塞进 `rateWindows[]`；iOS 通用渲染。**唯一 fork 动作**：给 Codex mock 加这两条 lane（`MockProviderInjector`）、跨版本验证。

> ⚠️ 注意区分：Spark 走的是 `extraRateWindows`（无条件循环），**不是** `tertiary`（受 §3 的 `supportsOpus` 闸门约束）。这是它无需改闸门即可流过的原因。

### 2.3 Antigravity 分模型配额 —— 路径 A（自动透传，零 schema）

**上游来源**（v0.30.0 #1139）：`AntigravityStatusProbe.toUsageSnapshot()` 把全部 `modelQuotas`（`AntigravityModelQuota{label, modelId, usedPercent, resetDescription}`）按模型逐条作为 `extraRateWindows` 暴露（之前仅 3 族汇总）。

**决策：零 fork schema 改动。** 同 2.2 经 `extraRateWindows → rateWindows[]` 自动透传，iOS 多渲染几条具名 lane。Antigravity 已有 `antigravityAccounts` 账号切换器（1.7.0），不受影响。fork 动作：mock 增补 + 验证。

### 2.4 Claude "Design" lane 移除 —— 路径 A（上游停发，零 schema）

**上游来源**（v0.31.0 #1197）：删除 `OAuthUsageResponse.sevenDayDesign` 与 `id:"claude-design"`/"Designs" 的 `extraRateWindows` 条目；现并入主 Claude 限额。`claude-routines`/"Daily Routines" lane 保留。

**决策：零 fork 改动。** 合并后上游不再发 "Designs" lane → 它自动从 `rateWindows[]` 消失，iOS 不渲染。**fork 动作**：`grep` iOS 是否对 "claude-design"/"Designs" 有任何硬编码标签/本地化残留需清理（预期无，因 iOS 通用渲染 lane 标签）。

### 2.5 数值修复类（路径 B，合并即生效，零 schema）

| 特性 | 上游改动 | 经哪个现有字段流到 iOS | iOS 效果 |
|---|---|---|---|
| **Claude 100× 修复**（0.29.1 #1114） | `treatAsMajorUnits: false`，修 `ProviderCostSnapshot.used/limit` | `claudeExtraUsage` envelope + `budget` | 企业版 extra-usage 显示正确币种，不再 100× |
| **Grok reset 窗口**（0.29.1 #1148） | 新派生 `GrokBillingResponse.billingPeriodMinutes`，primary `windowMinutes` nil→真实 | `SyncRateWindow.windowMinutes`（bridge line 523 已映射）+ 现有 `grokBilling` | 进度条按真实账单窗口标 Weekly/Monthly |
| **Ollama 配速**（0.30.0 #1136） | 新 `sessionWindowMinutes`，session/weekly `windowMinutes` nil→真实 | `SyncRateWindow.windowMinutes` | iOS 有 window 时长即可算"几时见底"配速 |
| **Alibaba Bailian**（0.30.0 #1142） | 换端点，快照结构不变 | 现有 `alibabaTokenPlan` envelope（V029） | 数值更准，无 UI 变化 |
| **OpenAI project 限定**（0.30.0 #1168） | 新 `projectID`，呈现为 `loginMethod:"Admin API: <id>"` | 现有 `loginMethod` | iOS 登录方式行显示项目限定 |

均无 fork schema 改动；测试侧验证数值/标签正确即可（见 [03](03-testing.md)）。

### 2.6 OpenAI/Mistral 成本卡请求数 —— 路径 C（可选 additive，建议做）

**上游来源**（v0.30.0 #1163）：共享成本模型新增 `CostUsageTokenSnapshot.sessionRequests/last30DaysRequests/currencyCode/historyLabel`、`CostUsageDailyReport.Entry.requestCount`、`ModelBreakdown.requestCount`。

我们的 `SyncCostSummary`/`SyncDailyPoint`/`SyncCostBreakdown` 目前**不带请求数与币种**。

**决策（依"多同步一点也好"宗旨）：建议做**，纯 additive：
```swift
// SyncCostSummary 追加：
public let sessionRequests: Int?      // 今日/会话请求数
public let last30DaysRequests: Int?   // 窗口请求数
public let currencyCode: String?      // 非 USD 成本（Mistral EUR 等）正确显示
// SyncDailyPoint 追加：
public let requestCount: Int?
// SyncCostBreakdown 追加：
public let requestCount: Int?
```
iOS 成本卡在有值时多显示一行 "N requests" 与正确币种符号；老 payload `nil` → 不显示，零回归。**若评审认为优先级低，可降级为 fast-follow**（不影响主线发布），这是唯一"可放"的取舍点。

---

## 3. `supportsOpus` 闸门审计（R1）

`SyncCoordinator.swift:535`：
```swift
if let metadata, metadata.supportsOpus, let t = snapshot?.tertiary {
    rateWindows.append(SyncRateWindow(label: metadata.opusLabel ?? "Sonnet", ... ))
}
```
该闸门仅放行 `supportsOpus == true` 的 provider 的 `tertiary` lane。`supportsOpus:false` 的 provider（含 **Codex**）的 `tertiary` 会被**静默丢弃**。

**本次结论：非阻塞。** 区间内：
- Codex Spark 走 `extraRateWindows`（无条件），不受此闸门影响。
- 0.30.0 的 "tertiary 行" 是 widget UI 化，`tertiary` 字段早已存在；区间内**无新 `tertiary` 数据**需要透传给非 opus provider。
- z.ai 的 5h tertiary：z.ai `supportsOpus:true`，本就放行。

**加固建议（可选，记录用）：** 长期看这个闸门是"按错维度门控"——`tertiary` 是否该传应取决于"该 lane 是否有数据"，而非"是否 opus 模型"。可改为无条件透传 `tertiary`（与 `extraRateWindows` 一致），消除未来非 opus provider 加第三条 lane 时的隐性丢弃。**本次先记为审计项，不强制改**（避免扩大改动面；若 CR 认为顺带改更安全，则在 bridge 一并处理并补测试）。

---

## 4. iOS 视图设计

| 特性 | iOS 视图 | 改动 |
|---|---|---|
| Codex Spark / Antigravity 分模型 / 任意新 lane | `ProviderUsageView`（`ForEach(allRateWindows)`） | **无**（通用渲染已支持任意条数） |
| Claude Design 移除 | 同上 | **无**（少一条而已） |
| 数值修复（Claude/Grok/Ollama/Alibaba/OpenAI） | 现有卡片/进度条 | **无**（值经现有字段流入） |
| **DeepSeek** | **新 `DeepSeekUsageCard.swift`** | 仿 `DeepgramUsageCard`：标题行（topModel 徽标）+ 今日/本月 token·成本+请求数两栏 + 余额行（total/granted/topped-up）+ 30 天迷你柱图（`daily`）。在 `ProviderDetailView` 里 `if let ds = provider.deepSeekUsage { DeepSeekUsageCard(ds) }` 派发 |
| OpenAI/Mistral 请求数（若做） | 现有成本卡 | 有值时加一行 "N requests" + 币种符号 |

**渲染降级矩阵（DeepSeek 卡）：** `deepSeekUsage == nil`（旧 Mac）→ 不显示该卡新区，回退现有通用呈现；用量字段齐而余额空 → 只显示用量区；`daily` 空 → 隐藏柱图。

---

## 5. 本地化清单（4 语：en / zh-Hans / zh-Hant / ja）

DeepSeek 卡片新增可见文案（English 为 key）：
- `"Today"` / `"This Month"`（若已有复用）
- `"Tokens"` · `"Requests"` · `"Cost"` · `"Balance"` · `"Granted"` · `"Topped Up"` · `"Top model"`
- release notes 条目（见 [02 §6](02-development.md)，1.10.0 用户向白话）

Codex Spark / Antigravity 的 lane 标签来自上游 `NamedRateWindow.title`（英文，透传显示，**非** iOS 本地化范畴——属 enum/动态数据，见 AGENTS.md「不需翻译」）。

> 自检（依 AGENTS.md）：每个新 `String(localized:)` 在 `Localizable.xcstrings` 有 4 语条目且 `state:"translated"`；无遗留 `state:"new"`。

---

## 6. Mock 设计（`Sources/CodexBar/Sync/MockProviderInjector.swift`，Mac 侧；iOS 经 `MockProviderDetector` 识别）

| provider | mock 增补 |
|---|---|
| `deepseek`（已有 mock @ line 1124/1319） | 注入 `SyncDeepSeekUsage`：today/month token·cost·requests、topModel、3 条余额、~14 天 `daily` |
| `codex` | `extraRateWindows` 加 `codex-spark` + `codex-spark-weekly` 两条 |
| `antigravity` | `extraRateWindows` 加 4~5 条分模型配额 |
| `claude` | 移除 "Designs" lane（与上游一致）；保留 "Daily Routines" |

mock 必须能让 iOS 在**无真实凭证**下完整走查 DeepSeek 卡与新 lane（依 `Research/021-mock-first-infrastructure.md`）。

---

## 7. 设计取舍小结（对照 PM 宗旨）

| 项 | 取舍 | 理由 |
|---|---|---|
| DeepSeek `categoryBreakdown` 暂不进 wire | **暂缓细节**，非放弃 | 信息密度低、占载荷；可后续 additive 补 |
| OpenAI/Mistral 请求数 | **建议做**（additive） | 符合"多同步一点也好"；唯一可降级为 fast-follow 的点 |
| 瑞典语/葡语（Mac 本地化） | **不进 iOS** | iOS 固定 4 语策略（AGENTS.md 护栏） |
| `supportsOpus` 闸门重构 | **本次记审计项** | 非阻塞；避免扩大改动面 |
| 其余 8 项 | **全保留** | 经路径 A/B 自动透传，零冲突，完全契合宗旨 |

**无任何特性因"与现有架构完全冲突"而放弃。**
