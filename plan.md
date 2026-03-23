# CodexBar Mobile — 项目计划

> 最后更新：2026-03-23 · 当前版本：1.0.0 (22) · 分支：mobile-dev

## 项目概况

CodexBar Mobile 是 CodexBar（macOS 菜单栏应用）的 iOS 伴侣应用，通过 iCloud 同步展示 AI 编程工具的用量和费用数据。

## 已完成功能

| 版本 | 功能 | 状态 |
|------|------|------|
| Build 9 | iOS 伴侣应用基础架构、iCloud KVS 同步、Provider 卡片、Usage/Cost/Settings 三 Tab | ✅ 已发布 |
| Build 9 | Provider 详情页：交互式日费用图表、Token 统计、预算进度条 | ✅ 已发布 |
| Build 9 | Cost 仪表盘：Provider 占比、Model Mix、Service Mix、30 天趋势图 | ✅ 已发布 |
| Build 9 | 设置页：显示剩余/已用切换、图表样式、隐私遮罩、默认 Tab | ✅ 已发布 |
| Build 9 | 4 语言本地化（en/zh-Hans/zh-Hant/ja） | ✅ 已发布 |
| Build 9 | Onboarding 引导、Demo 模式、空状态页 | ✅ 已发布 |
| Build 10 | 日费用图表横向滚动（30 天 + 历史） | ✅ 已发布 |
| Build 11 | 用量/费用标签清晰度优化（固定宽度布局） | ✅ 已发布 |
| Build 15 | **Cost 分享卡片**：一键生成分享图片（Today/7d/30d）、堆叠柱状图按 Provider 着色、QR 码 | ✅ 已发布 |
| Build 15 | **调研文档框架**：Research/ 目录 + 状态追踪（draft → done → dropped） | ✅ 已发布 |
| Build 15 | **AGENTS.md 工作流**：完整 7 步开发流程定义 | ✅ 已发布 |

## 进行中 / 待开发

| 优先级 | 功能 | 状态 | 调研文档 | 备注 |
|--------|------|------|----------|------|
| **P0** | **CloudKit 多设备同步升级** | `planning` | — | 见下方详细计划 |
| P1 | Daily Provider Utilization Chart | `blocked-upstream` | [001](CodexBarMobile/Research/001-daily-utilization-chart.md) | 等待上游 [PR #565](https://github.com/steipete/CodexBar/pull/565) 合并 |
| P2 | 分享卡片细节优化 | 待用户反馈 | [002](CodexBarMobile/Research/002-cost-share-card.md) | Build 15 已发布，等真机测试反馈 |

---

## P0: CloudKit 多设备同步升级 — 实施计划

### 背景

当前 iCloud 同步使用 NSUbiquitousKeyValueStore（KVS），单 key `com.codexbar.usage.snapshot` 存储整个快照。**Last-write-wins**，不支持多台 Mac 数据归总——后推送的 Mac 覆盖前者的全部数据。

此外，KVS 的 `synchronize()` 返回值不可靠，导致过"实际未同步但 UI 显示已同步"的问题。

### 目标

1. **多 Mac 数据归总** — 两台 Mac（同一 iCloud 账号）的 Provider 数据在 iPhone 上合并展示
2. **准确的同步状态** — Mac 端和 iOS 端都能显示 CloudKit 的具体错误（网络、权限、quota、账号等），杜绝"假已同步"
3. **实时推送** — 通过 CKSubscription 实时通知 iOS，不再依赖 KVS 被动轮询

### 架构设计

```
┌─────────────┐    ┌─────────────┐
│  Mac A      │    │  Mac B      │
│  deviceID:  │    │  deviceID:  │
│  uuid-aaa   │    │  uuid-bbb   │
└──────┬──────┘    └──────┬──────┘
       │                  │
       ▼                  ▼
┌──────────────────────────────────┐
│  CloudKit Private Database       │
│                                  │
│  Record: DeviceSnapshot/uuid-aaa │
│    └─ providers: [Claude, Cursor]│
│                                  │
│  Record: DeviceSnapshot/uuid-bbb │
│    └─ providers: [Claude, Codex] │
└──────────────────┬───────────────┘
                   │ CKSubscription
                   ▼
            ┌─────────────┐
            │  iPhone      │
            │  合并展示：   │
            │  Claude (×2) │
            │  Cursor      │
            │  Codex       │
            └─────────────┘
```

**CloudKit Record Schema:**

| 字段 | 类型 | 说明 |
|------|------|------|
| `recordName` | `String` | = `deviceID`（稳定 UUID） |
| `recordType` | — | `"DeviceSnapshot"` |
| `deviceName` | `String` | 人类可读设备名（如 "MacBook Air"） |
| `deviceID` | `String` | 稳定 UUID（Mac 端生成，持久化到 UserDefaults） |
| `payload` | `Data` (CKAsset/Bytes) | JSON 编码的 `SyncedUsageSnapshot` |
| `appVersion` | `String` | Mac app 版本 |

**iOS 端合并策略:**

- 查询所有 `DeviceSnapshot` record
- 按 `providerID + accountEmail` 去重：同 provider 同账号 → 取 `lastUpdated` 最新的；不同账号 → 并存
- 暴露"来自哪台设备"的信息供 UI 展示

### 涉及文件及改动

#### Phase 0: Shared 模型层（两端的依赖，必须先完成）

| 文件 | 改动 |
|------|------|
| `Shared/iCloud/CloudConstants.swift` | 新增 CloudKit container ID (`iCloud.com.o1xhack.codexbar`)、record type `"DeviceSnapshot"`、移除 KVS 常量 |
| `Shared/Models/UsageSnapshot.swift` | `SyncedUsageSnapshot` 新增 `deviceID: String` 字段，保持 backward-compatible decoding |
| `Shared/iCloud/CloudSyncManager.swift` | 重写为 CloudKit 操作：`pushSnapshot` → `CKDatabase.save(CKRecord)`；`fetchSnapshot` → `CKDatabase.fetch`；`startObserving` → `CKSubscription` + 推送通知；保留 `SyncPushing` protocol 接口不变（Mac 端无感）；新增 `fetchAllDeviceSnapshots() -> [SyncedUsageSnapshot]` 供 iOS 端调用 |

#### Phase 1a: Mac 端（可与 Phase 1b 并行）

| 文件 | 改动 |
|------|------|
| `Sources/CodexBar/Sync/SyncCoordinator.swift` | 生成并持久化稳定设备 UUID（`UserDefaults`）；构建 snapshot 时填入 `deviceID`；推送错误时更新 `lastSyncMessage` 为 CloudKit 具体错误描述 |
| `Sources/CodexBar/Sync/SyncModifier.swift` | 无改动 |
| Mac entitlements | 添加 CloudKit capability：`com.apple.developer.icloud-services = [CloudKit]`，`com.apple.developer.icloud-container-identifiers = [iCloud.com.o1xhack.codexbar]` |

**Mac 端错误展示要求:**

- `lastSyncSucceeded` / `lastSyncMessage` 已有，确保 CloudKit 错误映射到可读文案：
  - `CKError.networkUnavailable` → "网络不可用"
  - `CKError.notAuthenticated` → "iCloud 未登录"
  - `CKError.quotaExceeded` → "iCloud 存储空间不足"
  - `CKError.serverResponseLost` → "服务器响应超时，稍后重试"
  - 其他 → 显示 `localizedDescription`

#### Phase 1b: iOS 端（可与 Phase 1a 并行）

| 文件 | 改动 |
|------|------|
| `CodexBarMobile/iCloud/CloudSyncReader.swift` | 重写：调用 `fetchAllDeviceSnapshots()`，返回 `[SyncedUsageSnapshot]`；新增合并逻辑（按 providerID + accountEmail 去重）；监听 CKSubscription 推送通知 |
| `CodexBarMobile/Models/SyncedUsageData.swift` | `snapshot` → `mergedSnapshot`（合并后的结果）；新增 `deviceSnapshots: [SyncedUsageSnapshot]`（原始各设备数据）；错误状态精确化：`lastSyncError` 显示 CloudKit 具体错误而非通用文案；新增 `syncStatus: SyncStatus` 枚举（`.synced(ago:)` / `.syncing` / `.error(message:)` / `.notConfigured`） |
| iOS entitlements | 添加 CloudKit capability（同 Mac） |
| `CodexBarMobile/project.yml` | 添加 CloudKit entitlement + background remote notification capability |

**iOS 端错误展示要求:**

- Settings 页面显示精确同步状态，不再只有"已同步"/"未同步"
- 错误场景映射：
  - CloudKit 请求失败 → 显示具体原因（网络、账号、quota）
  - 查询到 0 条 record → "未找到 Mac 端数据，请确认 Mac 上已开启 iCloud 同步"
  - Record 解码失败 → "数据格式不兼容，请更新 Mac 端 CodexBar"
  - 长时间未更新（>1h） → 在 syncAge 旁显示警告色

#### Phase 2: 向后兼容 & 迁移

| 内容 | 说明 |
|------|------|
| 过渡期 KVS fallback | iOS 端先查 CloudKit，无数据时 fallback 读 KVS（兼容旧版 Mac app）|
| Mac 端双写 | 过渡期同时写 CloudKit + KVS（兼容旧版 iOS app），后续版本移除 KVS 写入 |
| 清理时机 | 确认两端都升级后，下一个大版本移除全部 KVS 代码 |

#### Phase 3: 测试

| 测试文件 | 覆盖范围 |
|----------|----------|
| `CodexBarMobileTests/SyncModelTests.swift` | `SyncedUsageSnapshot` 新增 `deviceID` 的 encode/decode 兼容性；旧 JSON（无 deviceID）仍可正常 decode |
| `CodexBarMobileTests/CloudKitMergeTests.swift` （新建）| 多设备合并逻辑：同 provider 同账号去重取最新；同 provider 不同账号并存；单设备场景退化为原有行为；空 record 列表处理 |
| `CodexBarMobileTests/SyncErrorTests.swift` （新建）| 错误场景：网络不可用时的状态；CloudKit 账号变更；quota 超限；record 解码失败（格式不兼容）；长时间未同步的 UI 状态 |
| Mac 端测试 | `SyncCoordinator` 已有 `SyncPushing` protocol mock，补充：push 失败时 `lastSyncMessage` 包含具体错误；`deviceID` 稳定性（重启后不变） |

### 并行执行策略

```
Phase 0 (Shared 模型层)     ──── 必须先完成 ────┐
                                                │
                              ┌─────────────────┤
                              ▼                 ▼
                     Phase 1a (Mac 端)   Phase 1b (iOS 端)
                              │                 │
                              └────────┬────────┘
                                       ▼
                              Phase 2 (向后兼容)
                                       │
                                       ▼
                              Phase 3 (测试)
```

- Phase 1a 和 1b **可并行**：接口契约由 Phase 0 定义的 CloudKit record schema 保证，无文件重叠
- Phase 2 依赖两端都完成
- Phase 3 的测试可与 Phase 1 部分并行编写（mock 测试不依赖真实 CloudKit）

### 风险

| 风险 | 缓解 |
|------|------|
| CloudKit 需要 App Store provisioning profile 有 CloudKit entitlement | 在 Apple Developer Portal 确认 container 已创建 |
| CloudKit 开发环境 vs 生产环境 schema 需要部署 | 开发阶段用 Development environment，发布前通过 CloudKit Dashboard 部署到 Production |
| 旧版 Mac app 用户不会立即升级 | Phase 2 双写 + KVS fallback 保证过渡期兼容 |
| CKSubscription 需要 iOS 后台推送权限 | project.yml 添加 background remote notification |

## 待调研 / 候选功能

| 功能想法 | 说明 |
|----------|------|
| Widget（桌面小组件） | 显示当日/当周费用摘要 |
| Provider 对比视图 | 多 Provider 费用趋势叠加对比 |
| 费用预算预警推送 | 本地通知：月预算超 80% 时提醒 |
| 深色模式分享卡片 | 当前分享卡片仅白底，可增加深色风格 |
| iPad 适配 | 利用更大屏幕展示更丰富的图表 |

## 技术债 / 改进

| 项目 | 说明 |
|------|------|
| 分享卡片数据桥接 | 7 天 provider 费用目前按 30 天比例缩放，非精确每日 provider 分拆 |
| UI 测试覆盖 | 分享功能尚无 UI 测试 |
| 上游同步 | 当前基于 0.18.0，上游已推进到 0.19.0+ |

## 里程碑

| 里程碑 | 目标 | 状态 |
|--------|------|------|
| M1: App Store 初版 | iOS 伴侣应用上架 | ✅ 完成（Build 9） |
| M2: 分享与社交 | Cost 分享卡片 | ✅ 完成（Build 15） |
| M3: 利用率追踪 | 每日 Session 利用率图表 | ⏳ 等上游 PR |
| M4: Widget | 桌面小组件 | 📋 待规划 |
| **M5: 多设备同步** | **KVS → CloudKit，多 Mac 数据归总** | **📋 规划中** |
