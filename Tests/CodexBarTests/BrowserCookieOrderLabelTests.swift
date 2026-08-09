import SweetCookieKit
import Testing
@testable import CodexBarCore

struct BrowserCookieOrderStatusStringTests {
    #if os(macOS)
    @Test
    func `Codex cookie import order keeps Firefox ahead of extra Chromium browsers`() {
        let order = ProviderDefaults.metadata[.codex]?.browserCookieOrder ?? Browser.defaultImportOrder
        #expect(Array(order.prefix(3)) == [.safari, .chrome, .firefox])
    }

    @Test
    func `automatic cookie import includes supported Chromium browsers`() {
        #expect(Browser.defaultImportOrder.contains(.comet))
        #expect(Browser.defaultImportOrder.contains(.yandex))
    }

    @Test
    func `Cursor missing session includes browser login hint`() {
        let order = ProviderDefaults.metadata[.cursor]?.browserCookieOrder ?? Browser.defaultImportOrder
        let message = CursorStatusProbeError.noSessionCookie.errorDescription ?? ""
        #expect(message.contains(order.loginHint))
    }

    @Test
    func `Cursor missing session shows full disk access hint before browser list`() throws {
        let order = ProviderDefaults.metadata[.cursor]?.browserCookieOrder ?? Browser.defaultImportOrder
        let message = try #require(CursorStatusProbeError.noSessionCookie.errorDescription)
        let fullDiskAccess = try #require(message.range(of: CursorStatusProbeError.safariFullDiskAccessHint))
        let browserList = try #require(message.range(of: order.loginHint))

        #expect(fullDiskAccess.lowerBound < browserList.lowerBound)
    }
    #endif
}
