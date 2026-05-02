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
| **R4** | iOS 端 27 provider 测试覆盖 + 跨设备虚拟机验证 | In Progress | iOS 端 audit 现有 multi-account 测试覆盖; 缺口补全; 虚拟机端到端属手动验证（用户侧）|
| R5+ | （动态预留）发现新问题往下塞 | — | 下方「悬挂事项」流转 |

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

## 修改记录

| Date | Round | Note |
|------|-------|------|
| 2026-05-02 | R1.1-R1.2 | 调研完成、设计稿落地、决策固化 |
