# 026 — v0.32.x 上游同步 · 总体文档

**Status:** ready
**Date:** 2026-06-03
**Target release tag:** `v0.32.4.1-mobile.1.11.0`（MOBILE 段待 G4 确认，可能为 Mac-only `1.10.0`）
**Branch:** `upstream-sync/v0.32.4-mobile.1.11.0`
**文档集:** 本目录共 4 份 —
[00 总体](00-overview.md) · [01 设计](01-design.md) · [02 开发+架构](02-development.md) · [03 测试](03-testing.md)

---

## ⭐ 最终目标版本号（锁定）+ 完成确认

> 本目标的**验收锚点**。每轮循环结束都对照此处：版本号是否 stamp 对、DONE 是否全勾。
> 只有下方版本号已落定 **且** G1–G10 全部勾选，才可对用户宣告"全部工作已完成"。

**最终版本号（达成时必须 stamp 成这些值，依 `docs/versioning.md`）：**

| 端 | 最终版本 | 落点文件 |
|---|---|---|
| **Mac** | MARKETING `0.32.4.1` · BUILD `79.1`（上游 v0.32.4 BUILD=79 + fork `.1`）· UPSTREAM `v0.31.0`→`v0.32.4`（**发布后才 bump**，F1） | `version.env` |
| **iOS** | MOBILE_VERSION `1.11.0`（**若 G4 判定零 iOS 代码改动则保持 `1.10.0`、走 Mac-only**）· BUILD `148`+ | `CodexBarMobile/project.yml` + `version.env` |
| **Sparkle / Release tag** | `sparkle:version` `79.1.1.11.0` · tag `v0.32.4.1-mobile.1.11.0`（或 `…-mobile.1.10.0`） | appcast / GitHub release |

> ⚠️ **关键设计决策（G4）**：本批上游**无新 wire 字段、无新 iOS 卡片**（见 §5）。iOS 端是
> "纯验证 + 可选小增强"。发布前定：iOS 是否 ship 新 build（MOBILE→1.11.0）还是 Mac-only
> （MOBILE 保持 1.10.0，不上 TestFlight）。默认倾向 ship 配套 iOS（PM 指令"尽可能全支持"
> + release notes 刷新），但若确无 iOS 代码改动，Mac-only 亦合规。

**完成确认（DONE —— 全部勾选才算"全部工作完成"）：**

- [ ] **G1 · Mac 合并**：`git merge v0.32.4`（67 commits）干净、`swift build` 绿、冲突全解
- [ ] **G2 · Codex parser 缓存失效**（本轮核心）：CostUsage 大改（+903/-91，含新 `CostUsageScanner+CodexFastJSON.swift`）→ `Scripts/regenerate-codex-parser-hash.sh` + bump `parserLogicVersion`；全量 `Scripts/lint.sh lint` 绿
- [ ] **G3 · 值修正自动透传验证**：Antigravity 配额行过滤（#1209）、Copilot 零权利 %（#1258）、Augment 解析（#1224）、Claude 快照保留（#1220）经现有 synced 字段透传 — grep 确认 + iOS 实机 = 用户 QA
- [ ] **G4 · iOS 面定稿**：判定 iOS scope（纯验证 / 可选 provider 搜索 #1184）+ 定 MOBILE 版本（1.11.0 或 Mac-only 1.10.0）
- [ ] **G5 · i18n / release notes**：若 iOS ship → 4 语 xcstrings + `MobileReleaseNotesCatalog` 1.11.0 条目 + CHANGELOG（Mac + iOS）
- [ ] **G6 · 测试**：全量 `swift test` 绿（含 cost-cache 失效单测）+ 跨版本兼容回归（2 Mac×2 iOS 不崩）
- [ ] **G7 · Code Review**：独立 Opus 4.7 agent CR loop 评审 fork 改动 → 零 findings
- [ ] **G8 · 版本号 stamp**：`version.env` + `project.yml` + `xcodegen` 重生成
- [ ] **G9 · CloudKit 审计**：本批无新 CKRecord 字段（无新 wire 结构）→ 预判**无需** Prod schema deploy；按 `docs/cloudkit-deploy-audit.md` 正式过审
- [ ] **G10 · 发布**：Mac 签名公证 + draft→publish + appcast + 装机；（iOS TestFlight 若 ship）；合并分支 → `mobile-dev`；关 issue #15/16/18/19/20；bump `version.env` UPSTREAM_VERSION

**当前进度：0 / 10（Round 0 起步：分支 + 文档集已建）。**

**`/goal` 自动循环完成条件**（每回合自动复检）：

```text
v0.32.x 同步达到「可发布前完成态」，且以下每项都在本会话由命令输出或文件内容证明，
四份文档 00–03 已回写到与代码一致：
(1) git merge v0.32.4 完成、git status 干净；
(2) swift build 退出 0、xcodebuild -scheme CodexBarMobile 构建成功；
(3) CostUsage 缓存失效已处理：CodexParserHash 重生成 + parserLogicVersion bump，全量 lint.sh lint 绿；
(4) swift test 全绿（含 cost-cache 失效 + 跨版本兼容场景）；
(5) Scripts/lint.sh 通过、（若 iOS ship）xcstrings 4 语齐、无 state:"new"；
(6) version.env = MARKETING 0.32.4.1 / BUILD 79.1 / MOBILE（1.11.0 或 1.10.0）/ UPSTREAM v0.31.0（发布前不 bump）；project.yml stamp 对；
(7) 本 ⭐ 节 DONE 计数 = 9/10（G1–G9 勾选）、四份文档「修订记录」已更新到本轮；
(8) 最近一轮做过防回归复验且通过。
到 9/10 即停并交回用户；或在 40 回合后停止并汇报当前 X/10。
```

---

## 1. 一句话目标

把上游 `steipete/CodexBar` 从 **v0.31.0 → v0.32.4**（即 `v0.32.0/0.32.1/0.32.2/0.32.3/0.32.4` 五个 tag，对应 open issue #15/#16/#18/#19/#20）**所有用户可见的显示数据 + 数值修正**同步到 fork 的 Mac 与 iOS 端，**一次合并发布**，不拆版本。

宗旨（PM 指令）：**只要 Mac 端新增的显示内容 iOS 能显示，就尽可能全部支持；除非与现有基础架构完全冲突才放弃。**

---

## 2. 当前状态 / 起点

| 维度 | 当前值 | 来源 |
|---|---|---|
| 已对齐上游 tag | `v0.31.0` | `version.env: UPSTREAM_VERSION` |
| Mac MARKETING_VERSION | `0.31.0.2` | `version.env` |
| Mac BUILD_NUMBER | `73.2` | `version.env` |
| MOBILE_VERSION | `1.10.0` | `version.env` |
| iOS project.yml | MARKETING `1.10.0` / BUILD `147` | `CodexBarMobile/project.yml` |
| 上游 v0.32.4 BUILD | `79`（appcast `sparkle:version`） | upstream `v0.32.4:appcast.xml` |

---

## 3. 范围（open issue 驱动）

`gh issue list --state open --label upstream-sync` → #15(v0.32.0) · #16(v0.32.1) · #18(v0.32.2) · #19(v0.32.3) · #20(v0.32.4)。整合成一次合并到 `v0.32.4`。

上游 `v0.31.0..v0.32.4` = **67 commits / 122 files / +8211 -699**（大头在 Mac UI/perf/tests/docs + Codex parser 重写）。

---

## 4. 上游逐版本变更摘要（仅列与显示/数据相关者）

### v0.32.0（#15）
- **Antigravity OAuth 配额行过滤**（#1209）— 过滤噪声远程 OAuth 配额行，仅显示已消耗行，阻止 image/lite/autocomplete/internal 行污染汇总进度条。**改变显示数据**，经现有 Antigravity 透传。
- **Copilot**（见 v0.32.3 #1258 修复）；**Augment 解析更新 + cookie fallback**（#1224）— 数据源修正，经现有字段透传。
- **Claude 保留最后有效 Web 用量快照**（#1220）— 短暂 Unauthorized 期间不清零，可靠性/新鲜度。
- **Settings Provider 搜索**（#1184）— Mac UI；iOS 可选小增强（P3）。
- 其余（Amp/Ollama HTTPS cookie 安全 #1226、CLI 临时脚本隔离 #1222、Codex WebKit 刷新取消 #1217、Menu Codex 附件刷新 #1150、菜单栏定位 #1216/#1227、公证路径隔离 #1228、Status 启动重试 #1211）— Mac 安全/性能/可靠性，**无新 iOS 显示字段**。

### v0.32.1（#16）
- **全部 Mac 可靠性/性能**：Claude OAuth refresh-token 委托 CLI（#1239，防强制重登）、菜单栏性能、输入响应、启动稳定。**无新显示字段。**

### v0.32.2（#18）
- **Codex token-cost 扫描器优化**（性能）— **触及 Codex parser**（`CostUsage/`），见 §5 #1 缓存失效。
- QA 文档、菜单栏留白。**无新显示字段。**

### v0.32.3（#19）
- **Copilot 零权利（zero-entitlement）配额修复**（#1258）— 防止显示误导性用量百分比。**数值/显示修正**，经现有 Copilot 字段透传。
- 菜单栏定位、SVG 缓存、菜单响应、OpenAI Web 稳定性 — Mac 性能/可靠性。

### v0.32.4（#20）
- **菜单栏 provider 刷新优化**（#1277）— Mac-only，**无新显示字段**。

---

## 5. 特性清单 → 同步路径 → fork 工作量

> 三条路径：**(A) 通用 lane 自动透传**（进 `rateWindows[]`，iOS 通用渲染）；**(B) 数值修复自动透传**（合并即经现有字段纠正）；**(C) 新 envelope**（新 optional `SyncXxx` + 新 iOS 卡）。

| # | 特性 | 版本 | 路径 | fork 工作量 |
|---|---|---|---|---|
| 1 | **Codex parser 重写**（FastJSON #?, truncated prefix, 扫描性能） | 0.32.0–0.32.2 | **缓存失效** | **regenerate CodexParserHash + bump parserLogicVersion**（本轮唯一必须的 fork 代码改动） |
| 2 | **Antigravity 配额行过滤** #1209 | 0.32.0 | A 自动 | 无（透传）；验证 iOS Antigravity 卡显示过滤后的行 |
| 3 | **Copilot 零权利 %** #1258 | 0.32.3 | B 自动 | 无；验证 iOS Copilot % 不再误导 |
| 4 | **Augment 解析 + cookie fallback** #1224 | 0.32.0 | B 自动 | 无；验证 iOS Augment 数值 |
| 5 | **Claude 快照保留** #1220 | 0.32.0 | B 自动 | 无；验证 iOS Claude 不闪空/旧 |
| 6 | **Claude OAuth refresh 委托** #1239 | 0.32.1 | B 自动（Mac 认证） | 无 iOS 显示影响（Mac 凭证健康） |
| 7 | **Settings Provider 搜索** #1184 | 0.32.0 | — | Mac UI；iOS 可选 provider 列表搜索（P3，默认跳过，除非 G4 决定做） |
| — | 菜单栏/性能/安全/CLI/release | 0.32.x | — | Mac-only，N/A iOS |

**结论：本批 fork 侧极轻 —— 无新 wire envelope、无新 iOS 卡片。** 唯一必须的代码改动是
**Codex parser 缓存失效（G2）**；其余全是经现有 synced 字段自动透传的数值修正（验证即可）。
iOS 可能**零代码改动**（→ Mac-only），或仅做可选 provider 搜索 + release notes 刷新。

详细字段落点见 [01 设计文档](01-design.md)。

---

## 6. 版本目标（依 `docs/versioning.md`）

| 变量 | From | To | 规则 |
|---|---|---|---|
| `MARKETING_VERSION`（Mac） | `0.31.0.2` | **`0.32.4.1`** | 前 3 段照抄上游 `v0.32.4`；fork 段回 `.1` |
| `BUILD_NUMBER`（Mac） | `73.2` | **`79.1`** | 上游 v0.32.4 BUILD=79 + fork `.1` |
| `MOBILE_VERSION` | `1.10.0` | **`1.11.0`**（或保持 `1.10.0` Mac-only） | 待 G4 定 |
| `UPSTREAM_VERSION` | `v0.31.0` | **`v0.31.0`→`v0.32.4`（G10 发布后）** | confirmed-shipped，发布后才 bump |
| iOS `CURRENT_PROJECT_VERSION` | `147` | **`148`+** | 每次 commit +1 |
| `sparkle:version` | `73.2.1.10.0` | **`79.1.1.11.0`**（或 `79.1.1.10.0`） | `BUILD.MOBILE` 5 段单调递增 |
| Release tag | `v0.31.0.2-mobile.1.10.0` | **`v0.32.4.1-mobile.1.11.0`** | `v{MARKETING}-mobile.{MOBILE}` |

---

## 7. 阶段计划（PM 6 步落进循环）

| 阶段 | 内容 | 闸门 |
|---|---|---|
| **A. Mac 合并** | `git merge v0.32.4`；解 fork-owned 冲突；`swift build` 绿 | 干净构建 |
| **B. parser 缓存失效** | regenerate hash + bump parserLogicVersion；全量 lint | lint 绿 |
| **C. 值修正透传 + iOS 面定** | grep 验证 #1209/#1258/#1224/#1220 经现有字段流过；定 iOS scope + MOBILE 版本 | 设计 ready |
| **D. Mac 草稿发布** | CloudKit 审计；sign-notarize；appcast | draft（用户 Mac 凭证） |
| **E. Mac 端到端 + 回归** | 全量 `swift test`；cost-cache 失效验证；跨版本同步走查 | 无回归 |
| **F. iOS（若 ship）** | project.yml bump + xcodegen；4 语 + release notes；冒烟 + lint | iOS 构建 |
| **G. 发布 + 收尾** | TestFlight（若 ship）；publish + appcast；合并 mobile-dev；关 issue | 用户手里可装 |

**CR 闸门**：每关键阶段后独立 Opus 4.7 agent CR loop，清干净再 bump 版本打包。

---

## 8. 风险

| # | 风险 | 缓解 |
|---|---|---|
| R1 | **CostUsage parser 大改（+903）→ 缓存失效轴漏滚** | 本轮已知必做 G2：regenerate hash + bump parserLogicVersion + 全量 lint（吸取 0.31.0.1 教训，见 memory `parser-cache-invalidation-on-upstream-merge`） |
| R2 | 67 commit 合并引入旧特性回归 | 阶段 E 全量回归 + 全 `swift test` |
| R3 | Antigravity 行过滤 #1209 改变现有显示 → iOS 旧缓存/旧 Mac 混用时不一致 | 跨版本兼容场景（03）；经现有 rateWindows 透传，加 mock |
| R4 | Copilot #1258 零权利 % 修复后 iOS 端显示口径变化 | 验证 iOS Copilot 卡；属 B 自动透传 |
| R5 | 无新 wire 字段却误触 CloudKit schema | 初判否（无新 CKRecord 字段）；阶段 D 正式审计 |
| R6 | iOS 实为零代码改动却强行 ship 1.11.0 | G4 显式决策 Mac-only vs iOS ship |

---

## 9. 与项目护栏的一致性

- 不改上游 Mac-only 逻辑：仅 `git merge` + fork-owned `Sources/CodexBar/Sync/`（bridge）+ `Shared/`（wire）+ `CodexBarMobile/`。`Sources/CodexBarCore/` 上游内容只读（含 CostUsage —— 只跑 regenerate 脚本 + 改 `parserLogicVersion`，不改 parser 逻辑）。
- 不推 upstream，只推 `origin`。不跳本地化（若 iOS ship，4 语齐）。每次 commit bump `CURRENT_PROJECT_VERSION`。不手编 .xcodeproj（`xcodegen`）。
- **Definition of Done** = 已签名公证 + 发到用户手里（见 `docs/RELEASE-CHECKLIST.md`），不是 commit。
- **CR before package**：清干净再打包。
- **parser 缓存失效护栏**：见 R1 + memory。

---

## 10. 执行轮次记录（Round log）

### Round 0 — 起步（2026-06-03）
- 读 5 个 open issue（#15/16/18/19/20）定范围 = v0.32.0→v0.32.4 一次合并。`git fetch upstream --tags` 拉到 v0.32.x。
- 上游 `v0.31.0..v0.32.4` = 67 commits / 122 files / +8211 -699。**关键画像**：无新 provider、无 `UsageSnapshot`/`Shared/Models` 新字段 → **无新 wire envelope、无新 iOS 卡片**；CostUsage parser 大改（+903，含新 `CostUsageScanner+CodexFastJSON.swift`）→ 必做 G2 缓存失效。
- 版本目标定（依 `docs/versioning.md`）：MARKETING `0.32.4.1` / BUILD `79.1`（上游 79）/ MOBILE `1.11.0`（待 G4）/ tag `v0.32.4.1-mobile.1.11.0`。
- 建分支 `upstream-sync/v0.32.4-mobile.1.11.0`，生成本文档集 00–03 + PROJECT-PROMPT.md。**进度 0/10**，下一步进 Round 1（Phase A：`git merge v0.32.4`）。
