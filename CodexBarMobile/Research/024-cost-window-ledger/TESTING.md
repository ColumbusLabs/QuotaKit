# CWL — 测试

## 测试框架

- **Swift Testing**(`@Test` / `@Suite`),**不**用 XCTest。
- 测试文件放 `Tests/CodexBarTests/CWL*.swift`(Mac swift test 跑,可访问 SwiftData 单测路径)。
- 必须 `--no-parallel`(项目已知 `SyncCoordinatorTests` 并行 flake)。
- 跑命令:`swift test --no-parallel --filter CWL`(本功能所有 suite)/ `swift test --no-parallel`(全量)。

## 自动化测试矩阵

| 编号 | 测试 | 文件 | Phase |
|---|---|---|---|
| **T1** | `SchemaV2` 编译 + 空表加载 + 与 `SchemaV1` 共存 | `CWLSchemaTests.swift`(新) | P1 |
| **T2** | `DailyCostPoint` upsert dedupe by `(deviceID, providerID, dayKey)`:同 key 第二次写,不重复存条 | `CWLUpsertTests.swift`(新) | P2 |
| **T3** | 同 key 第二次写:`lastUpdated` 更新 → 覆盖;`lastUpdated` 倒退 → 不动(保护已有更新数据) | `CWLUpsertTests.swift` | P2 |
| **T4** | `CostLedgerService.aggregate(windowDays:)` 单设备聚合:总额 / 总 tokens / activeDayCount 正确 | `CWLAggregateTests.swift`(新) | P3 |
| **T5** | 跨设备聚合:同 `(providerID, dayKey)` 取 max `lastUpdated` 那条 | `CWLAggregateTests.swift` | P3 + P5 |
| **T6** | 窗口过滤:7d / 30d / 90d / 365d 各算一次,边界 dayKey 正确(UTC `today - (N-1) days` 起) | `CWLAggregateTests.swift` | P3 |
| **T7** | **等价性回归**:CWL 路径与 blob 路径在等价输入下输出**数值完全一致**(浮点 tolerance < 0.001)。覆盖 Overview total / Provider Share / Model Mix / Active Days | `CWLEquivalenceTests.swift`(新) | P3 + P4 |
| **T8** | CWL OFF 下 Cost dashboard 行为与 build 140 完全一致(走 blob 路径) | `CWLOffPathRegressionTests.swift`(新) | P4 |
| **T9** | CWL ON + Picker 切换:7 / 30 / 90 / 365 → Overview / Provider Share / Model Mix 全部按新窗口聚合 | `CWLPickerTests.swift`(新) | P4 |
| **T10** | `seedFromExistingBlobs`:fixture blob(含 30 天 daily + 多模型 + isEstimated)→ ledger 完整保留 | `CWLSeedTests.swift`(新) | P6 |
| **T11** | 损坏 blob seed:解码失败 → 抛错 → 调用方应关 CWL + 不修改 ledger 已有数据 | `CWLSeedTests.swift` | P6 |
| **T12** | `clearAll()` → ledger 表空,blob 不动 | `CWLClearTests.swift`(新) | P4 + P6 |
| **T13** | `diagnostics()` 返回的 deviceCount / providerCount / dayCount / earliest / latest 与已写入对应 | `CWLDiagnosticsTests.swift`(新) | P4 |
| **T14** | **build 140 cap+Others 回归**:CWL ON 下 Provider Share / Model Mix / Budgets / Utilization 仍 top 5 + Others + drill-down 行为正确 | 现有 `MockProviderV029ExtrasTests.swift` + 新断言 | P4 + P7 |
| **T15** | 多设备 fixture:2 设备各 30 天(部分 dayKey 重叠) → 聚合后跨设备唯一 dayKey 全在,重叠 dayKey latest 赢 | `CWLMultiDeviceTests.swift`(新) | P5 |
| **T16** | Schema migration v1→v2 在已有 user data 下:旧 `ProviderSnapshotRecord` 表保留 + 新 `DailyCostPoint` 表加入 | `CWLMigrationTests.swift`(新) | P1 + P6 |
| **T17** | **性能验收**:365 天 × 40 providers 全 ledger → `aggregate(365)` ≤ **50 ms p95**(100 trials) | `CWLPerformanceTests.swift`(新) | P7 |

## 每 Phase 验收

### P1
- T1, T16 过。
- `swift build` 0 error。
- **CR**:`SchemaV1` 在 ledger 表加入后不受影响。

### P2
- T2, T3 过。
- 手工 inspect:Mac mock ON,iPhone 同步 ≥ 2 次 → 用 P4 诊断面板(或临时 print)看 ledger 表内容,确认逐日 upsert。
- **CR**:`SwiftDataBridge.upsertProvider` 的 blob 路径(`existing.costSummaryData = ...`)**零变化**。

### P3
- T4, T5, T6, T7 过。
- **T7 最关键**:同输入下 CWL 与 blob 路径数值一致(floating-point tolerance < 0.001)。任意偏差 = 聚合逻辑有 bug,本 phase 必须修。

### P4
- T8, T9, T12, T13, T14 过(自动化)。
- 手工 MANUAL:
  - **M1**:CWL OFF → Cost dashboard 与 build 140 截图对照,视觉一致。
  - **M2**:CWL ON → Picker 切 7/30/90/365 → 各窗口下 Overview 数字 / Provider Share 列表 / Model Mix 图表都更新。
  - **M3**:Settings 清空按钮 → 二次确认 → ledger 清空 → 继续同步 → 重新累积。

### P5
- T15 过。
- 手工 MANUAL:**M4** 两台 Mac 各开 mock,iPhone 看到合并后的跨设备数据(同 dayKey 取 latest)。

### P6
- T10, T11, T16 过。
- 手工 MANUAL:**M5** 已经在用 build 140(blob-only)的设备升级到 CWL build → 开 CWL → seed 完成 → 数据与升级前 Cost dashboard 一致。

### P7(整批)
- 全量 `swift test --no-parallel` 绿(或 flake 项已标 + 文档记录)。
- `./Scripts/lint.sh lint`:0 violation + 4 语全译 + parser hash OK。
- **T17 性能达标**:p95 ≤ 50 ms。
- 手工 MANUAL:
  - **M6**:TestFlight 真机装上,完整 mock 流程 ≥ 1 小时,看 ledger 增长 + UI 流畅 + 内存稳。
  - **M7**:CWL ON / OFF 切换无 crash 无数据丢失。
  - **M8**:build 140 已知 case(top 5 + Others + drill-down)在 CWL ON 下完全正确。

## Fixtures(测试材料)

- 单设备:30 天 daily,每天 5 providers,每个 provider 2 models(含 Codex std/fast 拆分)。
- 多设备:2 个 deviceID,各 30 天,15 天重叠 dayKey,`lastUpdated` 时间错开。
- 损坏 blob:故意往 `costSummaryData` 塞 invalid JSON / 不完整字段。
- 大 ledger:365 days × 40 providers × 2 models = ~29k 条 `DailyCostPoint`(性能测试用)。

放 `Tests/CodexBarTests/CWLFixtures/` 或 inline 在测试文件里。

## 不要做的

- ❌ 测试里读真 session / 真 CloudKit 数据 / `~/.codexbar-secrets/`。
- ❌ Mock 掉真行为来 "通过" failed test —— 视为失败。
- ❌ `skip` / `xfail` 来掩盖真问题。如必须 skip,在 README 的 TODO 写明原因 + 解决计划。
- ❌ 并行跑 swift test(已知 `SyncCoordinatorTests` flake)。**始终 `--no-parallel`**。
- ❌ 提交未跑通的测试。
- ❌ 测试里硬写期望值绕过 bug(改 fixture 让错误的代码 "对" —— 视为失败)。

## 报告测试结果(交接给负责人)

固定格式:
```
swift test --no-parallel --filter CWL : X passed / Y failed / Z skipped
xcodebuild iOS Debug build : BUILD SUCCEEDED
./Scripts/lint.sh lint : 0 violations, all locales translated

MANUAL items 本轮已跑:M1 ✓ / M2 ✓ / ...
MANUAL items 本轮未跑:M4(待 P5) / M5(待 P6)
```

任何失败 / skip / xfail / flake → 必须诚实写出 + 推迟原因 + 下一步。
