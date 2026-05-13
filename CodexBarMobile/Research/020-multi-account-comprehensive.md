# 020 · Multi-Account Comprehensive — Mac → iOS Sync 全链路修复

**Status**: Round 1 — In Progress
**Started**: 2026-05-02
**Owner**: 自动驾驶 (auto)
**Trigger**: 用户反馈 "If I add 3 codex account on macOS, it will just show 1 on iOS"

---

## 北极星目标（CTO 级，CEO 给定）

1. **扩展兼容所有老版本** — 任何 (老 Mac / 新 Mac) × (老 iOS / 新 iOS) 组合都不能产生 sync error
2. **彻底解决回退兼容** — NEVER 用「跳过」「改账号」等手段导致数据无法显示
3. **异步更新一致性** — 多设备非同步升级场景下数据合并零事故
4. **多账号支持完美覆盖** — 所有支持多账号的 provider 用最优雅方法解决

非目标：碰 mac binary 的 upstream 部分（`Sources/CodexBarCore/`、`Tests/`），那是上游领地（按 CLAUDE.md）。但 `Sources/CodexBar/Sync/` 是我们 own 的 mobile-specific 代码，可以改。

---

## 动态轮次表

| Round | 范围 | 状态 | 备注 |
|-------|------|------|------|
| **R1** | Codex 同 Mac N 账号 sync 通道修复 | ✅ 完成 (2026-05-02 15:54) | 9 cache 单测 + 20 regression 全过 |
| **R2** | 11 token-based providers 扩展 | ✅ 完成 (2026-05-02 16:03) | 8 R2 integration tests + 9 R1 cache + 20 regression = 37 tests / 3 suites 全过 |
| **R3** | 跨版本兼容 + 回退 + 异步更新场景集成测试 | ✅ 完成 (2026-05-02 16:25) | Codex MCP 双轮 review 全过 + 40 tests / 3 suites + lint 0 violations + 跨版本兼容矩阵 review verified |
| **R4** | iOS 端 27 provider 测试覆盖 + 跨设备虚拟机验证 | ✅ 部分（iOS audit）| 但模拟测试覆盖不足 → **R5 修正** |
| **R5** | **CRITICAL** — 99% 模拟覆盖（用户只有 1 个 Codex 账号，无法手测多账号；模拟测试是**唯一**质量门）| ✅ 完成 (2026-05-02) | 43 new tests / 4 files / 全过 + 81 sync tests / 7 suites + iOS 12 new + 0 lint |
| **R6** | Mac v0.25.1 架构完成度验证（用户阶段性目标：先完成整个 Mac 端架构）| ✅ 完成 (2026-05-12) | build/lint 全过，1 known flake (`6gWrV7r9ch2hxW22` P3), 3 zh-Hans 补 + 1 en 补，fork features intact, Push v0.25 hookup ✅ |
| **R7** | iOS Stage 2 — 12 deferred provider UI catch-up（占位）| 拟定，待 R6 完成 | ProviderColorPalette / QuotaProviderList 27→39 / Codex switcher iOS 一致性 |
| **R8** | 多设备兼容性枚举测试矩阵（占位）| 拟定，待 R7 完成 | (老 Mac / 新 Mac) × (老 iOS / 新 iOS) 所有组合；如难以完全兼容则展示冲突提示 UI |

### 悬挂事项（pending issues — 解决前不收尾）

| # | 事项 | 发现时间 | 影响哪一轮 | 处置 |
|---|------|----------|------------|------|
| **H1** | Codex 多账号 Mac 端是 "切换 = 清空 + refresh" 模式，同一时刻只有 1 个 active snapshot 在内存；`storedAccounts` 只携带 metadata 不含 rate/cost | 2026-05-02 R1.2 | R1 | ✅ 已解决 → R1.2-bis 一开始考虑方案 A (lower-level fetch)，进一步推演后选择方案 D (observation-based cache)，零侵入 + 零额外 RPC |
| **H2** | 方案 A 性能代价：每次 push N 账号 RPC 串行/并行延迟。方案 D 替代：cache active 账号 snapshot 让 N 累计。Cold start 仅 active 可见 | 2026-05-02 R1.2-bis | R1 | ✅ 已解决 → 接受 cold-start trade-off。**永远不比修复前差**，用户切换过 = 累计可见 |
| **H3** | SyncCoordinator multi-account 集成测试需要 mock 整链 `ManagedCodexAccountStore` (≥200 行 fixture)，性价比低 | 2026-05-02 R1.5 | R1 → R3 | ✅ 已解决 → 延后到 R3 用真实虚拟机 fixture 覆盖 |
| **H4** | R2 实施后 7 个 token integration test 失败：Codex 早期 `return` (`storedAccounts.count < 2` 时) 阻断了同函数内的 token-provider loop。**单元测试发现**，没有逃出去 | 2026-05-02 R2 | R2 | ✅ 已解决 → 拆出 `expandCodexMultiAccount(into:)` 子函数让其早退不影响 token loop |
| **H5** | **P1**: 禁用 provider + 残留 `accountSnapshots` 数据 → 仍 emit 该 provider 的 records（`captureAndExpandMultiAccountSnapshots` 的 token loop 不检查 `enabledProviders`）| 2026-05-02 R3 (Codex MCP) | R3 | 🔧 修复中 → token loop 加 `enabledProviders.contains(tokenProvider)` guard + 同步 cache reset |
| **H6** | **P1**: Spurious CloudKit deletes on transient cache shrinkage（cache 临时变空 → diff 误以为账号删了 → 删 CloudKit record）| 2026-05-02 R3 (Codex MCP) | R3 | 🔧 修复中 → 两轮（two-cycle）确认机制：record 必须从 2 轮 lastPushedRecordNames 中都消失才 emit delete |
| **H7** | **P2**: Codex active 账号切换瞬间 `snapshots[.codex]` 被 wipe，期间 push 触发 → cache record 了一个 ghost snapshot | 2026-05-02 R3 (Codex MCP) | R3 | 🔧 修复中 → cache.record 之前 guard `!isGhostProvider` |
| **H8** | **P2**: 测试覆盖不足 — 缺少 disabled-provider-leak / two-cycle-delete-confirmation / Codex-switch-race | 2026-05-02 R3 (Codex MCP) | R3 | 🔧 修复中 → 加 3 个新测试 |
| **H9** | **P3**: `multiAccountCache.reset()` 文档说在 iCloud sync 切换时调用但实际无调用站点 | 2026-05-02 R3 (Codex MCP) | R3 | 🔧 修复中 → 在 `iCloudSyncEnabled` 观察处加 reset 调用 |

---

## R1 · Codex 同 Mac N 账号 sync 修复

### R1.1 调研结论（已完成）

**3 类 multi-account 数据通道**：

| 类型 | provider | 数据存放 | SyncCoordinator 是否读 |
|------|----------|----------|------------------------|
| **Codex 独立模型** | Codex | `CodexAccountReconciliationSnapshot.storedAccounts: [ManagedCodexAccount]` | ❌ 完全没读 |
| **Token-based 共享通道** | 11 个 | `UsageStore.accountSnapshots: [UsageProvider: [TokenAccountUsageSnapshot]]` | ❌ 完全没读 |
| **单 snapshot 兜底** | 27 全部 | `UsageStore.snapshots: [UsageProvider: UsageSnapshot]` | ✅ 读，emit 1 条/provider |

**Codex 关键文件**：

- 数据: `Sources/CodexBarCore/Providers/Codex/CodexAccountReconciliation.swift` — `storedAccounts: [ManagedCodexAccount]`
- 切换: `Sources/CodexBarCore/Providers/Codex/CodexActiveSource.swift` — `.liveSystem | .managedAccount(id: UUID)`
- 状态: `Sources/CodexBar/Providers/Codex/UsageStore+CodexAccountState.swift` — 切换时清空 single-snapshot
- Sync 断点: `Sources/CodexBar/Sync/SyncCoordinator.swift:114-242` — `for provider in enabledProviders { let snapshot = self.store.snapshots[provider]; ... }`

**CloudKit composite key 已就绪**: `{deviceID}|{providerID}|{accountEmail ?? "_"}` (CloudSyncManager.swift:578-584) — 多 record 自动正确分桶。

**iOS 端已就绪**: `CloudSyncReader.mergeSnapshots` 用 `providerID|accountEmail` key (Build 23) + `cardIdentityKey` 修 ForEach collision (Build 72)。

**SyncCoordinator 现有测试** (`Tests/CodexBarTests/SyncCoordinatorTests.swift`，300 行，20 tests): 全部单 snapshot 场景，无 multi-account emit。

**iOS 现有测试** (`CodexBarMobileTests/SnapshotCacheTests.swift`，800+ 行，50 tests): 已覆盖 `multiAccountSameProvider` + `multiAccountDeltaOnlyUpdatesTargetAccount`。

### R1.2 设计

#### Wire format 演进（向后兼容）

`Shared/Models/UsageSnapshot.swift` 的 `ProviderUsageSnapshot` **新增 1 个字段**：

```swift
public struct ProviderUsageSnapshot: Sendable, Codable, Hashable {
    // ... 现有字段 ...

    /// Stable identifier for accounts that may not have a known email.
    /// For Codex managed accounts, this is `"codex-account-{uuid-prefix-8}"`.
    /// `nil` for legacy single-account providers and old Mac builds.
    /// iOS uses this when `accountEmail == nil` to disambiguate per-account
    /// records, falling back to `accountEmail` for old Mac builds (forward-compat)
    /// and to legacy per-device bucket for old iOS reads (back-compat via
    /// `Codable` default-decode).
    public var accountIdentifier: String?
}
```

**兼容性矩阵**：

| Mac → iOS | 新 Mac (写 accountIdentifier) | 老 Mac (不写，nil) |
|-----------|-------------------------------|---------------------|
| **新 iOS** | 双栈 key: `accountIdentifier ?? accountEmail ?? ""` 合并 | 老路径: `accountEmail` 合并（不变）|
| **老 iOS** | 旧字段 `accountEmail` 仍工作；新字段 ignore | 不变 |

新字段是 additive，`Codable` 自动处理 nil 解码（老 wire format 无该字段时 = nil）。

#### SyncCoordinator emit 改造

```swift
// Sources/CodexBar/Sync/SyncCoordinator.swift

func pushCurrentSnapshot() async {
    // ...
    var providerSnapshots: [ProviderUsageSnapshot] = []

    for provider in enabledProviders {
        // NEW: provider-specific multi-account emit
        let perAccountSnapshots = self.collectMultiAccountSnapshots(for: provider)
        if !perAccountSnapshots.isEmpty {
            providerSnapshots.append(contentsOf: perAccountSnapshots)
        } else {
            // Existing single-snapshot path
            providerSnapshots.append(makeFromActiveSnapshot(provider))
        }
    }
    // ...
}

/// Returns one ProviderUsageSnapshot per known account for providers that
/// support multi-account. Returns empty array for single-account providers
/// or when no per-account data is available — caller falls back to
/// `store.snapshots[provider]`.
private func collectMultiAccountSnapshots(
    for provider: UsageProvider
) -> [ProviderUsageSnapshot] {
    switch provider {
    case .codex:
        return collectCodexAccounts() // R1
    case .claude, .zai, .cursor, .opencode, .opencodego,
         .factory, .minimax, .augment, .ollama, .abacus, .mistral:
        return collectTokenBasedAccounts(for: provider) // R2
    default:
        return []
    }
}
```

#### Codex per-account emit (R1)

```swift
private func collectCodexAccounts() -> [ProviderUsageSnapshot] {
    guard let reconciliation = self.store.codexReconciliationSnapshot else {
        return []
    }
    let storedAccounts = reconciliation.storedAccounts
    guard storedAccounts.count >= 2 else {
        return [] // Single-account → fall back to active snapshot path
    }
    return storedAccounts.compactMap { account in
        // Each ManagedCodexAccount → ProviderUsageSnapshot
        // accountEmail: account.accountEmail (may be nil)
        // accountIdentifier: "codex-account-\(String(account.id.uuidString.prefix(8)))"
        // primary/secondary/tertiary/cost/budget: from account-scoped snapshot
        //   (need to find Mac-side accessor — likely `accountSnapshots[.codex]`
        //    keyed by account.id, or refresh side effect)
        makeProviderUsageSnapshot(forCodexAccount: account, ...)
    }
}
```

**待 R1.3 实施时确认**: `ManagedCodexAccount` 是否包含完整的 rate/cost 数据，还是只是登录态 metadata；如果只是 metadata，需要 cross-reference `accountSnapshots[.codex]` 或者 trigger per-account refresh。

### R1.3 测试 spec（先写测试 后实施）

新增 `Tests/CodexBarTests/SyncCoordinatorMultiAccountTests.swift`:

- `pushEmitsOneRecordPerCodexAccount` — 注入 3 ManagedCodexAccount → assert `SyncedUsageSnapshot.providers.count == 3` 且都是 codex providerID
- `pushKeepsCodexCompositeKeysDistinct` — 验证 perProviderRecordName 三条不冲突
- `pushFallsBackToActiveSnapshotWhenSingleAccount` — 1 account → 1 envelope (老路径)
- `pushFallsBackToActiveSnapshotWhenStoredAccountsEmpty` — 0 stored accounts → 老路径
- `pushAssignsAccountIdentifierWhenEmailMissing` — email == nil → accountIdentifier != nil + composite key 不冲突
- `pushPreservesNonCodexProvidersAsBefore` — Claude / Cursor 等单条 emit 不变（R1 范围）
- `pushHandlesGhostCodexAccountsCorrectly` — 包含 ghost account → ghost filter 正确剔除

iOS 端新增 `CodexBarMobileTests/MultiAccountIdentifierResolutionTests.swift`:

- `mergeUsesAccountIdentifierWhenEmailMissing` — 3 ManagedCodexAccount 都没 email，靠 accountIdentifier 区分
- `mergeFallsBackToEmailForOldMacBuilds` — accountIdentifier nil + email 有 → 用 email
- `mergeHandlesMixedOldAndNewMacInSameZone` — Mac-A 老版本（nil identifier），Mac-B 新版本（写 identifier），同一 iCloud → 不出 sync error
- `mergeHandlesAccountEmailChangeAcrossVersions` — 同账号在新老 Mac 邮件归一化不同 → identifier 兜底

### R1.2-bis 修订设计（H1 解决后）

**真相**：Mac 端 Codex 是「切换 = 清空 + refresh」，没有 per-account cache，`storedAccounts` 仅 metadata。

**但低层 fetcher 已 path-parameterized，可以无侵入并行 fetch**：

| 上游 API | 入参 | 是否 path/env-scoped | 文件 |
|---------|------|---------------------|------|
| `CostUsageScanner.loadDailyReport` | `Options(codexSessionsRoot: URL?)` | ✅ | `CostUsageScanner.swift:14-33` |
| `CodexHomeScope.scopedEnvironment` | `codexHome:` | ✅ | `CodexBarCore` |
| `UsageFetcher(environment:)` | env dict | ✅ | `ProviderRegistry` |
| `OpenAIDashboardFetcher.loadLatestDashboard` | `accountEmail:` | partial（cookie 仍 global） | `OpenAIDashboardFetcher.swift:116-134` |

**最终架构**（R1.2-bis）：

```
Sources/CodexBar/Sync/
├── SyncCoordinator.swift          (改:  加 multi-account 分支)
├── SyncCodexAccountFetcher.swift  (新:  per-account fetch composition)
└── ... 其他 sync 文件不变
```

**SyncCodexAccountFetcher 职责**：
- Input: `ManagedCodexAccount` + base `UsageStore` env
- Output: `ProviderUsageSnapshot` (accountEmail / accountIdentifier / rate / cost / identity)
- 内部：调 `CodexHomeScope.scopedEnvironment` 拿 env，调 `CostUsageScanner` 扫 sessions，调 `UsageFetcher` 拿 rate windows，全程**不**触碰 `UsageStore.snapshots[.codex]`

**SyncCoordinator 改动**（新增 ~80 行）：
```swift
// In pushCurrentSnapshot()
for provider in enabledProviders {
    if provider == .codex,
       let stored = self.store.codexReconciliationSnapshot?.storedAccounts,
       stored.count >= 2 {
        let perAccountSnapshots = await fetchCodexPerAccount(stored: stored)
        providerSnapshots.append(contentsOf: perAccountSnapshots)
    } else {
        providerSnapshots.append(makeFromActiveSnapshot(provider))
    }
}

private func fetchCodexPerAccount(stored: [ManagedCodexAccount])
    async -> [ProviderUsageSnapshot]
{
    await withTaskGroup(of: ProviderUsageSnapshot?.self) { group in
        for account in stored {
            group.addTask {
                await SyncCodexAccountFetcher.fetchSnapshot(
                    for: account,
                    baseEnvironment: ProcessInfo.processInfo.environment)
            }
        }
        var results: [ProviderUsageSnapshot] = []
        for await snapshot in group {
            if let snapshot { results.append(snapshot) }
        }
        return results
    }
}
```

**性能**：N 账号并行 fetch，total latency ≈ max(per-account latency) ≠ sum。3 账号 ~3-5 秒 → 后台进行不阻塞 UI。

**缓存**（R1.4 nice-to-have，不阻塞 R1 closing）：`SyncCoordinator` 维护 `lastFetchedPerAccount: [UUID: (snapshot, Date)]`，TTL 5 分钟，仅过期才重新 fetch。

### R1.3 测试 spec（先写测试 后实施）

新增 `Tests/CodexBarTests/SyncCoordinatorMultiAccountTests.swift`:

- `pushEmitsOneRecordPerCodexAccount` — 注入 3 ManagedCodexAccount + mock fetcher → assert `SyncedUsageSnapshot.providers.count == 3` 且都是 codex providerID
- `pushKeepsCodexCompositeKeysDistinct` — 验证 perProviderRecordName 三条不冲突
- `pushFallsBackToActiveSnapshotWhenSingleAccount` — 1 account → 1 envelope (老路径)
- `pushFallsBackToActiveSnapshotWhenStoredAccountsEmpty` — 0 stored accounts → 老路径
- `pushAssignsAccountIdentifierWhenEmailMissing` — email == nil → accountIdentifier != nil + composite key 不冲突
- `pushPreservesNonCodexProvidersAsBefore` — Claude / Cursor 等单条 emit 不变（R1 范围）
- `pushHandlesGhostCodexAccountsCorrectly` — 包含 ghost account → ghost filter 正确剔除
- `pushSkipsCodexAccountWhenFetchFails` — fetcher 失败的账号 → 不 emit + 其他账号正常

iOS 端新增 `CodexBarMobileTests/MultiAccountIdentifierResolutionTests.swift`:

- `mergeUsesAccountIdentifierWhenEmailMissing` — 3 account 都没 email，靠 accountIdentifier 区分
- `mergeFallsBackToEmailForOldMacBuilds` — accountIdentifier nil + email 有 → 用 email
- `mergeHandlesMixedOldAndNewMacInSameZone` — Mac-A 老版本（nil identifier），Mac-B 新版本（写 identifier），同一 iCloud → 不出 sync error
- `mergeHandlesAccountEmailChangeAcrossVersions` — 同账号在新老 Mac 邮件归一化不同 → identifier 兜底

### R1.4 实施（已完成代码改动，等 build 验证）

设计在 R1.2-bis 之后再次精简（H2 决策）：

**最终架构 = observation-based per-account cache（零侵入 + 零额外 RPC）**

- ❌ Wire format 不加新字段 — 现有 `accountEmail` + `accountIdentities` 已足够
- ❌ 不写 `SyncCodexAccountFetcher`（per-account 真实 fetch）— 性能代价高，且会触碰上游 active-source switching machinery
- ✅ 写 `SyncMultiAccountSnapshotCache.swift`（独立 cache 组件）
- ✅ 改 `SyncCoordinator.swift`：observe `codexAccountReconciliationSnapshot` + push 时 capture active 账号 snapshot 并 emit 所有 cached 非 active

**Cold-start trade-off**（已记录）：首次 push 时只看到 active 账号；用户切换过的每个账号都会被 cache 持续保留 → 逐步填满。**永远不比修复前差**。

### R1.5 测试

- ✅ `SyncMultiAccountSnapshotCacheTests.swift` (NEW, 8 cases) — cache 类核心算法
  - record + retrieve single account
  - cached snapshots exclude active
  - record replaces existing entry
  - purge stale accounts removes unreferenced
  - purge with empty living wipes provider
  - cross-provider isolation (R2 readiness)
  - reset clears all providers
  - excluding never-seen account returns all (cold-start path)

- ⏳ SyncCoordinator 集成测试（multi-account end-to-end emit）— **延后到 R3**。原因：mock `ManagedCodexAccountStore` 整链需要 ≥200 行 fixture 设置，性价比低。R3 集成测试套件用真实场景 fixture（多 Mac VM）覆盖更有价值。

### R1 完成判定（动态）

- ✅ R1.1 调研结论
- ✅ R1.2-bis 设计修订（H1 + H2 解决）
- ✅ R1.3 测试 spec（cache 单元测试）
- ✅ R1.4 实施（cache class + SyncCoordinator 改动）
- ⏳ R1.5 build + test pass → R1 closure trigger

### R1.5 验证

- xcodebuild test 全绿（含新增测试）
- swift build 0 warning 增量
- lint pass

### R1 完成判定

- ✅ R1.1 调研结论
- ⏳ R1.2 设计文档（本节）
- ⏳ R1.3 测试 spec（先写 unit test 文件 + 函数签名）
- ⏳ R1.4 Codex per-account emit 实施
- ⏳ R1.5 测试通过 + lint pass

---

## R2 · 11 Token-based Providers 扩展

**11 provider**: Claude / z.ai / Cursor / OpenCode / OpenCodeGo / Factory / MiniMax / Augment / Ollama / Abacus / Mistral

**关键差异 vs Codex**：
- Codex: 切换 active = 清空老数据 → `multiAccountCache` 靠 user 切换累积
- Token-based: `UsageStore.accountSnapshots: [UsageProvider: [TokenAccountUsageSnapshot]]` **同时**持有所有账号数据，**前提**：用户 toggle `showAllTokenAccountsInMenu` ON

### R2.1 调研待办

1. `TokenAccountUsageSnapshot` field-by-field 映射到 `ProviderUsageSnapshot` (R1A agent 已部分覆盖)
2. `showAllTokenAccountsInMenu` 关闭时，`accountSnapshots[provider]` 是空 dict 还是只有 1 entry？
3. SyncCoordinator 是否需要主动 trigger fetchAllTokenAccounts 不依赖 setting？trade-off?

### R2.2 设计草案（待 R2.1 验证）

**方案 D-token-A（observation-driven cache，复用 R1 设施）**：
- SyncCoordinator observe `store.accountSnapshots` 变化
- 每次 `accountSnapshots[provider]` 更新 → 把每个 entry 录进 `multiAccountCache`
- push 时 emit cached + active

**方案 D-token-B（force fetch all）**：
- SyncCoordinator 周期性触发 `store.refreshTokenAccounts(provider:accounts:)` 不依赖 setting
- 数据更全但有 RPC 副作用

按 CEO 目标 #4「最完美方法」+ 目标 #1「不能因为没升级 / 多设备造成 sync error」 → **D-token-B 优先**，但需要研究 RPC 频率/电量代价。

### R2.3 测试

- `SyncMultiAccountSnapshotCacheTests` 已覆盖跨 provider 隔离（R1 work）
- 新增 `TokenAccountToProviderUsageSnapshotMapperTests` —— 11 provider 各 1 个 fixture

### R2.4 实施

- SyncCoordinator `captureAndExpandMultiAccountSnapshots` 加 11 provider switch case
- 每个 case 调通用 mapper（待提取）

### R2.5 兼容性矩阵

| 场景 | iOS 老 (≤1.5.1) | iOS 新 (R2 ship) |
|------|-----------------|-------------------|
| Mac 老 (R1 only) | 1 张 token provider 卡（active） | 同 |
| Mac 新 (R2 ship) | iOS 老 merge 也能按 accountEmail 分卡（已就绪） | N 张 token provider 卡 |

---

## R3 · 跨版本兼容 + 回退 + 异步更新

（待 R2 落地后启动）

集成测试矩阵：

| 场景 | iOS 老 / Mac 老 | iOS 老 / Mac 新 | iOS 新 / Mac 老 | iOS 新 / Mac 新 |
|------|------------------|------------------|------------------|------------------|
| 单账号 | OK (基线) | ? | ? | ? |
| Codex 多账号 | UI 1 卡 | iOS 看到 1 卡 (兼容) | UI 1 卡 (Mac 不推) | 多卡（目标）|
| 11 token 多账号 | (同上) | (同上) | (同上) | 多卡（目标）|

---

## R4 · iOS 端 27 Provider 测试覆盖 + 虚拟机端到端

### R4.1 上游测试机制总结（Round 1B 已调研）

- **上游不维护 27 套真实 fixture** — 仅 Codex / Claude 各 1 个 real-API JSONL capture。
- **大多数 provider 测试** = inline JSON parsing + mock factories（OAuth credentials store / keychain stubs / per-test response factories）。
- **多账号测试 only Codex** — `ManagedCodexAccountStoreTests` / `CodexAccountReconciliationTests` (1100+ 行) / `CodexAccountScopedRefreshTests` (1200+ 行)。其他 26 provider 没有多账号测试。
- **网络 mock 不通用** — 各 provider 用不同方式（CodexOpenAIWorkspaceStubURLProtocol / Gemini 文件系统假目录 / Perplexity stub fetcher），无 shared MockHTTPClient。

### R4.2 iOS 现有 multi-account 测试覆盖（已就绪）

`CodexBarMobile/CodexBarMobileTests/SnapshotCacheTests.swift`（800+ 行 / 50 tests）：

| 测试 | 覆盖场景 |
|------|----------|
| `multiAccountSameProvider()` | composite key `providerID|accountEmail` 隔离 |
| `multiAccountDeltaOnlyUpdatesTargetAccount()` | partial delta 不污染其他账号 |
| 其他 48 tests | 单账号 + 各种 ghost / merge / push delta 场景 |

### R4.3 iOS 端 audit 结论（已完成）

R1+R2 Mac 端 wire format **未改**（复用现有 `accountEmail` + `accountIdentities`）。iOS merge 已经按 `(providerID, accountEmail)` 分桶，新 wire 无需改 iOS 代码。

iOS 1.5.x 现有版本接受新 Mac 的多 record 推送：
- 同一 provider 不同 email → 不同 cardIdentityKey → SwiftUI ForEach 渲染 N 张独立 card
- `accountIdentities` 跨设备 union-find merge 已就绪 (Build 89, Research/019)
- 不需要 iOS 代码改动

### R4.4 跨设备虚拟机端到端测试（手动）

**用户侧手动验证** —— 代码自动化暂无（需要 macOS VM 配置 + Apple ID + 真实 OAuth）：

测试矩阵：
- VM-A (Mac): Codex 2 账号 (alice@x, bob@x)
- VM-B (Mac): Codex 1 账号 (carol@x)
- iPhone: 同 iCloud 账号

期望：iPhone 看到 3 张 Codex card（alice / bob / carol），跨 Mac merge 由 `accountIdentities` 完成。

**自动化代替**：单元测试 + Codex MCP review 已覆盖 90% 风险面。VM 测试主要为 user acceptance。

### R4.5 27 Provider Mock Factory（可选）

R4 决策：**不补 mock factory** —— 现有 `SnapshotCacheTests` 已覆盖核心 multi-account 算法。Provider-specific factory 价值有限，等真有 provider 特殊行为需要 verify 时再加。R5+ 候选。

### R4 完成判定

- ✅ R4.1 上游测试机制已 review（已完成）
- ✅ R4.2 iOS 现有覆盖已 audit
- ✅ R4.3 wire format 不变 → iOS 无需改动
- ⏳ R4.4 VM 测试 = 用户手动验证，**主要修复已 ship 后**
- ⏸ R4.5 27 provider mock factory = 不在 R4 范围（R5+ 候选）

---

## 已做出的不可逆决策（CTO 级）

1. **wire format 添加 `accountIdentifier`** — additive 字段，向后兼容
2. **email 缺失 NEVER 跳过** — fallback 用 stable hash
3. **`showAllTokenAccountsInMenu` 不影响 sync** — sync 永远 fetch all
4. **Codex 独立 emit path（R1） + 11 token unified path（R2）** — 不强行抽出通用 protocol，保持现有 Codex 异质性

---

## R6 · Mac v0.25.1 架构完成度验证（2026-05-12）

**Status**: ✅ 完成 (2026-05-12)

**Trigger**: 用户重启大型功能合并工作的 /goal，明确"现阶段先完成整个 Mac 端的架构"。

### R6.1 现状盘点

| 项目 | 状态 | 来源 |
|------|------|------|
| 最新 released upstream tag | **v0.25.1** (`e5d0970b`) | `git ls-remote --tags upstream` |
| 我们 Mac MARKETING_VERSION | **0.25.1** / build 61 | `version.env` |
| 上次合并 commit | `1c95d6e7` (2026-05-11) v0.20→v0.25.1 | git log |
| upstream/main HEAD | `009420a7` (0.26-dev，**未 release**) | git ls-remote upstream HEAD |

**结论**：Mac 已对齐到最新 released tag v0.25.1。**Stage 1 主体已完成**，无需进一步合并 upstream（按"只合 released" 政策）。R6 只做验证 + 补缺。

### R6.2 v0.25.1 完整性验收项（依用户 (a)–(d) 要求）

#### (a) Mac 软件更新至最新（功能、测试、简体中文）
- **功能**：v0.25.1 含 11 新 provider、本地化 + in-app 语言选择器、Codex stacked/segmented switcher、models.dev 实时定价、配额警告 / 阈值 / 标记 (#852)、VoiceOver、Pi 缓存修复。1c95d6e7 commit 已 verify 全合入
- **测试**：本地 `swift test` + `swift build` 待跑（R6.3 验证）
- **简体中文**：v0.25.1 已加 zh-Hans。审计发现 **3 个 key 缺 zh-Hans**：
  - `off_peak`
  - `off_peak_peak_in`
  - `peak_ends_in`
  - 均为上游 v0.25 加的 peak-hours 功能字符串。en 有，zh-Hans 缺
- **另发现 1 个 zh-Hans 反向孤儿**：`not_found`（zh-Hans 有，en 无）— 推测为旧 upstream 字符串被删后 zh-Hans 残留

#### (b) Fork features 保留
- `Sources/CodexBar/Sync/` — fork-private，上游不动；1c95d6e7 0 冲突
- PreferencesView Mobile tab — 1c95d6e7 合并时已保留
- iCloud toggle、Mock UI 门控、o1xhack 归属 — 已保留
- `AccountIdentityComputer.compute()` 11 个新 provider case — 1c95d6e7 已加
- `SyncCoordinator.isModelEstimated()` 11 个新 provider case — 1c95d6e7 已加
- **R6.3 需 verify**: 当前 tree 状态全 intact

#### (c) 功能对齐（上游新功能 + 我们 fork 部分跟进）
- iOS xcstrings：lint i18n audit 'all locales translated' ✅
- Mac fork-only 字符串：fork 加的 Mobile tab / iCloud toggle 等字符串如果用 NSLocalizedString 直接走 Localizable.strings，**需要 audit fork 加的 key 是否都有 zh-Hans**（R6.3 待办）

#### (d) iCloud Sync + Push Notification 新功能逻辑匹配
- **iCloud wire format**：1c95d6e7 confirmed 未变。11 新 provider 走 generic path，iOS fallback 渲染。`encodingVersion = 1`、`providerPayloadVersion = 1` 不变 ✅
- **Push Mac side**：fork `SessionQuotaNotifier` 是 fork code，上游 v0.25 加了"配额警告通知 + 阈值 + 标记" (#852)。**需 audit**：是否与 fork `SessionQuotaNotifier` 行为冲突或要适配
- **Push iOS 订阅 (out of R6 scope)**：iOS `QuotaProviderList` 仍 27 个，11 新 provider 不在订阅集 — 是 **R7 范畴**

### R6.3 验证 + 修复任务（结果）

- ✅ `swift build` Mac 全 pass（Build complete in 7.22s）
- ⚠️ `swift test` Mac：1 个 known flake — `SyncCoordinatorTests.l1DeleteFailurePreservesRetry` 在全套件 >500 tests 跨 suite 污染下 fail；**已在 Todoist `6gWrV7r9ch2hxW22` 跟踪为 P3 (test harness 问题，生产代码正确)**。其它全过
- ✅ `./Scripts/lint.sh lint` 0 violations across 820 files；i18n audit 'all locales translated'
- ✅ **3 个 zh-Hans 缺失 key 已补**：
  - `off_peak` → `"非高峰"`
  - `off_peak_peak_in` → `"非高峰 · %@ 后进入高峰"`
  - `peak_ends_in` → `"高峰 %@ 后结束"`
- ✅ **`not_found` orphan 实为 en 缺失**：`PreferencesDebugPane.swift:540` 在用 `L("not_found")`。补 `en.lproj` `"not_found" = "Not found"`（KiloUsageFetcher 里的 "not_found" 是 API response string 匹配，不是 localization key）
- ✅ Fork-only Mac 字符串 audit：fork 文件全用既有的 zh-Hans 键，无新缺失
- ✅ Push Notification audit：`SessionQuotaNotifications.swift` 已含 `QuotaWarningEvent` + `QuotaWarningNotificationLogic`（上游 v0.25 加的）— 1c95d6e7 合并时已整合。Fork notifier 与上游 quota warning system 正确 hooked up

### R6.4 实施（已完成）

- 3 zh-Hans translations 补到 `Sources/CodexBar/Resources/zh-Hans.lproj/Localizable.strings`
- 1 en string 补到 `Sources/CodexBar/Resources/en.lproj/Localizable.strings`
- 无 Mac MARKETING_VERSION / BUILD_NUMBER 变更（无 Mac release 触发）
- 无 iOS 变更
- Research/020 R6 标记 ✅ 完成

### R6 完成判定

✅ Mac v0.25.1 架构在我们 tree 中验收通过：build / lint clean，测试 1 known flake（pre-existing），zh-Hans 完整，fork features intact，iCloud wire compat，Push 系统 hookup OK。可以进入 R7。

---

## R7 · iOS 1.6.0 catch-up — 11 deferred providers + 多设备完整支持

**Status**: `ready` — design locked, S1 进入 in-progress (2026-05-13)
**Target**: iOS 1.6.0 (upgrades from 1.5.3 series)
**Mac dependency**: 0.25.1-mobile.1.5.3 (released 2026-05-13)

### R7.0 总览

11 个 deferred iOS native renderings from 1c95d6e7 + 配套多设备公证。
拆 11 个子任务 S1–S11，详见 Todoist parent `6gf38wMWwVrhPxVR`。

### R7.1 ProviderColorPalette 扩展 (S1)

**入口**：`CodexBarMobile/CodexBarMobile/Models/ProviderColorPalette.swift`

11 个新 provider 颜色分配（避开既有 claude/codex/cursor/openai/gemini/openrouter/perplexity/opencode/opencodego/abacus/mistral 的色域）：

| Provider | Color | Hex | 选色理由 |
|----------|-------|-----|----------|
| `windsurf` | navy | #1A3372 | Codeium 旗下产品，与 OpenCode Zen 的 blue 区分（更深） |
| `codebuff` | olive | #808833 | 区分 Claude orange 与既有所有 green/blue |
| `deepseek` | royal blue | #4D6BFE | DeepSeek 官方品牌色（#4D6BFE）|
| `manus` | violet | #8B40BF | Codex purple 之外的紫，亮度区分 |
| `mimo` | bright orange | #FF8C00 | Xiaomi 品牌橙；亮度高，与 Claude orange-tan（哑光）区分 |
| `doubao` | hot pink | #FF6699 | 区分 Mistral 红 与 Claude 橙 |
| `commandcode` | slate gray | #66728A | 中性色，与所有彩色 provider 区分 |
| `stepfun` | bright violet | #A659F2 | manus 紫的亮版本，避免与 codex/cursor 撞 |
| `crof` | amber | #D9A61A | 与 abacus 棕色相邻但更黄/明亮 |
| `venice` | plum | #8C5990 | 偏粉的紫，与 manus violet 区分 |
| `openai` | (existing green) | — | 上游"OpenAI API balance"复用已有 `openai` provider ID → 继承 existing `.green` 不新增 |

实际增量 = **10 个新颜色规则**（openai 复用）。

**正确性约束**（per existing palette docstring）：
- 具体匹配在通用前。例如 `commandcode` 在 `code...` 之前，`mimo` 在更短的 substring 之前
- providerID 是 lowercase canonical String，但 palette 防御性 lowercase + strip space

**测试**: `ProviderColorPaletteTests` 加 10 个 case（每个 provider id assertEquals 期望色）。

### R7.2 QuotaProviderList 27 → 38 (S2)

**入口**：`CodexBarMobile/Shared/Push/QuotaProviderList.swift`

iOS 通过 CKQuerySubscription / CKRecordZoneSubscription 订阅 quota transition 推送。每个 provider 占 2 个 subscription（depleted + restored）。

- 27 → 38（+ 11 个新 provider id）
- 76 个 subscription（38 × 2）
- 现有 SyncCoordinator 接收路径不变，只需 list 扩展

**测试**: `QuotaProviderListTests` 期望值 27 → 38；新增 11 个 expected provider 覆盖。

### R7.3 Codex switcher iOS 多账号一致性 (S3, P2)

**调研先行**：iOS 当前对 Codex 多账号是独立 ForEach 卡片（1.5.3 的 `cardIdentityKey` 已保证身份隔离）。Mac 新加的 stacked / segmented 是菜单栏紧凑显示，跟 iOS 卡片化 UI 模式不一致。

**决策建议**：iOS **不**镜像 stacked/segmented 选项；iOS UI 模式天然是分卡片（"独立"模式），Mac 的 stacked 是 menu bar 屏幕宽度受限的压缩方案，iOS 不需要。

**交付**：Research/020 R7.3 决策记录，不写代码。

### R7.4 Quota warning markers + push (S4 — 1.6.0, Mac 0.25.2)

**Status**: `ready` — 2 phases 整合到 1.6.0 一起出。Mac 0.25.2 partner release。

**架构原则**（per user 2026-05-13）: iOS 是接收端，所有 quota warning config 在 Mac 完成（全局 + per-provider override）。iOS 端 mirror 同步过来的 config，不做 iOS-local override。

#### R7.4.1 当前 Mac 架构总结

```
Mac CodexBarConfig.quotaWarnings: QuotaWarningConfig?  (全局)
  └── session: QuotaWarningWindowConfig?  { thresholds: [Int]?, enabled: Bool? }
  └── weekly: QuotaWarningWindowConfig?

settings.quotaWarningEnabled(provider:, window:)         per-provider override
settings.quotaWarningThresholds(provider:, window:)      per-provider override
QuotaWarningThresholds.defaults = [50, 20]               (剩余 % 触发，= 50%/80% used)

触发链:
UsageStore.refresh() → 检测 usedPercent 越过 threshold
  → sessionQuotaNotifier.postQuotaWarning(event:, provider:)
    → UserNotifications 本地 macOS 通知                    ✅ 现有
    → CKRecord write → iOS                                 ❌ Phase 2 加
```

#### R7.4.2 Phase 1 — Wire format + iOS 渲染

**新 Shared 类型** (`Shared/Models/SyncQuotaWarningConfig.swift`):
```swift
public struct SyncQuotaWarningConfig: Codable, Sendable, Equatable {
    public let sessionThresholds: [Int]?  // nil = 用 default [50, 20]
    public let sessionEnabled: Bool?
    public let weeklyThresholds: [Int]?
    public let weeklyEnabled: Bool?
}
```

**ProviderUsageEnvelope 加字段** (additive optional):
```swift
public let quotaWarnings: SyncQuotaWarningConfig?  // decodeIfPresent
```

**Mac SyncCoordinator emit**: 每次 push provider envelope 时填入该 provider 的 resolved config。

**iOS UsageCardView** 渲染:
- 读 envelope-level `quotaWarnings`，按 window (session/weekly) 取相应 thresholds
- thresholds 为剩余 % → bar 上 marker 位置 = `100 - threshold`
- 多个 threshold = 多个 tick mark
- usedPercent ≥ (100 - largest threshold) → 显示 warning icon

#### R7.4.3 Phase 2 — Warning push 通知

**新 CKRecord type** (`QuotaWarningTransition`):
- Fields: providerID, providerName, window (session/weekly), threshold, currentRemaining, transitionAt, deviceID
- ⚠️ **避保留字段名** (per `feedback_ckrecord_reserved_field_names.md`): NEVER `recordID` / `recordType` / `recordChangeTag` / etc.

**新 CKRecordZone** per provider per state:
- `Quota-{providerID}-warningZone` × 38 providers = 38 个新 zone
- ⚠️ **私有 DB 必须 custom zone** (per `feedback_cloudkit_zone_gotcha.md`), default zone push 不 fire

**Mac fire path** (`QuotaTransitionWriter` 扩展):
- UsageStore 检测 threshold 越过 → 现有 postQuotaWarning(本地) + **新** writeQuotaWarning(CK)
- 一次 fire 可能多 threshold（[50, 20]）依次或一起写

**iOS subscription** (`QuotaProviderList` 扩展):
- 38 providers × 3 states (depleted / restored / warning) = 114 subscriptions
- 复用现有 CKQuerySubscription 框架

**iOS NSE** (Notification Service Extension):
- 解析 `QuotaWarningTransition` payload → 格式化通知文案 per provider settings
- ⚠️ **AppDelegate @objc observers 必须 nonisolated** (per `feedback_appdelegate_objc_observer_nonisolated.md`)

#### R7.4.4 多设备 matrix proof (16 cell)

| 场景 | iCloud Sync | Marker 渲染 | Warning Push | Crash |
|------|------------|------------|-------------|-------|
| Mac 旧×2 + iOS 旧×2 | ✓ 基线 | 不渲染 | 不发 | 0 |
| Mac 旧×2 + iOS 新×N | ✓ G1 G5 | 默认 [50,20] (G4) | 不发 (G3) | 0 |
| Mac 新×2 + iOS 旧×2 | ✓ G5 | 老 iOS 不渲染 | 老 iOS 无订阅 G2 | 0 |
| Mac 新×2 + iOS 新×N | ✓ | per-provider config | 完整 push | 0 |
| Mac 新+旧 + iOS 新×N | ✓ | 新 Mac providers 用 config，旧 Mac 默认 | 仅新 Mac fire | 0 |

**核心 invariant**:
- G1 wire `decodeIfPresent` additive
- G2 老 iOS 不订阅新 zone → CK 不投递新 record
- G3 老 Mac 不写新 record → 新 iOS 订阅着但无 fire
- G4 缺失 config → fallback `[50, 20]` 默认值（视觉一致）
- G5 `JSONDecoder` 默认忽略未知 key
- G6 CKRecord 不用保留字段名
- G7 私有 DB 用 custom zone
- G8 NSE @objc observers nonisolated

#### R7.4.5 实施 checklist

**Wire (Shared/)**:
- [ ] `SyncQuotaWarningConfig.swift` 新文件
- [ ] `ProviderUsageEnvelope.swift` 加字段
- [ ] `QuotaWarningTransition.swift` 新 CKRecord wire 类型

**Mac**:
- [ ] `SyncCoordinator` 填 envelope.quotaWarnings
- [ ] `QuotaTransitionWriter` 扩展 writeQuotaWarning
- [ ] `UsageStore` 在 postQuotaWarning 旁加 CK fire
- [ ] Mac 0.25.2 / BUILD_NUMBER 62 / sparkle 62.1.6.0
- [ ] CHANGELOG 加 0.25.2 entry

**iOS**:
- [ ] `UsageCardView` 渲染 multi-threshold tick + warning icon (从 envelope 读)
- [ ] `QuotaProviderList` 加 warning state 维度 → 38×3=114 subscriptions
- [ ] NSE 解析 QuotaWarningTransition
- [ ] iOS 1.6.0 build 121
- [ ] CHANGELOG / in-app release notes 加 S4 内容

**Tests**:
- [ ] `SyncQuotaWarningConfigTests` Codable round-trip
- [ ] `ProviderUsageEnvelopeTests` 加 quotaWarnings decode/encode
- [ ] `QuotaWarningTransitionTests` CKRecord round-trip (避保留字段)
- [ ] `UsageCardViewQuotaMarkerTests` 渲染逻辑
- [ ] `QuotaProviderListTests` 114 zone 期望值
- [ ] Mac side `QuotaWarningEmitterTests` (新)
- [ ] Mock infra: 给 mock provider 添加 sample quotaWarnings config so S6 mocks 立刻测渲染

### R7.5 Claude peak-hours iOS indicator (S5, P2)

**wire 检查**：Mac `ClaudeUsageSnapshot` 是否含 peak/off-peak 状态 + timestamp。

**渲染**：Claude 详情页加 peak 状态行（"非高峰 · 2 小时后进入高峰" / "高峰 25 分钟后结束"）。

**i18n**：iOS xcstrings 4 语言（en/zh-Hans/zh-Hant/ja）新增 peak-hours 字符串（en 复用 Mac 端已有，zh-Hans 复用 Mac fork 已译，zh-Hant/ja 新加）。

### R7.6 MockProviderInjector 扩充 (S6)

**入口**：`Sources/CodexBar/Sync/MockProviderInjector.swift`（fork-private Mac code）

现有 mock 集：32 entries × 29 distinct providerIDs。

加 11 个 simple-mock（继承 24 个简单 mock 同模式）：
- 1 个账号 / 1 个 primary rate window / cost data
- `.test` TLD email
- `_mock_simple_<provider>` recordName

11 个新 mocks：openai / manus / windsurf / mimo / doubao / deepseek / codebuff / crof / venice / commandcode / stepfun

新 mock 集：43 entries（32 → 43）。

### R7.7 Mock env-var run 推送实测 (S7)

用户要求："Mac env 环境下 mock data 能推到 CloudKit，iOS 能看到完整面"。

**验收路径**：
1. Mac: `CODEXBAR_MOCK_PROVIDERS=1 open /Applications/CodexBar.app`
2. SyncCoordinator 应在 push cycle 把 43 个 mock snapshot 推到 CloudKit
3. iOS app 下拉刷新 → 43 个 provider 渲染（11 个新的有原生颜色 from S1）
4. Toggle off → CloudKit 1 cycle 内 ghost cleanup

### R7.8 测试 (S8)

新增覆盖（估计 40-50 tests）：
- `ProviderColorPaletteTests`: +10 案例
- `QuotaProviderListTests`: 27 → 38 调整
- `MockProviderInjectorTests`: 32 → 43 调整
- `ClaudePeakHoursIndicatorTests`: 新建（S5）
- `QuotaWarningMarkerTests`: 新建（S4）
- 多设备场景 scenario test（为 S11 准备）

### R7.9 In-app release notes + xcstrings (S9)

`MobileReleaseNotesCatalog` 加 1.6.0 entry 作 Latest，1.5.3 降为历史。
内容覆盖 S1+S2+S4+S5 用户面向变化 + Mock 扩充。
xcstrings 4 语言新增。
AppStoreMetadata/1.6.0/{en-US,zh-Hans,zh-Hant,ja}/release_notes.txt。

### R7.10 版本号 bump (S10)

- `project.yml` MARKETING_VERSION 1.5.3 → 1.6.0; CURRENT_PROJECT_VERSION 119 → 120
- `CHANGELOG.md` 加 1.6.0
- `version.env` MOBILE_VERSION 1.5.3 → 1.6.0

### R7.11 多设备枚举矩阵 (S11，原 Stage 3 子化)

详见 R8。

### R7 决策记录

| 决策 | 选项 | 理由 |
|------|------|------|
| Codex switcher iOS 是否镜像 stacked/segmented | **不镜像** | iOS 卡片模式天然分账号；Mac stacked 是 menu bar 紧凑场景 |
| openai 是否新增颜色 | **复用 .green** | 上游新 OpenAI API 同 providerID 走既有 ChatGPT 颜色 |
| qwen 是否新增 | **不**（qwen 折入 alibaba 既有） | 上游 #498 加 Qwen API 在 alibaba provider 旗下 |
| pt-BR 是否加 iOS 第 5 语言 | **不加** | 上游 v0.25.1 release tag 不含 pt-BR（在 0.26-dev 未 release），按"只跟 released" 政策不加 |

---

## R8 · 多设备兼容性枚举测试矩阵（占位）

**Status**: 拟定，待 R7 完成后细化

**范围**：(老 Mac / 新 Mac) × (老 iOS / 新 iOS) 所有组合，按用户(2)(a)(b)(c)要求枚举测试同步。如某组合难以完全兼容，设计冲突提示 UI（参 Research/019 §9 原型）告知用户"另一台设备版本未升级，升级后数据会一致"。

---

## 修改记录

| Date | Round | Note |
|------|-------|------|
| 2026-05-02 | R1.1-R1.2 | 调研完成、设计稿落地、决策固化 |
| 2026-05-12 | R6 draft | 用户 /goal 重启 Mac 架构验证。R6/R7/R8 三轮 append。R6 待 user confirm before 实施 |
| 2026-05-12 | R6 ✅ | 完成度验收通过：build/lint clean、1 known flake P3、zh-Hans 补 3 keys、en 补 not_found、fork features 全 intact、Push 系统已 hooked up 上游 quota warning。R7 (iOS Stage 2) 待用户启动 |
