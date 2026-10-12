import CodexBarSync
import Foundation
import LiteCore
import Testing

/// A CloudKit stand-in that records what it was asked to do.
private final class FakePusher: SyncPushing, @unchecked Sendable {
    var pushes: [[ProviderUsageEnvelope]] = []
    var deletes: [[String]] = []
    var fails = false

    func pushSnapshot(_: SyncedUsageSnapshot) async -> SyncPushResult {
        Issue.record("Lite must not write the legacy DeviceSnapshot record")
        return .success
    }

    func pushPerProviderRecords(_ envelopes: [ProviderUsageEnvelope]) async -> SyncPushResult {
        self.pushes.append(envelopes)
        return self.fails ? .failure("offline") : .success
    }

    func deletePerProviderRecords(recordNames: [String]) async -> SyncPushResult {
        self.deletes.append(recordNames)
        return self.fails ? .failure("offline") : .success
    }
}

@MainActor
struct SyncBridgeTests {
    private typealias Fixture = SyncSnapshotTests

    private final class Harness {
        let pusher = FakePusher()
        var states = [Fixture.state(), Fixture.state(.codex)]
        var enabled: Set<LiteProvider> = [.claude, .codex]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncBridgeTests-\(UUID().uuidString)")
            .appendingPathComponent("sync.json")

        @MainActor
        func bridge() -> SyncBridge {
            SyncBridge(
                pusher: { self.pusher },
                device: { SyncBridge.Device(id: Fixture.deviceID, name: "Mac", appVersion: "Lite 0.1.0") },
                inputs: { SyncBridge.Inputs(states: self.states, enabled: self.enabled) },
                store: SyncLedgerStore(fileURL: self.url),
                now: { Fixture.now })
        }

        deinit {
            try? FileManager.default.removeItem(at: self.url.deletingLastPathComponent())
        }
    }

    @Test
    func `the first sync writes one envelope per provider with Lite's device metadata`() async throws {
        let harness = Harness()
        let bridge = harness.bridge()

        bridge.requestSync()
        await bridge.waitUntilIdle()

        let envelopes = try #require(harness.pusher.pushes.first)
        #expect(harness.pusher.pushes.count == 1)
        #expect(envelopes.map(\.provider.providerID) == ["claude", "codex"])
        #expect(envelopes.allSatisfy { $0.deviceID == Fixture.deviceID && $0.appVersion == "Lite 0.1.0" })
        #expect(envelopes.allSatisfy { $0.mobileVersion == nil })
        #expect(bridge.hasPublishedRecords)
    }

    @Test
    func `a second sync with nothing changed does not touch CloudKit`() async {
        let harness = Harness()
        let bridge = harness.bridge()
        bridge.requestSync()
        await bridge.waitUntilIdle()

        bridge.requestSync()
        await bridge.waitUntilIdle()

        #expect(harness.pusher.pushes.count == 1)
        #expect(harness.pusher.deletes.isEmpty)
    }

    @Test
    func `a restart does not re-upload unchanged records`() async {
        let harness = Harness()
        let first = harness.bridge()
        first.requestSync()
        await first.waitUntilIdle()

        let restarted = harness.bridge()
        restarted.requestSync()
        await restarted.waitUntilIdle()

        #expect(harness.pusher.pushes.count == 1)
    }

    @Test
    func `a failed write is retried by the next sync`() async {
        let harness = Harness()
        let bridge = harness.bridge()
        harness.pusher.fails = true
        bridge.requestSync()
        await bridge.waitUntilIdle()
        #expect(bridge.lastError == "offline")
        #expect(!bridge.hasPublishedRecords)

        harness.pusher.fails = false
        bridge.requestSync()
        await bridge.waitUntilIdle()

        #expect(harness.pusher.pushes.count == 2)
        #expect(bridge.lastError == nil)
        #expect(bridge.hasPublishedRecords)
    }

    @Test
    func `disabling a provider deletes its record`() async {
        let harness = Harness()
        let bridge = harness.bridge()
        bridge.requestSync()
        await bridge.waitUntilIdle()

        harness.enabled = [.claude]
        bridge.requestSync()
        await bridge.waitUntilIdle()

        #expect(harness.pusher.deletes == [["LITE-DEVICE|codex|me@example.com"]])
    }

    @Test
    func `unpublish deletes every record Lite wrote`() async {
        let harness = Harness()
        let bridge = harness.bridge()
        bridge.requestSync()
        bridge.unpublishAll()
        await bridge.waitUntilIdle()

        #expect(harness.pusher.deletes == [[
            "LITE-DEVICE|claude|me@example.com",
            "LITE-DEVICE|codex|me@example.com",
        ]])
        #expect(!bridge.hasPublishedRecords)
    }
}
