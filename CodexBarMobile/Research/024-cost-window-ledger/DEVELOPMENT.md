# CWL — 开发

## 分 Phase 实现(每 phase 一轮 / 一 commit)

| Phase | 内容 | 影响文件 | 验证 |
|---|---|---|---|
| **P1** | SwiftData schema —— 新增 `DailyCostPoint` + Migration v1→v2 | `Storage/CostLedgerModels.swift`(新), `Storage/SwiftDataSchema.swift` | T1 / T16,`swift build` |
| **P2** | Writer —— `SwiftDataBridge.upsertProvider` 末尾加 ledger upsert(**仅 CWL ON**)。blob 路径不动 | `Storage/SwiftDataBridge.swift`, `Storage/CostLedgerService.swift`(新,先写 upsert), `Models/MobileDisplayPreferences.swift` | T2 / T3,手工验证 |
| **P3** | Reader —— `CostLedgerService.aggregate(...)` + provider rollup + 诊断 | `Storage/CostLedgerService.swift`(补 aggregate / diagnostics) | T4 / T5 / T6 / T7 |
| **P4** | UI —— Settings 加 CWL 开关 + 窗口 Picker(7/30/90/365)+ 清空 + 诊断面板。`CostDashboardInsights` 接 ledger 后端 | `ContentView.swift`(`CostDashboardView` + `CostDashboardInsights` + `CostSettingsView`), `Models/CostShareService.swift`, `Views/ProviderDetailView.swift`, `Localizable.xcstrings` | T8 / T9 / T12 / T13 / T14,M1–M3 |
| **P5** | 多设备 —— CWL ON 路径替代 `mergeSnapshots`(group `(providerID, dayKey)` take max lastUpdated)。OFF 走原 | `iCloud/CloudSyncReader.swift`, `Storage/CostLedgerService.swift` | T15,M4 |
| **P6** | Migration —— 首次开 CWL 触发 `seedFromExistingBlobs`,展示 spinner,失败回退 | `Storage/CostLedgerService.swift`(补 seed), `ContentView.swift`(`CostSettingsView` flow) | T10 / T11 / T16,M5 |
| **P7** | 性能 + 回归 + lint + TestFlight | — | T17,M6–M8,`./Scripts/lint.sh lint`,`swift test --no-parallel` |

每个 phase = 一轮工作循环(见 README 的"启动 / 循环")。

## 本地命令

### Build(每次改完代码必跑)
```bash
# 新增 .swift 文件后必跑(否则 xcodebuild 找不到)
cd CodexBarMobile && xcodegen generate

# iOS build
cd CodexBarMobile && xcodebuild -project CodexBarMobile.xcodeproj \
    -scheme CodexBarMobile \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build > /tmp/cb_build.log 2>&1
echo "EXIT=$?"; grep -E 'BUILD (SUCCEEDED|FAILED)|error:' /tmp/cb_build.log | tail
```

### Test(权威 gate)
```bash
# 针对本 phase
swift test --no-parallel --filter <suite name> 2>&1 | tail -10

# 全量(必须 --no-parallel,见下面 flake 说明)
swift test --no-parallel 2>&1 | tail -3
```

**注意**:项目有已知 `SyncCoordinatorTests` 在并行 swift-testing 下 Index-out-of-range flake(`project_swift_test_parallel_flake` 记录)。**必须 `--no-parallel`**。

### Lint(release 闸门)
```bash
./Scripts/lint.sh lint    # swiftformat + swiftlint --strict + i18n audit + parser audit
# 必须输出 "Found 0 violations, 0 serious in N files" + "all locales translated"
```

### 回归保护(build 140 cap+Others)

每轮必须 check:

1. **代码层面**(diff 不应改这些函数):
   - `ContentView.swift:690` `contributionSection`(top 5 + Others + NavigationLink)
   - `ContentView.swift:741` `budgetSection`
   - `Views/UtilizationAggregateView.swift:128` 区块
   - `Models/CostShareService.swift:76` `displayProviders`
2. **运行层面**(CWL OFF / ON 各跑一次):
   - Mac mock 开,iPhone 验:Cost tab 的 Provider Share / Model Mix / Budgets 都有 top 5 + Others + drill-down。
3. **测试层面**:`swift test --no-parallel --filter MockProviderV029Extras` 必须过(build 140 加的)。

### Mac 端 mock(测 CWL UI 流程)
```bash
killall CodexBar 2>/dev/null
launchctl setenv CODEXBAR_MOCK_PROVIDERS 0
open -a /Applications/CodexBar.app
# Mac → Settings → Mobile → Debug · Mock Provider Data → 打开
# iPhone ~30 秒后出现合成 provider
```

## Commit / Push 风格

- 每 phase 一个 commit(可拆更小)。
- Commit 前缀:`feat(cwl):` / `test(cwl):` / `docs(cwl):` / `refactor(cwl):`。
- Co-Authored-By tag 见根 `AGENTS.md` 规范。
- Push 到 `origin/mobile-dev`。**不动 main / upstream**。

## 不许动的东西

- ❌ `Sources/`(Mac 上游)
- ❌ `Sources/CodexBarCore/`
- ❌ `Shared/Models/UsageSnapshot.swift`(wire 格式,改 = 改 Mac 推送)
- ❌ `version.env` MARKETING_VERSION(留到整批交付时统一)
- ❌ Mac 端的 CHANGELOG.md / project.pbxproj / appcast.xml
- ❌ secrets / `~/.codexbar-secrets/` / `.p8` / `.env`
- ❌ Mac `BUILD_NUMBER`

## iOS build 号

- 中间 phase commit:**不 bump**。
- 整批 ready(P7 完成)时:`CodexBarMobile/project.yml` `CURRENT_PROJECT_VERSION` 140 → 141。
- xcodegen → xcodebuild → TestFlight upload(`Scripts/upload_ios_testflight.sh`)。

## 文档同步(每 phase 结束前必做)

1. 更新 `README.md`:
   - Round 历史追加一行(`Round N(YYYY-MM-DD)— <主题>`)。
   - TODO 状态 ✓ / 推后 / 阻塞。
2. 如本 phase 改了设计 / 接口 / 测试矩阵:
   - 同步进对应 `DESIGN.md` / `ARCHITECTURE.md` / `TESTING.md`。
3. 发现的新问题 → 追加 `README.md` 的"未决问题"或 TODO。
4. **文档与代码不一致 = 本轮不算完成,不能 commit**。

## 中断 / 重启

如果 phase 没跑完就中断:
- `README.md` 写明上轮停在哪里 / 已 commit 的部分 / 待完成。
- 下次启动按 README 状态续上。

## 紧急回滚

- 任意 phase 完成后发现破坏 build 140 → revert 该 phase commit,从 `README.md` 重新评估。
- CWL 默认 OFF,即使 ledger 路径有 bug,用户不开 CWL 完全不受影响 —— 这是隔离设计的保险。
