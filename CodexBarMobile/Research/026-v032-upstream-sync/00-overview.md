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

- [x] **G1 · Mac 合并**：`git merge v0.32.4`（67 commits）干净、`swift build` 绿（21s）、5 冲突全解 — 提交 `6d3e54d4`（R1）
- [x] **G2 · Codex parser 缓存失效**（本轮核心）：`regenerate-codex-parser-hash.sh` → hash `518924b891f96a03` + `parserLogicVersion` 4→5；全量 `Scripts/lint.sh lint` 绿（parser-version + hash 审计均 OK）— 提交 `5d8f6167`（R1）
- [~] **G3 · 值修正自动透传验证**：Antigravity 配额行过滤（#1209）、Copilot 零权利 %（#1258）、Augment 解析（#1224）、Claude 快照保留（#1220）—— grep 确认在合并树 + `Shared/`/`Sync/` 相对 base 零 diff（经现有字段透传，无需 bridge）✓；iOS 实机可视化 = 用户 QA
- [x] **G4 · iOS 面定稿**：用户决策 = **配套 ship iOS 1.11.0**（纯 release-notes，无功能代码；值修正经同步到达 iOS）。MOBILE → 1.11.0，tag `v0.32.4.1-mobile.1.11.0`（R3）
- [x] **G5 · i18n / release notes**：`MobileReleaseNotesCatalog` 1.11.0 条目（5 项）+ 7 文案 ×4 语 xcstrings（314 keys 全在）+ root CHANGELOG 0.32.4.1 双语 + iOS CHANGELOG 1.11.0(148)（R3）
- [x] **G6 · 测试**：全量串行 `swift test --no-parallel` 绿（3630 tests / 417 suites）；唯一失败 `KeychainPromptSafetyAuditTests` 是 mobile-dev 预存的 AGENTS.md 审计缺口（非合并回归），已修。并行 flake `SyncCoordinatorTests`（Index out of range）属已知（memory）。跨版本 iOS 实机 = 用户 QA
- [x] **G7 · Code Review**：独立 Opus 4.7 agent 评审 fork 改动（合并冲突解决 + parser 缓存失效）→ **SHIP**，零阻塞 findings（R1）
- [x] **G8 · 版本号 stamp**：`version.env`（MARKETING 0.32.4.1 / BUILD 79.1 / MOBILE 1.11.0）+ `project.yml`（1.11.0 / 148）+ `xcodegen` 重生成；iOS sim build 绿（R3）
- [x] **G9 · CloudKit 审计**：`CloudConstants.swift` 相对 base 零 diff、`providerPayloadVersion=1` 未变、无新 CKRecord 字段 → **无需 Prod schema deploy** ✓
- [ ] **G10 · 发布**：Mac 签名公证 + draft→publish + appcast + 装机；（iOS TestFlight 若 ship）；合并分支 → `mobile-dev`；关 issue #15/16/18/19/20；bump `version.env` UPSTREAM_VERSION

**当前进度：9 / 10（G1–G9 ✓，G3 代码层已验证 + iOS 可视化属真机 QA；剩 G10 发布 = 用户环节）。**

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

### Round 1 — Phase A 合并 + Phase B parser 缓存失效（2026-06-03）
- **G1 ✓**：`git merge v0.32.4`（67 commits）→ 5 冲突全解：`version.env`（→0.32.4.1/79.1）、`CHANGELOG.md`（两侧都留）、`appcast.xml`（ours）、`CodexParserHash.generated`（ours，待 regenerate）、`sign-and-notarize.sh`。`swift build` 绿（21s）。提交 `6d3e54d4`。核心 fork 代码（`Shared/`、`Sync/`）零冲突。
- **发现 F1（sign-and-notarize.sh 冲突，release 脚本坑）**：上游 #1228 把公证 API key/zip 隔离到私有临时目录，且下游公共代码改用 `$API_KEY_PATH`/`$NOTARIZATION_ZIP`（只在上游块定义）。但上游块**只认 `_P8`**，而 fork/用户用 `_FILE`。解法：采纳 #1228 私有目录隔离 + 定义两变量，但**保留 fork 的 `_FILE`/`_P8` 双支持 + fork 的 mobile 后缀 `ZIP_NAME`/`DSYM_ZIP`**（不用上游 `codexbar_app_zip_name`，否则 release.sh/appcast 找不到 zip）。属 release-time 风险，build/test 抓不到（memory `fork-script-conflict`），Phase D 打包时复核。
- **G2 ✓**：CostUsage 确认大改（+903/-91，新 `CostUsageScanner+CodexFastJSON.swift`）。bump `parserLogicVersion` 4→5（+ v5 history 注释）→ `regenerate-codex-parser-hash.sh` → hash `518924b`。坑：`audit-parser-version` 查 `base...HEAD` 已提交 diff，故须**先提交**缓存失效改动审计才认（merge commit 里还是 4）。提交 `5d8f6167` 后全量 lint 绿。
- **进度 2/10**。下一步：G3（值修正透传 grep 验证）+ G9（CloudKit 审计 grep）+ G6（swift test 回归）+ G7（Opus CR）。

### Round 2 — G3/G6/G7/G9 验证（2026-06-03）
- **G3 ✓（代码层）**：Antigravity #1209 / Copilot #1258（`ffd8d75a`）/ Augment #1224（`4a2ef3ae`）在合并树；`Shared/`+`Sources/CodexBar/Sync/` 相对 base **零 diff** → 值修正经现有 synced 字段透传，无需 bridge/wire 改动。iOS 可视化 = 用户真机 QA。
- **G9 ✓**：`CloudConstants.swift` 零 diff、`providerPayloadVersion=1` 未变 → 无新 CKRecord 字段 → **无需 Prod schema deploy**。
- **G6 ✓**：全量串行 `swift test --no-parallel` = 3630 tests / 417 suites，唯一失败是 `KeychainPromptSafetyAuditTests`（断言 AGENTS.md 含 keychain-prompt 安全指引）。查实：**mobile-dev 早就缺这两句、测试早就在 fail（非本次合并回归）**；其余 3629 全过。修法：把上游那条安全指引加进 fork AGENTS.md Step 4（提交 `d9b746f8`）→ `KeychainPromptSafetyAuditTests` 4/4 过。并行 `SyncCoordinatorTests` flake（Index out of range）属已知 memory。
- **G7 ✓**：独立 Opus 4.7 agent 评审合并冲突解决 + parser 缓存失效 → **SHIP**，零阻塞。确认 `sign-and-notarize.sh` 所有变量 set-u 下用前已定义、`codexbar_app_zip_name` 无人调用、parser 双轴失效 `regenerate --check` 通过。
- **进度 6/10**。剩 **G4 iOS scope（用户决策：Mac-only vs 配套 ship 1.11.0）** → G5/G8（依 G4）→ G10 发布（用户环节）。

### Round 3 — G4 决策 + G5/G8 iOS 1.11.0 收尾（2026-06-03）
- **G4 ✓**：用户定 = **配套 ship iOS 1.11.0**（纯 release-notes，无功能代码）。锁定 MOBILE 1.11.0、tag `v0.32.4.1-mobile.1.11.0`、sparkle `79.1.1.11.0`。
- **G5 ✓**：`ContentView` `MobileReleaseNotesCatalog` 加 1.11.0 条目（Antigravity 行 / Copilot % / Augment / Claude 快照 / Codex-Claude 成本重扫 5 项 + Required Mac），1.10.0 取消 Latest；7 文案 ×4 语加进 xcstrings（Python 零 churn，314 source keys 全在）；root CHANGELOG 0.32.4.1 双语（changelog-to-html 渲染干净）+ iOS CHANGELOG 1.11.0(148)。
- **G8 ✓**：`version.env` MOBILE→1.11.0；`project.yml` 1.11.0 / 148；`xcodegen` 重生成。全量 lint 绿、iOS sim build SUCCEEDED。提交 `3d59278f`。
- **进度 9/10**。剩 **G10 发布**（用户环节）：Mac sign-notarize→draft→publish+appcast→装机 + iOS 1.11.0(148) TestFlight + 合并 mobile-dev + 关 issue #15/16/18/19/20 + bump UPSTREAM_VERSION→v0.32.4。**Phase D 打包时复核 F1 的 sign-and-notarize.sh widget/notarize 改动。**

### Round 4 — iOS Usage provider 搜索（用户加需求，2026-06-04）
- 用户反馈：20+ provider 时 Usage 列表滑动找 provider 麻烦 → 在 Usage tab 顶部加 `.searchable` 搜索栏（`.navigationBarDrawer(.always)`），按 `providerName`/`providerID` 过滤 `groups`（空查询 = 全量，零行为变化），无匹配显示 `EmptyStateView`。**linkage / 多账号分组仍用全量 `liveProviders`，过滤只隐藏行、不丢 linkage 提示**（Opus CR 专门确认）。
- 4 个新文案 ×4 语；in-app 1.11.0 release-notes 加"搜索"项；root + iOS CHANGELOG；`project.yml` build 148→149。
- 验证：`Scripts/lint.sh lint` 绿（source keys 全在 + 4 语齐）、iOS sim build SUCCEEDED、独立 Opus CR → **SHIP**。提交 `811f9c46`。
- **iOS scope 修正**：本批不再是"零功能代码" —— 新增 provider 搜索（即 #1184 在只读 companion 上有意义的形态）。iOS 最终 build = **149**，tag 仍 `v0.32.4.1-mobile.1.11.0`。
- 进度仍 **9/10**（G10 发布 = 用户环节，待授权）。G10 的 iOS TestFlight 上传 build **149**（非 148）。

### Round 5 — G10 部分：Mac Draft + 装机 + iOS TestFlight（用户授权，2026-06-04）
- 用户授权：Mac 出 Draft Release + 装机；iOS 传 TestFlight（明确"Draft"，未授权 publish）。
- **Mac phase1**（`release.sh`）：lint 绿 → build → Developer ID 签名 → **Apple 公证 Accepted + staple + validate** → launch 验证 OK → `CodexBar-0.32.4.1-mobile.1.11.0.zip`。**R1 的 `sign-and-notarize.sh` 合并解法（#1228 私有临时目录 + fork 双 `_FILE`/`_P8` 密钥 + fork mobile 后缀 ZIP_NAME）+ widget 打包首次真打包验证通过 → F1 风险解除。** tag `v0.32.4.1-mobile.1.11.0` 已推、draft 已建（`untagged-9aea4c9cc9f60b5cc9e4`）。
- 产物验证：`0.32.4.1` / `79.1.1.11.0`、widget `CodexBarWidget.appex` 已签、CloudKit entitlement = **Production**、Gatekeeper accepted。装到 `/Applications/CodexBar.app` 并启动（运行中）。
- **iOS build 149**：archive + cloud-sign + 上传 ASC 成功（EXPORT SUCCEEDED），TestFlight 处理中。in-app 1.11.0 release notes 已确认含搜索 + 5 项值修正（4 语）。
- **未做（等用户审 draft 后授权 publish）**：publish draft live + 推 appcast（Sparkle）+ close issue #15/16/18/19/20 + bump `version.env` UPSTREAM_VERSION→v0.32.4 + 合并分支→mobile-dev。
- 进度：**G10 部分完成**（draft + 装机 + iOS TestFlight）；剩 publish 收尾（用户授权后）。
