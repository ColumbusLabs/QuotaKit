import CodexBarCore
import Foundation

@MainActor
protocol CodexActiveSourceWriting {
    func writeCodexActiveSource(_ source: CodexActiveSource)
}

@MainActor
protocol CodexAccountScopedRefreshing {
    func refreshCodexAccountScopedState(allowDisabled: Bool) async
}

@MainActor
struct SettingsStoreCodexAccountReconciliationSnapshotLoader: CodexAccountReconciliationSnapshotLoading {
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func loadSnapshot() -> CodexAccountReconciliationSnapshot {
        self.settingsStore.codexAccountReconciliationSnapshot
    }
}

@MainActor
struct SettingsStoreCodexActiveSourceWriter: CodexActiveSourceWriting {
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func writeCodexActiveSource(_ source: CodexActiveSource) {
        self.settingsStore.codexActiveSource = source
    }
}

@MainActor
struct UsageStoreCodexAccountScopedRefresher: CodexAccountScopedRefreshing {
    private let usageStore: UsageStore

    init(usageStore: UsageStore) {
        self.usageStore = usageStore
    }

    func refreshCodexAccountScopedState(allowDisabled: Bool) async {
        await self.usageStore.refreshCodexAccountScopedState(allowDisabled: allowDisabled)
    }
}

@MainActor
final class CodexAccountPromotionService {
    private let transaction: CodexAccountPromotionTransaction
    private let activeSourceWriter: any CodexActiveSourceWriting
    private let accountScopedRefresher: any CodexAccountScopedRefreshing
    private let daemon: CodexAppServerDaemon
    @ProcessEnvironment private var baseEnvironment: [String: String]
    private let fileManager: FileManager

    init(
        store: any ManagedCodexAccountStoring,
        homeFactory: any ManagedCodexHomeProducing,
        workspaceResolver: any ManagedCodexWorkspaceResolving = DefaultManagedCodexWorkspaceResolver(),
        snapshotLoader: any CodexAccountReconciliationSnapshotLoading,
        authMaterialReader: any CodexAuthMaterialReading,
        liveAuthSwapper: any CodexLiveAuthSwapping,
        activeSourceWriter: any CodexActiveSourceWriting,
        accountScopedRefresher: any CodexAccountScopedRefreshing,
        daemon: CodexAppServerDaemon = CodexAppServerDaemon(),
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default)
    {
        self.transaction = CodexAccountPromotionTransaction(
            store: store,
            homeFactory: homeFactory,
            workspaceResolver: workspaceResolver,
            snapshotLoader: snapshotLoader,
            authMaterialReader: authMaterialReader,
            liveAuthSwapper: liveAuthSwapper,
            baseEnvironment: baseEnvironment,
            fileManager: fileManager)
        self.activeSourceWriter = activeSourceWriter
        self.accountScopedRefresher = accountScopedRefresher
        self.daemon = daemon
        self.baseEnvironment = baseEnvironment
        self.fileManager = fileManager
    }

    convenience init(
        settingsStore: SettingsStore,
        usageStore: UsageStore,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default)
    {
        self.init(
            store: FileManagedCodexAccountStore(fileManager: fileManager),
            homeFactory: ManagedCodexHomeFactory(fileManager: fileManager),
            workspaceResolver: DefaultManagedCodexWorkspaceResolver(),
            snapshotLoader: SettingsStoreCodexAccountReconciliationSnapshotLoader(settingsStore: settingsStore),
            authMaterialReader: DefaultCodexAuthMaterialReader(),
            liveAuthSwapper: DefaultCodexLiveAuthSwapper(),
            activeSourceWriter: SettingsStoreCodexActiveSourceWriter(settingsStore: settingsStore),
            accountScopedRefresher: UsageStoreCodexAccountScopedRefresher(usageStore: usageStore),
            baseEnvironment: baseEnvironment,
            fileManager: fileManager)
    }

    func promoteManagedAccount(id: UUID) async throws -> CodexAccountPromotionResult {
        var result = try await self.transaction.promoteManagedAccount(id: id)
        self.activeSourceWriter.writeCodexActiveSource(result.resultingActiveSource)
        if result.didMutateLiveAuth {
            let home = CodexHomeScope.ambientHomeURL(env: self.baseEnvironment, fileManager: self.fileManager)
            result.daemonRestartNote = await self.daemon.restartIfRunning(
                homeURL: home,
                environment: self.baseEnvironment)
        }
        await self.accountScopedRefresher.refreshCodexAccountScopedState(allowDisabled: true)
        return result
    }
}
