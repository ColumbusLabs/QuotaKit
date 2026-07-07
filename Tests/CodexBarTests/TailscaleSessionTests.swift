import CodexBarCore
import Foundation
import Testing

struct TailscaleSessionTests {
    @Test
    func `online mac and linux peers become hosts`() throws {
        let url = try AgentSessionParserTests.fixtureURL("agent-sessions-tailscale", extension: "json")
        let hosts = try TailscaleStatusParser.hosts(
            from: Data(contentsOf: url),
            excludingLocalHost: "local-mac")

        #expect(hosts == ["clawmac", "linuxbox"])
    }

    @Test
    func `ssh destinations reject options whitespace and controls`() {
        let hosts = RemoteSessionFetcher.sanitizedHosts([
            "user@clawmac",
            "USER@CLAWMAC",
            "-oProxyCommand=touch /tmp/unsafe",
            "host with-space",
            "host\nother",
            "linuxbox",
        ])

        #expect(hosts == ["user@clawmac", "linuxbox"])
    }

    @Test
    func `remote session commands use QuotaKit cli and bundled helper fallback`() {
        let fetch = RemoteSessionFetcher.fetchCommand()
        #expect(fetch.contains("quotakit sessions --json"))
        #expect(fetch.contains("/Applications/QuotaKit.app/Contents/Helpers/QuotaKitCLI"))
        #expect(!fetch.contains("codexbar"))
        #expect(!fetch.contains("CodexBar.app"))

        let focus = RemoteSessionFetcher.focusCommand(sessionID: "abc'123")
        #expect(focus.contains("quotakit sessions focus 'abc'\\''123'"))
        #expect(focus.contains("/Applications/QuotaKit.app/Contents/Helpers/QuotaKitCLI"))
        #expect(!focus.contains("codexbar"))
        #expect(!focus.contains("CodexBar.app"))
    }
}
