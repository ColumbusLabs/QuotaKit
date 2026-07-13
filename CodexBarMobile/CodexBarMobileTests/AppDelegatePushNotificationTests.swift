import Testing
import UIKit
@testable import CodexBarMobile

@Suite("App Delegate Push Notification Tests")
@MainActor
struct AppDelegatePushNotificationTests {
    @Test
    func `Active application posts incremental refresh`() {
        let appDelegate = AppDelegate()
        var postCount = 0

        let posted = appDelegate.postProviderZoneChangeOrDefer(
            applicationState: .active,
            post: { postCount += 1 })

        #expect(posted)
        #expect(postCount == 1)
    }

    @Test
    func `Inactive application defers incremental refresh until active`() {
        let appDelegate = AppDelegate()
        var postCount = 0

        let posted = appDelegate.postProviderZoneChangeOrDefer(
            applicationState: .inactive,
            post: { postCount += 1 })

        #expect(!posted)
        #expect(postCount == 0)

        let consumedWhileInactive = appDelegate.consumePendingProviderZoneChangeIfActive(
            applicationState: .inactive)
        let consumedWhenActive = appDelegate.consumePendingProviderZoneChangeIfActive(
            applicationState: .active)

        #expect(!consumedWhileInactive)
        #expect(consumedWhenActive)
        #expect(postCount == 0)
        #expect(!appDelegate.consumePendingProviderZoneChangeIfActive(applicationState: .active))
    }

    @Test
    func `Background application coalesces deferred refreshes`() {
        let appDelegate = AppDelegate()
        var postCount = 0

        let firstPosted = appDelegate.postProviderZoneChangeOrDefer(
            applicationState: .background,
            post: { postCount += 1 })
        let secondPosted = appDelegate.postProviderZoneChangeOrDefer(
            applicationState: .background,
            post: { postCount += 1 })

        #expect(!firstPosted)
        #expect(!secondPosted)
        #expect(postCount == 0)

        let activePosted = appDelegate.postProviderZoneChangeOrDefer(
            applicationState: .active,
            post: { postCount += 1 })
        let consumedPending = appDelegate.consumePendingProviderZoneChangeIfActive(
            applicationState: .active)
        let consumedAgain = appDelegate.consumePendingProviderZoneChangeIfActive(
            applicationState: .active)

        #expect(activePosted)
        #expect(postCount == 1)
        #expect(consumedPending)
        #expect(!consumedAgain)
    }
}
