import CodexBarCore

/// Loads the unified provider configuration and fills in any missing supported providers.
///
/// Unknown provider entries remain intact so older or externally managed config files can
/// round-trip without data loss, but QuotaKit no longer scans or clears retired Keychain stores.
enum CodexBarConfigMigrator {
    static func load(configStore: CodexBarConfigStore) -> CodexBarConfig {
        let stored = try? configStore.load()
        return (stored ?? CodexBarConfig.makeDefault()).normalized()
    }
}
