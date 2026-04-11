# 004: Mac→iOS 推送通知（CloudKit alert push 方案）

- **Status**: research-complete, awaiting plan approval
- **Created**: 2026-04-08
- **Supersedes**: [003-push-notifications.md](003-push-notifications.md)
- **Goal**: Mac 端检测到 quota 变化时，iOS 收到一条**用户可见的本地化通知**，**不要求 Background App Refresh**，**不需要 app 唤醒跑代码**，**不需要服务端**

## 为什么换方案

[003 文档](003-push-notifications.md) 用的是 silent push (`shouldSendContentAvailable=true`)，必须 wake app → fetch → 算 transition → post local notification。这条架构在生产中被验证不可行：

1. iOS 强制要求 Background App Refresh
2. 即便开了，iOS 系统按节流策略静默丢弃 silent push
3. 链路过长（5+ 环），任何一环失败整条断

新方案的核心改变：**让 CloudKit 服务端直接告诉 APNs"弹这条文案给用户"，iOS 系统在 APNs 层直接弹，app 不需要醒，跟 Instagram 推送的交付模型完全一致。**

## CloudKit alert push 工作原理（多源交叉验证）

### 关键事实 1：alert push vs silent push 是两条独立路径

来源：[Apple `CKSubscription.NotificationInfo` 官方文档](https://developer.apple.com/documentation/cloudkit/cksubscription/notificationinfo-swift.class)

> "If you don't set any of the **alertBody, soundName, or shouldBadge** properties, CloudKit sends the push notification using a lower priority and doesn't display any content to the user."

也就是说：
- **设了 `alertBody`/`alertLocalizationKey`/`soundName`/`shouldBadge` 任一** → CloudKit 走高优先级 alert push 路径，APNs 把通知直接交给 iOS 系统弹出
- **全部不设，只设 `shouldSendContentAvailable=true`** → CloudKit 走低优先级 silent push 路径（就是我们之前的废弃路径）

### 关键事实 2：alertBody 由 iOS 系统直接显示，app 不需要醒

来源：[`alertBody` 官方文档](https://developer.apple.com/documentation/cloudkit/cksubscription/notificationinfo-swift.class/alertbody)

> "Set this property's value to have the system display the specified string when it receives the corresponding push notification."

"system displays" = iOS 系统层直接显示。app 不需要 awake，不需要 didReceiveRemoteNotification 处理。

来源：[Apple Local and Remote Notification Programming Guide](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/) (linked from CKSubscription.NotificationInfo class doc)

> "A regular push notification notifies the user by displaying a message, making a sound, or badging the application icon, and they show up in Notification Center and on the device's Lock Screen."

iOS 接收到 alert push 后由 SpringBoard / NotificationCenter 直接显示，**完全不依赖 app 是否在运行 / 后台**。这跟 Instagram / 微信 / Twitter 的可见 push 是同一条 API 路径。

### 关键事实 3：`titleLocalizationArgs` 是 record 字段名引用

来源：[`titleLocalizationArgs` 官方文档](https://developer.apple.com/documentation/cloudkit/cksubscription/notificationinfo-swift.class/titlelocalizationargs)

```
var titleLocalizationArgs: [CKRecord.FieldKey]? { get set }
```

> "This property is an array of field names that CloudKit uses to extract the corresponding values from the record that triggers the push notification. The values must be strings, numbers, or dates. Don't specify keys that use other value types. CloudKit may truncate strings with a length greater than 100 characters when it adds them to a notification's payload."

> "If you use `%@` for your substitution variables, CloudKit replaces those variables by traversing the array in order. If you use variables of the form `%n$@`, where `n` is an integer, `n` represents the index..."

也就是说：
- `titleLocalizationKey` = iOS Localizable.strings 里的 key（如 `"Push.QuotaDepleted"`），由 iOS 设备的当前语言解析
- `titleLocalizationArgs = ["providerName"]` = CloudKit 在 push 时**从触发的 record 抽 `providerName` 字段值**填进模板的 `%@`
- 同样的逻辑适用于 `alertLocalizationArgs` / `subtitleLocalizationArgs`

**这意味着 Mac 端写 record 时不需要知道 iOS 端语言**，只需要往 record 字段里写入"Codex"、"Claude"等不需要本地化的标识。本地化在 iOS 设备根据自己的 locale 完成。

### 关键事实 4：alert push 需要用户授权 `UNAuthorizationOptions.alert`

来源：fluffy.es CloudKit 推送教程 + Apple `UNUserNotificationCenter` 文档

> "Your application doesn't need to request the user's explicit permission to receive silent notifications. However, because regular push notifications are visible to the user, applications need to ask the user for permission."

iOS 端需要：
1. `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])`
2. `UIApplication.shared.registerForRemoteNotifications()`

用户拒绝 → 不显示通知（标准 iOS 通知行为）。这是用户预期内的体验。

### 关键事实 5：CKQuerySubscription 在 private DB **custom zone** 上工作

来源：[Apple `CKQuerySubscription` 官方文档](https://developer.apple.com/documentation/cloudkit/ckquerysubscription) example code

```objc
subscription.zoneID = recordZone.zoneID;
```

Apple 的 example 代码显式设 `zoneID = customZone.zoneID`。这跟 003 文档调研结果一致——CKQuerySubscription **必须**用在 custom zone，default zone 不可靠。

我们的 `DeviceSnapshotsZone` custom zone 在 1.2.0 build 41 中**保留**（数据同步路径还在用），可以**复用**给新 `QuotaTransition` record type，不需要再做一次 zone migration。

### 关键事实 6：subscription 是账号级，多设备自动覆盖

CloudKit subscription 注册在 user iCloud account 的 private DB 上，**APNs 投递目标 = 该账号下所有装了此 app 且注册过 remote notification 的设备**。

含义：
- 用户只有 1 部 iPhone：iOS 在 first launch 创建 subscription，CloudKit 之后所有 push 都到这部 iPhone
- 用户 2 部 iPhone（如手机 + iPad）：两部各自 first launch 时都调 setupSubscription（CloudKit 用 subscriptionID 去重），两部都收到 push
- 用户切 iCloud 账号：subscription 还在原账号的 private DB，但新账号下 iOS app 没 subscription → 需要 iOS app 在 account 切换时检测并重新创建（CKContainer.accountChangedNotification 处理）

## 设计

### 数据流

```
Mac 端 SessionQuotaNotifier.post(transition:provider:)
    ↓ (现有代码 — 已发本地通知给 Mac 用户)
    ↓ 新增分支
SyncCoordinator.writeQuotaTransition(provider:state:)
    ↓
CloudKit private DB / DeviceSnapshotsZone / QuotaTransition record
    ↓ CKQuerySubscription with predicate (state="depleted") fires
APNs Production
    ↓ (alert payload with titleLocalizationKey + alertLocalizationArgs from record)
iPhone NotificationCenter
    ↓ (iOS 系统层直接 display, app 不需要醒)
🔔 用户看到 "Codex session depleted"
```

### Record schema：`QuotaTransition`

新增 record type，住在 **`DeviceSnapshotsZone`**（已有的 custom zone，复用）。

| 字段 | 类型 | Queryable | 说明 |
|---|---|---|---|
| `providerName` | String | ✓ | 用户可见的 provider 名（"Codex"、"Claude"），不需要本地化 |
| `state` | String | ✓ | `"depleted"` 或 `"restored"`（不本地化，纯枚举值，作为 subscription predicate 过滤用） |
| `transitionAt` | Date | ✓ Sortable | 事件时间，去重 + 排序 |
| `deviceID` | String | ✓ | 哪台 Mac 写的，供未来去重逻辑使用 |

`recordName` 用 `"\(deviceID)-\(provider)-\(state)-\(hourBucket)"` 这种确定性 key，让同一小时内同设备同 provider 的同状态写入是 idempotent overwrite，避免大量重复 push。

### Subscription 设计

iOS app 在 first launch 创建 **2 条 CKQuerySubscription**，作用域 `DeviceSnapshotsZone`：

#### Subscription 1: depleted

```swift
let subscription = CKQuerySubscription(
    recordType: "QuotaTransition",
    predicate: NSPredicate(format: "state == %@", "depleted"),
    subscriptionID: "quota-transition-depleted",
    options: [.firesOnRecordCreation])
subscription.zoneID = customZone.zoneID

let info = CKSubscription.NotificationInfo()
info.titleLocalizationKey = "Push.QuotaDepleted.title"  // "%@"
info.titleLocalizationArgs = ["providerName"]
info.alertLocalizationKey = "Push.QuotaDepleted.body"    // "Session depleted"
info.alertLocalizationArgs = []
info.soundName = "default"  // 必须设否则 CloudKit 不当作 visible push
subscription.notificationInfo = info
```

#### Subscription 2: restored

跟 1 一样，predicate 改 `"restored"`，subscriptionID 改 `"quota-transition-restored"`，localization key 改 `Push.QuotaRestored.*`。

### Localization keys

iOS `Localizable.xcstrings` 新增：

| key | en | ja | zh-Hans | zh-Hant |
|---|---|---|---|---|
| `Push.QuotaDepleted.title` | `%@` | `%@` | `%@` | `%@` |
| `Push.QuotaDepleted.body` | `Session depleted` | `セッション枠を使い切りました` | `会话额度已耗尽` | `工作階段額度已耗盡` |
| `Push.QuotaRestored.title` | `%@` | `%@` | `%@` | `%@` |
| `Push.QuotaRestored.body` | `Session restored` | `セッション枠が復活しました` | `会话额度已恢复` | `工作階段額度已恢復` |

iPhone 收到通知后会显示成（en 系统）：

> **Codex**
> Session depleted

或（zh-Hans 系统）：

> **Codex**
> 会话额度已耗尽

### iOS 端代码量

**新增**：
- `QuotaTransitionSubscriptionSetup.swift`（~60 行）：first launch 创建 2 条 subscription，self-healing fetch-first 模式（验证 server 状态后再决定 create / no-op / recreate）
- iOS App 加 `requestAuthorization` + `registerForRemoteNotifications` + `UNUserNotificationCenterDelegate.willPresent`（~30 行）

**净删**（相对于 1.2.0 build 41 之前的版本）：
- `AppDelegate.swift`、`SessionQuotaMonitor.swift`、`LocalNotificationManager.swift`、`PushDiagnosticStore.swift`、`PushDiagnosticView`（~700 行总计，build 41 已经删完）
- 不需要 `MobileSettingsKeys.sessionQuotaNotificationsEnabled`（subscription 是否存在 = 用户是否想收）

### Mac 端代码量

**新增**：
- `Sources/CodexBar/Sync/QuotaTransitionWriter.swift`（~50 行）：`SessionQuotaNotifier.post()` 之后顺手往 CloudKit 写 `QuotaTransition` record
- `Shared/iCloud/CloudSyncManager.swift` 加 `writeQuotaTransition(...)` 方法

**已删**（1.2.0 build 41）：
- `MacPushDiagnostics.swift`、`PreferencesMobilePane` 的 DEV section、`pushTestSnapshot`、`notificationPushToiOSEnabled` setting

## 风险与边界条件

### 风险 1：CloudKit Production schema 部署

新加 `QuotaTransition` record type 需要：
1. 本地 build → CloudKit 自动在 Development 创建 schema
2. 用户在 CloudKit Dashboard 手动 deploy 到 Production
3. `state` 字段必须 Queryable（否则 predicate 失效）

**缓解**：在 plan 里写明这一步是"手动 dashboard 操作"，build 验证 + 上传前要求用户确认部署。

### 风险 2：CloudKit Production 部署窗口

Schema deploy 后，CloudKit Production 上的旧版 iOS 客户端（build 38/39/40）如果还在跑会查不到新 record type → 返回 schema mismatch error。

**缓解**：1.2.0 build 41 已经没人用 push subscription，不会查 QuotaTransition。Plan B 在 build ≥ 42 才出现，那时所有用户已经升级。**没有兼容性问题。**

### 风险 3：通知节流

Mac 端如果某段时间内 quota 抖动剧烈（depleted → restored → depleted → ...），会写大量 record → 触发大量 push → 用户被骚扰。

**缓解**：
- Mac 端 `QuotaTransitionWriter` 加 **debounce**：同 (provider, state) 在 5 分钟内只写一次
- recordName 用 `"\(deviceID)-\(provider)-\(state)-\(hourBucket)"`，同小时内同设备 idempotent

### 风险 4：用户拒绝通知权限

第一次启动 iOS app 弹权限请求，用户拒绝 → subscription 创建后服务端有 push 但 iOS 不显示。

**缓解**：
- 在 Settings 里加一个 "Enable quota notifications" 入口，点了之后跳到系统设置（标准 iOS 模式）
- 不在 first launch 立即弹权限对话框（用户可能还没了解功能），改成在 Cost / Usage 页面 quota 第一次变化时弹（contextual）。**这个延后弹的策略需要在 plan 里定**。

### 风险 5：iCloud 账号切换

用户在 iPhone 上切 iCloud 账号 → subscription 还在旧账号的 private DB → 新账号下没 subscription → 不收 push。

**缓解**：iOS 端监听 `CKContainer.accountChangedNotification`，账号切换时强制重建 subscription。

### 风险 6：多 Mac 写入并发

两台 Mac 同时检测到相同 provider 同时 depleted → 同时写 record → 触发两次 push。

**缓解**：recordName 的 `hourBucket` 让它们 idempotent overwrite（同一小时内只生成一个 record）。CloudKit subscription firesOnRecordCreation 只 fire 一次（第二次写是 update 不是 create）。

### 风险 7：APNs 投递不是 100% 保证

Apple 官方声明 APNs 是 best-effort，不承诺 100% 投递。但 alert push 比 silent push 可靠得多——alert push 是给真实用户看的，APNs throttle 策略宽松很多。

**缓解**：接受这个事实。v1 不做 fallback。如果未来有持续丢失反馈，再加 retry / fallback 机制。

### 风险 8：subscription 在 CloudKit Production 上要先存在

iOS app 第一次启动调 `modifySubscriptions(saving:)`，CloudKit 会验证 record type / fields / zoneID 都存在。如果 schema 没 deploy 到 Production，subscription 创建失败。

**缓解**：plan 的执行顺序里写明——schema deploy 到 Production **必须在** iOS app 上 TestFlight **之前**完成。

## 与 003 方案的对比

| 维度 | 003 silent push | 004 alert push（本方案）|
|---|---|---|
| Background App Refresh | 必须开 ❌ | 不需要 ✅ |
| 用户授权 | 不需要 | 需要 `.alert` |
| iOS app 是否要 wake | 是 ❌ | 否 ✅ |
| 文案决定者 | iOS 客户端 | CloudKit 服务端（从 record 字段读）|
| 投递可靠性 | iOS 系统激进 throttle ❌ | APNs best-effort ~99% ✅ |
| 客户端代码量 | ~700 行（5 个文件 + AppDelegate）| ~90 行（subscription setup + 通知 delegate）|
| 服务端 | 不需要 | 不需要 ✅ |
| Mac 端额外工作 | 大（diagnostic、test buttons）| 小（一个 record writer）|
| 本地化 | 客户端算 | iOS 系统从 Localizable.xcstrings 解析 |
| 多 iPhone | 自动支持 | 自动支持 |
| 切 iCloud 账号 | 同样问题 | 加 accountChangedNotification 监听 |
| 节流抖动控制 | 客户端 baseline 比对 | Mac debounce + recordName idempotent |

## 参考来源

- [Apple `CKSubscription.NotificationInfo`](https://developer.apple.com/documentation/cloudkit/cksubscription/notificationinfo-swift.class)
- [Apple `alertBody` doc](https://developer.apple.com/documentation/cloudkit/cksubscription/notificationinfo-swift.class/alertbody)
- [Apple `shouldSendContentAvailable` doc](https://developer.apple.com/documentation/cloudkit/cksubscription/notificationinfo-swift.class/shouldsendcontentavailable)
- [Apple `titleLocalizationArgs` doc](https://developer.apple.com/documentation/cloudkit/cksubscription/notificationinfo-swift.class/titlelocalizationargs)
- [Apple `CKQuerySubscription`](https://developer.apple.com/documentation/cloudkit/ckquerysubscription) (zoneID example)
- [Apple `CKNotification`](https://developer.apple.com/documentation/cloudkit/cknotification)
- [Apple Local and Remote Notification Programming Guide](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/)
- [Hacking with Swift CKQuerySubscription tutorial](https://www.hackingwithswift.com/read/33/8/delivering-notifications-with-cloudkit-push-messages-ckquerysubscription)
- [fluffy.es CloudKit push notification tutorial](https://fluffy.es/push-notification-cloudkit/)
- [Cocoacasts: Five Reasons CloudKit Notifications Are Not Arriving](https://cocoacasts.com/five-reasons-cloudkit-notifications-are-not-arriving)
- [Filip Němeček: How to setup CloudKit subscription](https://nemecek.be/blog/31/how-to-setup-cloudkit-subscription-to-get-notified-for-changes)
- [`apple/sample-cloudkit-privatedb-sync`](https://github.com/apple/sample-cloudkit-privatedb-sync)
