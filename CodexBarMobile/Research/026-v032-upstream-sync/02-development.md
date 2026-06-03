# 026 — v0.32.x 同步 · 开发 + 架构

[00 总体](00-overview.md) · [01 设计](01-design.md) · **02 开发+架构** · [03 测试](03-testing.md)

---

## 1. Phase A — 合并（Round 1）

`git checkout upstream-sync/v0.32.4-mobile.1.11.0`（已建，从 mobile-dev）→ `git merge v0.32.4`。

**预期冲突面（照 fork 历史解）：**
- **Fork 元文件**：`AGENTS.md`（ours）、`CHANGELOG.md` / `README*.md`（两侧都留）、`appcast.xml`（ours）、`version.env`（目标值）。
- **Mac 发布脚本**（`package_app.sh` / `sign-and-notarize.sh` / `compile_and_run.sh`）：保留 fork 手写 widget/CloudKit 打包；**但要确认 ours 没依赖上游已删函数**（memory `fork-script-conflict` + 025 R9 的 `generate_widget_appintents_metadata` 教训）。
- **CostUsage（`Sources/CodexBarCore/Vendored/`）**：**这是上游代码，取 upstream 整块**（fork 不拥有 parser 逻辑）。合并后再跑缓存失效脚本。
- **核心 fork 代码**（`Shared/`、`Sources/CodexBar/Sync/`、`CodexBarMobile/`）：预期零冲突（本批无新 wire 字段）。

闸门：`swift build` 绿。

---

## 2. Phase B — Codex parser 缓存失效（Round 1/2，本轮核心）

合并后 CostUsage 必然变化（+903）。**必做两步**（memory `parser-cache-invalidation-on-upstream-merge`）：

```bash
bash Scripts/regenerate-codex-parser-hash.sh        # 滚动 Codex producerKey（hash → 新值）
# 编辑 Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift:
#   static let parserLogicVersion = N → N+1  （当前 4 → 5）
#   + 在 History 注释加 `- 5 (0.32.4.1): v0.32.x Codex 扫描器重写…` 一条
bash Scripts/regenerate-codex-parser-hash.sh        # parserLogicVersion 改完再跑一次（脚本 hash 整个 CostUsage 目录）
Scripts/lint.sh lint                                 # 全量：swiftformat + swiftlint + i18n + parser-version + parser-hash
```

> **顺序坑**（025 踩过）：先 bump parserLogicVersion 再 regenerate hash（脚本 hash 整个 `Vendored/CostUsage` 目录，含 CostUsagePricing.swift），否则要 regenerate 两次。
> **为什么两轴都要**：Codex 走 producerKey（hash），Claude 只走 pricingFingerprint（parserLogicVersion）。只滚 hash 治不了 Claude。
> **为什么 lint 要全量**：`audit-parser-version` 是 base...HEAD 前向的，合并把 parser 改动落在 base 上抓不到；只有 `audit-parser-hash`（绝对）能抓。

---

## 3. Phase C — bridge / wire（预期零改动）

本批无新显示字段 → `Shared/Models/`、`SyncCoordinator.swift` 预期不动。合并后 grep 确认：
```bash
git diff f<merge>^..HEAD -- Shared/ Sources/CodexBar/Sync/   # 应只有冲突解决，无新 mapper
```
若上游某 provider 的现有 synced 字段语义变了（如 Antigravity 行过滤改变 rateWindows 内容），属数据内容变化而非 schema 变化，无需 bridge 改动。

---

## 4. Phase D — CloudKit 审计

按 `docs/cloudkit-deploy-audit.md`：本批**无新 CKRecord 字段 / record type / zone / 索引**（无新 wire 结构，`CloudConstants.swift` 不动）→ **预判无需 Prod schema deploy**。发布前 grep 确认 `CloudConstants` 未变 + `providerPayloadVersion` 不变，历史存档记一笔。

---

## 5. 版本 stamp + 工程

- `version.env`：MARKETING `0.32.4.1` / BUILD `79.1`（MOBILE 待 G4；UPSTREAM 发布后才 bump）。
- `CodexBarMobile/project.yml`：`CURRENT_PROJECT_VERSION` 147 → 148+（每 commit +1）。
- `xcodegen generate --spec CodexBarMobile/project.yml`。
- CHANGELOG：root（0.32.4.1 段，双语、converter-clean）+ iOS（若 ship，build 148 段）。

---

## 修订记录
- **Round 0（2026-06-03）**：初稿。合并冲突面预判 + parser 缓存失效标准流程（含顺序坑）+ CloudKit 预判无需 deploy。
