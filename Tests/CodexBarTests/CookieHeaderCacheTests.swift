import Foundation
import Testing
@testable import CodexBarCore

@Suite
struct CookieHeaderCacheTests {
    @Test
    func storesAndLoadsEntry() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = tempDir.appendingPathComponent("cookie-cache.json")
        let storedAt = Date(timeIntervalSince1970: 0)
        let entry = CookieHeaderCache.Entry(
            cookieHeader: "auth=abc",
            storedAt: storedAt,
            sourceLabel: "Chrome")

        CookieHeaderCache.store(entry, to: url)
        let loaded = CookieHeaderCache.load(from: url)

        #expect(loaded?.cookieHeader == "auth=abc")
        #expect(loaded?.sourceLabel == "Chrome")
        #expect(loaded?.storedAt == storedAt)
    }
}
