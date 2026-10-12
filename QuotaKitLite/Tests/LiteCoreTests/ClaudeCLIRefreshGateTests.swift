import Foundation
import LiteCore
import Testing

struct ClaudeCLIRefreshGateTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `only an expired token starts the CLI`() {
        let gate = ClaudeCLIRefreshGate()

        #expect(gate.allowsAttempt(for: .tokenExpired, at: Self.now))
        #expect(!gate.allowsAttempt(for: .signInRequired, at: Self.now))
        #expect(!gate.allowsAttempt(for: .tokenUnavailable, at: Self.now))
        #expect(!gate.allowsAttempt(for: .network("offline"), at: Self.now))
    }

    @Test
    func `one attempt per half hour whatever the outcome`() {
        var gate = ClaudeCLIRefreshGate()
        gate.recordAttempt(at: Self.now)

        #expect(!gate.allowsAttempt(for: .tokenExpired, at: Self.now.addingTimeInterval(29 * 60)))
        #expect(gate.allowsAttempt(for: .tokenExpired, at: Self.now.addingTimeInterval(30 * 60)))
    }

    @Test
    func `a clock moved backwards does not block forever`() {
        var gate = ClaudeCLIRefreshGate()
        gate.recordAttempt(at: Self.now)

        #expect(gate.allowsAttempt(for: .tokenExpired, at: Self.now.addingTimeInterval(-3600)))
    }
}

struct ClaudeCLITrustPromptTests {
    /// The prompt as Claude Code 2.1 draws it: spaces as cursor moves, the default "No, exit" highlighted first.
    private static let screen = "\u{1b}[2J\u{1b}[1mQuick\u{1b}[1Csafety\u{1b}[1Ccheck:\u{1b}[0m Is this a project"
        + " you trust?\r\n\u{1b}[36m❯\u{1b}[1CNo,\u{1b}[1Cexit\u{1b}[39m\r\n"
        + "  Yes,\u{1b}[1CI\u{1b}[1Ctrust\u{1b}[1Cthis\u{1b}[1Cfolder\r\n"
        + "Enter\u{1b}[1Cto\u{1b}[1Cconfirm · Esc to cancel"

    @Test
    func `the trust prompt is answered with Down then Enter`() {
        #expect(ClaudeCLITrustPrompt.keys(forScreen: Data(Self.screen.utf8)) == "\u{1b}[B\r")
    }

    @Test
    func `Enter alone when Yes is listed first`() {
        let screen = "Yes, I trust this folder\r\nNo, exit"

        #expect(ClaudeCLITrustPrompt.keys(forScreen: Data(screen.utf8)) == "\r")
    }

    @Test
    func `no prompt on screen sends nothing`() {
        #expect(ClaudeCLITrustPrompt.keys(forScreen: Data("Welcome back! /status".utf8)) == nil)
    }
}
