import Foundation
import Testing
import WebKit
@testable import CodexBarCore

@Suite
struct OpenAIDashboardNavigationDelegateTests {
    @Test("ignores NSURLErrorCancelled")
    func ignoresCancelledNavigationError() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        #expect(NavigationDelegate.shouldIgnoreNavigationError(error))
    }

    @Test("does not ignore non-cancelled URL errors")
    func doesNotIgnoreOtherURLErrors() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        #expect(!NavigationDelegate.shouldIgnoreNavigationError(error))
    }

    @MainActor
    @Test("cancelled failures complete with success")
    func cancelledFailureCompletesWithSuccess() {
        let webView = WKWebView()
        var result: Result<Void, Error>?
        let delegate = NavigationDelegate { result = $0 }

        delegate.webView(webView, didFail: nil, withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))

        switch result {
        case .success?:
            #expect(Bool(true))
        default:
            #expect(Bool(false))
        }
    }
}
