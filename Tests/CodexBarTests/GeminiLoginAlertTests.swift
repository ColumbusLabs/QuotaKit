import Testing
@testable import CodexBar

@Suite
struct GeminiLoginAlertTests {
    @Test
    func returnsAlertForMissingBinary() {
        let result = GeminiLoginRunner.Result(outcome: .missingBinary)
        let info = StatusItemController.geminiLoginAlertInfo(for: result)
        #expect(info?.title == "Gemini CLI not found")
        #expect(info?.message == "Install the Gemini CLI (npm i -g @google/gemini-cli) and try again.")
    }

    @Test
    func returnsAlertForLaunchFailure() {
        let result = GeminiLoginRunner.Result(outcome: .launchFailed("Boom"))
        let info = StatusItemController.geminiLoginAlertInfo(for: result)
        #expect(info?.title == "Could not open Terminal for Gemini")
        #expect(info?.message == "Boom")
    }

    @Test
    func returnsNilOnSuccess() {
        let result = GeminiLoginRunner.Result(outcome: .success)
        let info = StatusItemController.geminiLoginAlertInfo(for: result)
        #expect(info == nil)
    }
}
