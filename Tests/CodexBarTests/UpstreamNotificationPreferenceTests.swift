import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct UpstreamNotificationPreferenceTests {
    @Test
    func `reset reminders default off and round trip without changing each other`() throws {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(!settings.codexResetCreditExpiryNotificationsEnabled)
        #expect(!settings.upcomingResetNotificationsEnabled)
        settings.codexResetCreditExpiryNotificationsEnabled = true
        let reloaded = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(reloaded.codexResetCreditExpiryNotificationsEnabled)
        #expect(!reloaded.upcomingResetNotificationsEnabled)
        reloaded.upcomingResetNotificationsEnabled = true
        let target = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        try target.importPreferences(reloaded.exportPreferences())
        #expect(target.codexResetCreditExpiryNotificationsEnabled)
        #expect(target.upcomingResetNotificationsEnabled)
        reloaded.codexResetCreditExpiryNotificationsEnabled = false
        try target.importPreferences(reloaded.exportPreferences())
        #expect(!target.codexResetCreditExpiryNotificationsEnabled)
        #expect(target.upcomingResetNotificationsEnabled)
    }
}
