import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct SettingsStoreRefreshDefaultTests {
    @Test
    func `fresh install defaults to adaptive and persists the choice`() throws {
        let fixture = try self.fixture("fresh")

        #expect(fixture.store.refreshFrequency == .adaptive)
        #expect(fixture.defaults.string(forKey: "refreshFrequency") == RefreshFrequency.adaptive.rawValue)
        #expect(fixture.store.adaptiveActivityScanConsent == .undecided)
    }

    @Test
    func `previous app group install keeps five minute fallback`() throws {
        let fixture = try self.fixture("previous", configure: { defaults in
            defaults.set(AppGroupSupport.migrationVersion, forKey: AppGroupSupport.migrationVersionKey)
        })

        #expect(fixture.store.refreshFrequency == .fiveMinutes)
        #expect(fixture.defaults.string(forKey: "refreshFrequency") == RefreshFrequency.fiveMinutes.rawValue)
    }

    @Test
    func `explicit refresh choice survives reload`() throws {
        let fixture = try self.fixture("explicit", configure: { defaults in
            defaults.set(RefreshFrequency.thirtyMinutes.rawValue, forKey: "refreshFrequency")
        })

        #expect(fixture.store.refreshFrequency == .thirtyMinutes)
        #expect(fixture.store.refreshFrequency.seconds == 1800)
    }

    @Test
    func `unrecognized refresh frequency uses safe fallback`() throws {
        let fixture = try self.fixture("invalid", configure: { defaults in
            defaults.set("legacy-value", forKey: "refreshFrequency")
        })

        #expect(fixture.store.refreshFrequency == .fiveMinutes)
    }

    @Test
    func `agent aware adaptive mode requests consent only while undecided`() throws {
        let fixture = try self.fixture("agent-aware")
        fixture.store.refreshFrequency = .adaptiveAgentAware

        #expect(fixture.store.shouldRequestAdaptiveActivityScanConsent)
        fixture.store.adaptiveActivityScanConsent = .declined
        #expect(fixture.store.refreshFrequency == .adaptiveAgentAware)
        #expect(!fixture.store.shouldRequestAdaptiveActivityScanConsent)
    }

    private func fixture(
        _ suffix: String,
        configure: (UserDefaults) -> Void = { _ in }) throws
        -> (store: SettingsStore, defaults: UserDefaults)
    {
        let suite = "SettingsStoreRefreshDefaultTests-\(suffix)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        configure(defaults)
        return (
            SettingsStore(userDefaults: defaults, configStore: testConfigStore(suiteName: suite)),
            defaults)
    }
}
