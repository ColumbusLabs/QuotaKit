import CodexBarCore

extension UsageStore {
    func codexMenuAccountName(for provider: UsageProvider, context: UsageMenuCardContext) -> String? {
        guard provider == .codex, !context.isSettings, context.account == nil,
              !self.settings.hidePersonalInfo, self.settings.codexUsageDataSource != .pat,
              self.lastSourceLabels[.codex] != "pat",
              let account = self.settings.codexVisibleAccountProjectionForMenuDisplay?.visibleAccounts
                  .first(where: { $0.isActive }),
                  account.customName != nil
        else { return nil }
        return account.menuDisplayName
    }
}
