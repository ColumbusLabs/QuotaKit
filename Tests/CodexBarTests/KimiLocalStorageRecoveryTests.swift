#if os(macOS)
import Foundation
import Testing
@testable import CodexBarCore

struct KimiLocalStorageRecoveryTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let token = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE4MDAwMDM2MDB9.signature"

    @Test
    func `imports only valid unexpired regional access tokens and deduplicates`() {
        let expired = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjF9.signature"
        let api = BrowserLocalStorageAPI { origin, browsers, _, _ in
            #expect(browsers == ChromiumLocalStorageDiscovery.defaultBrowsers)
            guard origin == "https://www.kimi.ai" else { return [] }
            return [
                .init(id: "chrome:Default", label: "Chrome Default", entries: [
                    .init(key: "refresh_token", value: Self.token),
                    .init(key: "access_token", value: expired),
                    .init(key: "access_token", value: "not-a-token"),
                    .init(key: "access_token", value: "a.b.c"),
                    .init(key: "access_token", value: Self.token + "; kimi-auth=x"),
                    .init(key: "access_token", value: " \(Self.token)\n"),
                ]),
                .init(id: "chrome:Profile 2", label: "Chrome Profile 2", entries: [
                    .init(key: "access_token", value: "\"\(Self.token)\""),
                ]),
            ]
        }

        #expect(KimiCookieImporter.localStorageTokens(
            region: .international,
            localStorage: api,
            now: Self.now) == [Self.token])
        #expect(KimiCookieImporter.localStorageTokens(
            region: .china,
            localStorage: api,
            now: Self.now).isEmpty)
        #expect(KimiCookieImporter.localStorageTokens(
            region: .international,
            localStorage: api,
            now: Self.now.addingTimeInterval(3600)).isEmpty)
    }
}
#endif
