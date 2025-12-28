#if os(macOS)
import SweetCookieKit

public typealias BrowserCookieImportOrder = [Browser]
#else
public struct Browser: Sendable, Hashable {
    public init() {}
}

public typealias BrowserCookieImportOrder = [Browser]
#endif
