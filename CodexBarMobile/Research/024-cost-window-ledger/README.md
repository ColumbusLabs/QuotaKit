# Cost Window Ledger (CWL) — 总览

> iOS-only feature。Mac 上游 / CloudKit envelope **不动**。

## 一句话目标
让 iOS Cost dashboard 能展示比 Mac 当前 `historyDays` 更长的成本历史 —— 通过本地逐日累积 ledger 实现。

## 决策:走 B 路径

- **A(已弃)**:iOS Picker clamp 到 Mac 当前 historyDays。~50 行,简单,但窗口被 Mac 卡死,Mac 改窗口 iOS 跟着变,核心诉求没解决。
- **B(走)**:iOS 本地 ledger 累积每日 cost point,长期持有,窗口选择独立于 Mac。详见 [DESIGN.md](DESIGN.md)。

## 当前状态

- **Round 4(2026-05-29)— account-aware key 修复(本提交)**:P4a 集成时**发现根本问题** —— `DailyCostPoint` key 不含 `accountEmail`,会让同 provider 的多账号成本 collide 丢失(回退项目多账号能力)。修:key 改 `{deviceID}|{providerID}|{accountEmail ?? "_"}|{dayKey}`(对齐 blob 路径 cardIdentityKey),writer 传 `provider.accountEmail`,reader dedup/rollup 按 cardIdentityKey。加多账号"不 collide"测试(writer + aggregate 各一)。38 tests / 6 suites 全绿。**P4a 数据源集成顺延到 Round 5**(先修地基)。
- Round 3(2026-05-28)— P3 Reader:`CostLedgerService.{aggregate, aggregateProvider, diagnostics}` + 3 个数据类型。窗口过滤 + 跨设备 dedup + 三向累积。T4/T5/T6 9 tests(详见 Round 历史)。
- Round 2(2026-05-28)— P2 Writer:`CostLedgerService.{isEnabled, upsertFromSnapshot, upsertDayPoint}` + `SwiftDataBridge.upsertProvider` 末尾 gate hook + `MobileSettingsKeys.cwlEnabled`(默认 false)。T2 + T3 + gate + wrapper 9 tests ✓。
- Round 1(2026-05-28)— P1 SwiftData schema:`DailyCostPoint @Model` + 注册 + lightweight migration。T1 + T16 ✓。
- Round 0(2026-05-28)— Bootstrap docs:创建本目录 5 份文档。
- 下一步:Round 5 / P4a 数据源集成(`CostDashboardInsights` 接 ledger + `cwlEnabled` 分派 + T7 等价回归)。
- 上一轮交付:build 140 — Cost dashboard top-5 + Others + drill-down。**CWL 不许回退这一批**(CWL 默认 OFF,P2 没人开,行为 == 140)。

## 硬约束(每轮 CR 必须核对)

1. **iOS-only**。`Sources/`(Mac 上游)和 `Shared/Models/UsageSnapshot.swift`(wire 格式)**不许碰**。详见 [DEVELOPMENT.md § 不许动的东西](DEVELOPMENT.md#不许动的东西)。
2. **默认 OFF**。CWL 是新行为模式,Settings 加显式开关,OFF 时完全不接管。
3. **向后兼容**。老用户(blob-only)升级不丢数据 —— 首次开 CWL 时 `seedFromExistingBlobs` 把现有 blob 喂作 ledger seed。详见 [DESIGN.md](DESIGN.md) + [ARCHITECTURE.md § 向后兼容](ARCHITECTURE.md#向后兼容)。
4. **build 140 不回退**。Provider Share / Model Mix / Codex Service Mix / Budgets / Subscription Utilization 的 top-5 + Others + drill-down 必须在 CWL ON / OFF 两种模式下都正确。
5. **lint.sh 0 violation** + **`swift test --no-parallel` 全绿**(项目已知 SyncCoordinatorTests 并行 flake,**必须 --no-parallel**)。

## TODO(分 phase,见 [DEVELOPMENT.md](DEVELOPMENT.md))

- [x] **Round 1 / P1**:SwiftData schema —— 新增 `@Model DailyCostPoint`,注册到 `CodexBarSwiftDataSchema.models`(lightweight migration,无 versioned schema)。T1 + T16 ✓。
- [x] **Round 2 / P2**:Writer —— `CostLedgerService.upsertFromSnapshot` + `SwiftDataBridge.upsertProvider` 末尾 gate hook + `MobileSettingsKeys.cwlEnabled`(默认 false)。T2 + T3 + gate + wrapper 9 tests ✓,blob 路径无变化。
- [x] **Round 3 / P3**:Reader —— `CostLedgerService.aggregate(windowDays:asOf:)` + `aggregateProvider` + `diagnostics`,数据类型 `CostLedgerAggregation` / `CostLedgerProviderRollup` / `CostLedgerDiagnostics`。窗口过滤 + 跨设备 dedup(latest lastUpdated 赢)+ per-provider / per-day / per-model 三向累积。T4 + T5 + T6 + 子项 9 tests ✓。T7(等价于 blob 路径)推迟到 Round 4。
- [x] **Round 4 / account-aware key 修复**:`DailyCostPoint` key 加 `accountEmail`(`{deviceID}|{providerID}|{accountEmail ?? "_"}|{dayKey}`),writer/reader/rollup 全线 account-aware。P4a 集成前置阻塞,先修。多账号不 collide 测试 ✓。
- [ ] **Round 5 / P4a**:数据源集成 —— `CostDashboardInsights` 接 ledger 后端(`windowDays:` + `cwlEnabled` 分派)+ **T7 等价回归**(同数据双路径 < 0.001)。
- [ ] **Round 6 / P4b**:UI —— Settings CWL 开关 + Picker(7/30/90/365)+ 清空 + 诊断面板 + `Localizable.xcstrings` 4 语 + T8/T9/T12/T13。
- [ ] **Round 7 / P6**:Migration —— `seedFromExistingBlobs` + 失败回退(T10/T11)。
- [ ] **Round 8 / P7**:性能 T17 + 真机 M1–M8 + build bump + TestFlight。

> 注:原 P5 多设备 merge 已被 P3 reader + Round 4 account-key 覆盖(跨设备按 `(providerID, accountEmail, dayKey)` group 取 latest lastUpdated),不再单列;端到端多设备验证并入 Round 5 的 T7。

## 未决问题(发现新的请追加)

- **Q1**:老 blob seed 进 ledger 时,daily 里 `isEstimated` 字段保留还是丢?**倾向保留**(见 DESIGN.md 「关键决策」)。
- **Q2**:Mac 端卸载 provider 后,iOS ledger 里旧 daily 点要不要 GC?**倾向不 GC**,加显式"清空 provider ledger"按钮。
- **Q3**:CloudKit 多设备:同 dayKey 来自两台 Mac,哪个赢?**倾向 latest `lastUpdated` 赢**(见 ARCHITECTURE.md 「多设备 merge」)。
- **Q4**:ledger 表大小要不要限?**当前不限制**(40 providers × 365 days ≈ 14k 行,小)。≥ 100k 行时再优化,记进 TODO。

## Round 历史

- **Round 4(2026-05-29)— account-aware key 修复**:Round 5(P4a 数据源集成)时**发现根本阻塞** —— `DailyCostPoint` 的 composite key 是 `(deviceID, providerID, dayKey)`,缺 `accountEmail`。但 blob 路径的 Cost dashboard `providerRows` 是 per-`cardIdentityKey`(providerID|accountEmail),同 providerID 的多账号是两行。ledger 不带 account → 两账号 collide 互相覆盖,CWL ON 时多账号成本被合并丢失,回退项目多账号能力(doc 019 / 1.5.3 fix)。修:① `DailyCostPoint` 加 `accountEmail`,key 改 `{deviceID}|{providerID}|{accountEmail ?? "_"}|{dayKey}`(`"_"` 与 `ProviderSnapshotModel` 一致);② writer `upsertFromSnapshot` 传 `provider.accountEmail`(`upsertDayPoint` 给 `accountEmail = nil` 默认,便于单账号 test/seed);③ reader dedup group + `providerRollups` key 改 cardIdentityKey(`providerID|accountEmail`),`CostLedgerProviderRollup` + `aggregateProvider` 带 accountEmail。新增多账号"不 collide"测试(writer + aggregate 各 1),修正 Round 1-3 受影响 test(init/makeCompositeKey/compositeKey 断言/rollup key 查找)。文档同步:DESIGN 决策 8、ARCHITECTURE schema + group key。38 tests / 6 suites 全绿,lint 0。**P4a 顺延 Round 5**。
- **Round 3(2026-05-28)— P3 Reader**:`CostLedgerService.{aggregate, aggregateProvider, diagnostics}` + 数据类型 `CostLedgerAggregation` / `CostLedgerProviderRollup` / `CostLedgerDiagnostics`。算法:cutoffDayKey = asOf - (N-1) days(UTC),字典序对比 `DailyCostPoint.dayKey >= cutoffKey` 走窗口过滤;再按 `(providerID, dayKey)` group + 取 max lastUpdated 做跨设备 dedup;再三向累积(per-provider / per-day / per-model)。`asOf` 参数注入"今天"使测试确定。窗口 clamp 到 [1, 365]。`CWLAggregateTests.swift` 9 用例:T4 单设备聚合 / T5 跨设备 latest 赢(× 2)/ T6 7-30-90-100 窗口边界(× 2)+ cutoffDayKey 字符串(× 1)/ aggregateProvider(× 2)/ diagnostics(× 1)。全 CWL 36 tests / 6 suites 全绿。**bug 修了一处:test fixture 的 `asOf` magic number(1_780_272_000)算成了 2026-06-01,改成显式 `DateComponents` 构造 2026-05-28**。下一步 Round 4 = P4 UI。
- **Round 2(2026-05-28)— P2 Writer**:`CostLedgerService.swift` 新增(`isEnabled` / `upsertFromSnapshot` / `upsertDayPoint`);`SwiftDataBridge.upsertProvider` 末尾 6 行 gate hook(blob 路径完全不变);`MobileSettingsKeys.cwlEnabled` 新增,默认 false。Dedup 规则:`existing.lastUpdated >= incoming.lastUpdated` → 跳过(同 Mac 同 cycle 同 dayKey 第二次冗余写直接 skip)。`CWLWriterTests.swift` 9 用例:T2 dedup by composite key(2 个) + T3 newer/older/equal lastUpdated(3 个) + Gate(2 个) + upsertFromSnapshot wrapper(2 个)。所有 CWL 测试 + 防回归(SwiftDataBridge / ModelContainerFactory)共 27 tests / 5 suites 全绿。下一步 Round 3 = P3 Reader。
- **Round 1(2026-05-28)— P1 SwiftData schema**:`DailyCostPoint @Model` 新增 + 注册。校正 3 份文档(ARCHITECTURE / DEVELOPMENT / TESTING):**测试位置改为 `CodexBarMobileTests/Storage/`**(iOS test target,非 Mac SPM);**lightweight migration 替代"VersionedSchema + MigrationPlan"**(过度设计;现 `ModelContainerFactory` 还无 migration 基础设施)。T1 + T16 共 6 tests / 2 suites 全过。
- **Round 0(2026-05-28)— Bootstrap docs**:本目录 5 份文档创建。

## 关键文件(本目录)

| 文件 | 给谁看 |
|---|---|
| [README.md](README.md) | 负责人 —— 状态 / TODO / Round 历史 / 未决问题 |
| [DESIGN.md](DESIGN.md) | 设计 —— 为什么 + A vs B + 权衡 + 决策 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 架构 —— schema / 数据流 / 多设备 / 兼容 |
| [DEVELOPMENT.md](DEVELOPMENT.md) | 开发 —— 分 phase + 命令 + 不许动 |
| [TESTING.md](TESTING.md) | 测试 —— 矩阵 + 验收 + 人工项 |

## 完成标准

- [ ] 文档 / 代码 / 测试 三方一致。
- [ ] 现有 Cost dashboard 行为不回退(build 140 在 CWL OFF 下完全正常,在 CWL ON 下逻辑等价)。
- [ ] CWL 在 ON 下:能累积、能按 7/30/90/365 聚合、能查诊断、能清空。
- [ ] SwiftData 迁移路径已测试(老 blob 不丢)。
- [ ] 多设备 merge 在 ledger 路径正确(2 设备 fixture 测试通过)。
- [ ] 性能验收 T17 达标(详见 [TESTING.md](TESTING.md))。
- [ ] lint.sh 0 violation,4 语全译。
- [ ] `swift test --no-parallel` 全绿(flake 项已标记)。
- [ ] 真机 / TestFlight 人工验证项(M1–M8)逐条跑过 + 结果记录。
