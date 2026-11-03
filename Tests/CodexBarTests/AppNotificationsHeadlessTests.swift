import Testing
@testable import CodexBar

@MainActor
struct AppNotificationsHeadlessTests {
    @Test
    func `headless posting completes as undelivered without consulting the notification center`() {
        let notifications = AppNotifications(centerProvider: {
            fatalError("Headless posting must not consult the system notification center")
        })
        var outcomes: [Bool] = []
        notifications.requestAuthorizationOnStartup()
        notifications.post(
            idPrefix: "synthetic-headless",
            title: "Synthetic",
            body: "Synthetic",
            onCompletion: { outcomes.append($0) })
        #expect(outcomes == [false])
    }
}
