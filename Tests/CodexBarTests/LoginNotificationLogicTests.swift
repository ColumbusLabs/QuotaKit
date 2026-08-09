import Testing
@testable import CodexBar

@Suite(.serialized)
struct LoginNotificationLogicTests {
    @Test
    func `login success notification uses English copy`() {
        let copy = LoginNotificationLogic.notificationCopy(providerName: "Codex")

        #expect(copy.title == "Codex login successful")
        #expect(copy.body == "You can return to the app; authentication finished.")
    }
}
