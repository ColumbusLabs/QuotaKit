import CodexBarCore
import Testing
@testable import CodexBarCLI

@Suite
struct CLIWebFallbackTests {
    @Test
    func codexFallsBackWhenCookiesMissing() {
        #expect(CodexBarCLI.shouldFallbackToCodexCLI(
            for: OpenAIDashboardBrowserCookieImporter.ImportError.noCookiesFound))
        #expect(CodexBarCLI.shouldFallbackToCodexCLI(
            for: OpenAIDashboardBrowserCookieImporter.ImportError.noMatchingAccount(found: [])))
        #expect(CodexBarCLI.shouldFallbackToCodexCLI(
            for: OpenAIDashboardBrowserCookieImporter.ImportError.browserAccessDenied(details: "no access")))
        #expect(CodexBarCLI.shouldFallbackToCodexCLI(
            for: OpenAIDashboardBrowserCookieImporter.ImportError.dashboardStillRequiresLogin))
        #expect(CodexBarCLI.shouldFallbackToCodexCLI(
            for: OpenAIDashboardFetcher.FetchError.loginRequired))
    }

    @Test
    func codexDoesNotFallbackForDashboardDataErrors() {
        #expect(!CodexBarCLI.shouldFallbackToCodexCLI(
            for: OpenAIDashboardFetcher.FetchError.noDashboardData(body: "missing")))
    }

    @Test
    func claudeFallsBackWhenNoSessionKey() {
        #expect(CodexBarCLI.shouldFallbackToClaudeCLI(
            for: ClaudeWebAPIFetcher.FetchError.noSessionKeyFound))
        #expect(!CodexBarCLI.shouldFallbackToClaudeCLI(
            for: ClaudeWebAPIFetcher.FetchError.unauthorized))
    }
}
