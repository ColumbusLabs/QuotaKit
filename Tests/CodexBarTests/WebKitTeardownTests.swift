#if os(macOS)
import AppKit
import Testing
@testable import CodexBarCore

@Suite
@MainActor
struct WebKitTeardownTests {
    final class Owner {}

    @Test
    func scheduleCleanupReleasesOwner() async {
        let owner = Owner()
        WebKitTeardown.resetForTesting()
        WebKitTeardown.scheduleCleanup(owner: owner, window: nil, webView: nil)

        #expect(WebKitTeardown.isRetainedForTesting(owner))
        #expect(WebKitTeardown.isScheduledForTesting(owner))

        let deadline = Date().addingTimeInterval(9)
        while Date() < deadline {
            if !WebKitTeardown.isRetainedForTesting(owner),
               !WebKitTeardown.isScheduledForTesting(owner)
            {
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        #expect(!WebKitTeardown.isRetainedForTesting(owner))
        #expect(!WebKitTeardown.isScheduledForTesting(owner))
    }
}
#endif
