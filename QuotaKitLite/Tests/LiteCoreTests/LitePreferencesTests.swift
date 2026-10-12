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

        #expect(preferences.enabledProviders == [.claude, .codex])
        #expect(preferences.menuBarStyle == .percentages)
    }

    @Test
    func `toggling turns a provider off and back on in display order`() {
        let preferences = Self.preferences()

        preferences.toggle(.claude)
        #expect(preferences.enabledProviders == [.codex])

        preferences.toggle(.claude)
        #expect(preferences.enabledProviders == [.claude, .codex])
    }

    @Test
    func `the last enabled provider cannot be turned off`() {
        let preferences = Self.preferences()
        preferences.toggle(.claude)

        preferences.toggle(.codex)

        #expect(preferences.enabledProviders == [.codex])
    }

    @Test
    func `a provider that is not available yet is ignored`() {
        let preferences = Self.preferences()

        preferences.enabledProviders = [.antigravity]

        #expect(preferences.enabledProviders == [.claude, .codex])
    }

    @Test
    func `the menu bar style is remembered`() {
        let preferences = Self.preferences()

        preferences.menuBarStyle = .logosAndBars

        #expect(preferences.menuBarStyle == .logosAndBars)
    }
}
