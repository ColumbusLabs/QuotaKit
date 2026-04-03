# CodexBar Mobile — 项目计划

> 最后更新：2026-04-01 · 当前版本：1.1.0 (24) · 分支：mobile-dev

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
| Build 21 | **Vibe 赛博朋克分享卡片**：弧形仪表、霓虹风格、深浅主题 | ✅ 已发布 |
| Build 22 | **App Store 截图**：中英文上架截图 | ✅ 已发布 |
| Build 23 | **CloudKit 多设备同步**：KVS→CloudKit、多 Mac 合并、设备 UUID、CKSubscription | ✅ 已发布 |
| Build 24 | **CloudKit Production**：Mac+iOS 均切换至 Production 环境 | ✅ 已发布 |

## 进行中 / 待开发

| 优先级 | 功能 | 状态 | 调研文档 | 备注 |
|--------|------|------|----------|------|
| **P0** | **iOS Build 25 上传 TestFlight** | ✅ done | — | 通知用户 Mac 版已更新 |
| **P0** | **Mac→iOS 推送通知** | ✅ done | [003](CodexBarMobile/Research/003-push-notifications.md) | 3 轮 Codex CR，commit `b5bee234` |
| **P0** | **上游同步到 0.19.0** | `in-progress` | — | 见下方详细计划 |
| P1 | Daily Provider Utilization Chart (Mac) | ✅ done | [001](CodexBarMobile/Research/001-daily-utilization-chart.md) | 通过上游 PR #589 (supersedes #565) 合入解决 |
| P1 | **iOS Subscription Utilization History** | `backlog` | — | Mac 端合并后，iOS 端需单独实现图表 |
| P2 | 分享卡片细节优化 | 待用户反馈 | [002](CodexBarMobile/Research/002-cost-share-card.md) | Build 15 已发布，等真机测试反馈 |

---

## P0: iOS Build 25 → TestFlight

**角色**：Release Engineer · **触发**：上传

仅 bump build number，无代码变更：
1. `CodexBarMobile/project.yml`: `CURRENT_PROJECT_VERSION` 24 → 25（两处）
2. `xcodegen generate` → `xcodebuild archive` → `xcodebuild -exportArchive`

---

## P0: Mac→iOS 推送通知 — 实施计划

### 背景

用户痛点：iOS 端不打开 App 就不会刷新数据，无法及时获知 session quota 变化。Mac 端已有本地通知（`SessionQuotaNotifier`：depleted/restored），但 iOS 端完全没有通知能力。

### 调研结论

**关键发现：CloudKit 已经在发 silent push，但 iOS 完全没处理。**

| 基础设施 | 状态 |
|----------|------|
| CloudKit entitlements (Mac+iOS) | ✅ 已配置 |
| `aps-environment` 推送能力 | ✅ 已配置 |
| `UIBackgroundModes: remote-notification` | ✅ 已配置 |
| `CKQuerySubscription` (shouldSendContentAvailable) | ✅ 已创建 |
| iOS remote notification handler | ❌ **缺失** |
| iOS UNUserNotificationCenter delegate | ❌ **缺失** |
| iOS 端 quota 状态检测逻辑 | ❌ **缺失** |

### 最优方案：CloudKit Silent Push → 本地通知

```
Mac (UsageStore)
  ↓ snapshot 变化
SyncCoordinator → CloudKit (DeviceSnapshot record)
  ↓ CKQuerySubscription 自动触发 silent push
iOS (AppDelegate.didReceiveRemoteNotification)
  ↓ 后台唤醒
fetchAllDeviceSnapshots() → 对比上次状态
  ↓ 检测到 depleted/restored
UNUserNotificationCenter → 本地通知
```

**不需要自建服务器** — CloudKit CKSubscription 已自动推送，只需 iOS 端补上接收+处理。

### 实施步骤

| Phase | 角色 | 内容 | 涉及文件 |
|-------|------|------|----------|
| **Step 1** | Architect | Research 文档 | `Research/003-push-notifications.md` |
| **Step 2** | Developer | AppDelegate + 远程通知处理 | 新建 `AppDelegate.swift`，改 `CodexBarMobileApp.swift` |
| **Step 3** | Developer | Session Quota 状态检测 | 新建 `Notifications/SessionQuotaMonitor.swift` |
| **Step 4** | Developer | 本地通知发送 | 新建 `Notifications/LocalNotificationManager.swift` |
| **Step 5** | Developer | 通知设置 UI + 本地化 | 改 `ContentView.swift`、`Localizable.xcstrings` |
| **Step 6** | Release Engineer | CHANGELOG + in-app notes + 提交 | 改 `CHANGELOG.md`、`ContentView.swift` |

### 关键实现细节

**Step 2: AppDelegate**
```swift
// CodexBarMobileApp.swift
@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

// AppDelegate.swift
func application(_:didReceiveRemoteNotification:) async -> UIBackgroundFetchResult {
    // CloudKit silent push → 拉取最新 snapshot → 检测变化 → 本地通知
}
```

**Step 3: SessionQuotaMonitor**
- 复用 Mac 端 `SessionQuotaNotificationLogic.transition()` 的判断逻辑（阈值 0.0001）
- iOS 端独立实现，不动 Mac 代码
- `lastKnownSessionRemaining` 持久化到 UserDefaults（app 被杀也能保留状态）

**Step 4: 本地通知内容**
- depleted: `"{Provider} session depleted"` / `"0% left. Will notify when it's available again."`
- restored: `"{Provider} session restored"` / `"Session quota is available again."`
- 与 Mac 端通知文案一致

**Step 5: 设置 UI**
- 开关：`"Session quota notifications"` + 4 语言
- 说明：`"Notifies when the 5-hour session quota hits 0% and when it becomes available again."`

### 文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `Research/003-push-notifications.md` | 新建 | 调研文档 |
| `CodexBarMobile/AppDelegate.swift` | 新建 | 远程通知处理 |
| `CodexBarMobileApp.swift` | 修改 | 添加 UIApplicationDelegateAdaptor |
| `Notifications/SessionQuotaMonitor.swift` | 新建 | quota 状态变化检测 |
| `Notifications/LocalNotificationManager.swift` | 新建 | 本地通知管理 |
| `ContentView.swift` | 修改 | 通知设置开关 |
| `Localizable.xcstrings` | 修改 | 4 语言翻译 |
| `CHANGELOG.md` | 修改 | 变更记录 |

### 风险与注意事项

| 风险 | 缓解 |
|------|------|
| silent push 到达率受 iOS 系统调度 | 文档说明：非 100% 即时，受电池和使用习惯影响 |
| 模拟器不支持 remote notification | 必须真机测试 |
| CloudKit 环境必须一致 | Mac+iOS 都用 Production（已确认） |
| 不动 Mac 端代码 | quota 检测在 iOS 端独立实现 |
| 通知权限被拒 | 设置页引导用户到系统设置开启 |

### 测试计划

1. Mac 端手动触发 quota depleted → 验证 iOS 收到通知（真机）
2. iOS app 在后台 → Mac 触发变化 → 验证后台唤醒 + 通知
3. iOS app 被杀 → Mac 触发变化 → 验证仍能收到（系统重启 app 处理 push）
4. 关闭通知开关 → 验证不再推送
5. 多 Mac 场景 → 任意一台 Mac 触发变化 → iOS 收到通知

### 执行顺序

```
任务一（独立，先行）：
  bump build 25 → archive → TestFlight

任务二（顺序执行）：
  Step 1 (Architect) → Step 2-5 (Developer) → Step 6 (Release Engineer)
```

---

## 已完成：CloudKit 多设备同步升级

> 已在 Build 23-24 实现并发布，以下为历史计划记录。

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
| M2: 分享与社交 | Cost 分享卡片 + Vibe 风格 | ✅ 完成（Build 15-21） |
| M3: 多设备同步 | KVS → CloudKit，多 Mac 数据归总 | ✅ 完成（Build 23-24） |
| **M4: 推送通知** | **Mac→iOS quota 变化推送** | **🚧 进行中** |
| M5: 利用率追踪 | 每日 Session 利用率图表 | ⏳ 等上游 PR |
| M6: Widget | 桌面小组件 | 📋 待规划 |
