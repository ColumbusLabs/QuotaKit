import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct WidgetEmptyProjectionTests {
    @Test(arguments: [false, true])
    func `all failed providers retain published entries and original ages`(queued: Bool) async throws {
        let (store, settings) = self.makeStore()
        var saved: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { saved.append($0) }
        self.seed(store)
        store.persistWidgetSnapshot(reason: "synthetic-success")
        if !queued { await store.widgetSnapshotPersistTask?.value }

        store.snapshots.removeAll()
        store.errors = [.minimax: "Synthetic offline failure", .deepseek: "Synthetic offline failure"]
        settings.usageBarsShowUsed = true
        store.persistWidgetSnapshot(reason: "synthetic-all-failed")
        await store.widgetSnapshotPersistTask?.value

        let before = try #require(saved.first)
        let after = try #require(saved.last)
        #expect(saved.count == 2)
        #expect(before.entries.count == 2)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(after.entries) == encoder.encode(before.entries))
        #expect(after.usageBarsShowUsed)
        #expect(after.generatedAt >= before.generatedAt)
        #expect(store.snapshots.isEmpty)
        #expect(store.cloudSyncAccountSnapshots().isEmpty)
    }

    @Test(arguments: [
        "disabled", "blocked", "retired", "no-failure", "partial", "missing-error", "cold-start",
    ])
    func `empty projection fallback respects invalidation boundaries`(scenario: String) async throws {
        let (store, settings) = self.makeStore()
        let url = try #require(store.widgetSnapshotURL)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var saved: WidgetSnapshot?
        store._test_widgetSnapshotSaveOverride = { saved = $0 }
        self.seed(store)
        store.persistWidgetSnapshot(reason: "synthetic-success")
        await store.widgetSnapshotPersistTask?.value

        store.snapshots.removeAll()
        store.errors = [.minimax: "Synthetic offline failure", .deepseek: "Synthetic offline failure"]
        switch scenario {
        case "disabled":
            settings.setProviderEnabled(provider: .minimax, metadata: store.metadata(for: .minimax), enabled: false)
        case "blocked": store.widgetUsagePreservationBlockedProviders.insert(.minimax)
        case "retired":
            store.clearProviderRuntimeState(.minimax)
            store.errors[.minimax] = "Synthetic offline failure"
        case "no-failure": store.errors.removeAll()
        case "partial": self.seed(store, providers: [.deepseek])
        case "missing-error": store.errors.removeValue(forKey: .deepseek)
        case "cold-start":
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try WidgetSnapshotStore.save(#require(saved), to: url)
            store._test_widgetSnapshotSaveOverride = nil
            store.lastQueuedWidgetSnapshot = nil
        default: break
        }

        store.persistWidgetSnapshot(reason: "synthetic-invalidation")
        await store.widgetSnapshotPersistTask?.value
        if scenario == "cold-start" { saved = WidgetSnapshotStore.load(from: url) }
        let shouldKeepDeepSeek = scenario == "partial" || scenario == "retired"
        #expect(saved?.entries.count == (shouldKeepDeepSeek ? 1 : 0))
        if shouldKeepDeepSeek {
            #expect(saved?.entries.first?.provider == .deepseek)
        }
    }

    @Test(arguments: [false, true])
    func `terminal failures cannot revive published usage`(clearBeforeFailure: Bool) async {
        let (store, _) = self.makeStore()
        var saved: WidgetSnapshot?
        store._test_widgetSnapshotSaveOverride = { saved = $0 }
        self.seed(store)
        store.persistWidgetSnapshot(reason: "synthetic-success")
        await store.widgetSnapshotPersistTask?.value
        #expect(saved?.entries.count == 2)
        if clearBeforeFailure { store.snapshots.removeAll() }

        store._test_providerFetchOutcomeOverride = { _ in
            ProviderFetchOutcome(result: .failure(URLError(.userAuthenticationRequired)), attempts: [])
        }
        for provider in [UsageProvider.minimax, .deepseek] {
            await store.refreshProvider(provider, allowDisabled: true)
            await store.refreshProvider(provider, allowDisabled: true)
        }
        store.persistWidgetSnapshot(reason: "synthetic-terminal-failures")
        await store.widgetSnapshotPersistTask?.value
        #expect(saved?.entries.isEmpty == true)
    }

    @Test
    func `fresh provider success must be published before its queued usage can be retained`() async {
        let (store, _) = self.makeStore(providers: [.minimax])
        var saved: WidgetSnapshot?
        store._test_widgetSnapshotSaveOverride = { saved = $0 }
        self.seed(store, providers: [.minimax])
        store.persistWidgetSnapshot(reason: "synthetic-old-account")
        await store.widgetSnapshotPersistTask?.value
        store.clearProviderRuntimeState(.minimax)

        let replacement = UsageSnapshot(
            primary: RateWindow(usedPercent: 75, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_060))
        store._test_providerFetchOutcomeOverride = { _ in
            ProviderFetchOutcome(result: .success(ProviderFetchResult(
                usage: replacement,
                credits: nil,
                dashboard: nil,
                sourceLabel: "fixture",
                strategyID: "fixture",
                strategyKind: .apiToken)), attempts: [])
        }
        await store.refreshProvider(.minimax)
        #expect(store.snapshot(for: .minimax)?.primary?.usedPercent == 75)

        store.snapshots.removeAll()
        store.errors[.minimax] = "Synthetic offline failure"
        store.persistWidgetSnapshot(reason: "synthetic-offline-before-replacement-publication")
        await store.widgetSnapshotPersistTask?.value
        #expect(saved?.entries.isEmpty == true)

        store._setSnapshotForTesting(replacement, provider: .minimax)
        store.persistWidgetSnapshot(reason: "synthetic-replacement-publication")
        await store.widgetSnapshotPersistTask?.value
        store.snapshots.removeAll()
        store.errors[.minimax] = "Synthetic offline failure"
        store.persistWidgetSnapshot(reason: "synthetic-offline-after-replacement-publication")
        await store.widgetSnapshotPersistTask?.value
        #expect(saved?.entries.first?.primary?.usedPercent == 75)
        #expect(saved?.entries.first?.updatedAt == replacement.updatedAt)
    }

    @Test
    func `selecting an unavailable cached account cannot revive the previous account`() async throws {
        let (store, settings) = self.makeStore(providers: [.openrouter])
        settings.addTokenAccount(provider: .openrouter, label: "First", token: "fixture-first-key")
        settings.addTokenAccount(provider: .openrouter, label: "Second", token: "fixture-second-key")
        settings.setActiveTokenAccountIndex(0, for: .openrouter)
        self.seed(store, providers: [.openrouter])
        var saved: WidgetSnapshot?
        store._test_widgetSnapshotSaveOverride = { saved = $0 }
        store.persistWidgetSnapshot(reason: "synthetic-first-account")
        await store.widgetSnapshotPersistTask?.value
        #expect(saved?.entries.count == 1)

        settings.setActiveTokenAccountIndex(1, for: .openrouter)
        let account = try #require(settings.effectiveSelectedTokenAccount(for: .openrouter))
        store.accountSnapshots[.openrouter] = [TokenAccountUsageSnapshot(
            account: account,
            snapshot: nil,
            error: "Synthetic unavailable account",
            sourceLabel: "fixture",
            cacheKey: store.tokenAccountSnapshotCacheKey(provider: .openrouter, account: account))]
        store.activateCachedTokenAccountSnapshot(provider: .openrouter, accountID: account.id)
        #expect(store.snapshot(for: .openrouter) == nil)

        store.persistWidgetSnapshot(reason: "synthetic-second-account-unavailable")
        await store.widgetSnapshotPersistTask?.value
        #expect(saved?.entries.isEmpty == true)
    }

    @Test
    func `switching one provider account preserves another failed providers queued widget usage`() async throws {
        let (store, settings) = self.makeStore(providers: [.openrouter, .deepseek])
        settings.addTokenAccount(provider: .openrouter, label: "First", token: "fixture-first-key")
        settings.addTokenAccount(provider: .openrouter, label: "Second", token: "fixture-second-key")
        settings.setActiveTokenAccountIndex(0, for: .openrouter)
        self.seed(store, providers: [.openrouter, .deepseek])

        var saved: WidgetSnapshot?
        store._test_widgetSnapshotSaveOverride = { saved = $0 }
        store.persistWidgetSnapshot(reason: "synthetic-two-provider-accounts")
        await store.widgetSnapshotPersistTask?.value
        let originalSnapshot = try #require(saved)
        let deepSeekEntry = try #require(originalSnapshot.entries.first { $0.provider == .deepseek })
        #expect(originalSnapshot.entries.count == 2)

        settings.setActiveTokenAccountIndex(1, for: .openrouter)
        let selectedAccount = try #require(settings.effectiveSelectedTokenAccount(for: .openrouter))
        store.activateCachedTokenAccountSnapshot(provider: .openrouter, accountID: selectedAccount.id)

        let filteredSnapshot = try #require(store.lastQueuedWidgetSnapshot)
        #expect(filteredSnapshot.enabledProviders == originalSnapshot.enabledProviders)
        #expect(filteredSnapshot.entries.map(\.provider) == [.deepseek])

        store.snapshots.removeAll()
        store.errors = [.deepseek: "Synthetic transient offline failure"]
        store.persistWidgetSnapshot(reason: "synthetic-other-provider-transient-failure")
        await store.widgetSnapshotPersistTask?.value

        #expect(saved?.entries.map(\.provider) == [.deepseek])
        #expect(saved?.entries.first?.updatedAt == deepSeekEntry.updatedAt)
        #expect(store.snapshots.isEmpty)
        #expect(store.cloudSyncAccountSnapshots().isEmpty)
    }

    @Test
    func `account switch during queued widget save repairs the published snapshot`() async throws {
        let (store, settings) = self.makeStore(providers: [.openrouter, .deepseek])
        settings.addTokenAccount(provider: .openrouter, label: "First", token: "fixture-first-key")
        settings.addTokenAccount(provider: .openrouter, label: "Second", token: "fixture-second-key")
        settings.setActiveTokenAccountIndex(0, for: .openrouter)
        self.seed(store, providers: [.openrouter, .deepseek])

        let saveGate = WidgetSnapshotSaveGate()
        var saved: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { snapshot in
            if saved.isEmpty { await saveGate.pauseFirstSave() }
            saved.append(snapshot)
        }
        store.persistWidgetSnapshot(reason: "synthetic-racing-account-switch")
        await saveGate.waitUntilFirstSaveStarts()
        defer { saveGate.releaseFirstSave() }

        let firstAccountSnapshot = try #require(store.lastQueuedWidgetSnapshot)
        #expect(firstAccountSnapshot.entries.map(\.provider).contains(.openrouter))
        settings.setActiveTokenAccountIndex(1, for: .openrouter)
        let selectedAccount = try #require(settings.effectiveSelectedTokenAccount(for: .openrouter))
        store.activateCachedTokenAccountSnapshot(provider: .openrouter, accountID: selectedAccount.id)

        let filteredSnapshot = try #require(store.lastQueuedWidgetSnapshot)
        #expect(filteredSnapshot.generatedAt > firstAccountSnapshot.generatedAt)
        #expect(filteredSnapshot.enabledProviders == firstAccountSnapshot.enabledProviders)
        #expect(filteredSnapshot.entries.map(\.provider) == [.deepseek])
        store.snapshots.removeAll()

        saveGate.releaseFirstSave()
        await store.widgetSnapshotPersistTask?.value

        #expect(saved.count == 3)
        #expect(saved.first?.entries.map(\.provider).contains(.openrouter) == true)
        #expect(saved.last?.entries.map(\.provider) == [.deepseek])
        #expect(saved.last?.entries.first?.updatedAt == firstAccountSnapshot.entries
            .first(where: { $0.provider == .deepseek })?.updatedAt)
        #expect(saved.last?.enabledProviders == firstAccountSnapshot.enabledProviders)
        #expect(store.snapshots.isEmpty)
        #expect(store.cloudSyncAccountSnapshots().isEmpty)
    }

    @Test
    func `completed widget save is republished after an account switch`() async throws {
        let (store, settings) = self.makeStore(providers: [.openrouter, .deepseek])
        settings.addTokenAccount(provider: .openrouter, label: "First", token: "fixture-first-key")
        settings.addTokenAccount(provider: .openrouter, label: "Second", token: "fixture-second-key")
        settings.setActiveTokenAccountIndex(0, for: .openrouter)
        self.seed(store, providers: [.openrouter, .deepseek])

        var saved: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { saved.append($0) }
        store.persistWidgetSnapshot(reason: "synthetic-completed-save-before-account-switch")
        await store.widgetSnapshotPersistTask?.value
        let originalSnapshot = try #require(saved.first)
        let deepSeekEntry = try #require(originalSnapshot.entries.first { $0.provider == .deepseek })
        #expect(originalSnapshot.entries.count == 2)

        settings.setActiveTokenAccountIndex(1, for: .openrouter)
        let selectedAccount = try #require(settings.effectiveSelectedTokenAccount(for: .openrouter))
        store.activateCachedTokenAccountSnapshot(provider: .openrouter, accountID: selectedAccount.id)
        store.snapshots.removeAll()
        await store.widgetSnapshotPersistTask?.value

        let repairedSnapshot = try #require(saved.last)
        #expect(saved.count == 2)
        #expect(repairedSnapshot.entries.map(\.provider) == [.deepseek])
        #expect(repairedSnapshot.entries.first?.updatedAt == deepSeekEntry.updatedAt)
        #expect(repairedSnapshot.enabledProviders == originalSnapshot.enabledProviders)
        #expect(repairedSnapshot.generatedAt > originalSnapshot.generatedAt)
        #expect(store.cloudSyncAccountSnapshots().isEmpty)
    }

    @Test
    func `account switch filters persisted snapshot when in process queue is empty`() async throws {
        let (store, settings) = self.makeStore(providers: [.openrouter, .deepseek])
        let snapshotURL = try #require(store.widgetSnapshotURL)
        defer { try? FileManager.default.removeItem(at: snapshotURL.deletingLastPathComponent()) }
        settings.addTokenAccount(provider: .openrouter, label: "First", token: "fixture-first-key")
        settings.addTokenAccount(provider: .openrouter, label: "Second", token: "fixture-second-key")
        settings.setActiveTokenAccountIndex(0, for: .openrouter)
        self.seed(store, providers: [.openrouter, .deepseek])

        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        store.persistWidgetSnapshot(reason: "synthetic-disk-snapshot-before-process-restart")
        await store.widgetSnapshotPersistTask?.value
        let originalSnapshot = try #require(WidgetSnapshotStore.load(from: snapshotURL))
        #expect(originalSnapshot.entries.count == 2)

        store.lastQueuedWidgetSnapshot = nil
        store.snapshots.removeAll()
        settings.setActiveTokenAccountIndex(1, for: .openrouter)
        let selectedAccount = try #require(settings.effectiveSelectedTokenAccount(for: .openrouter))
        store.activateCachedTokenAccountSnapshot(provider: .openrouter, accountID: selectedAccount.id)
        await store.widgetSnapshotPersistTask?.value

        let repairedSnapshot = try #require(WidgetSnapshotStore.load(from: snapshotURL))
        #expect(repairedSnapshot.entries.map(\.provider) == [.deepseek])
        #expect(repairedSnapshot.enabledProviders == originalSnapshot.enabledProviders)
        #expect(repairedSnapshot.generatedAt > originalSnapshot.generatedAt)
        #expect(store.cloudSyncAccountSnapshots().isEmpty)
    }

    @Test
    func `retained entries respect hidden optional spending`() async throws {
        let (store, settings) = self.makeStore(providers: [.devin])
        settings.showOptionalCreditsAndExtraUsage = true
        let measuredAt = Date(timeIntervalSince1970: 1_700_000_000)
        store._setSnapshotForTesting(UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 25, limit: 100, currencyCode: "USD", period: "Monthly", updatedAt: measuredAt),
            updatedAt: measuredAt), provider: .devin)
        var saved: WidgetSnapshot?
        store._test_widgetSnapshotSaveOverride = { saved = $0 }
        store.persistWidgetSnapshot(reason: "synthetic-visible-spending")
        await store.widgetSnapshotPersistTask?.value
        let before = try #require(saved)
        #expect(before.enabledProviders.contains(.devin))
        #expect(before.entries.first?.providerCost != nil)

        settings.showOptionalCreditsAndExtraUsage = false
        store.snapshots.removeAll()
        store.errors[.devin] = "Synthetic offline failure"
        store.persistWidgetSnapshot(reason: "synthetic-hidden-spending")
        await store.widgetSnapshotPersistTask?.value
        #expect(saved?.entries.contains(where: { $0.providerCost != nil }) == false)
    }

    @Test
    func `Claude owner mismatch and Codex account switch never revive queued usage`() async throws {
        let (claudeStore, _) = self.makeStore(providers: [.claude])
        claudeStore._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 24, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)),
            provider: .claude)
        claudeStore.lastSourceLabels[.claude] = "oauth"
        var claudeSaved: WidgetSnapshot?
        claudeStore._test_widgetSnapshotSaveOverride = { claudeSaved = $0 }
        await UsageStore.withActiveClaudeAccountUuidForTesting("account-a") {
            claudeStore.persistWidgetSnapshot(reason: "synthetic-claude-owner-a")
            await claudeStore.widgetSnapshotPersistTask?.value
        }
        let ownerA = try #require(claudeSaved?.entries.first?.quotaOwnerKey)
        claudeStore.snapshots.removeValue(forKey: .claude)
        claudeStore.errors[.claude] = "Synthetic failed refresh"
        await UsageStore.withActiveClaudeAccountUuidForTesting("account-b") {
            claudeStore.persistWidgetSnapshot(reason: "synthetic-claude-owner-b")
            await claudeStore.widgetSnapshotPersistTask?.value
        }
        #expect(ownerA != claudeSaved?.entries.first?.quotaOwnerKey)
        #expect(claudeSaved?.entries.isEmpty == true)

        let (codexStore, _) = self.makeStore(providers: [.codex])
        self.seed(codexStore, providers: [.codex])
        var codexSaved: WidgetSnapshot?
        codexStore._test_widgetSnapshotSaveOverride = { codexSaved = $0 }
        codexStore.persistWidgetSnapshot(reason: "synthetic-codex-owner-a")
        await codexStore.widgetSnapshotPersistTask?.value
        #expect(codexSaved?.entries.contains(where: { $0.provider == .codex }) == true)

        codexStore.lastCodexUsagePublicationGuard = CodexAccountScopedRefreshGuard(
            source: .liveSystem,
            identity: .providerAccount(id: "account-a"),
            accountKey: "a@example.com")
        let ownerChanged = codexStore.reconcileCodexPublishedUsageOwner(
            with: CodexAccountScopedRefreshGuard(
                source: .liveSystem,
                identity: .providerAccount(id: "account-b"),
                accountKey: "b@example.com"),
            persistWidgetSnapshot: false)
        #expect(ownerChanged)
        codexStore.errors[.codex] = "Synthetic failed refresh"
        codexStore.persistWidgetSnapshot(reason: "synthetic-codex-owner-b")
        await codexStore.widgetSnapshotPersistTask?.value
        #expect(codexSaved?.entries.contains(where: { $0.provider == .codex }) == false)
        #expect(codexStore.snapshot(for: .codex) == nil)
        #expect(codexStore.cloudSyncAccountSnapshots().contains(where: { $0.provider == .codex }) == false)
    }

    private func makeStore(
        providers: Set<UsageProvider> = [.minimax, .deepseek]) -> (UsageStore, SettingsStore)
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetEmptyProjectionTests-\(UUID().uuidString)", isDirectory: true)
        let environment = ["HOME": root.path, "CODEX_HOME": root.appendingPathComponent("codex").path]
        let settings = testSettingsStore(
            suiteName: "WidgetEmptyProjectionTests",
            config: CodexBarConfig.makeDefault())
        for provider in UsageProvider.allCases {
            settings.setProviderEnabled(
                provider: provider,
                metadata: ProviderDescriptorRegistry.metadata[provider]!,
                enabled: providers.contains(provider))
        }
        settings._test_codexReconciliationEnvironment = environment
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(homeDirectory: root.path, fileExists: { _ in false }),
            settings: settings,
            historicalUsageHistoryStore: HistoricalUsageHistoryStore(fileURL: root
                .appendingPathComponent("history.json")),
            planUtilizationHistoryStore: PlanUtilizationHistoryStore(directoryURL: nil),
            startupBehavior: .testing,
            environmentBase: environment,
            widgetSnapshotURL: root.appendingPathComponent("widget.json"))
        return (store, settings)
    }

    private func seed(_ store: UsageStore, providers: [UsageProvider] = [.minimax, .deepseek]) {
        for (index, provider) in providers.enumerated() {
            store._setSnapshotForTesting(
                UsageSnapshot(
                    primary: RateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                    secondary: nil,
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index))),
                provider: provider)
        }
    }
}

@MainActor
private final class WidgetSnapshotSaveGate {
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var firstSaveStarted = false

    func waitUntilFirstSaveStarts() async {
        guard !self.firstSaveStarted else { return }
        await withCheckedContinuation { self.startedContinuation = $0 }
    }

    func pauseFirstSave() async {
        self.firstSaveStarted = true
        self.startedContinuation?.resume()
        self.startedContinuation = nil
        await withCheckedContinuation { self.releaseContinuation = $0 }
    }

    func releaseFirstSave() {
        self.releaseContinuation?.resume()
        self.releaseContinuation = nil
    }
}
