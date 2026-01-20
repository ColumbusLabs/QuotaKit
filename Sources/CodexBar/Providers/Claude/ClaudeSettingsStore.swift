import CodexBarCore
import Foundation

extension SettingsStore {
    var claudeUsageDataSource: ClaudeUsageDataSource {
        get {
            let source = self.configSnapshot.providerConfig(for: .claude)?.source
            return Self.claudeUsageDataSource(from: source)
        }
        set {
            let source: ProviderSourceMode? = switch newValue {
            case .auto: .auto
            case .oauth: .oauth
            case .web: .web
            case .cli: .cli
            }
            self.updateProviderConfig(provider: .claude) { entry in
                entry.source = source
            }
            self.logProviderModeChange(provider: .claude, field: "usageSource", value: newValue.rawValue)
            if newValue != .cli {
                self.claudeWebExtrasEnabled = false
            }
        }
    }

    var claudeCookieHeader: String {
        get { self.configSnapshot.providerConfig(for: .claude)?.sanitizedCookieHeader ?? "" }
        set {
            self.updateProviderConfig(provider: .claude) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .claude, field: "cookieHeader", value: newValue)
        }
    }

    var claudeCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .claude, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .claude) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .claude, field: "cookieSource", value: newValue.rawValue)
        }
    }

    func ensureClaudeCookieLoaded() {}
}

extension SettingsStore {
    private static func claudeUsageDataSource(from source: ProviderSourceMode?) -> ClaudeUsageDataSource {
        guard let source else { return .auto }
        switch source {
        case .auto, .api:
            return .auto
        case .web:
            return .web
        case .cli:
            return .cli
        case .oauth:
            return .oauth
        }
    }
}
