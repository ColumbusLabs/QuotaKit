import CodexBarCore
import Testing

@Suite
struct PlatformGatingTests {
    @Test
    func claudeWebFetcher_isNotSupportedOnLinux() async {
        #if os(Linux)
        let error = #expect(throws: ClaudeWebAPIFetcher.FetchError.self) {
            _ = try await ClaudeWebAPIFetcher.fetchUsage()
        }
        if let error, case .notSupportedOnThisPlatform = error {
            #expect(true)
        } else {
            #expect(false)
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
        let error = #expect(throws: ClaudeWebAPIFetcher.FetchError.self) {
            _ = try ClaudeWebAPIFetcher.sessionKeyInfo()
        }
        if let error, case .notSupportedOnThisPlatform = error {
            #expect(true)
        } else {
            #expect(false)
        }
        #else
        #expect(true)
        #endif
    }
}
