import Foundation
import Testing
@testable import CodexBarCore

@Suite
struct OpenCodeCookieCacheTests {
    @Test
    func storesAndLoadsEntry() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = tempDir.appendingPathComponent("opencode-cookie.json")
        let storedAt = Date(timeIntervalSince1970: 0)
        let entry = OpenCodeCookieCache.Entry(
            cookieHeader: "auth=abc",
            storedAt: storedAt,
            sourceLabel: "Chrome")

        OpenCodeCookieCache.store(entry, to: url)
        let loaded = OpenCodeCookieCache.load(from: url)

        #expect(loaded?.cookieHeader == "auth=abc")
        #expect(loaded?.sourceLabel == "Chrome")
        #expect(loaded?.storedAt == storedAt)
    }
}
