import CodexBarCore

extension UsageStore {
    func clearTokenSnapshotAfterFailedRefresh(for provider: UsageProvider) {
        // Provider-specific by design: Codex retains its established ledger through transient scan failures.
        if provider != .codex {
            self.clearTokenSnapshot(for: provider)
        }
    }
}
