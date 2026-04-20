import Foundation
import Testing
@testable import CodexBarMobile

/// P7 — tests for the silent-push routing predicate. The actual subscription
/// save / fetch and the AppDelegate handler require a real CloudKit round
/// trip and are covered by real-device smoke testing.
@Suite("Silent-push routing")
struct DeviceProviderZoneSubscriptionTests {

    @Test("userInfo with our subscription ID is recognised")
    func matchesOurSubscription() {
        let userInfo: [AnyHashable: Any] = [
            "ck": [
                "sid": DeviceProviderZoneSubscription.subscriptionID,
            ],
        ]
        #expect(DeviceProviderZoneSubscription.isPushForThisSubscription(
            userInfo: userInfo))
    }

    @Test("userInfo with our subscription ID nested under a sub-dict is recognised")
    func matchesNested() {
        let userInfo: [AnyHashable: Any] = [
            "ck": [
                "fet": [
                    "sid": DeviceProviderZoneSubscription.subscriptionID,
                    "zid": "DeviceProvidersZone",
                ],
            ],
        ]
        #expect(DeviceProviderZoneSubscription.isPushForThisSubscription(
            userInfo: userInfo))
    }

    @Test("userInfo from a quota transition subscription is rejected")
    func rejectsQuotaPush() {
        let userInfo: [AnyHashable: Any] = [
            "ck": [
                "sid": "quota-codex-depleted-sub",
            ],
        ]
        #expect(!DeviceProviderZoneSubscription.isPushForThisSubscription(
            userInfo: userInfo))
    }

    @Test("Empty userInfo is rejected")
    func rejectsEmpty() {
        #expect(!DeviceProviderZoneSubscription.isPushForThisSubscription(
            userInfo: [:]))
    }

    @Test("userInfo without ck key is rejected")
    func rejectsNoCKKey() {
        let userInfo: [AnyHashable: Any] = ["aps": ["alert": "hi"]]
        #expect(!DeviceProviderZoneSubscription.isPushForThisSubscription(
            userInfo: userInfo))
    }
}
