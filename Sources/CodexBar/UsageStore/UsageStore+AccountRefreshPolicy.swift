import CodexBarCore

extension UsageStore {
    static let tokenAccountMenuSnapshotLimit = 6

    func freshCodexVisibleAccountsForSnapshotHydration() -> [CodexVisibleAccount] {
        self.freshCodexVisibleAccountProjectionForAccountRefresh().visibleAccounts
    }

    func tokenAccounts(for provider: UsageProvider) -> [ProviderTokenAccount] {
        guard TokenAccountSupportCatalog.support(for: provider) != nil else { return [] }
        return self.settings.tokenAccounts(for: provider)
    }

    func shouldFetchAllTokenAccounts(provider: UsageProvider, accounts: [ProviderTokenAccount]) -> Bool {
        guard let support = TokenAccountSupportCatalog.support(for: provider), accounts.count > 1 else {
            return false
        }
        // Saved credentials stay passive while a provider uses a web or other non-token source.
        let source = self.settings.providerConfig(for: provider)?.source ?? .auto
        guard !support.passiveSourceModes.contains(source) else { return false }
        // CloudKit sync and account widgets both need every saved token account, independent of menu layout.
        if self.settings.iCloudSyncEnabled || self.settings.accountWidgetsEnabled { return true }
        return self.settings.multiAccountMenuLayout == .stacked
    }

    func shouldFetchAllCodexVisibleAccounts() -> Bool {
        // PAT is not a per-visible-account credential. Fan-out would fetch the same token for
        // every row and then reject its whoami identity against other accounts.
        guard !self.shouldUseAmbientCodexPATForUsage() else { return false }
        let projection = self.freshCodexVisibleAccountProjectionForAccountRefresh()
        return (self.settings.multiAccountMenuLayout == .stacked || self.settings.accountWidgetsEnabled)
            && projection.visibleAccounts.count > 1
    }
}
