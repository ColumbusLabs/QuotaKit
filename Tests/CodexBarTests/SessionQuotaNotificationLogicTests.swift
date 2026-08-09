import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
struct SessionQuotaNotificationLogicTests {
    @Test
    func `does nothing without previous value`() {
        let transition = SessionQuotaNotificationLogic.transition(previousRemaining: nil, currentRemaining: 0)
        #expect(transition == .none)
    }

    @Test
    func `detects depleted transition`() {
        let transition = SessionQuotaNotificationLogic.transition(previousRemaining: 12, currentRemaining: 0)
        #expect(transition == .depleted)
    }

    @Test
    func `detects restored transition`() {
        let transition = SessionQuotaNotificationLogic.transition(previousRemaining: 0, currentRemaining: 5)
        #expect(transition == .restored)
    }

    @Test
    func `ignores non transitions`() {
        #expect(SessionQuotaNotificationLogic.transition(previousRemaining: 0, currentRemaining: 0) == .none)
        #expect(SessionQuotaNotificationLogic.transition(previousRemaining: 10, currentRemaining: 10) == .none)
        #expect(SessionQuotaNotificationLogic.transition(previousRemaining: 10, currentRemaining: 9) == .none)
    }

    @Test
    func `treats tiny positive remaining as depleted`() {
        let transition = SessionQuotaNotificationLogic.transition(previousRemaining: 0, currentRemaining: 0.00001)
        #expect(transition == .none)
    }

    @Test
    func `depleted notification uses English copy`() {
        let copy = SessionQuotaNotificationLogic.notificationCopy(
            transition: .depleted,
            providerName: "Codex")

        #expect(copy.title == "Codex session depleted")
        #expect(copy.body == "0% left. Will notify when it's available again.")
    }

    @Test
    func `restored notification uses English copy`() {
        let copy = SessionQuotaNotificationLogic.notificationCopy(
            transition: .restored,
            providerName: "Codex")

        #expect(copy.title == "Codex session restored")
        #expect(copy.body == "Session quota is available again.")
    }
}
