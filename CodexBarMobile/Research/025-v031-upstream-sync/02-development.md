# 025 — v0.31.0 上游同步 · 开发文档 + 后端/CloudKit 架构

**Status:** ready · **Date:** 2026-05-30 · 配套 [00 总体](00-overview.md) / [01 设计](01-design.md) / [03 测试](03-testing.md)
**最终版本：** Mac `0.31.0.1`(BUILD 73.1) · iOS `1.10.0`(BUILD 145+) · tag `v0.31.0-mobile.1.10.0` · **完成定义(DONE G1–G10) → [00 总体 ⭐ 节](00-overview.md)**

本文档 = 实现手册 + 后端数据库（CloudKit）架构说明。按 PM 要求："如确定涉及架构变动必须出后端数据库架构文档"——**本次结论是无架构变动**，§2 正式论证为什么，并给出 CloudKit deploy 审计判定。

---

## 1. 后端/CloudKit 数据架构（现状回顾）

我们不是传统数据库，"后端"= **CloudKit 容器** `iCloud.com.o1xhack.codexbar`（Mac 写、iOS 读，端到端加密在用户 iCloud 私有库）。

### 1.1 记录模型（`Shared/iCloud/CloudConstants.swift`）

| 记录类型 | Zone | 用途 | Record name 格式 |
|---|---|---|---|
| `DeviceProviderSnapshot`（**主**，P4 起） | `DeviceProvidersZone` | 每 (设备×provider×账号) 一条增量记录 | `"{deviceID}|{providerID}|{accountEmail ?? "_"}"` |
| `DeviceSnapshot`（legacy） | `DeviceSnapshotsZone` | 旧整包；仅老 Mac 回退 | per-device |
| `ProviderAccountLinkage` | `DeviceProvidersZone` | 用户确认的跨设备账号连接边 | `"linkage-{uuid}"` |
| `QuotaTransition` | `QuotaDepletedZone`/`QuotaRestoredZone` | 配额涨落推送事件 | per (provider, hourBucket) |

### 1.2 载荷编码（关键）

`DeviceProviderSnapshot` 的业务数据**不是**摊平成多个 CKRecord 字段，而是：

```
ProviderUsageEnvelope { deviceID, deviceName, appVersion, mobileVersion,
                        syncTimestamp, notificationPushEnabled, provider }
  → JSONEncoder(.iso8601)            // CloudConstants.makeJSONEncoder()
  → zlib 压缩 (PayloadCompression)
  → 写入 CKRecord 的单个 blob 字段 `payload`
CKRecord 上另有标量字段：`encodingVersion`(= providerPayloadVersion=1) 等
```

**这条是本次同步"零架构变动"的根本原因**（详见 §2）：`ProviderUsageSnapshot` 里所有 `SyncXxx` 富数据字段都活在**压缩 blob 内部**，CloudKit 只看到一个不透明 `payload`。新增/删除 Swift 字段**不改变 CKRecord 的字段集**。

### 1.3 数据流

```
[Mac] 各 provider fetcher → UsageSnapshot(上游) 
   → SyncCoordinator.buildProviderUsageSnapshot (fork bridge)
   → ProviderUsageSnapshot → Envelope → JSON → zlib → CKRecord.payload
   → CloudSyncManager.pushPerProviderRecords  →→ CloudKit
                                                    ↓ CKRecordZoneSubscription 静默推送
[iOS] CloudSyncReader 拉取 → 解 zlib → JSON decode(decodeIfPresent)
   → SnapshotCache 合并(union-find by accountIdentities) → SwiftDataBridge 持久化
   → ProviderUsageView / 各卡片渲染
```

---

## 2. 本次架构影响判定：**无架构变动 + 无需 Prod schema deploy**

### 2.1 为什么无架构变动

| 改动 | 是否动 CKRecord 字段集 / zone / 记录名 / 压缩格式 | 结论 |
|---|---|---|
| 新增 `SyncDeepSeekUsage?` 等 optional 字段 | 否——在 blob 内部 | additive optional |
| 新增 `SyncCostSummary.requestCount?` 等 | 否——在 blob 内部 | additive optional |
| Codex Spark / Antigravity 多几条 `rateWindows[]` | 否——数组元素，blob 内部 | 无 |
| Claude Design lane 移除 | 否——少一个数组元素 | 无 |

`providerPayloadVersion` **保持 = 1**（仅当压缩算法/envelope 整体形状变才 bump；additive optional 不算）。zone / 记录类型 / 记录名格式 / 订阅**全不动**——这些是 `CloudConstants.swift` 标了 **WIRE CONTRACT · IRREVERSIBLE** 的，本次一律不碰。

### 2.2 CloudKit Production schema deploy 审计

依 [`docs/cloudkit-deploy-audit.md`](../../../docs/cloudkit-deploy-audit.md)（项目反复踩的坑：Dev 加了字段没 deploy 到 Prod，索引不会自动复制）。

**判定流程：** "是否新增/改名 **CKRecord 顶层字段**（非 blob 内 Codable 字段）、新 record type、新 zone、新 queryable 索引？"
- 本次：**全否。** 所有新数据在压缩 blob 内。
- **判定：本次同步无需 Production schema deploy。**

> 阶段 D 发布前仍按该文档跑一遍 grep 清单复核（搜 `CKRecord(`、新 `recordType`、新 zone 常量、`CloudConstants` 新字段），把"本次无新 CKRecord 字段"写进该文档的历史决策存档。

---

## 3. Mac 合并（阶段 A）

```bash
git checkout upstream-sync/v0.31.0-mobile.1.10.0   # 已在此分支
git merge v0.31.0
```

**预期冲突面**（依 023 经验：`Shared/` 与 `CodexBarMobile/` 上游不碰 → 零冲突；冲突集中在 fork 同时改过的 Mac 文件）：
- `version.env`（fork 4 段版本 vs 上游 3 段）— 手动取 fork 方案后填本次目标值。
- `Sources/CodexBar/Sync/SyncCoordinator.swift` / `MockProviderInjector.swift`（若上游恰好动了相邻 provider 枚举/cost cache）— 取并集。
- 可能的 cost-usage cache 指纹（fork `pricingFingerprint` + 上游 `producerKey`）— 如 023 般合并两者。
- 新增 enum case（DeepSeek 等已存在；本次上游若加 provider 枚举值，fork 的 `switch` 需补 case）。

**验收：** `swift build` 干净；受影响的 `*CacheTests` / `SyncModelTests` 绿。

> 实际冲突清单以 `git merge` 输出为准；解冲突遵循 AGENTS.md「解冲突而非丢弃改动」。

---

## 4. 文件级改动清单

### 4.1 `Shared/`（wire schema，fork-owned）

| 文件 | 改动 |
|---|---|
| `Shared/Models/V030Snapshots.swift` **(新建)** | `SyncDeepSeekUsage` + `SyncDeepSeekDaily`（结构见 [01 §2.1](01-design.md)）。文件头注释照 `V029Snapshots.swift` 范式（additive、无 CK schema 变动、双向兼容） |
| `Shared/Models/UsageSnapshot.swift` | `ProviderUsageSnapshot` 加 `public let deepSeekUsage: SyncDeepSeekUsage?`；同步更新：成员声明、`init(...)` 形参、`init(from:)` 的 `decodeIfPresent`、`with(quotaWarnings:)` 透传。**若做请求数**：`SyncCostSummary` 加 `sessionRequests?/last30DaysRequests?/currencyCode?`、`SyncDailyPoint` 加 `requestCount?`、`SyncCostBreakdown` 加 `requestCount?`（各自 init + 自定义 decoder/合成 decoder 保持老 payload 可解） |

> ⚠️ `UsageSnapshot.swift` 的 `ProviderUsageSnapshot` 有**手写** `init(from:)` 与 `with(...)`：加字段时**三处**（成员、init、decoder、with）必须同步，否则编译失败或字段丢失。这是改这文件的唯一陷阱。

### 4.2 Mac bridge（`Sources/CodexBar/Sync/`，fork-owned）

| 文件 | 改动 |
|---|---|
| `SyncCoordinator.swift` | 新增 `static func mapDeepSeekUsage(provider:snapshot:) -> SyncDeepSeekUsage?`（`guard provider == .deepseek, let ds = snapshot?.deepseekUsage`，把瞬态 `DeepSeekUsageSummary` + `DeepSeekUsageSnapshot` 余额映射进来）；在 `buildProviderUsageSnapshot` 的 `return ProviderUsageSnapshot(...)` 里挂 `deepSeekUsage: ...`。**若做请求数**：在 cost summary 映射处带上 requestCount/currency。**审计**（[01 §3](01-design.md)）：`supportsOpus` 闸门 line 535——本次记录为非阻塞，若 CR 决定顺带加固则改为无条件透传 `tertiary` 并补测试 |
| `MockProviderInjector.swift` | deepseek mock 注入 `SyncDeepSeekUsage`；codex mock 加 2 条 Spark lane；antigravity mock 加分模型 lane；claude mock 去掉 Designs（见 [01 §6](01-design.md)） |

### 4.3 iOS（`CodexBarMobile/`，fork-owned）

| 文件 | 改动 |
|---|---|
| `Views/DeepSeekUsageCard.swift` **(新建)** | 仿 `DeepgramUsageCard`：今日/本月 token·cost·requests + 余额 + 30 天迷你柱图 |
| `Views/ProviderDetailView.swift` | `if let ds = provider.deepSeekUsage { DeepSeekUsageCard(ds) }` 派发 |
| `Models/SyncedUsageData.swift` / 解码路径 | 确认新 optional 字段随 `ProviderUsageSnapshot` 自动解码（无需手改，除非有显式字段拷贝点）；检查 `CloudSyncReader.swift:457` 一带重建逻辑是否需带新字段 |
| `Storage/SwiftDataBridge.swift` | 若 DeepSeek 卡需离线持久化新字段，确认 `allRateWindows`/envelope 编码已覆盖（envelope 整体编码则自动覆盖） |
| `Localizable.xcstrings` | DeepSeek 卡新文案 ×4 语（[01 §5](01-design.md)） |
| `ContentView.swift`（`MobileReleaseNotesCatalog`） | 新增 `1.10.0` release notes 块（白话，4 语，见 §6） |
| `Preview Content/PreviewData.swift` | DeepSeek 卡预览数据 |

### 4.4 版本 / 构建

| 文件 | 改动 |
|---|---|
| `version.env` | `MARKETING_VERSION=0.31.0.1` · `BUILD_NUMBER=73.1` · `MOBILE_VERSION=1.10.0` · `UPSTREAM_VERSION=v0.31.0` · `UPSTREAM_SYNC_DATE=2026-05-30` |
| `CodexBarMobile/project.yml` | 三处 `MARKETING_VERSION: "1.10.0"`、`CURRENT_PROJECT_VERSION: "145"`（每 commit +1）；改后 `cd CodexBarMobile && xcodegen generate` |
| `CodexBarMobile/CHANGELOG.md` | 本次技术变更（Added: DeepSeek 卡 / Codex Spark / Antigravity 分模型；Changed: Claude Design 并入；Fixed 透传项） |

---

## 5. 实现顺序（protocol-first，分阶段可构建）

1. **Shared 模型先行**：建 `V030Snapshots.swift` + `UsageSnapshot.swift` 加字段 → `swift build` 绿（此时无人用，纯结构）。
2. **bridge 填充**：`mapDeepSeekUsage` + mock → `SyncModelTests` 往返绿。
3. **iOS 渲染**：`DeepSeekUsageCard` + 派发 + 本地化 → `xcodebuild` + 模拟器冒烟。
4. **自动透传项**：仅加 mock + 跑兼容测试（Spark/Antigravity/Design），无新代码。
5. **可选请求数**：additive 字段 + cost 卡渲染。
6. **版本 bump + 文档 + lint**。

每阶段后 `swift build` / `xcodebuild` 必须绿；关键阶段（合并 A / bridge C / iOS F）后跑 Opus CR loop（项目 memory `CR before package`：清干净再打包）。

---

## 6. Release notes（`MobileReleaseNotesCatalog` 1.10.0，4 语白话）草案

- **"新增 DeepSeek 用量卡：今日/本月 tokens、花费与请求数，外加余额与近 30 天走势。"**
- **"Codex 新增 Spark 模型的 5 小时 / 每周用量条。"**
- **"Antigravity 现按模型逐条显示配额，不再只给汇总。"**
- **"修正企业版 Claude extra-usage 金额显示（此前可能偏高）。"**
- **"Grok / Ollama 进度条按真实周期标注并支持用尽预估。"**

（English 为源，zh-Hans/zh-Hant/ja 同步；Claude Design 行并入主限额属内部变化，不单列用户条目。）

---

## 7. Lint / 自检闸门（提交前）

- `Scripts/lint.sh` i18n 审计：无 `state:"new"`、4 语齐。
- `swift build` + `swift test`（注意 `SyncCoordinatorTests` 并行偶发 flake，项目 memory 记录为非回归——串行复跑）。
- `xcodebuild -scheme CodexBarMobile` 构建 + 模拟器冒烟（mock 全 provider 走查 DeepSeek 卡 + 新 lane）。
- CloudKit 审计（§2.2）写回 `docs/cloudkit-deploy-audit.md` 历史存档。
- 提交后按 CLAUDE.md Post-Commit Checklist：`git push` → Todoist comment(含 commit 链接) → 移 Code Complete。
