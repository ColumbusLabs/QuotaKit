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

        try? await Task.sleep(for: .seconds(3))

        #expect(!WebKitTeardown.isRetainedForTesting(owner))
        #expect(!WebKitTeardown.isScheduledForTesting(owner))
    }
}
#endif
