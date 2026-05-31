# 025 — v0.31.0 上游同步 + iOS 1.10.0 · 总体文档

**Status:** ready
**Date:** 2026-05-30
**Target release tag:** `v0.31.0-mobile.1.10.0`
**Branch:** `upstream-sync/v0.31.0-mobile.1.10.0`
**文档集:** 本目录共 4 份 —
[00 总体](00-overview.md) · [01 设计](01-design.md) · [02 开发+架构](02-development.md) · [03 测试](03-testing.md)

---

## ⭐ 最终目标版本号（锁定）+ 完成确认

> 本目标的**验收锚点**。每轮循环结束都对照此处：版本号是否 stamp 对、DONE 是否全勾。
> 只有下方版本号已落定 **且** G1–G10 全部勾选，才可对用户宣告"全部工作已完成"。

**最终版本号（达成时必须 stamp 成这些值）：**

| 端 | 最终版本 | 落点文件 |
|---|---|---|
| **Mac** | MARKETING `0.31.0.1` · BUILD `73.1` · UPSTREAM `v0.29.0`→`v0.31.0`（**发布时才 bump**，见 Round 1 发现 F1） | `version.env` |
| **iOS** | MARKETING `1.10.0` · BUILD `145`+ · MOBILE_VERSION `1.10.0` | `CodexBarMobile/project.yml` + `version.env` |
| **Sparkle / Release tag** | `sparkle:version` `73.1.1.10.0` · tag `v0.31.0-mobile.1.10.0` | appcast / GitHub release |

> 完整对照与决策依据见 [§6 版本目标](#6-版本目标依-docsversioningmd)；命名规则见 `docs/versioning.md`。

**完成确认（DONE —— 全部勾选才算"全部工作完成"）：**

- [x] **G1 · Mac 合并**：`git merge v0.31.0` 干净、`swift build` 绿（22s）、10 冲突全解 — 提交 `f8644d4c`（2026-05-30）
- [x] **G2 · 后台/数据结构**：`SyncDeepSeekUsage` envelope 落地（`V030Snapshots.swift` + `ProviderUsageSnapshot.deepSeekUsage` + `SyncCoordinator.mapDeepSeekUsage`）；`swift build` 绿。请求数 additive 延后（fast-follow，D2）
- [ ] **G3 · 自动透传验证**：Codex Spark / Antigravity 分模型 lane 在 iOS 正确显示
- [ ] **G4 · 数值修复验证**：Claude 100× / Grok / Ollama / Alibaba / OpenAI 数值与标签正确
- [x] **G5 · iOS 前端**：`DeepSeekUsageCard` + `ProviderDetailView` 派发 + 4 语 xcstrings；`xcodebuild -sdk iphonesimulator` 编译通过
- [ ] **G6 · 测试**：4 种兼容性场景 + S5 全过；单测绿；回归无退化
- [ ] **G7 · Code Review**：关键阶段（合并 A / bridge C / iOS F）Opus CR loop 清干净
- [x] **G8 · 版本号 stamp**：`version.env`（R1）+ `project.yml` MARKETING 1.10.0 / BUILD 145；`xcodegen` 已重生成 .xcodeproj
- [ ] **G9 · CloudKit 审计**：deploy 判定已记录（本次预判：**无需** Prod schema deploy）
- [ ] **G10 · 发布（Definition of Done）**：签名公证 + iOS TestFlight + Sparkle appcast，发到用户手里

**当前进度：4 / 10（G1/G2/G5/G8 ✓；G3/G6 wire 层完成待 sim 可视化）—— 下一步：G3 sim 可视化 + G4 数值验证 + G6 回归 + G9 审计 + G7 CR。**

> ⚠️ 任一项未达成即视为未完成；不得以 "commit/push 了" 充当 G10。进度计数随开发推进在本块实时更新。

**`/goal` 自动循环完成条件**（设进 Claude Code 的 `/goal`，它每回合自动复检、没满足就再开一轮；G10 发布属用户 Mac 手动环节不计入）：

```text
/goal v0.31.0 同步达到「可发布前完成态」，且以下每项都在本会话对话中由命令输出或文件内容证明，
并且四份文档 00–03 已被回写到与代码一致（对话中有对应 Edit）：
(1) git merge v0.31.0 完成、git status 干净；
(2) swift build 退出 0、xcodebuild -scheme CodexBarMobile 构建成功；
(3) swift test 全绿（含 DeepSeek 往返 + 缺字段解码 + 4 兼容性场景对应单测）；
(4) DeepSeekUsageCard 已实现并在 ProviderDetailView 派发；Codex Spark / Antigravity lane 经 rateWindows 透传；
(5) Scripts/lint.sh 通过、xcstrings 新文案 4 语齐、无 state:"new"；
(6) version.env = MARKETING 0.31.0.1 / BUILD 73.1 / MOBILE 1.10.0 / UPSTREAM v0.29.0（发布前不 bump，F1）；project.yml = 1.10.0 / 145；
(7) 本 ⭐ 节 DONE 计数 = 9/10（G1–G9 勾选）、四份文档「修订记录」已更新到本轮；
(8) 最近一轮做过防回归复验且通过（对话中有 build+test 重跑证据，4 兼容性场景未回退）。
到 9/10 即停并交回用户；或在 40 回合后停止并汇报当前 X/10。
```

---

## 1. 一句话目标

把上游 `steipete/CodexBar` 从 **v0.29.0 → v0.31.0** 跨度内（即 `v0.29.1 / v0.30.0 / v0.30.1 / v0.31.0` 四个 tag）**所有用户可见的显示数据**，同步到我们 fork 的 Mac 端与 iOS 端，**一次合并发布**（Mac Sparkle + iOS TestFlight），不拆分。

宗旨（PM 指令）：**只要 Mac 端新增的显示内容 iOS 能显示，就全部保留；尽可能多同步，哪怕只是多同步一点数据；除非与现有基础架构完全冲突才考虑放弃或调整。**

---

## 2. 当前状态 / 起点

| 维度 | 当前值 | 来源 |
|---|---|---|
| 已对齐上游 tag | `v0.29.0` | `version.env: UPSTREAM_VERSION` |
| 上次同步日期 | 2026-05-25 | `version.env: UPSTREAM_SYNC_DATE` |
| Mac MARKETING_VERSION | `0.29.0.1` | `version.env` |
| Mac BUILD_NUMBER | `68.1` | `version.env` |
| MOBILE_VERSION | `1.9.0` | `version.env` |
| iOS project.yml | MARKETING `1.9.0` / BUILD `144` | `CodexBarMobile/project.yml` |

**关键背景：** 上一份同步文档 [`Research/023-v029-upstream-sync-ios-190.md`](../023-v029-upstream-sync-ios-190.md) 当时**明确把 0.29.1 的修复"延期到下一次 sync"**（原文 §Scope boundary 列了 #1114 / #1148 / #1112 / #1102 / zh-Hant / #1143）。**本次 025 就是承接那次延期**，所以范围从 0.29.1 起算，而非 0.30.0。

---

## 3. 范围

**纳入（v0.29.0 之后、v0.31.0 及之前）：**
- `v0.29.1`（023 延期项）
- `v0.30.0`
- `v0.30.1`
- `v0.31.0`

**边界提示（不要重复算）：** 上游 changelog 里挂在 0.29.0 标题下的 "Alibaba Token Plan 接入 #1098"、"OpenCode 续期日 #1099"、"Codex std/fast 拆分 #1070" 三项，落在 `v0.28.0..v0.29.0` 区间，**已在 023/1.9.0 处理过**，本次不重复。

---

## 4. 上游逐版本变更摘要（仅列与 iOS 显示相关者）

> 完整字段级证据见 [01 设计文档 §2](01-design.md) 与子调研报告。下面是高层摘要。

### v0.29.1
- **Claude OAuth extra-usage 金额从 minor units 归一化**（#1114）— 企业版 extra-usage 之前显示成 100×。**数值修复**。
- **Grok reset 窗口标注**（#1148）— 用真实账单窗口给进度条贴标签（Weekly/Monthly），`windowMinutes` 由 nil → 真实值。**数值修复 + 一个派生字段**。
- 其余（Claude CLI 2.1 订阅识别 #1121、OpenCode Go 本地用量 #1021、Groq 图标 #1112、菜单栏恢复等）— 数据源/可靠性/Mac UI，**无新显示字段**。

### v0.30.0
- **DeepSeek web-session 用量 + 成本摘要**（#1166）— **新结构体 `DeepSeekUsageSummary` + 核心新字段 `UsageSnapshot.deepseekUsage`**。本次唯一真正的新富数据。
- **Antigravity 完整分模型配额**（#1139）— 把全部 `modelQuotas` 作为 `extraRateWindows` 暴露（之前只给 3 族汇总）。**经现有容器透传**。
- **OpenAI / Mistral 走共享成本卡 + OpenAI 请求数**（#1163）— 共享成本模型新增 `requestCount` / `currencyCode` / `historyLabel` 等字段。
- **OpenAI Admin API project 限定**（#1168）— 新字段 `projectID`，以 `loginMethod:"Admin API: <id>"` 形式呈现。
- **Ollama 配速投影**（#1136）— 新字段 `sessionWindowMinutes`，session/weekly 的 `windowMinutes` 由 nil → 真实值，使配速可算。
- **Alibaba 改 Bailian 订阅摘要端点**（#1142）— 快照结构不变，**数值/数据源修正**。
- "tertiary 行" widget 化（#1160）、z.ai 5h tertiary（#00905b52）— `tertiary` 字段早在 v0.29.0 就存在，**这是 widget UI 化，非新数据字段**。

### v0.30.1
- **无新显示数据字段。** 两条修复（Claude OAuth 429 处理 #1179、MiniMax 通用诊断导出）属可靠性与 CLI-only。

### v0.31.0
- **Codex Spark 模型专属用量作为额外配额 lane**（#1195 / #1201）— 经现有 `extraRateWindows` 容器透传：`codex-spark`（5 小时）+ `codex-spark-weekly`（每周）两条具名 lane。**新数据、现有容器**。
- **Claude "Design" 配额 lane 移除**（#1197）— 现并入主 Claude 限额；上游删除 `sevenDayDesign` 与 "Designs" lane。**数据移除**（fork 侧：停止预期/渲染它）。
- 其余（Bedrock AWS profile 凭证 #1190、Spark 扫描可取消、瑞典语/葡语本地化、弹窗本地化）— 凭证/本地化/性能，**无新显示字段或不适用 iOS 4 语策略**。

---

## 5. 完整特性清单 → 同步路径 → fork 工作量

> 这是全局最重要的一张表。**三条同步路径**：
> **(A) 通用 lane 自动透传** = 进入动态数组 `ProviderUsageSnapshot.rateWindows[]`，iOS `ProviderUsageView` 已用 `ForEach(allRateWindows)` 通用渲染，**零 schema、零视图改动**；
> **(B) 数值修复自动透传** = 合并上游后纠正值经现有字段/envelope 流过；
> **(C) 新 envelope 块** = 新增 optional `SyncXxx` 字段（additive，不 bump wire 版本）+ 新 iOS 卡片。

| # | 特性 | 版本 | 路径 | fork 工作量 |
|---|---|---|---|---|
| 1 | **DeepSeek** web-session 用量+成本 | 0.30.0 | **C 新 envelope** | **`SyncDeepSeekUsage` + 映射 + iOS 卡片 + mock**（本次唯一新增块） |
| 2 | **Codex Spark** 两条 lane | 0.31.0 | A 自动 | 无（自动透传）；加 mock + 验证 |
| 3 | **Antigravity** 分模型配额 | 0.30.0 | A 自动 | 无（自动透传）；加 mock + 验证 |
| 4 | **Claude Design** lane 移除 | 0.31.0 | A 自动（上游停发） | 无；grep iOS 是否有硬编码残留 |
| 5 | **Claude** extra-usage 100× 修复 | 0.29.1 | B 自动 | 无（合并即生效）；验证币种正确 |
| 6 | **Grok** reset 窗口标注 | 0.29.1 | B 自动 | 无；验证 Weekly/Monthly 标签 |
| 7 | **Ollama** 配速投影 | 0.30.0 | B 自动（windowMinutes 透传） | 无；验证 iOS 配速渲染 |
| 8 | **Alibaba** Bailian 端点 | 0.30.0 | B 自动（现有 `alibabaTokenPlan`） | 无；验证数值 |
| 9 | **OpenAI** project 限定 loginMethod | 0.30.0 | B 自动（现有 `loginMethod`） | 无；可选补 `accountOrganization` |
| 10 | **OpenAI/Mistral** 成本卡请求数 | 0.30.0 | **C 可选 additive** | 可选：给 `SyncCostSummary`/`SyncCostBreakdown` 加 `requestCount?`（符合"多同步一点"宗旨） |

**结论：本次同步 fork 侧极轻。** 真正的新管道只有 DeepSeek 一个 envelope（+ 一个可选的请求数富化）；其余 8 项要么经动态 `rateWindows[]` 自动透传、要么经现有字段在合并后自动纠正。绝大部分工作是 **合并上游 + 加 mock + 跨版本兼容验证 + 版本/本地化/发布**。

详细设计与每个字段落点见 [01 设计文档](01-design.md)。

---

## 6. 版本目标（依 `docs/versioning.md`）

| 变量 | From | To | 规则 |
|---|---|---|---|
| `MARKETING_VERSION`（Mac） | `0.29.0.1` | **`0.31.0.1`** | 前 3 段照抄上游 tag `v0.31.0`；第 4 段 fork 补丁回到 `.1` |
| `BUILD_NUMBER`（Mac） | `68.1` | **`73.1`** | 上游 v0.31.0 BUILD=73；fork 补丁 `.1` |
| `MOBILE_VERSION` | `1.9.0` | **`1.10.0`** | iOS 上一批 provider/特性 → minor bump（沿用 1.9.0 惯例） |
| `UPSTREAM_VERSION` | `v0.29.0` | **`v0.29.0`（合并不动）→ `v0.31.0`（G10 发布后）** | version.env 内联策略：confirmed-shipped bookmark，发布后才 bump（F1） |
| `UPSTREAM_SYNC_DATE` | `2026-05-25` | **`2026-05-30`** | 今天 |
| iOS `MARKETING_VERSION` | `1.9.0` | **`1.10.0`** | = MOBILE_VERSION |
| iOS `CURRENT_PROJECT_VERSION` | `144` | **`145`+** | 每次 commit +1 |
| `sparkle:version` | `68.1.1.9.0` | **`73.1.1.10.0`** | `BUILD_NUMBER.MOBILE_VERSION`（5 段单调递增） |
| Release tag | `v0.29.0-mobile.1.9.0` | **`v0.31.0-mobile.1.10.0`** | `v{MARKETING}-mobile.{MOBILE}` |

---

## 7. 阶段计划

| 阶段 | 内容 | 产出 / 闸门 |
|---|---|---|
| **A. Mac 合并** | `git merge v0.31.0`；解决 fork-owned 冲突（`Shared/` + `CodexBarMobile/` 上游不碰，冲突面应很小，见 [02 §3](02-development.md)）；`swift build` 通过 | 干净构建 |
| **B. iOS 面定稿** | 本文档 + 01 设计锁定：DeepSeek 新卡 + 自动透传项 + 可选请求数 | 设计 ready |
| **C. Mac→iOS bridge** | `SyncCoordinator` 加 `mapDeepSeekUsage`；审计 `supportsOpus` 闸门（§下方风险 R1）；可选请求数富化；跨版本 envelope 往返测试 | bridge 测试绿 |
| **D. Mac 草稿发布** | 跑 `docs/cloudkit-deploy-audit.md` 审计（预判**无需** Prod schema deploy，见 [02 §2](02-development.md)）；sign-notarize；appcast `73.1.1.10.0` | 草稿 release（需用户 Mac 凭证） |
| **E. Mac 端到端 + 回归** | 全量 `swift test`；逐 provider/菜单/设置走查；CloudKit Mac→iOS sim 同步；防 79+ commit 合并引入旧特性回归 | 无回归 |
| **F. iOS 1.10.0 实现** | `project.yml` bump + `xcodegen`；`DeepSeekUsageCard`；mock；`Localizable.xcstrings` ×4 语；release notes + CHANGELOG；`xcodebuild` + 模拟器冒烟 + `Scripts/lint.sh` i18n | iOS 构建 + 冒烟 |
| **G. iOS 测试 + 合并发布** | 单测 + 模拟器 + 真机（需用户设备）；TestFlight；重打 Mac release（MOBILE 1.10.0）；发 appcast + GitHub release；合并 sync 分支 → `mobile-dev` | 用户手里可装 |

**CR 闸门：** 依项目 memory `CR before package` —— 每个关键阶段（A 合并 / C bridge / F iOS）后跑 Opus CR loop，**清干净再 bump 版本打包**（每次重打包 ~15 分钟）。

**Definition of Done：** 依 `docs/RELEASE-CHECKLIST.md` —— "完成" = 已签名公证 + 发到用户手里（Sparkle appcast + iOS TestFlight），**不是** commit/push 了。

---

## 8. 风险

| # | 风险 | 缓解 |
|---|---|---|
| R1 | `supportsOpus` 闸门（`SyncCoordinator.swift:535`）把 `snapshot.tertiary` 仅对 opus provider 透传 | **本次已核实非阻塞**：Codex Spark 走 `extraRateWindows`（无条件循环 line 545），非 `tertiary`；区间内无新 `tertiary` 数据。仍在 [01 §3](01-design.md) 记为待加固审计项 |
| R2 | DeepSeek `deepseekUsage` 是**瞬态**字段（不持久化、解码为 nil），同步时机若拿不到值则 envelope 为空 | `SyncCoordinator` 在每次 fetch 后即时读取；空则不发 envelope，iOS 回退余额卡。测试覆盖（[03 §4](03-testing.md)） |
| R3 | DeepSeek 现有"余额"在 iOS 是否已可见存疑（无专属卡） | 新 `DeepSeekUsageCard` 一并承载余额 + 新用量/成本，顺手补齐既有 parity gap |
| R4 | 79+ commit 合并引入旧特性回归 | 阶段 E 全量回归走查 + 全 `swift test` |
| R5 | 新增字段误触 CloudKit schema → 需 Prod deploy | 初判**否**（字段在压缩 blob 内，不新增 CKRecord 字段）；阶段 D 按 `docs/cloudkit-deploy-audit.md` 正式过审计 |
| R6 | 旧 iOS（1.9.0）读到含 `SyncDeepSeekUsage` / 请求数的新 payload 崩溃 | additive optional + `decodeIfPresent`，旧解码器忽略未知 key；[03 §3 场景 S2](03-testing.md) 专测 |
| R7 | 真实凭证不全（DeepSeek web session / 企业版 Claude） | mock-only 覆盖；测试清单标注 |

---

## 9. 与项目护栏的一致性

- **不改 Mac 端上游代码逻辑**：仅 `git merge` + fork-owned 的 `Sources/CodexBar/Sync/`（bridge）+ `Shared/`（wire schema）。`Sources/CodexBarCore/` 上游内容只读。
- **不推 upstream**：只推 `origin`（o1xhack/CodexBar-Mobile）。
- **不跳过本地化**：DeepSeek 卡片所有可见文案 4 语（en/zh-Hans/zh-Hant/ja）。瑞典语/葡语是 Mac-only，iOS 不加。
- **不跳过版本号**：每次 commit bump `CURRENT_PROJECT_VERSION`。
- **不手编 .xcodeproj**：经 `xcodegen generate`。

---

## 10. 执行轮次记录（Round log）

### Round 1 — Phase A 合并（2026-05-30）
- `git merge v0.31.0`（83 commits）完成，提交 **`f8644d4c`**。10 个冲突全解：fork 元文件（AGENTS→ours、CHANGELOG/README→两侧都留、appcast→ours、version.env→目标值）+ Mac 发布脚本（保留 fork widget/CloudKit 打包）+ 生成哈希→上游 + Mistral 测试→fork UTC 修复。**`swift build` 绿（22s）**。核心 fork 代码（`Shared/`、`Sources/CodexBar/Sync/`、`CodexBarMobile/`）零冲突。**G1 ✓（进度 1/10）**。
- **发现 F1（版本策略，已改正本文档）**：`version.env` 内联注释规定 `UPSTREAM_VERSION` = "confirmed shipped to users，bump **after** live，**not at merge time**"。原本文档 ⭐/§6 版本表 + /goal 条件(6)写成"合并即设 v0.31.0"是错的。已改：合并时 `UPSTREAM_VERSION` 保持 `v0.29.0`，G10 发布后才 bump 到 `v0.31.0`。
- **发现 F2（Mac 发布脚本，待 Phase D / G10 复核）**：`package_app.sh` / `sign-and-notarize.sh` / `compile_and_run.sh` 的冲突按"保留 fork 手写 widget .appex 打包（含 `${BUILD_NUMBER}.${MOBILE_VERSION}` 版本 + CloudKit 签名链路）"解决；上游 v0.30.0 已把 widget 重构为真正的 Xcode app-extension target（新增 `WidgetExtension/`，用 `install_widget_extension` 替代手写块，#1095）。fork 手写法（从 SPM 产物 `resolve_binary_path CodexBarWidget` 装配）可能与上游新 widget 构建不一致 → **打包发布前必须复核 widget .appex 是否正确生成/签名/版本**。属 release-time 风险，不影响 `swift build` / iOS。
- **持有项**：首次 `git push` 到 origin + Todoist 同步暂未执行（对外动作，待用户确认）；本地开发继续。

### Round 2 — G2 DeepSeek 数据管道（2026-05-30）
- 新建 `Shared/Models/V030Snapshots.swift`（`SyncDeepSeekUsage` + `SyncDeepSeekDaily`，optional + 自定义 decoder，前后兼容）；`ProviderUsageSnapshot` 加 `deepSeekUsage` 字段（member/init/decoder/`with` 四处同步）；`SyncCoordinator.mapDeepSeekUsage` 从 `snapshot.deepseekUsage`（`DeepSeekUsageSummary`）映射 today/month tokens·cost·requests + topModel + daily。**`swift build` 绿（7s）**。**G2 ✓（2/10）**。
- **决策 D1（余额不重复传）**：上游 `DeepSeekUsageFetcher.toUsageSnapshot()` 把余额拍平成 primary `RateWindow` 的字符串（"$X (Paid/Granted)"），iOS 已通过通用 window 渲染。故 `SyncDeepSeekUsage` 的 `*BalanceUSD` 保持 nil，iOS 卡片只承载**新的**用量/成本/请求数；余额走 window。→ G5 实现卡片时据此微调 [01 §4]。
- **延后项 D2**：OpenAI/Mistral 请求数 additive（01 §2.6）属可选，延后为 fast-follow，不阻塞主线。

### Round 3 — G3 mock + G6 wire 兼容测试（2026-05-30）
- `MockProviderInjector`：`V026MockExtras` 加 `deepSeekUsage` + `case "deepseek"`（today/month tokens·cost·requests + topModel），iOS 可无凭证可视化 DeepSeek 卡。
- 新建 `Tests/CodexBarTests/V030SnapshotsCodableTests.swift`（**5 测试全绿**）：S1 全往返 + free-tier 缺字段降级（currency 默认 USD、daily []）+ **S3 旧 payload 无 `deepSeekUsage` → nil** + **S2 含未知 future key 不崩**。`swift test` 全测试目标编译通过（45s，顺带确认 Mistral `toCostUsageTokenSnapshot` 等只是 SourceKit 索引假警、无回归）。
- **Codex Spark / Antigravity 分模型透传**：结构性保证（bridge `extraRateWindows` 无条件循环 line 545 + iOS `ProviderUsageView.ForEach(allRateWindows)`）；iOS 可视化验证并入 G5 卡片完成后一起做。
- G3/G6 **wire 层完成**；G3 的 iOS 可视化显示 + G5 卡片 = 下一步。

### Round 4 — G5 iOS 卡片 + G8 版本 bump（2026-05-30）
- 新建 `Views/DeepSeekUsageCard.swift`（仿 `DeepgramUsageCard`：标题 + topModel 徽标 + 今日/本月 `tokens·cost·requests` 行 + 可选余额行 + daily 迷你条；余额 nil 则隐藏，与 D1 一致）；`ProviderDetailView` 加 `deepseek` 派发块（providerID 匹配 + `deepSeekUsage` 非 nil）。
- `Localizable.xcstrings` 加 4 个 key × 4 语（`deepseek_usage_title` / `_today_label` / `_month_label` / `_balance_label`），全 `state:"translated"`，无 `state:"new"`。
- `project.yml` → MARKETING `1.10.0` / BUILD `145`（3 处）；`xcodegen generate` 重生成 `.xcodeproj`（已纳管）。
- **`xcodebuild -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO` 成功**（iOS app 全量编译通过，含新卡 + 派发 + 本地化）。**G5 ✓ / G8 ✓（4/10）**。
