import CodexBarCore
import Foundation

extension SettingsStore {
    var cursorUsageDataSource: ProviderSourceMode {
        get {
            let source = self.configSnapshot.providerConfig(for: .cursor)?.source
            return source == .api ? .api : .auto
        }
        set {
            let resolved: ProviderSourceMode = newValue == .api ? .api : .auto
            self.updateProviderConfig(provider: .cursor) { entry in
                entry.source = resolved == .auto ? nil : resolved
            }
            self.logProviderModeChange(provider: .cursor, field: "source", value: resolved.rawValue)
        }
    }

    var cursorCookieHeader: String {
        get { self.configSnapshot.providerConfig(for: .cursor)?.sanitizedCookieHeader ?? "" }
        set {
            self.updateProviderConfig(provider: .cursor) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .cursor, field: "cookieHeader", value: newValue)
        }
    }

    var cursorCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .cursor, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .cursor) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .cursor, field: "cookieSource", value: newValue.rawValue)
        }
    }

    func ensureCursorCookieLoaded() {}
}

extension SettingsStore {
    func cursorSettingsSnapshot(tokenOverride: TokenAccountOverride?) -> ProviderSettingsSnapshot
    .CursorProviderSettings {
        self.resolvedCookieSettings(
            provider: .cursor,
            configuredSource: self.cursorCookieSource,
            configuredHeader: self.cursorCookieHeader,
            tokenOverride: tokenOverride)
    }
}
