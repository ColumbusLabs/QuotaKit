import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite
struct ZaiAvailabilityTests {
    @Test
    func enablesZaiWhenTokenExistsInStore() {
        let suite = "ZaiAvailabilityTests-token"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let tokenStore = StubZaiTokenStore(token: "zai-test-token")
        let settings = SettingsStore(userDefaults: defaults, zaiTokenStore: tokenStore)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)

        let metadata = ProviderRegistry.shared.metadata[.zai]!
        settings.setProviderEnabled(provider: .zai, metadata: metadata, enabled: true)

        let envToken = ZaiSettingsReader.apiToken(environment: ProcessInfo.processInfo.environment)

        #expect(settings.zaiAPIToken.isEmpty)
        #expect(store.isEnabled(.zai) == true)
        if envToken == nil {
            #expect(settings.zaiAPIToken == "zai-test-token")
        } else {
            #expect(settings.zaiAPIToken.isEmpty)
        }
    }
}

private struct StubZaiTokenStore: ZaiTokenStoring {
    let token: String?

    func loadToken() throws -> String? { self.token }
    func storeToken(_: String?) throws {}
}
