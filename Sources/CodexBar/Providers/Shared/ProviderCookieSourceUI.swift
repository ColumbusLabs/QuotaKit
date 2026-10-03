import CodexBarCore

enum ProviderCookieSourceUI {
    struct Subtitles {
        let auto: String
        let manual: String
        let off: String
    }

    static let keychainDisabledPrefixKey =
        "Keychain access is disabled in Advanced, so browser cookie import is unavailable."

    @MainActor
    static func browserImportSubtitle(_ summary: String, provider: UsageProvider) -> String {
        let hint = L(
            "Supported browsers: %@. Use Manual for other browsers.",
            BrowserCookieImportSupport.browserNames(for: provider))
        return "\(summary) \(hint)"
    }

    @MainActor
    static func cachedTrailingText(provider: UsageProvider, scope: CookieHeaderCache.Scope? = nil) -> String? {
        guard let entry = CookieHeaderCache.loadForDisplay(provider: provider, scope: scope) else { return nil }
        return self.cachedTrailingText(entry: entry)
    }

    @MainActor
    static func cachedTrailingText(entry: CookieHeaderCache.Entry) -> String {
        let when = entry.storedAt.relativeDescription()
        return L("Cached: %1$@ • %2$@", entry.sourceLabel, when)
    }

    static func options(allowsOff: Bool, keychainDisabled: Bool) -> [ProviderSettingsPickerOption] {
        var options: [ProviderSettingsPickerOption] = []
        if !keychainDisabled {
            options.append(ProviderSettingsPickerOption(
                id: ProviderCookieSource.auto.rawValue,
                title: ProviderCookieSource.auto.displayName))
        }
        options.append(ProviderSettingsPickerOption(
            id: ProviderCookieSource.manual.rawValue,
            title: ProviderCookieSource.manual.displayName))
        if allowsOff {
            options.append(ProviderSettingsPickerOption(
                id: ProviderCookieSource.off.rawValue,
                title: ProviderCookieSource.off.displayName))
        }
        return options
    }

    static func subtitle(
        source: ProviderCookieSource,
        keychainDisabled: Bool,
        subtitles: Subtitles) -> String
    {
        if keychainDisabled {
            return source == .off
                ? subtitles.off
                : "\(L(self.keychainDisabledPrefixKey)) \(subtitles.manual)"
        }
        switch source {
        case .auto:
            return subtitles.auto
        case .manual:
            return subtitles.manual
        case .off:
            return subtitles.off
        }
    }
}
