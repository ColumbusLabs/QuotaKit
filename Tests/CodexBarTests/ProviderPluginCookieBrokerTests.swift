import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ProviderPluginCookieBrokerTests {
    @Test
    func `disabled source neither reads cached cookies nor imports a browser session`() throws {
        try self.withIsolatedCookieCache {
            CookieHeaderCache.store(provider: .zed, cookieHeader: "zed.session=cached", sourceLabel: "Chrome")
            let broker = ProviderPluginCookieBroker(
                provider: .zed,
                domains: ["zed.dev"],
                settings: .init(cookieSource: .off, manualCookieHeader: nil),
                importer: { _ in
                    Issue.record("Disabled browser cookies must not import from a browser")
                    return ("zed.session=imported", "Chrome")
                })

            let error = #expect(throws: ProviderPluginError.self) {
                try broker.cookieHeader(domain: "zed.dev")
            }

            #expect(error == .secretAccess("browser cookies are disabled for this provider"))
            #expect(CookieHeaderCache.load(provider: .zed)?.cookieHeader == "zed.session=cached")
        }
    }

    @Test
    func `rejected session clears only the observed cache entry`() throws {
        try self.withIsolatedCookieCache {
            let broker = ProviderPluginCookieBroker(
                provider: .zed,
                domains: ["zed.dev"],
                settings: .init(cookieSource: .auto, manualCookieHeader: nil),
                importer: { _ in ("zed.session=old", "Chrome") })
            let initialHeader = try broker.cookieHeader(domain: "zed.dev")
            #expect(initialHeader == "zed.session=old")

            CookieHeaderCache.store(
                provider: .zed,
                cookieHeader: "zed.session=replacement",
                sourceLabel: "Safari",
                now: Date(timeIntervalSince1970: 1))
            broker.rejectCookie(domain: "zed.dev")

            #expect(CookieHeaderCache.load(provider: .zed)?.cookieHeader == "zed.session=replacement")
        }
    }

    @Test
    func `cookie domains are isolated and manual sessions are never invalidated`() throws {
        try self.withIsolatedCookieCache {
            let broker = ProviderPluginCookieBroker(
                provider: .zed,
                domains: ["zed.dev", "staging.zed.dev"],
                settings: .init(cookieSource: .auto, manualCookieHeader: nil),
                importer: { domain in ("zed.session=\(domain)", "Chrome") })
            let productionHeader = try broker.cookieHeader(domain: "zed.dev")
            let stagingHeader = try broker.cookieHeader(domain: "staging.zed.dev")
            #expect(productionHeader == "zed.session=zed.dev")
            #expect(stagingHeader == "zed.session=staging.zed.dev")
            let productionScope = CookieHeaderCache.Scope.providerVariant("zed.dev")
            let stagingScope = CookieHeaderCache.Scope.providerVariant("staging.zed.dev")

            broker.rejectCookie(domain: "zed.dev")

            #expect(CookieHeaderCache.load(provider: .zed, scope: productionScope) == nil)
            #expect(CookieHeaderCache.load(provider: .zed, scope: stagingScope)?.cookieHeader ==
                "zed.session=staging.zed.dev")

            let manualBroker = ProviderPluginCookieBroker(
                provider: .zed,
                domains: ["zed.dev"],
                settings: .init(cookieSource: .manual, manualCookieHeader: "zed.session=manual"),
                importer: { _ in Issue.record("Manual sessions must not import browser cookies"); return ("", "") })
            let manualHeader = try manualBroker.cookieHeader(domain: "zed.dev")
            #expect(manualHeader == "zed.session=manual")
            CookieHeaderCache.store(provider: .zed, cookieHeader: "zed.session=cached", sourceLabel: "Chrome")
            manualBroker.rejectCookie(domain: "zed.dev")
            #expect(CookieHeaderCache.load(provider: .zed)?.cookieHeader == "zed.session=cached")
        }
    }

    private func withIsolatedCookieCache<T>(_ operation: () throws -> T) throws -> T {
        let service = "com.columbuslabs.quotakit.tests.plugin-cookie-\(UUID().uuidString)"
        let legacyBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-plugin-cookie-\(UUID().uuidString)", isDirectory: true)
        return try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try CookieHeaderCache.withLegacyBaseURLOverrideForTesting(legacyBase) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }
                CookieHeaderCache.resetDisplayCacheForTesting()
                defer { CookieHeaderCache.resetDisplayCacheForTesting() }
                return try operation()
            }
        }
    }
}
