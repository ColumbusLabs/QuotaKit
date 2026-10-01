import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageStorePathReconciliationTests {
    @Test
    func `identity reconciliation skips path normalization when root devices match`() {
        var normalizationCount = 0
        let identity = "device-42:987654"
        let roots = [CostUsageStore.CurrentCodexRootDevice(path: "/sessions", device: "device-42")]

        let normalized = CostUsageStore.normalizedCodexFileIdentity(
            path: "/sessions/day/rollout.jsonl",
            identity: identity,
            persistedInode: 987_654,
            currentRootDevices: roots)
        { path in
            normalizationCount += 1
            return path
        }

        #expect(normalized == identity)
        #expect(normalizationCount == 0)
    }

    @Test
    func `identity reconciliation normalizes only when a root device can change identity`() {
        var normalizationCount = 0
        let identity = "old-device:987654"
        let roots = [CostUsageStore.CurrentCodexRootDevice(path: "/private/var/sessions", device: "new-device")]

        let normalized = CostUsageStore.normalizedCodexFileIdentity(
            path: "/var/sessions/day/rollout.jsonl",
            identity: identity,
            persistedInode: 987_654,
            currentRootDevices: roots)
        { _ in
            normalizationCount += 1
            return "/private/var/sessions/day/rollout.jsonl"
        }

        #expect(normalized == "new-device:987654")
        #expect(normalizationCount == 1)
    }
}
