# 026 — v0.32.x 同步 · 设计文档

[00 总体](00-overview.md) · **01 设计** · [02 开发+架构](02-development.md) · [03 测试](03-testing.md)

---

## 1. 一句话设计

本批上游**无新 wire 字段、无新 iOS 卡片**（[00 §5](00-overview.md) 已确认：无新 provider、`UsageSnapshot`/`Shared/Models` 零变动）。设计 = 三件事：
1. **Codex parser 缓存失效**（唯一必须的 fork 代码改动）；
2. **值修正经现有 synced 字段自动透传**（验证为主，零 iOS 代码）；
3. **iOS scope 决策**（Mac-only vs ship 1.11.0）。

---

## 2. 字段级落点（逐特性）

### 2.1 Codex parser 重写 → 缓存失效（路径：缓存失效，非 wire）
- 上游改了 `Sources/CodexBarCore/Vendored/CostUsage/`（+903/-91，含新 `CostUsageScanner+CodexFastJSON.swift`、`CostUsageScanner.swift` +646、`CostUsagePricing.swift` +10）。
- **不新增 wire 字段**：Codex/Claude 成本仍经现有 `SyncCostSummary` / 成本卡同步。
- **失效轴**（见 `CostUsageCache.swift`）：
  - `producerKey`（codex-only）= `"codex:cu:p<CodexParserHash.value>"` → 跑 `Scripts/regenerate-codex-parser-hash.sh` 滚动。
  - `pricingFingerprint`（全 provider，Claude 唯一轴）= `"v<parserLogicVersion>|codex=…|claude=…"` → bump `parserLogicVersion` 滚动（`CostUsagePricing.swift` 若新增定价条目也会滚，但仍显式 bump 以覆盖 Claude scanner 改动）。
- **落点**：`CodexParserHash.generated.swift`（脚本生成）+ `CostUsagePricing.swift` 的 `parserLogicVersion N→N+1` + 历史注释。**Mac 端缓存重扫 → 纠正后的成本数据自动同步到 iOS（零 iOS 改动）。**

### 2.2 Antigravity 配额行过滤 #1209（路径 A 自动透传）
- Mac 侧 `AntigravityStatusProbe.swift`（+160）过滤噪声 OAuth 配额行后，经现有 `extraRateWindows` / `rateWindows[]` 同步；iOS `ProviderUsageView.ForEach(allRateWindows)` 自动渲染过滤后的行。**零 iOS 代码**；验证 iOS Antigravity 卡显示更干净。

### 2.3 Copilot 零权利 % #1258（路径 B 自动透传）
- Mac `CopilotUsageFetcher.swift`（+15）修正 zero-entitlement 场景的 %；经现有 Copilot synced 字段透传。**零 iOS 代码**；验证 iOS Copilot 卡不再误导。

### 2.4 Augment 解析 + cookie fallback #1224（路径 B）
- Mac `Auggie*`/`Augment*`（解析格式更新 + 浏览器 cookie fallback）；数值经现有 Augment synced 字段透传。**零 iOS 代码**；验证数值正确。

### 2.5 Claude 快照保留 #1220 / OAuth 委托 #1239（路径 B，可靠性）
- Mac `ClaudeOAuthCredentials.swift`（+98）等；短暂 Unauthorized 不清零 + refresh-token 委托 CLI。提升 Mac 端数据新鲜度/凭证健康，经现有 Claude synced 字段透传。**零 iOS 代码**；验证 iOS Claude 不闪空。

---

## 3. iOS scope 决策（G4）

| 选项 | 内容 | MOBILE | 适用 |
|---|---|---|---|
| **A. Mac-only** | iOS 零代码改动，值修正经同步自动到达 iOS；不发 iOS build | `1.10.0` 不动 | 若确认无任何 iOS 可见增量 |
| **B. iOS 配套 ship**（默认倾向） | 零功能代码，但刷新 `MobileReleaseNotesCatalog`（1.11.0 条目说明本批值修正）+ 版本 bump，配套上 TestFlight | `1.11.0` | PM"尽可能全支持" + release notes 一致性 |
| **C. iOS + 可选增强** | B + 实现 provider 列表搜索（对应上游 Settings 搜索 #1184） | `1.11.0` | 仅当用户明确要这个增强 |

**默认走 B**（配套 ship，零功能代码，只 release notes + 版本）。Round 1 合并后复核确无 iOS 代码改动需求即锁定 B；若用户要 provider 搜索则转 C。

---

## 4. Mock / i18n

- **无新结构 → 无需新 mock**（除非走 C 加 provider 搜索）。
- **i18n**：仅当走 B/C 且新增 `MobileReleaseNotesCatalog` 1.11.0 条目时，新文案 4 语（en/zh-Hans/zh-Hant/ja），照 025 的 xcstrings 加法（json.load → 加 key → dump 不排序，零 churn）。

---

## 修订记录
- **Round 0（2026-06-03）**：初稿。确认无新 wire/卡片；设计聚焦 parser 缓存失效 + 值修正透传验证 + iOS scope 决策（默认 B 配套 ship）。
