import CodexBarCore
import Foundation

struct CLIServeAccountsPayload: Encodable, Equatable {
    let schemaVersion: Int
    let accounts: [CLIServeAccountPayload]
}

struct CLIServeAccountPayload: Encodable, Equatable {
    let id: String
    let provider: String
    let source: String
    let label: String
    let active: Bool
    let identity: CLIServeAccountIdentityPayload?
}

struct CLIServeAccountIdentityPayload: Encodable, Equatable {
    let accountEmail: String?
}

enum CLIServeAccountDiscovery {
    private static let schemaVersion = 1
    private static let managedCodexSource = "codex-managed"
    private static let tokenAccountSource = "token-account"
    /// Provider-specific by design: only Codex has a managed-home metadata store.
    private static let managedCodexProvider = UsageProvider.codex

    /// Reads the config paths used by the store without invoking its legacy-copy
    /// migration. Account discovery must remain metadata-only and read-only.
    static func loadConfigReadOnly(from configStore: CodexBarConfigStore) throws -> CodexBarConfig {
        let fileManager = FileManager.default
        let configURL: URL
        if fileManager.fileExists(atPath: configStore.fileURL.path) {
            configURL = configStore.fileURL
        } else if configStore.fileURL.lastPathComponent == "config.json",
                  configStore.fileURL.deletingLastPathComponent().lastPathComponent == ".quotakit"
        {
            let home = configStore.fileURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let legacyURL = CodexBarConfigStore.legacyDefaultURL(home: home)
            guard fileManager.fileExists(atPath: legacyURL.path) else {
                return CodexBarConfig.makeDefault()
            }
            configURL = legacyURL
        } else {
            return CodexBarConfig.makeDefault()
        }
        let data = try Data(contentsOf: configURL)
        guard !data.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }) else {
            return CodexBarConfig.makeDefault()
        }
        return try CodexBarConfig.decode(from: data).normalized()
    }

    static func makePayload(
        config: CodexBarConfig,
        managedCodexAccounts: [ManagedCodexAccount],
        identityMode: DashboardIdentityMode) -> CLIServeAccountsPayload
    {
        var accounts = self.tokenAccounts(config: config, identityMode: identityMode)
        accounts.append(contentsOf: self.managedCodexAccounts(
            config: config,
            accounts: managedCodexAccounts,
            identityMode: identityMode))
        accounts.sort {
            if $0.provider != $1.provider { return $0.provider < $1.provider }
            if $0.source != $1.source { return $0.source < $1.source }
            return $0.id < $1.id
        }
        return CLIServeAccountsPayload(schemaVersion: self.schemaVersion, accounts: accounts)
    }

    static func response(
        payload: CLIServeAccountsPayload,
        requestedID: String?) -> CLILocalHTTPResponse
    {
        if let requestedID {
            guard let account = payload.accounts.first(where: { $0.id == requestedID }) else {
                return CodexBarCLI.serveError(status: .notFound, message: "account not found")
            }
            return CodexBarCLI.serveJSON(account)
        }
        return CodexBarCLI.serveJSON(payload)
    }

    private static func tokenAccounts(
        config: CodexBarConfig,
        identityMode: DashboardIdentityMode) -> [CLIServeAccountPayload]
    {
        config.providers.flatMap { providerConfig -> [CLIServeAccountPayload] in
            guard let data = providerConfig.tokenAccounts else { return [] }
            let activeIndex = data.clampedActiveIndex()
            return data.accounts.enumerated().map { index, account in
                let identity = ProviderAccountIdentity(
                    source: self.tokenAccountSource,
                    opaqueID: account.id.uuidString.lowercased())
                return CLIServeAccountPayload(
                    id: "\(identity.source):\(providerConfig.id.rawValue):\(identity.opaqueID)",
                    provider: providerConfig.id.rawValue,
                    source: identity.source,
                    label: self.presentedLabel(account.label, accountID: identity.opaqueID, mode: identityMode),
                    active: index == activeIndex,
                    identity: nil)
            }
        }
    }

    /// Provider-specific by design: managed-home accounts currently exist only for Codex.
    private static func managedCodexAccounts(
        config: CodexBarConfig,
        accounts: [ManagedCodexAccount],
        identityMode: DashboardIdentityMode) -> [CLIServeAccountPayload]
    {
        let activeSource = config.providerConfig(for: self.managedCodexProvider.instanceID)?
            .codexActiveSource ?? .liveSystem
        return accounts.map { account in
            let identity = ProviderAccountIdentity(
                source: self.managedCodexSource,
                opaqueID: account.id.uuidString.lowercased())
            let email = DashboardSnapshotBuilder.dashboardEmail(account.email, mode: identityMode)
            let rawLabel = account.workspaceLabel ?? account.email
            return CLIServeAccountPayload(
                id: "\(identity.source):\(identity.opaqueID)",
                provider: self.managedCodexProvider.rawValue,
                source: identity.source,
                label: self.presentedLabel(rawLabel, accountID: identity.opaqueID, mode: identityMode),
                active: activeSource == .managedAccount(id: account.id),
                identity: identityMode == .none ? nil : CLIServeAccountIdentityPayload(accountEmail: email))
        }
    }

    private static func presentedLabel(
        _ raw: String,
        accountID: String,
        mode: DashboardIdentityMode) -> String
    {
        let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return "Account \(accountID)" }
        // Mirror PersonalInfoRedactor's safe source-issued account placeholder convention.
        // This CLI target cannot depend on the app target where that helper lives.
        if mode == .redacted { return "Account \(accountID)" }
        guard mode != .none else { return label.contains("@") ? "Account \(accountID)" : label }
        return label
    }
}

extension CodexBarCLI {
    static func serveAccountsRoute(
        _ request: CLILocalHTTPRequest,
        id: String?,
        runtime: ServeRuntime) -> CLILocalHTTPResponse
    {
        guard !runtime.dataRoutesRequireAuth || runtime.dashboardAuth.authorize(request) else {
            return self.serveUnauthorizedResponse()
        }
        let config: CodexBarConfig
        let managedAccounts: [ManagedCodexAccount]
        do {
            config = try CLIServeAccountDiscovery.loadConfigReadOnly(from: runtime.configStore)
            managedAccounts = try FileManagedCodexAccountStore().loadAccountMetadata().accounts
        } catch {
            return self.addingNoStore(self.serveError(
                status: .internalServerError,
                message: "could not load accounts"))
        }
        // Serve resolves this mode once at startup and defaults to QuotaKit's
        // redacted policy. Keep account discovery aligned with its snapshots.
        let identityMode = runtime.dashboardIdentityMode
        let payload = CLIServeAccountDiscovery.makePayload(
            config: config,
            managedCodexAccounts: managedAccounts,
            identityMode: identityMode)
        return self.addingNoStore(CLIServeAccountDiscovery.response(
            payload: payload,
            requestedID: id))
    }
}
