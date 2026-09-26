import CodexBarCore
import Foundation

extension SettingsStore {
    var typesafeCookieHeader: String {
        get { self[providerConfig: .typesafe, field: .cookieHeader] }
        set { self[providerConfig: .typesafe, field: .cookieHeader] = newValue }
    }

    var typesafeCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .typesafe, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .typesafe) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .typesafe, field: "cookieSource", value: newValue.rawValue)
        }
    }
}
