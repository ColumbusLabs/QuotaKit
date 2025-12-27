import SweetCookieKit

public typealias BrowserCookieImportOrder = [Browser]

extension BrowserCookieImportOrder {
    public static let safariChromeFirefox: BrowserCookieImportOrder = BrowserCookieDefaults.importOrder

    public var browsers: [Browser] { self }
}
