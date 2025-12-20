import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite
struct SettingsStoreTests {
    @Test
    func defaultRefreshFrequencyIsFiveMinutes() {
        let suite = "SettingsStoreTests-default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = SettingsStore(userDefaults: defaults)

        #expect(store.refreshFrequency == .fiveMinutes)
        #expect(store.refreshFrequency.seconds == 300)
    }

    @Test
    func persistsRefreshFrequencyAcrossInstances() {
        let suite = "SettingsStoreTests-persist"
        let defaultsA = UserDefaults(suiteName: suite)!
        defaultsA.removePersistentDomain(forName: suite)
        let storeA = SettingsStore(userDefaults: defaultsA)

        storeA.refreshFrequency = .fifteenMinutes

        let defaultsB = UserDefaults(suiteName: suite)!
        let storeB = SettingsStore(userDefaults: defaultsB)

        #expect(storeB.refreshFrequency == .fifteenMinutes)
        #expect(storeB.refreshFrequency.seconds == 900)
    }

    @Test
    func persistsSelectedMenuProviderAcrossInstances() {
        let suite = "SettingsStoreTests-selectedMenuProvider"
        let defaultsA = UserDefaults(suiteName: suite)!
        defaultsA.removePersistentDomain(forName: suite)
        let storeA = SettingsStore(userDefaults: defaultsA)

        storeA.selectedMenuProvider = .claude

        let defaultsB = UserDefaults(suiteName: suite)!
        let storeB = SettingsStore(userDefaults: defaultsB)

        #expect(storeB.selectedMenuProvider == .claude)
    }

    @Test
    func defaultsSessionQuotaNotificationsToEnabled() {
        let key = "sessionQuotaNotificationsEnabled"
        let suite = "SettingsStoreTests-sessionQuotaNotifications"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(userDefaults: defaults)
        #expect(store.sessionQuotaNotificationsEnabled == true)
        #expect(defaults.bool(forKey: key) == true)
    }
}
