import Commander
import Foundation
@preconcurrency import JavaScriptCore
import Testing
@testable import CodexBarCLI

struct CLIServeWebUITests {
    private var html: String {
        String(bytes: CLIServeWebUI.response().body, encoding: .utf8) ?? ""
    }

    @Test(arguments: [false, true])
    func `usage window follows the server fill preference`(showUsed: Bool) throws {
        let start = try #require(self.html.range(of: "function renderWindow(window)"))
        let end = try #require(self.html.range(of: "function renderCostChart(history)"))
        let context = try #require(JSContext())
        context.evaluateScript("""
        const state = {snapshot: {host: {usageBarsShowUsed: \(showUsed)}}};
        function finiteNumber(value) { return Number.isFinite(value) ? value : 0; }
        function percent(value) { return `${Math.round(value)}%`; }
        function resetTime() { return null; }
        function node(tag, className, text) {
          return {
            className, text, children: [], style: {}, attributes: {},
            append(...items) { this.children.push(...items); },
            setAttribute(key, value) { this.attributes[key] = value; }
          };
        }
        """)
        context.evaluateScript(String(self.html[start.lowerBound..<end.lowerBound]))
        context.evaluateScript("const rendered = renderWindow({label: 'Session', usedPercent: 25, remainingPercent: 75});")
        #expect(context.exception == nil)
        let expected = showUsed ? 25 : 75
        #expect(context.evaluateScript("rendered.children[0].children[0].text")?.toString() ==
            "Session · \(expected)% \(showUsed ? "used" : "left")")
        #expect(context.evaluateScript("rendered.children[1].children[0].style.width")?.toString() ==
            "\(expected)%")
        #expect(context.evaluateScript("rendered.children[1].attributes['aria-valuenow']")?.toString() ==
            String(expected))
    }

    @Test
    func `web ui renders account cards in titled groups for multi account providers`() {
        let html = self.html
        // Multi-account providers render one card per account inside a titled
        // vertical group; identity falls back to the slot label when redacted.
        #expect(html.contains("function renderAccountCard(provider, account)"))
        #expect(html.contains("account.identity?.accountEmail || account.label"))
        #expect(html.contains("provider.accountsError"))
        #expect(html.contains("group-title"))
    }

    @Test
    func `web ui embeds provider icon urls and serves embedded svgs`() {
        let html = self.html
        // The placeholder must be substituted at render time with a JSON map.
        #expect(!html.contains("__PROVIDER_ICON_URLS__"))
        #expect(html.contains("/icons/ProviderIcon-claude.svg"))
        #expect(CLIServeWebUI.iconResponse(name: "ProviderIcon-claude") != nil)
        #expect(CLIServeWebUI.iconResponse(name: "ProviderIcon-nonexistent") == nil)
        #expect(CLIServeWebUI.iconResponse(name: "../etc/passwd") == nil)
    }

    @Test
    func `web ui renders account windows alongside an error note`() {
        let html = self.html
        let errorAppend = "card.append(node(\"p\", \"error-message\", account.error));"
        #expect(html.contains(errorAppend))
        #expect(!html.contains(errorAppend + "\n            return card;"))
        #expect(html.contains(
            "for (const window of visibleWindows(account.windows)) windows.append(renderWindow(window))"))
    }

    @Test
    func `web ui skips windows the snapshot marks idle`() {
        let html = self.html
        // The producer decides which lanes are idle, so the page must not repeat any
        // provider-specific rule. It filters on the generic flag and nothing else.
        #expect(html.contains("function visibleWindows(windows)"))
        #expect(html.contains("w.idle !== true"))
        #expect(html.contains("for (const window of visibleWindows(provider.windows))"))
        #expect(html.contains("for (const window of visibleWindows(account.windows))"))
        #expect(html.contains("worstWindowLevel(visibleWindows(account.windows))"))
    }

    @Test
    func `web ui keeps ambient windows when no accounts are present`() {
        let html = self.html
        #expect(html.contains("Array.isArray(provider.accounts)"))
        #expect(html.contains("renderWindow(window)"))
    }

    @Test
    func `web ui keeps healthy ambient summary when active swap account has no usage`() {
        let html = self.html
        #expect(html.contains("const activeAccount = accounts.find(account => account.active === true)"))
        #expect(html.contains("visibleWindows(activeAccount.windows).length > 0"))
        #expect(html.contains("provider.cost || provider.credits || provider.status"))
        #expect(html.contains("if (!activeHasUsableWindows && hasAmbientSummary) rest.push(provider)"))
    }

    @Test
    func `web ui renders daily spend charts from cost history`() {
        let html = self.html
        // Chart data rides /cost daily buckets keyed by provider; rendering is
        // skipped for zero-spend or single-day histories, and a /cost failure
        // must never block the snapshot render.
        #expect(html.contains("function renderCostChart(history)"))
        #expect(html.contains("refreshCostHistory(headers)"))
        #expect(html.contains("state.costHistories[provider.id]"))
        #expect(html.contains("fetch(\"/cost\""))
    }

    @Test
    func `web ui progressively paints cached shell and provider snapshots`() {
        let html = self.html
        #expect(html.contains("quotakit.lastSnapshot"))
        #expect(html.contains("/dashboard/v1/snapshot?detail=shell"))
        #expect(html.contains("card pending"))
        #expect(html.contains("Promise.allSettled"))
        #expect(html.contains("encodeURIComponent(provider.id)"))
    }

    @Test
    func `serve identity flag decodes like the dashboard command`() {
        #expect(CodexBarCLI.decodeDashboardIdentityMode(
            from: ParsedValues(positional: [], options: [:], flags: [])) == .redacted)
        #expect(CodexBarCLI.decodeDashboardIdentityMode(
            from: ParsedValues(positional: [], options: ["identity": ["redacted"]], flags: [])) == .redacted)
        #expect(CodexBarCLI.decodeDashboardIdentityMode(
            from: ParsedValues(positional: [], options: ["identity": ["full"]], flags: [])) == .full)
        #expect(CodexBarCLI.decodeDashboardIdentityMode(
            from: ParsedValues(positional: [], options: ["identity": ["nope"]], flags: [])) == nil)
    }
}
