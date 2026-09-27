import Testing
@testable import CodexBar

@MainActor
struct AboutUpdateCommandTests {
    @Test
    func `Homebrew command targets the QuotaKit cask`() {
        let updater = DisabledUpdaterController.homebrew()
        #expect(updater.manualUpdateCommand?.command == "brew upgrade --cask steipete/tap/quotakit")
        #expect(updater.unavailableReason != nil)
    }

    @Test
    func `generic unavailable updater does not offer a Homebrew command`() {
        let updater = DisabledUpdaterController(unavailableReason: "Updates unavailable")
        #expect(updater.manualUpdateCommand == nil)
    }
}
