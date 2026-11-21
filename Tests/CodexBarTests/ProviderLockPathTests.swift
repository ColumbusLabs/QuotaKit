import Foundation
import Testing
@testable import CodexBarCore

struct ProviderLockPathTests {
    @Test
    func `provider locks preserve existing coordination paths without creating files`() {
        let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".codexbar", isDirectory: true)
        let claude = ClaudeOAuthPendingCacheClearUserDefaultsStore(
            domain: "ProviderLockPathTests.\(UUID().uuidString)", key: "pending")
        let antigravity = AntigravityFileCLISessionLaunchLock()

        #expect(claude.lockURL == root.appendingPathComponent("claude-oauth-cache.lock"))
        #expect(antigravity.fileURL == root.appendingPathComponent("antigravity/agy-session.lock"))
    }
}
