import AppKit
import CodexBarCore
import Foundation
import XCTest
@testable import CodexBar

@MainActor
final class StatusMenuTokenAccountSwitcherTests: XCTestCase {
    private func disableMenuCardsForTesting() {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(false)
    }

    private func makeSettings() -> SettingsStore {
        testSettingsStore(
            suiteName: "StatusMenuTokenAccountSwitcherTests",
            tokenAccountStore: InMemoryTokenAccountStore())
    }

    private func enableOnlyClaude(_ settings: SettingsStore) {
        self.enableOnly(.claude, settings)
    }

    private func enableOnly(_ enabledProvider: UsageProvider, _ settings: SettingsStore) {
        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: provider == enabledProvider)
        }
    }

    private func representedIDs(in menu: NSMenu) -> [String] {
        menu.items.compactMap { $0.representedObject as? String }
    }

    private func installBlockingClaudeProvider(on store: UsageStore, blocker: BlockingTokenAccountFetchStrategy) {
        let baseSpec = store.providerSpecs[.claude]!
        store.providerSpecs[.claude] = Self.makeClaudeProviderSpec(baseSpec: baseSpec) {
            try await blocker.awaitResult()
        }
    }

    private func installRotatingProvider(
        on store: UsageStore,
        provider: UsageProvider,
        rotatedToken: String)
    {
        let baseSpec = store.providerSpecs[provider]!
        let baseDescriptor = baseSpec.descriptor
        let snapshot = self.snapshot(percent: 37)
        let descriptor = ProviderDescriptor(
            id: provider,
            metadata: baseDescriptor.metadata,
            branding: baseDescriptor.branding,
            tokenCost: baseDescriptor.tokenCost,
            fetchPlan: ProviderFetchPlan(
                sourceModes: baseDescriptor.fetchPlan.sourceModes,
                pipeline: ProviderFetchPipeline { _ in [
                    RotatingTokenAccountFetchStrategy(
                        provider: provider,
                        rotatedToken: rotatedToken,
                        snapshot: snapshot),
                ] }),
            cli: baseDescriptor.cli)
        store.providerSpecs[provider] = ProviderSpec(
            style: baseSpec.style,
            isEnabled: baseSpec.isEnabled,
            descriptor: descriptor,
            makeFetchContext: baseSpec.makeFetchContext)
    }

    private static func makeClaudeProviderSpec(
        baseSpec: ProviderSpec,
        loader: @escaping @Sendable () async throws -> UsageSnapshot) -> ProviderSpec
    {
        let baseDescriptor = baseSpec.descriptor
        let strategy = StatusMenuTokenAccountFetchStrategy(loader: loader)
        let descriptor = ProviderDescriptor(
            id: .claude,
            metadata: baseDescriptor.metadata,
            branding: baseDescriptor.branding,
            tokenCost: baseDescriptor.tokenCost,
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .cli, .oauth],
                pipeline: ProviderFetchPipeline { _ in [strategy] }),
            cli: baseDescriptor.cli)
        return ProviderSpec(
            style: baseSpec.style,
            isEnabled: baseSpec.isEnabled,
            descriptor: descriptor,
            makeFetchContext: baseSpec.makeFetchContext)
    }

    private func snapshot(percent: Double = 12) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: percent,
                windowMinutes: 300,
                resetsAt: Date().addingTimeInterval(300),
                resetDescription: nil),
            secondary: nil,
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .claude,
                accountEmail: "claude@example.com",
                accountOrganization: nil,
                loginMethod: "OAuth"))
    }

    func test_tokenAccountMenuSelectionRefreshesProviderWhileGlobalRefreshIsActive() async throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        // Fork: iCloud sync defaults on and fans out a fetch per token
        // account, so the global refresh alone would put two fetches in
        // flight. Disable it so this test exercises upstream's
        // single-selected-account path and its refresh-coalescing
        // assertion; the sync fan-out is covered by
        // ShouldFetchAllTokenAccountsTests.
        settings.iCloudSyncEnabled = false
        self.enableOnlyClaude(settings)
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "Bearer sk-ant-oat-primary")
        settings.addTokenAccount(provider: .claude, label: "Secondary", token: "Bearer sk-ant-oat-secondary")
        settings.setActiveTokenAccountIndex(0, for: .claude)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let blocker = BlockingTokenAccountFetchStrategy()
        self.installBlockingClaudeProvider(on: store, blocker: blocker)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        let refreshTask = Task { @MainActor in
            await store.refresh()
        }
        await blocker.waitUntilStarted(count: 1)
        XCTAssertTrue(store.isRefreshing)

        let menu = controller.makeMenu()
        defer { withExtendedLifetime(menu) {} }
        controller.menuWillOpen(menu)
        let switcher = try XCTUnwrap(menu.items.compactMap { $0.view as? TokenAccountSwitcherView }.first)

        let selectionTask = try XCTUnwrap(switcher._test_select(index: 1))
        XCTAssertEqual(settings.tokenAccountsData(for: .claude)?.clampedActiveIndex(), 1)
        for _ in 0..<40 {
            await Task.yield()
        }
        let startedBeforeDrain = await blocker.startedCallCount()
        XCTAssertEqual(startedBeforeDrain, 1)

        await blocker.resumeAll(with: .success(self.snapshot(percent: 17)))
        await blocker.waitUntilStarted(count: 2)
        await selectionTask.value
        await refreshTask.value
        let startedCallCount = await blocker.startedCallCount()
        XCTAssertGreaterThanOrEqual(startedCallCount, 2)
    }

    func test_multiAccountStackedRefreshStartsAccountFetchesConcurrently() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.multiAccountMenuLayout = .stacked
        self.enableOnlyClaude(settings)
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "Bearer sk-ant-oat-primary")
        settings.addTokenAccount(provider: .claude, label: "Secondary", token: "Bearer sk-ant-oat-secondary")

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let blocker = BlockingTokenAccountFetchStrategy()
        self.installBlockingClaudeProvider(on: store, blocker: blocker)

        let refreshTask = Task { @MainActor in
            await store.refreshProvider(.claude)
        }

        await blocker.waitUntilStarted(count: 2)
        let startedBeforeResume = await blocker.startedCallCount()
        XCTAssertEqual(startedBeforeResume, 2)

        await blocker.resumeAll(with: .success(self.snapshot(percent: 17)))
        await refreshTask.value
        XCTAssertEqual(store.accountSnapshots[.claude]?.count, 2)
    }

    func test_multiAccountStackedCancellationCannotRestoreCredentialStaleSnapshots() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.multiAccountMenuLayout = .stacked
        self.enableOnlyClaude(settings)
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "p1")
        settings.addTokenAccount(provider: .claude, label: "Secondary", token: "p2")
        let originalAccounts = settings.tokenAccounts(for: .claude)

        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store.accountSnapshots[.claude] = originalAccounts.map { account in
            TokenAccountUsageSnapshot(
                account: account,
                snapshot: self.snapshot(),
                error: nil,
                sourceLabel: "fixture",
                cacheKey: store.tokenAccountSnapshotCacheKey(provider: .claude, account: account))
        }
        settings.updateTokenAccount(
            provider: .claude,
            accountID: originalAccounts[0].id,
            token: "rotated-p1")
        let blocker = BlockingTokenAccountFetchStrategy()
        self.installBlockingClaudeProvider(on: store, blocker: blocker)

        let refreshTask = Task { @MainActor in
            await store.refreshProvider(.claude)
        }
        await blocker.waitUntilStarted(count: 2)
        await blocker.resumeAll(with: .failure(CancellationError()))
        await refreshTask.value

        XCTAssertEqual(store.accountSnapshots[.claude]?.map(\.account.id), [originalAccounts[1].id])
    }

    func test_validTokenAccountSnapshotsHandlesDuplicateAccountIDsWithoutTrapping() {
        let settings = self.makeSettings()
        self.enableOnlyClaude(settings)
        let id = UUID()
        let first = ProviderTokenAccount(
            id: id,
            label: "First",
            token: "f1",
            addedAt: 1,
            lastUsed: nil)
        let duplicate = ProviderTokenAccount(
            id: id,
            label: "Duplicate",
            token: "d1",
            addedAt: 2,
            lastUsed: nil)
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store.accountSnapshots[.claude] = [
            TokenAccountUsageSnapshot(
                account: first,
                snapshot: self.snapshot(),
                error: nil,
                sourceLabel: "fixture",
                cacheKey: store.tokenAccountSnapshotCacheKey(provider: .claude, account: first)),
        ]

        XCTAssertTrue(store.validTokenAccountSnapshots(provider: .claude, accounts: [first, duplicate]).isEmpty)
    }

    func test_duplicateAccountIDsRejectCrossCredentialPublication() async {
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        self.enableOnlyClaude(settings)
        settings.addTokenAccount(provider: .claude, label: "First", token: "f1")
        settings.addTokenAccount(provider: .claude, label: "Second", token: "s1")
        let accounts = settings.tokenAccounts(for: .claude)
        let duplicate = ProviderTokenAccount(
            id: accounts[0].id,
            label: accounts[1].label,
            token: accounts[1].token,
            addedAt: accounts[1].addedAt,
            lastUsed: accounts[1].lastUsed)
        settings.updateProviderConfig(provider: .claude) { config in
            config.tokenAccounts = ProviderTokenAccountData(
                version: 1,
                accounts: [accounts[0], duplicate],
                activeIndex: 1)
        }
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._test_providerFetchOutcomeOverride = { _ in
            ProviderFetchOutcome(
                result: .success(ProviderFetchResult(
                    usage: self.snapshot(percent: 66),
                    credits: nil,
                    dashboard: nil,
                    sourceLabel: "fixture",
                    strategyID: "fixture",
                    strategyKind: .apiToken)),
                attempts: [])
        }

        await store.refreshProvider(.claude)

        XCTAssertNil(store.snapshot(for: .claude))
        XCTAssertNil(store.accountSnapshots[.claude])
    }

    func test_tokenAccountSwitchDefersOpenMenuRebuildUntilAfterSwitcherAction() async throws {
        self.disableMenuCardsForTesting()
        StatusItemController.setMenuRefreshEnabledForTesting(true)
        defer { StatusItemController.setMenuRefreshEnabledForTesting(false) }

        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .claude
        settings.multiAccountMenuLayout = .segmented
        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            settings.setProviderEnabled(
                provider: provider,
                metadata: metadata,
                enabled: provider == .claude || provider == .codex)
        }
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "Bearer sk-ant-oat-primary")
        settings.addTokenAccount(provider: .claude, label: "Secondary", token: "Bearer sk-ant-oat-secondary")
        settings.setActiveTokenAccountIndex(0, for: .claude)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let blocker = BlockingTokenAccountFetchStrategy()
        self.installBlockingClaudeProvider(on: store, blocker: blocker)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let switcher = try XCTUnwrap(menu.items.compactMap { $0.view as? TokenAccountSwitcherView }.first)

        var rebuildCount = 0
        controller._test_openMenuRebuildObserver = { _ in
            rebuildCount += 1
        }
        defer { controller._test_openMenuRebuildObserver = nil }

        let selectionTask = try XCTUnwrap(switcher._test_select(index: 1))

        XCTAssertEqual(rebuildCount, 0)
        for _ in 0..<20 where rebuildCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(rebuildCount, 1)

        await blocker.waitUntilStarted(count: 1)
        await blocker.resumeAll(with: .success(self.snapshot(percent: 17)))
        await selectionTask.value
        for _ in 0..<20 where rebuildCount < 2 {
            await Task.yield()
        }
        XCTAssertEqual(rebuildCount, 2)
    }

    func test_tokenAccountSwitchUsesSelectedAccountCacheWhileRefreshIsInFlight() async throws {
        self.disableMenuCardsForTesting()
        StatusItemController.setMenuRefreshEnabledForTesting(true)
        defer { StatusItemController.setMenuRefreshEnabledForTesting(false) }

        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.multiAccountMenuLayout = .segmented
        self.enableOnlyClaude(settings)
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "Bearer sk-ant-oat-primary")
        settings.addTokenAccount(provider: .claude, label: "Secondary", token: "Bearer sk-ant-oat-secondary")
        settings.setActiveTokenAccountIndex(0, for: .claude)
        let accounts = settings.tokenAccounts(for: .claude)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        store.snapshots[.claude] = self.snapshot(percent: 11)
        store.lastKnownResetSnapshots[.claude] = self.snapshot(percent: 11)
        store.errors[.claude] = "primary-error"
        store.lastSourceLabels[.claude] = "primary-cache"
        store.accountSnapshots[.claude] = [
            TokenAccountUsageSnapshot(
                account: accounts[0],
                snapshot: self.snapshot(percent: 11),
                error: nil,
                sourceLabel: "primary-cache",
                cacheKey: store.tokenAccountSnapshotCacheKey(provider: .claude, account: accounts[0])),
            TokenAccountUsageSnapshot(
                account: accounts[1],
                snapshot: self.snapshot(percent: 72),
                error: nil,
                sourceLabel: "secondary-cache",
                cacheKey: store.tokenAccountSnapshotCacheKey(provider: .claude, account: accounts[1])),
        ]
        let blocker = BlockingTokenAccountFetchStrategy()
        self.installBlockingClaudeProvider(on: store, blocker: blocker)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu(for: .claude)
        controller.menuWillOpen(menu)
        let switcher = try XCTUnwrap(menu.items.compactMap { $0.view as? TokenAccountSwitcherView }.first)

        let selectionTask = try XCTUnwrap(switcher._test_select(index: 1))

        XCTAssertEqual(store.snapshot(for: .claude)?.primary?.usedPercent, 72)
        XCTAssertEqual(store.lastKnownResetSnapshots[.claude]?.primary?.usedPercent, 72)
        XCTAssertNil(store.errors[.claude])
        XCTAssertEqual(store.sourceLabel(for: .claude), "secondary-cache")

        await blocker.waitUntilStarted(count: 1)
        await blocker.resumeAll(with: .success(self.snapshot(percent: 45)))
        await selectionTask.value
    }

    func test_tokenAccountSwitchClearsPreviousAccountIdentityUntilSelectedRefreshCompletes() async throws {
        self.disableMenuCardsForTesting()

        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.multiAccountMenuLayout = .segmented
        self.enableOnlyClaude(settings)
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "Bearer sk-ant-oat-primary")
        settings.addTokenAccount(provider: .claude, label: "Secondary", token: "Bearer sk-ant-oat-secondary")
        settings.setActiveTokenAccountIndex(0, for: .claude)
        let accounts = settings.tokenAccounts(for: .claude)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        store.snapshots[.claude] = self.snapshot(percent: 11)
        store.lastKnownResetSnapshots[.claude] = self.snapshot(percent: 11)
        store.errors[.claude] = "primary-error"
        store.lastSourceLabels[.claude] = "primary-cache"
        store.accountSnapshots[.claude] = [
            TokenAccountUsageSnapshot(
                account: accounts[0],
                snapshot: self.snapshot(percent: 11),
                error: nil,
                sourceLabel: "primary-cache",
                cacheKey: store.tokenAccountSnapshotCacheKey(provider: .claude, account: accounts[0])),
        ]
        let blocker = BlockingTokenAccountFetchStrategy()
        self.installBlockingClaudeProvider(on: store, blocker: blocker)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu(for: .claude)
        controller.menuWillOpen(menu)
        let switcher = try XCTUnwrap(menu.items.compactMap { $0.view as? TokenAccountSwitcherView }.first)

        let selectionTask = try XCTUnwrap(switcher._test_select(index: 1))

        XCTAssertNil(store.snapshot(for: .claude))
        XCTAssertNil(store.snapshot(for: .claude)?.identity(for: .claude))
        let pausedModel = try XCTUnwrap(controller.menuCardModel(for: .claude))
        XCTAssertTrue(pausedModel.email.isEmpty)
        XCTAssertTrue(pausedModel.metrics.isEmpty)
        XCTAssertNil(store.lastKnownResetSnapshots[.claude])
        XCTAssertNil(store.errors[.claude])
        XCTAssertNil(store.lastSourceLabels[.claude])

        await blocker.waitUntilStarted(count: 1)
        await blocker.resumeAll(with: .success(self.snapshot(percent: 45)))
        await selectionTask.value

        XCTAssertEqual(store.snapshot(for: .claude)?.primary?.usedPercent, 45)
        XCTAssertEqual(
            store.accountSnapshots[.claude]?.first(where: { $0.account.id == accounts[1].id })?
                .snapshot?.primary?.usedPercent,
            45)
    }

    func test_segmentedRefreshPreservesValidAccountCacheAndInvalidatesCredentialChanges() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.multiAccountMenuLayout = .segmented
        // QuotaKit intentionally fans out every account while iCloud sync is
        // enabled. This upstream test targets segmented local-only behavior.
        settings.iCloudSyncEnabled = false
        self.enableOnlyClaude(settings)
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "p1")
        settings.addTokenAccount(provider: .claude, label: "Secondary", token: "p2")
        settings.setActiveTokenAccountIndex(0, for: .claude)

        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._test_providerFetchOutcomeOverride = { _ in
            let percent = settings.selectedTokenAccount(for: .claude)?.label == "Primary" ? 11.0 : 72.0
            return ProviderFetchOutcome(
                result: .success(ProviderFetchResult(
                    usage: self.snapshot(percent: percent),
                    credits: nil,
                    dashboard: nil,
                    sourceLabel: "fixture",
                    strategyID: "fixture",
                    strategyKind: .apiToken)),
                attempts: [])
        }

        await store.refreshProvider(.claude)
        let originalAccounts = settings.tokenAccounts(for: .claude)
        XCTAssertEqual(store.snapshot(for: .claude)?.primary?.usedPercent, 11)
        XCTAssertEqual(store.accountSnapshots[.claude]?.count, 1)

        settings.setActiveTokenAccountIndex(1, for: .claude)
        store.activateCachedTokenAccountSnapshot(provider: .claude, accountID: originalAccounts[1].id)
        XCTAssertNil(store.snapshot(for: .claude))
        await store.refreshProvider(.claude)
        XCTAssertEqual(store.snapshot(for: .claude)?.primary?.usedPercent, 72)
        XCTAssertEqual(store.accountSnapshots[.claude]?.count, 2)

        settings.setActiveTokenAccountIndex(0, for: .claude)
        store.activateCachedTokenAccountSnapshot(provider: .claude, accountID: originalAccounts[0].id)
        XCTAssertEqual(store.snapshot(for: .claude)?.primary?.usedPercent, 11)

        settings.updateTokenAccount(
            provider: .claude,
            accountID: originalAccounts[0].id,
            token: "rotated-p1")
        store.activateCachedTokenAccountSnapshot(provider: .claude, accountID: originalAccounts[0].id)
        XCTAssertNil(store.snapshot(for: .claude))
        XCTAssertEqual(store.accountSnapshots[.claude]?.map(\.account.id), [originalAccounts[1].id])

        settings.removeTokenAccount(provider: .claude, accountID: originalAccounts[1].id)
        store.pruneTokenAccountSnapshots(provider: .claude, accounts: settings.tokenAccounts(for: .claude))
        XCTAssertNil(store.accountSnapshots[.claude])
    }
}

extension StatusMenuTokenAccountSwitcherTests {
    func test_segmentedRefreshClearsLiveSnapshotWhenCredentialChangesAndReplacementFails() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.multiAccountMenuLayout = .segmented
        self.enableOnlyClaude(settings)
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "p1")
        let account = try? XCTUnwrap(settings.selectedTokenAccount(for: .claude))

        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._test_providerFetchOutcomeOverride = { _ in
            ProviderFetchOutcome(
                result: .success(ProviderFetchResult(
                    usage: self.snapshot(percent: 45),
                    credits: nil,
                    dashboard: nil,
                    sourceLabel: "fixture",
                    strategyID: "fixture",
                    strategyKind: .apiToken)),
                attempts: [])
        }
        await store.refreshProvider(.claude)
        XCTAssertEqual(store.snapshot(for: .claude)?.primary?.usedPercent, 45)
        XCTAssertEqual(store.sourceLabel(for: .claude), "fixture")

        if let account {
            settings.updateTokenAccount(provider: .claude, accountID: account.id, token: "rotated-p1")
        }
        store._test_providerFetchOutcomeOverride = { _ in
            ProviderFetchOutcome(result: .failure(StatusMenuTokenAccountTestError.rejected), attempts: [])
        }
        await store.refreshProvider(.claude)

        XCTAssertNil(store.snapshot(for: .claude))
        XCTAssertNil(store.lastSourceLabels[.claude])
        XCTAssertNil(store.lastKnownResetSnapshots[.claude])
        XCTAssertNil(store.accountSnapshots[.claude])
    }

    func test_segmentedRefreshClearsLiveSnapshotWhenLastAccountIsRemovedAndFallbackFails() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.multiAccountMenuLayout = .segmented
        self.enableOnlyClaude(settings)
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "p1")
        let accountID = settings.selectedTokenAccount(for: .claude)?.id

        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._test_providerFetchOutcomeOverride = { _ in
            ProviderFetchOutcome(
                result: .success(ProviderFetchResult(
                    usage: self.snapshot(percent: 45),
                    credits: nil,
                    dashboard: nil,
                    sourceLabel: "fixture",
                    strategyID: "fixture",
                    strategyKind: .apiToken)),
                attempts: [])
        }
        await store.refreshProvider(.claude)
        XCTAssertEqual(store.snapshot(for: .claude)?.primary?.usedPercent, 45)

        if let accountID {
            settings.removeTokenAccount(provider: .claude, accountID: accountID)
        }
        store._test_providerFetchOutcomeOverride = { _ in
            ProviderFetchOutcome(result: .failure(StatusMenuTokenAccountTestError.rejected), attempts: [])
        }
        await store.refreshProvider(.claude)

        XCTAssertNil(store.snapshot(for: .claude))
        XCTAssertNil(store.lastSourceLabels[.claude])
        XCTAssertNil(store.lastKnownResetSnapshots[.claude])
        XCTAssertNil(store.accountSnapshots[.claude])
    }

    func test_segmentedRefreshClearsTokenAccountErrorWhenFailedAccountIsRemovedAndFallbackCancels() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.multiAccountMenuLayout = .segmented
        self.enableOnlyClaude(settings)
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "p1")
        let accountID = settings.selectedTokenAccount(for: .claude)?.id

        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._test_providerFetchOutcomeOverride = { _ in
            ProviderFetchOutcome(result: .failure(StatusMenuTokenAccountTestError.rejected), attempts: [])
        }
        await store.refreshProvider(.claude)
        XCTAssertNotNil(store.userFacingError(for: .claude))
        XCTAssertTrue(store.tokenAccountLiveStateProviders.contains(.claude))

        if let accountID {
            settings.removeTokenAccount(provider: .claude, accountID: accountID)
        }
        store._test_providerFetchOutcomeOverride = { _ in
            ProviderFetchOutcome(result: .failure(CancellationError()), attempts: [])
        }
        await store.refreshProvider(.claude)

        XCTAssertNil(store.snapshot(for: .claude))
        XCTAssertNil(store.userFacingError(for: .claude))
        XCTAssertNil(store.knownLimitsAvailabilityByProvider[.claude])
        XCTAssertFalse(store.tokenAccountLiveStateProviders.contains(.claude))
    }

    func test_segmentedRefreshPreservesAmbientSnapshotWithoutTokenAccountOwnership() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.multiAccountMenuLayout = .segmented
        self.enableOnlyClaude(settings)

        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._setSnapshotForTesting(self.snapshot(percent: 45), provider: .claude)
        store._test_providerFetchOutcomeOverride = { _ in
            ProviderFetchOutcome(result: .failure(CancellationError()), attempts: [])
        }

        await store.refreshProvider(.claude)

        XCTAssertEqual(store.snapshot(for: .claude)?.primary?.usedPercent, 45)
        XCTAssertFalse(store.tokenAccountLiveStateProviders.contains(.claude))
    }
}

private enum StatusMenuTokenAccountTestError: Error {
    case rejected
}

private struct StatusMenuTokenAccountFetchStrategy: ProviderFetchStrategy {
    let loader: @Sendable () async throws -> UsageSnapshot

    var id: String {
        "status-menu-token-account-test"
    }

    var kind: ProviderFetchKind {
        .cli
    }

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let snapshot = try await self.loader()
        return self.makeResult(usage: snapshot, sourceLabel: "status-menu-token-account-test")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}

private struct RotatingTokenAccountFetchStrategy: ProviderFetchStrategy {
    let provider: UsageProvider
    let rotatedToken: String
    let snapshot: UsageSnapshot

    var id: String {
        "rotating-token-account-test"
    }

    var kind: ProviderFetchKind {
        .apiToken
    }

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let accountID = context.selectedTokenAccountID,
              let updater = context.tokenAccountTokenUpdater
        else {
            throw RotatingTokenAccountTestError.missingUpdater
        }
        await updater(self.provider, accountID, self.rotatedToken)
        return self.makeResult(usage: self.snapshot, sourceLabel: "rotating-token-account-test")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}

private enum RotatingTokenAccountTestError: Error {
    case missingUpdater
}

private actor BlockingTokenAccountFetchStrategy {
    private var waiters: [CheckedContinuation<Result<UsageSnapshot, Error>, Never>] = []
    private var startedWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var resolvedResult: Result<UsageSnapshot, Error>?
    private var startedCount = 0

    func awaitResult() async throws -> UsageSnapshot {
        if let resolvedResult {
            self.startedCount += 1
            self.resumeStartedWaiters()
            return try resolvedResult.get()
        }
        let result = await withCheckedContinuation { continuation in
            self.waiters.append(continuation)
            self.startedCount += 1
            self.resumeStartedWaiters()
        }
        return try result.get()
    }

    func waitUntilStarted(count: Int) async {
        if self.startedCount >= count {
            return
        }
        await withCheckedContinuation { continuation in
            self.startedWaiters.append((count: count, continuation: continuation))
        }
    }

    func startedCallCount() -> Int {
        self.startedCount
    }

    func resumeAll(with result: Result<UsageSnapshot, Error>) {
        self.resolvedResult = result
        self.waiters.forEach { $0.resume(returning: result) }
        self.waiters.removeAll()
    }

    private func resumeStartedWaiters() {
        let ready = self.startedWaiters.filter { self.startedCount >= $0.count }
        self.startedWaiters.removeAll { self.startedCount >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }
}
