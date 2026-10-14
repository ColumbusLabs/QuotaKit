import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
import SweetCookieKit

struct VeniceBrowserOrderTests {
    @Test
    func `venice web import uses the shared browser order`() throws {
        let metadata = try #require(ProviderDefaults.metadata[.venice])
        #expect(metadata.browserCookieOrder == ProviderBrowserCookieDefaults.defaultImportOrder)
    }
}
#endif
