import CodexBarCore
import Foundation
import Testing

struct ProviderCookieSettingsResolverTests {
    @Test
    func `configured Cursor credentials remain without a selected account`() {
        let settings = ProviderCookieSettingsResolver.resolve(
            provider: .cursor,
            configuredSource: .manual,
            configuredHeader: "Cookie: session=config",
            selectedAccount: nil)

        #expect(settings.cookieSource == .manual)
        #expect(settings.manualCookieHeader == "Cookie: session=config")
    }

    @Test
    func `selected Claude cookie account overrides configured credentials`() {
        let settings = ProviderCookieSettingsResolver.resolve(
            provider: .claude,
            configuredSource: .auto,
            configuredHeader: "sessionKey=config",
            selectedAccount: Self.account(token: "account"))

        #expect(settings.cookieSource == .manual)
        #expect(settings.manualCookieHeader == "sessionKey=account")
    }

    @Test
    func `Grok ignores generic selected token accounts`() {
        let settings = ProviderCookieSettingsResolver.resolve(
            provider: .grok,
            configuredSource: .auto,
            configuredHeader: "sso=configured",
            selectedAccount: Self.account(token: "account"))

        #expect(settings.cookieSource == .auto)
        #expect(settings.manualCookieHeader == "sso=configured")
    }

    private static func account(token: String) -> ProviderTokenAccount {
        ProviderTokenAccount(id: UUID(), label: "Test", token: token, addedAt: 0, lastUsed: nil)
    }
}
