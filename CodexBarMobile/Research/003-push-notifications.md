# 003: Mac→iOS 推送通知

- **Status**: in-progress
- **Created**: 2026-04-01
- **Goal**: Mac 端检测到 session quota 变化（depleted/restored）时，iOS 端即使不在前台也能收到推送提醒

## 背景

用户痛点：iOS 端不打开 App 就不会刷新数据，无法及时获知 session quota 变化。Mac 端已有本地通知能力（`SessionQuotaNotifier`），但 iOS 端完全没有通知功能。

## 调研结论

### Mac 端现有通知系统

| 文件 | 功能 |
|------|------|
| `Sources/CodexBar/AppNotifications.swift` | `UNUserNotificationCenter` 本地通知封装 |
| `Sources/CodexBar/SessionQuotaNotifications.swift` | quota 状态检测 + 通知触发 |
| `Sources/CodexBar/PreferencesGeneralPane.swift:113` | 设置开关 `sessionQuotaNotificationsEnabled` |
| `Sources/CodexBar/UsageStore.swift:520` | `handleSessionQuotaTransition()` 状态变化入口 |

**通知类型**：仅 session quota 两种
- **depleted**: session remaining ≤ 0.01% → `"{Provider} session depleted"`
- **restored**: 从 depleted 恢复 → `"{Provider} session restored"`

**检测逻辑** (`SessionQuotaNotificationLogic.transition()`):
- 阈值：`0.0001` (0.01%)
- `wasDepleted && !isDepleted` → `.restored`
- `!wasDepleted && isDepleted` → `.depleted`

### iOS 端基础设施现状

| 基础设施 | 状态 | 位置 |
|----------|------|------|
| CloudKit entitlements | ✅ 已配置 | `CodexBarMobile.entitlements` |
| `aps-environment` | ✅ 已配置 | `CodexBarMobile.entitlements:17` |
| `UIBackgroundModes: remote-notification` | ✅ 已配置 | `Info.plist:40-43` |
| `CKQuerySubscription` (shouldSendContentAvailable) | ✅ 已创建 | `CloudSyncManager.swift:306-327` |
| remote notification handler | ❌ 缺失 | — |
| UNUserNotificationCenter delegate | ❌ 缺失 | — |
| quota 状态检测 | ❌ 缺失 | — |

**关键发现**：CloudKit 已经在通过 `CKQuerySubscription` 给 iOS 发 silent push，但 iOS 没有任何代码处理它。

### CloudKit 数据流

```
Mac (UsageStore) → SyncCoordinator → CloudKit (DeviceSnapshot)
                                         ↓ CKQuerySubscription
                                    iOS (silent push) → ???（无处理）
```

`DeviceSnapshot` 记录包含 `payload` 字段（JSON 编码的 `SyncedUsageSnapshot`），其中有每个 provider 的 `rateWindows[]`，包含 `remaining` 百分比值。

## 方案选型

### 方案 A：CloudKit Silent Push → 本地通知（选定）

```
Mac → CloudKit → silent push → iOS AppDelegate → fetch snapshot → 检测变化 → 本地通知
```

**优势**：
- 不需要自建服务器，零运维
- CloudKit subscription 基础设施已全部就绪
- 只需 iOS 端补上接收和处理代码

**局限**：
- silent push 到达率受 iOS 系统调度（电池、使用习惯），非 100% 即时
- iOS app 被杀后仍可被 silent push 唤醒，但频率受系统控制

### 方案 B：自建 APNs 服务器（排除）
需要维护服务器，复杂度高，无必要。

### 方案 C：Mac 直接推送给 iOS（不可行）
Apple 不允许设备间直接推送。

## 实施计划

### Step 2: AppDelegate + 远程通知处理
- 新建 `AppDelegate.swift`
- `CodexBarMobileApp.swift` 添加 `@UIApplicationDelegateAdaptor`
- 在 `didReceiveRemoteNotification` 中拉取最新 snapshot 并检测变化

### Step 3: SessionQuotaMonitor
- 新建 `Notifications/SessionQuotaMonitor.swift`
- 复用 Mac 端阈值逻辑（0.0001），iOS 端独立实现
- `lastKnownSessionRemaining` 持久化到 UserDefaults

### Step 4: LocalNotificationManager
- 新建 `Notifications/LocalNotificationManager.swift`
- 通知文案与 Mac 端一致
- 请求通知权限 (.alert, .sound, .badge)

### Step 5: 通知设置 UI
- ContentView.swift Settings 中添加开关
- 4 语言本地化

### Step 6: 文档 + 测试
- 更新 CHANGELOG.md 和 in-app release notes
- 真机测试（模拟器不支持 remote notification）
