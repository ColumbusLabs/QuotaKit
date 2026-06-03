# 026 — v0.32.x 同步 · 测试

[00 总体](00-overview.md) · [01 设计](01-design.md) · [02 开发+架构](02-development.md) · **03 测试**

---

## 1. Codex parser 缓存失效（本轮核心，可自动验证）

- `swift test --filter CostUsageCacheTests` 全绿（含 "pricingFingerprint includes parser logic version"、"rolls when price changes"、"non codex cache does not require producer key"）。
- 全量 `Scripts/lint.sh lint`：`Codex parser hash is current (<新hash>)` + `parser-version audit` 通过。
- **语义验证**：parserLogicVersion N→N+1 使 `pricingFingerprint` 变 → 升级用户 Codex+Claude 成本缓存失效重扫（对照 0.31.0.1→0.31.0.2 的修复路径）。

## 2. 跨版本兼容（2 Mac × 2 iOS，用户真机 QA）

| Mac \ iOS | iOS 1.10.0（旧） | iOS 1.11.0/Mac-only（新） |
|---|---|---|
| **73.2（旧）** | 现状基线 | 旧 Mac 不发新内容，新 iOS 回退渲染 |
| **79.1（新）** | 新 Mac 值修正经同步到旧 iOS，**旧 iOS 通用渲染不崩** | 全新组合 |

重点：
- **Antigravity 行过滤 #1209**：新 Mac 发过滤后的 rateWindows，旧/新 iOS `ForEach(allRateWindows)` 都正常渲染（行变少，不崩）。
- **Copilot % #1258**：新 Mac 发修正后的 %，iOS 显示正确口径。
- 任意组合**无崩溃 / 无丢数据**。

## 3. 回归（防 67 commit 引入旧特性回归）

- 全量 `swift test`：注意 `SyncCoordinatorTests` 并行 flake（memory `swift-test-parallel-flake`）—— `--no-parallel --filter SyncCoordinatorTests` 串行确认。
- 逐 provider / 菜单 / 设置走查（Mac）；CloudKit Mac→iOS sim 同步。
- 重点查 Codex 成本卡（parser 重写后）数值合理、std/fast/Spark lane 不回退。

## 4. 值修正可视化验证（用户真机 QA）

- Antigravity 卡：配额行更干净（无 image/lite/autocomplete/internal 噪声行）。
- Copilot 卡：zero-entitlement 账户不再显示误导 %。
- Augment 卡：解析更新后数值正确。
- Claude：短暂 Unauthorized 期间不闪空/不清零。

## 5. iOS（若 G4 走 ship）

- `xcodebuild -sdk iphonesimulator` 冒烟；`MobileReleaseNotesCatalog` 1.11.0 条目 4 语渲染；`Scripts/lint.sh` i18n 全译无 `state:"new"`。

---

## 修订记录
- **Round 0（2026-06-03）**：初稿。测试矩阵聚焦 parser 缓存失效 + 跨版本透传不崩 + 值修正真机验证。
