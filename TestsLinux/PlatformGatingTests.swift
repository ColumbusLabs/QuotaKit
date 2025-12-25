import CodexBarCore
import Testing

@Suite
struct PlatformGatingTests {
    @Test
    func claudeWebFetcher_isNotSupportedOnLinux() async {
        #if os(Linux)
        await #expect(throws: ClaudeWebAPIFetcher.FetchError.notSupportedOnThisPlatform) {
            _ = try await ClaudeWebAPIFetcher.fetchUsage()
        }
        #else
        #expect(true)
        #endif
    }

    @Test
    func claudeWebFetcher_hasSessionKey_isFalseOnLinux() {
        #if os(Linux)
        #expect(ClaudeWebAPIFetcher.hasSessionKey() == false)
        #else
        #expect(true)
        #endif
    }

    @Test
    func claudeWebFetcher_sessionKeyInfo_throwsOnLinux() {
        #if os(Linux)
        #expect(throws: ClaudeWebAPIFetcher.FetchError.notSupportedOnThisPlatform) {
            _ = try ClaudeWebAPIFetcher.sessionKeyInfo()
        }
        #else
        #expect(true)
        #endif
    }
}

