# 025 — v0.31.0 上游同步 · 测试文档

**Status:** ready · **Date:** 2026-05-30 · 配套 [00 总体](00-overview.md) / [01 设计](01-design.md) / [02 开发](02-development.md)
**最终版本：** Mac `0.31.0.1`(BUILD 73.1) · iOS `1.10.0`(BUILD 145+) · tag `v0.31.0-mobile.1.10.0` · **完成定义(DONE G1–G10) → [00 总体 ⭐ 节](00-overview.md)**

核心：以 **2 台 Mac + 2 台 iOS** 为基准，**枚举 4 种新旧组合的兼容性场景**，确保各种新旧版本在同一 iCloud 账号下同步都不出问题。外加一个把四台设备全开的并发集成场景（S5）。

---

## 1. 版本基线定义

| 角色 | "旧"（已发布） | "新"（本次 025） |
|---|---|---|
| **Mac 写端** | `v0.29.0-mobile.1.9.0`（BUILD 68.1） | `v0.31.0-mobile.1.10.0`（BUILD 73.1） |
| **iOS 读端** | `1.9.0`（build 144） | `1.10.0`（build 145+） |

**测试设备台账：**

| 设备 | 版本 | 角色 |
|---|---|---|
| **Mac-O** | 旧 `v0.29.0-mobile.1.9.0` | 写端（旧 schema） |
| **Mac-N** | 新 `v0.31.0-mobile.1.10.0` | 写端（新 schema：DeepSeek envelope + Spark/Antigravity lane + 数值修复 +（可选）请求数） |
| **iOS-O** | 旧 `1.9.0` | 读端（旧解码器） |
| **iOS-N** | 新 `1.10.0` | 读端（新解码器：DeepSeek 卡等） |

四台共用**同一 iCloud 账号**（同一 CloudKit 私有库），这样一台 Mac 写、两台 iOS 同时读；两台 Mac 同时写则触发跨设备合并（S5）。

---

## 2. 兼容性契约（被测的根）

依 [01 §1](01-design.md)：全部新数据是 **additive optional 字段 + `decodeIfPresent`**，活在 zlib 压缩 blob 内（`providerPayloadVersion` 不变 = 1）。由此两条契约：

- **前向兼容（新 Mac → 旧 iOS）**：旧解码器遇未知 JSON key 直接忽略；已知字段照常解。
- **后向兼容（旧 Mac → 新 iOS）**：新解码器 `decodeIfPresent` 取 `nil` → 回退通用渲染。

4 个场景就是把这张 2×2 写×读矩阵的每一格各测一遍。

| | iOS-O（旧 1.9.0） | iOS-N（新 1.10.0） |
|---|---|---|
| **Mac-O（旧）** | **S4** 基线 | **S3** 后向兼容 |
| **Mac-N（新）** | **S2** 前向兼容 | **S1** 全新全功能 |

---

## 3. 四种兼容性场景

> 每个场景统一结构：**前置 / 操作 / 关注字段 / 预期 / 通过判据**。被测特性覆盖本次全部 10 项（见 [00 §5](00-overview.md)）。

### S1 · 新 Mac → 新 iOS（全功能基准）

- **前置**：Mac-N 配好 deepseek / codex / antigravity / claude / grok / ollama / alibaba / openai（或用 mock 注入器铺满）。iOS-N 配对同账号。
- **操作**：Mac-N 刷新全 provider → 推 CloudKit → iOS-N 收推送/下拉刷新。
- **关注字段**：`deepSeekUsage`、`rateWindows[]` 中的 `codex-spark*` / antigravity 分模型条、`claudeExtraUsage`、`SyncRateWindow.windowMinutes`、（可选）`SyncCostSummary.requestCount`。
- **预期**：
  - DeepSeek 出现专属卡：今日/本月 tokens·cost·requests + 余额 + 30 天柱图。
  - Codex 详情多出 `Codex Spark 5-hour` + `Codex Spark Weekly` 两条进度条。
  - Antigravity 按模型逐条显示配额（非仅 3 族汇总）。
  - Claude **无** "Designs" 条（已并入主限额），"Daily Routines" 仍在。
  - 企业版 Claude extra-usage 金额币种正确（**非** 100×）。
  - Grok 进度条标 Weekly/Monthly；Ollama 显示配速/用尽预估。
  - （若做）OpenAI/Mistral 成本卡多一行 "N requests" + 正确币种。
- **通过判据**：以上全部可见且数值合理；无崩溃、无空卡、无 "data not aligned" 提示。

### S2 · 新 Mac → 旧 iOS（前向兼容：旧 App 必须不被新字段噎到）

- **前置**：Mac-N 写新 schema；iOS-O 仍是 1.9.0。
- **操作**：Mac-N 刷新 → 推送 → iOS-O 刷新。
- **关注字段**：iOS-O **不认识**的新 key：`deepSeekUsage`、（可选）`requestCount` 系列。iOS-O **认识**的：`rateWindows[]`、`claudeExtraUsage` 等。
- **预期**：
  - iOS-O **正常解码**整个 payload，**忽略** `deepSeekUsage` / `requestCount`（未知 key）——**不崩溃、不丢已知字段**。
  - Codex Spark / Antigravity 分模型 lane **照常显示**——因为它们是通用 `rateWindows[]` 元素，iOS-O 早已 `ForEach(allRateWindows)` 通用渲染（1.9.0 即支持任意条数）。✅ 这是"自动透传"的价值：旧 iOS 也能看到新 lane。
  - DeepSeek 在 iOS-O 上维持 1.9.0 既有呈现（无新卡），无异常。
  - Claude 少一条 Designs，正常。
- **通过判据**：iOS-O 无崩溃、无解码错误日志；新 lane 可见；DeepSeek 退回旧呈现；其它 provider 与 1.9.0 行为一致。

### S3 · 旧 Mac → 新 iOS（后向兼容：新 App 读老数据要优雅降级）

- **前置**：Mac-O 写旧 schema（无 DeepSeek envelope、无 Spark、仍发 Claude Designs）；iOS-N 是 1.10.0。
- **操作**：Mac-O 刷新 → 推送 → iOS-N 刷新。
- **关注字段**：iOS-N 期待但**缺席**的字段：`deepSeekUsage == nil`、无 `codex-spark*` lane、`requestCount == nil`；老 Mac **仍发**的 `claude-design` lane。
- **预期**：
  - DeepSeek 卡**不显示新区**（`deepSeekUsage` 为 nil）→ 回退余额/通用呈现；不显示空卡或占位崩溃。
  - Codex **无** Spark 条（老 Mac 不发）——正常，仅显示既有 5h/weekly。
  - Claude **仍显示** "Designs" 条（老 Mac 还在发它）——iOS-N 通用渲染照常显示，不报错（新 iOS 不会因为"上游已删 Designs"就拒绝渲染一条仍然存在的 lane）。
  - 成本卡无 "requests" 行（`requestCount` nil）。
- **通过判据**：iOS-N 无崩溃；所有"新功能区"在数据缺席时静默隐藏（[01 §4 降级矩阵](01-design.md)）；老数据完整呈现。

### S4 · 旧 Mac → 旧 iOS（基线回归）

- **前置**：Mac-O + iOS-O，皆本次同步前版本。
- **操作**：常规同步。
- **预期**：与 1.9.0 发布时**完全一致**——本场景纯粹用来确认"我们没在共享层引入会影响旧×旧组合的改动"（理论上 blob 内 additive 不该影响，但仍需实测兜底）。
- **通过判据**：行为与 1.9.0 GA 无差异；无新增告警。

---

## 4. S5 · 全混合并发集成（2 Mac + 2 iOS 同时在线，同一账号）

这是用户强调的"两台 Mac + 两台 iOS"拓扑的整合验证——把 S1~S4 四格**同时**观测，并额外压跨设备合并逻辑。

- **前置**：Mac-O + Mac-N **都**登录**同一批 provider 账号**（关键：让两台 Mac 报告**同一个逻辑账号**，例如同一 Codex org、同一 Claude 账号），都开同步；iOS-O + iOS-N 都配对同账号。
- **操作**：两台 Mac 先后/并发刷新；两台 iOS 各自刷新。
- **关注机制**（依 `Research/019` 账号合并、`Research/017` 防幽灵记录）：
  1. **每设备记录隔离**：`DeviceProviderSnapshot` 记录名含 `deviceID`（`"{deviceID}|{providerID}|{email}"`），Mac-O 与 Mac-N 各写各的记录，**不互相覆盖**。
  2. **跨设备账号合并（union-find）**：同一逻辑账号被两台 Mac 报告 → iOS 端按 `accountIdentities` 并成**一张卡**。注意 `accountIdentities` 自 Mac 0.20.3 起发出，**Mac-O(v0.29.0) 与 Mac-N(v0.31.0) 都发** → 合并干净，不应出现重复双卡。
  3. **新旧数据并存取并集**：同一账号卡里，Mac-N 记录带 Spark/DeepSeek，Mac-O 记录没有 → iOS 应呈现**并集 / 最新**（不因为 Mac-O 的旧记录把 Spark 抹掉）。
  4. **无幽灵记录**：在某台 Mac 上登出/移除一个 provider，其记录经 `recordIDsToDelete` 级联删除，iOS 对应数据消失，不残留。
- **预期**：
  - iOS-N：同账号单卡，显示两台 Mac 的并集（含 Spark + DeepSeek + 数值修复）。
  - iOS-O：同账号单卡，显示其能理解的并集（含新 lane，忽略 DeepSeek envelope）。
  - 不出现"同一账号两张卡"、不出现 "data not aligned" 误报、不出现幽灵残留。
- **通过判据**：四台设备各自表现符合 S1~S4 对应格；账号合并为单卡；删除级联生效；反复刷新无抖动/重复。

---

## 5. 单元测试（`CodexBarMobileTests` + 共享 `SyncModelTests`）

| 测试 | 断言 |
|---|---|
| **DeepSeek 往返**（新增） | `SyncDeepSeekUsage` 全字段 encode→decode 相等；`Equatable` 稳定 |
| **DeepSeek 降级**（新增） | 余额字段全 nil（free-tier）仍解码；`daily=[]` 不崩；`todayCost` nil 不崩 |
| **后向：旧 payload → 新类型**（新增/扩充） | 构造**缺** `deepSeekUsage`/`requestCount` key 的 JSON，`ProviderUsageSnapshot.init(from:)` 解出 `nil`，其余字段完好（模拟 S3） |
| **前向：未知 key 容忍** | 含**额外未知** key 的 JSON 解码不抛错（模拟 S2 的对偶——保证未来字段也不噎住当前解码器） |
| **Codex Spark lane 透传** | 给 `extraRateWindows` 注入 `codex-spark*`，经 `buildProviderUsageSnapshot` 后出现在 `rateWindows[]`（验证 bridge line 545 无条件循环） |
| **Claude Designs 缺席** | 不含 Designs 的 snapshot 不产生该 lane；含则产生（覆盖移除前后） |
| **请求数 additive**（若做） | `SyncCostSummary` 带/不带 `requestCount` 均往返正确；老 payload `requestCount=nil` |
| **`supportsOpus` 闸门**（审计） | Codex（`supportsOpus:false`）若仅有 `tertiary` 则被丢弃（记录现状）；Spark 经 `extraRateWindows` 不受影响——断言 Spark 仍在 `rateWindows[]` |
| **回归** | 全量 `swift test`；`SyncCoordinatorTests` 并行偶发 flake（项目 memory：`Index out of range`，非回归）→ 串行复跑确认 |

---

## 6. 真机 / TestFlight（需用户设备与凭证）

- iOS-N 真机装 1.10.0（TestFlight 或 Xcode 直连），Mac-N 出 Sparkle 包，走 S1 全功能真机确认（mock 无法替代真实 CloudKit 推送时序）。
- 至少一台真旧设备或降级构建覆盖 S2/S3 的真实解码（模拟器可，但真机验推送）。
- DeepSeek / 企业版 Claude 若无真实凭证 → mock-only，测试报告标注覆盖缺口（[00 §8 R7](00-overview.md)）。

---

## 7. 回归走查（防 79+ commit 合并副作用，阶段 E）

逐项确认本次"自动透传/数值修复"未误伤既有：
- 既有富卡片：Perplexity / Grok billing / ElevenLabs / Deepgram / Groq / LLMProxy / Claude Admin / MiniMax / OpenRouter / Azure / Alibaba / Bedrock / Moonshot / Kiro / z.ai —— 各开一遍，无空卡/错值。
- 多账号 / 账号合并 / 配额预警 tick / mock 横幅 / 成本分享卡 —— 走查。
- Sparkle 更新路径（旧版 → 新版自更新）。

---

## 8. 通过标准汇总

| 场景 | 必过判据 |
|---|---|
| S1 | 全 10 项新特性在 iOS-N 正确呈现 |
| S2 | iOS-O 不崩、忽略新 envelope、仍显示新通用 lane |
| S3 | iOS-N 不崩、新功能区在数据缺席时静默降级、老数据完整 |
| S4 | 与 1.9.0 GA 行为一致 |
| S5 | 跨设备合并为单卡、取并集、删除级联、无重复/幽灵 |
| 单测 | 全绿（flake 串行复跑确认） |
| 回归 | 既有 provider/功能无退化 |

**任一场景出现崩溃、解码错误、数据丢失、重复卡或幽灵记录 → 阻断发布，任务移回 In Progress 并记 comment。**
