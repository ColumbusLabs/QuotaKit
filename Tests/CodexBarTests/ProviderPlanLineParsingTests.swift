import Testing
@testable import CodexBarCore

struct ProviderPlanLineParsingTests {
    @Test
    func `Claude plan matching does not bridge usage lines`() {
        let usageText = """
        Skills, subagents, plugins, and MCP servers
        Noattributiondatayet·accumulatesasyouuseClaude

        dtoday·wtoweek

        Usagecredits
        Usagecreditsareoff·/usage-creditstoturnthemon
        """

        let identity = ClaudeStatusProbe.parseIdentity(usageText: usageText, statusText: nil)

        #expect(identity.loginMethod == nil)
    }

    @Test
    func `Claude plan matching keeps single line phrases`() {
        let identity = ClaudeStatusProbe.parseIdentity(
            usageText: nil,
            statusText: "Sonnet 4.6 · Claude Max · you@example.com")

        #expect(identity.loginMethod == "Max")
    }
}
