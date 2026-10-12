import Foundation
import LiteCore
import Testing

struct LitePreferencesTests {
    /// A throwaway defaults domain per test, so nothing touches the app's real preferences.
    private static func preferences() -> LitePreferences {
        let suite = "LitePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return LitePreferences(defaults: defaults)
    }

    @Test
    func `defaults to every available provider and percentages`() {
        let preferences = Self.preferences()

        #expect(preferences.enabledProviders == [.claude, .codex, .antigravity])
        #expect(preferences.menuBarStyle == .percentages)
        #expect(preferences.refreshInterval == .twoMinutes)
    }

    @Test
    func `toggling turns a provider off and back on in display order`() {
        let preferences = Self.preferences()

        preferences.toggle(.claude)
        #expect(preferences.enabledProviders == [.codex, .antigravity])

        preferences.toggle(.claude)
        #expect(preferences.enabledProviders == [.claude, .codex, .antigravity])
    }

    @Test
    func `the last enabled provider cannot be turned off`() {
        let preferences = Self.preferences()
        preferences.toggle(.claude)
        preferences.toggle(.antigravity)

        preferences.toggle(.codex)

        #expect(preferences.enabledProviders == [.codex])
    }

    @Test
    func `a stored list keeps display order and an empty one means all`() {
        let preferences = Self.preferences()

        preferences.enabledProviders = [.antigravity, .claude]
        #expect(preferences.enabledProviders == [.claude, .antigravity])

        preferences.enabledProviders = []
        #expect(preferences.enabledProviders == [.claude, .codex, .antigravity])
    }

    @Test
    func `the menu bar style is remembered`() {
        let preferences = Self.preferences()

        preferences.menuBarStyle = .logosAndBars

        #expect(preferences.menuBarStyle == .logosAndBars)
    }
}
