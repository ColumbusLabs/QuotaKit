import Foundation
#if os(macOS)
import SweetCookieKit
#endif

/// Shared browser import policies; providers retain session validation and logging.
enum BrowserCookieImportSupport {
    /// Keep deliberate Chrome-only policies explicit without duplicating platform guards in descriptors.
    static func chromeOnly(reason _: StaticString) -> BrowserCookieImportOrder? {
        #if os(macOS)
        Browser.defaultImportOrder.filter { $0 == .chrome }
        #else
        nil
        #endif
    }
}
