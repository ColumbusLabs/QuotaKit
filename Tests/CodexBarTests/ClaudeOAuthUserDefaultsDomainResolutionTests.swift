import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeOAuthUserDefaultsDomainResolutionTests {
    @Test
    func `uses standard defaults when the app domain is the current bundle identifier`() {
        let standard = InMemoryUserDefaults()
        let fallback = InMemoryUserDefaults()
        var requestedSuites: [String] = []

        let resolved = ClaudeOAuthKeychainPromptPreference.resolveUserDefaults(
            domain: "com.example.app",
            bundleIdentifier: "com.example.app",
            standard: standard,
            suiteFactory: { requestedSuites.append($0); return nil },
            fallback: fallback)

        #expect(resolved === standard)
        #expect(requestedSuites.isEmpty)
    }

    @Test
    func `uses the named suite when the app domain differs from the bundle identifier`() {
        let standard = InMemoryUserDefaults()
        let suite = InMemoryUserDefaults()
        let fallback = InMemoryUserDefaults()

        let resolved = ClaudeOAuthKeychainPromptPreference.resolveUserDefaults(
            domain: "com.example.shared",
            bundleIdentifier: "com.example.app",
            standard: standard,
            suiteFactory: { $0 == "com.example.shared" ? suite : nil },
            fallback: fallback)

        #expect(resolved === suite)
    }

    @Test
    func `uses the fallback when the named suite cannot be created`() {
        let fallback = InMemoryUserDefaults()

        let resolved = ClaudeOAuthKeychainPromptPreference.resolveUserDefaults(
            domain: "com.example.shared",
            bundleIdentifier: nil,
            standard: InMemoryUserDefaults(),
            suiteFactory: { _ in nil },
            fallback: fallback)

        #expect(resolved === fallback)
    }
}
