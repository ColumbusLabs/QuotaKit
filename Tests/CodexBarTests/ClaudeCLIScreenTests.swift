import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeCLIScreenTests {
    @Test(arguments: [
        ("abc\rZ", "Zbc"),
        ("one\r\ntwo\nthree", "one\ntwo\nthree"),
        ("abc\u{8}Z", "abZ"),
        ("abc\r\u{1b}[2CZ", "abZ"),
        ("abc\u{1b}[2DZ", "aZc"),
        ("one\r\ntwo\u{1b}[1A\u{1b}[1GX", "Xne\ntwo"),
        ("abc\r\u{1b}[2G\u{1b}[K", "a"),
        ("abc\nxyz\u{1b}[1;2H\u{1b}[J", "a"),
        ("a\u{1b}]0;hidden\u{7}b\u{1b}]8;;hidden\u{1b}\\c", "abc"),
        ("中文x\u{1b}[4G\u{1b}[K", "中"),
        ("e\u{1b}[0m\u{301}x", "éx"),
    ])
    func `cursor redraw preserves only the final visible cells`(stream: String, expected: String) {
        #expect(ClaudeCLIScreen.render(stream) == expected)
    }

    @Test
    func `differential usage fixture preserves scoped quota and reset spacing`() throws {
        let text = try Self.fixture("usage-differential-redraw")
        #expect(TextParsing.stripANSICodes(text).contains("51%usd"))

        let snapshot = try ClaudeStatusProbe.parse(text: text)
        #expect(snapshot.sessionPercentLeft == 97)
        #expect(snapshot.weeklyPercentLeft == 73)
        #expect(snapshot.secondaryResetDescription == "Resets Sep 23 at 3pm (Europe/Stockholm)")
        let fable = try #require(snapshot.extraRateWindows.first { $0.id == "claude-weekly-scoped-fable" })
        #expect(fable.title == "Fable only")
        #expect(fable.window.usedPercent == 51)
    }

    @Test
    func `differential status fixture keeps the final identity frame`() throws {
        let text = try Self.fixture("status-differential-redraw")
        let identity = ClaudeStatusProbe.parseIdentity(usageText: nil, statusText: text)
        #expect(identity.accountEmail == "fixture@example.com")
        #expect(identity.accountOrganization == "Example Org")
        #expect(identity.loginMethod == "Max")

        let snapshot = try ClaudeStatusProbe.parse(
            text: "Current session\n3% used",
            statusText: text)
        #expect(snapshot.accountEmail == identity.accountEmail)
        #expect(snapshot.accountOrganization == identity.accountOrganization)
        #expect(snapshot.loginMethod == identity.loginMethod)
    }

    @Test
    func `styled plain reports keep CR delimiters and ignore OSC contents`() throws {
        let title = "\u{1b}]0;\u{1b}[HCurrent session 99% used\u{7}"
        let text = title + "\u{1b}[35mCurrent session\u{1b}[0m\r3% used\r"
        let snapshot = try ClaudeStatusProbe.parse(text: text)
        #expect(snapshot.sessionPercentLeft == 97)
    }

    @Test
    func `plain reports are not clipped or wrapped to PTY geometry`() throws {
        let padding = String(repeating: "report detail\n", count: 55)
        let organization = String(repeating: "Example", count: 30)
        let text = "\u{1b}[32mCurrent session\n3% used\n" + padding
            + "Org: \(organization)\nEmail: fixture@example.com\u{1b}[0m"
        let snapshot = try ClaudeStatusProbe.parse(text: text)
        #expect(snapshot.sessionPercentLeft == 97)
        #expect(snapshot.accountOrganization == organization)
        #expect(snapshot.accountEmail == "fixture@example.com")
    }

    @Test
    func `clearing screen cannot restore an earlier quota`() {
        let frame = "\u{1b}[HCurrent session\n3% used\u{1b}[2J"
        #expect(throws: ClaudeStatusProbeError.self) { try ClaudeStatusProbe.parse(text: frame) }
    }

    @Test
    func `screen dimensions match the bounded PTY geometry`() {
        let huge = String(repeating: "9", count: 100)
        let frame = "\u{1b}[\(huge);\(huge)HQ\u{1b}[\(huge)AZ\u{1b}[\(huge)DX"
        let lines = ClaudeCLIScreen.render(frame).components(separatedBy: "\n")
        #expect(lines.count == ClaudeCLIScreen.rows)
        #expect(lines.allSatisfy { $0.count <= ClaudeCLIScreen.columns })
        #expect(lines[0] == "X" + String(repeating: " ", count: ClaudeCLIScreen.columns - 2) + "Z")
        #expect(lines.last == String(repeating: " ", count: ClaudeCLIScreen.columns - 1) + "Q")
    }

    private static func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "ansi",
            subdirectory: "Fixtures/Providers/Claude"))
        let encoded = try String(contentsOf: url, encoding: .utf8)
        return encoded
            .replacingOccurrences(of: "\\e", with: "\u{1b}")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\r")
    }
}
