import Foundation
import Testing
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
}
