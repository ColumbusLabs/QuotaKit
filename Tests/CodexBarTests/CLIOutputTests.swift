import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct CLIOutputTests {
    @Test
    func `output preferences json only forces JSON`() {
        let output = CLIOutputPreferences.from(argv: ["--json-only"])
        #expect(output.jsonOnly == true)
        #expect(output.format == .json)
    }

    @Test
    func `cli error payload is JSON array`() throws {
        let payload = CodexBarCLI.makeCLIErrorPayload(
            message: "Nope",
            code: .failure,
            kind: .args,
            pretty: false)
        #expect(payload != nil)
        let data = payload?.data(using: .utf8) ?? Data()
        let json = try JSONSerialization.jsonObject(with: data) as? [Any]
        #expect(json?.isEmpty == false)
        let first = json?.first as? [String: Any]
        #expect(first?["provider"] as? String == "cli")
        let error = first?["error"] as? [String: Any]
        #expect(error?["message"] as? String == "Nope")
    }

    @Test
    func `exit omits generic error when command already emitted payload`() {
        #expect(!CodexBarCLI.shouldPrintExitError(code: .success, message: nil))
        #expect(!CodexBarCLI.shouldPrintExitError(code: .failure, message: nil))
        #expect(CodexBarCLI.shouldPrintExitError(code: .failure, message: "Nope"))
    }

    @Test
    func `text renderer includes deepgram usage metrics`() {
        let deepgram = DeepgramUsageSnapshot(
            projectID: "project-123",
            start: "2026-05-10",
            end: "2026-05-17",
            hours: 12.5,
            totalHours: 14,
            agentHours: 1.25,
            tokensIn: 100,
            tokensOut: 50,
            ttsCharacters: 1200,
            requests: 42,
            updatedAt: Date(timeIntervalSince1970: 0))
        let text = CLIRenderer.renderText(
            provider: .deepgram,
            snapshot: deepgram.toUsageSnapshot(),
            credits: nil,
            context: RenderContext(
                header: "Deepgram (api)",
                status: nil,
                useColor: false,
                resetStyle: .countdown))

        #expect(text.contains("Requests: 42"))
        #expect(text.contains("Usage: 12.5 audio hours · 14 billable hours"))
        #expect(text.contains("Usage: 1.2 agent hours · 150 tokens · 1,200 TTS chars"))
        #expect(text.contains("Period: 2026-05-10 to 2026-05-17"))
    }
}
