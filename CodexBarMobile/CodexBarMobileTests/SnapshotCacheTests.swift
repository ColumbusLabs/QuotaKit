import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// v2 incremental sync — tests the in-memory cache + priority merge rules,
/// with explicit multi-device scenarios matching Research/011's trace section.
@MainActor
@Suite("Snapshot cache priority + multi-device")
struct SnapshotCacheTests {
    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_700_100_000)
    private let t3 = Date(timeIntervalSince1970: 1_700_200_000)

    private func provider(
        id: String,
        name: String? = nil,
        email: String? = nil,
        lastUpdated: Date
    ) -> ProviderUsageSnapshot {
        // Include a non-empty primary rate window so the provider does NOT
        // trip the ghost filter — test fixtures represent real providers.
        ProviderUsageSnapshot(
            providerID: id,
            providerName: name ?? id.capitalized,
            primary: SyncRateWindow(
                usedPercent: 42.0,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: email,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated)
    }

    private func snapshot(
        deviceID: String?,
        deviceName: String,
        providers: [ProviderUsageSnapshot],
        timestamp: Date
    ) -> SyncedUsageSnapshot {
        SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: timestamp,
            deviceName: deviceName,
            deviceID: deviceID,
            appVersion: "0.20.1",
            mobileVersion: "1.3.0")
    }

    private func envelope(
        deviceID: String,
        deviceName: String,
        providerID: String,
        email: String? = nil,
        providerLastUpdated: Date,
        syncTimestamp: Date
    ) -> ProviderUsageEnvelope {
        ProviderUsageEnvelope(
            deviceID: deviceID,
            deviceName: deviceName,
            appVersion: "0.20.1",
            mobileVersion: "1.3.0",
            syncTimestamp: syncTimestamp,
            notificationPushEnabled: true,
            provider: provider(
                id: providerID,
                email: email,
                lastUpdated: providerLastUpdated))
    }

    // MARK: - Basic cache operations

    @Test("Empty cache returns no snapshots")
    func emptyCacheEmpty() {
        let cache = SnapshotCache()
        #expect(cache.buildDeviceSnapshots().isEmpty)
    }

    @Test("Delta upsert populates perProviderByDevice, leaves legacy alone")
    func applyDeltaIsolated() {
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [envelope(
                deviceID: "mac-A", deviceName: "Mac A",
                providerID: "codex", providerLastUpdated: t1, syncTimestamp: t1)],
            deletedRecordNames: [])

        #expect(cache.perProviderByDevice["mac-A"]?.count == 1)
        #expect(cache.legacyByDevice.isEmpty) // untouched
        #expect(cache.deviceMetadata["mac-A"]?.deviceName == "Mac A")
    }

    @Test("Delta delete removes exactly the matched composite")
    func applyDeltaDelete() {
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "codex", providerLastUpdated: t1, syncTimestamp: t1),
                envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "claude", providerLastUpdated: t1, syncTimestamp: t1),
            ],
            deletedRecordNames: [])
        #expect(cache.perProviderByDevice["mac-A"]?.count == 2)

        // Delete just codex.
        cache.applyDelta(
            upserted: [],
            deletedRecordNames: ["mac-A|codex|_"])
        #expect(cache.perProviderByDevice["mac-A"]?.count == 1)
        #expect(cache.perProviderByDevice["mac-A"]?.keys.contains("claude|_") == true)
    }

    @Test("Delete last provider of a device removes the device entry")
    func applyDeltaDeleteLastRemovesDevice() {
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [envelope(
                deviceID: "mac-A", deviceName: "Mac A",
                providerID: "codex", providerLastUpdated: t1, syncTimestamp: t1)],
            deletedRecordNames: [])
        cache.applyDelta(
            upserted: [],
            deletedRecordNames: ["mac-A|codex|_"])

        #expect(cache.perProviderByDevice["mac-A"] == nil)
        // metadata stays — legacy could still have a snapshot
        #expect(cache.deviceMetadata["mac-A"] != nil)
    }

    // MARK: - Priority merge

    @Test("Device in per-provider bucket wins over legacy bucket")
    func priorityPerProviderWins() {
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [provider(id: "codex", lastUpdated: t3)],
                timestamp: t3)],
            legacySnapshots: [snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [provider(id: "claude", lastUpdated: t1)],
                timestamp: t1)])

        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].providers.first?.providerID == "codex")
    }

    @Test("Device only in legacy bucket falls through")
    func priorityLegacyFallThrough() {
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [],
            legacySnapshots: [snapshot(
                deviceID: "mac-B", deviceName: "Mac B",
                providers: [provider(id: "claude", lastUpdated: t1)],
                timestamp: t1)])

        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].deviceID == "mac-B")
    }

    // MARK: - Multi-device scenarios (from Research/011)

    @Test("Scenario 1: Mac A on new zone + Mac B legacy-only — both surface")
    func scenario1_asymmetric() {
        var cache = SnapshotCache()
        // Full fetch result: Mac A has per-provider envelopes, both Macs
        // are in legacy (because P4 is dual-write; Mac A still writes legacy
        // too).
        cache.replaceFromFullFetch(
            perProviderSnapshots: [snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [provider(id: "codex", lastUpdated: t3)],
                timestamp: t3)],
            legacySnapshots: [
                snapshot(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providers: [provider(id: "codex", lastUpdated: t2)], // older than per-provider
                    timestamp: t2),
                snapshot(
                    deviceID: "mac-B", deviceName: "Mac B",
                    providers: [provider(id: "claude", lastUpdated: t2)],
                    timestamp: t2),
            ])

        var result = cache.buildDeviceSnapshots()
        #expect(result.count == 2)
        let macA = try? #require(result.first(where: { $0.deviceID == "mac-A" }))
        let macB = try? #require(result.first(where: { $0.deviceID == "mac-B" }))
        #expect(macA?.syncTimestamp == t3) // per-provider won
        #expect(macB?.syncTimestamp == t2) // legacy path

        // Now a silent push from Mac A with a newer codex provider.
        cache.applyDelta(
            upserted: [envelope(
                deviceID: "mac-A", deviceName: "Mac A",
                providerID: "codex",
                providerLastUpdated: t3.addingTimeInterval(100),
                syncTimestamp: t3.addingTimeInterval(100))],
            deletedRecordNames: [])

        result = cache.buildDeviceSnapshots()
        #expect(result.count == 2) // Mac B still there, not touched
        let macBAfter = try? #require(result.first(where: { $0.deviceID == "mac-B" }))
        #expect(macBAfter?.syncTimestamp == t2) // UNCHANGED — incremental never touched legacy
        let macAAfter = try? #require(result.first(where: { $0.deviceID == "mac-A" }))
        #expect(macAAfter?.syncTimestamp == t3.addingTimeInterval(100))
    }

    @Test("Scenario 2: Both Macs on new zone — both refresh independently")
    func scenario2_bothNew() {
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [
                snapshot(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providers: [provider(id: "codex", lastUpdated: t1)],
                    timestamp: t1),
                snapshot(
                    deviceID: "mac-B", deviceName: "Mac B",
                    providers: [provider(id: "claude", lastUpdated: t1)],
                    timestamp: t1),
            ],
            legacySnapshots: [])

        // Silent push from Mac A.
        cache.applyDelta(
            upserted: [envelope(
                deviceID: "mac-A", deviceName: "Mac A",
                providerID: "codex",
                providerLastUpdated: t2, syncTimestamp: t2)],
            deletedRecordNames: [])

        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 2)
        let macA = try? #require(result.first(where: { $0.deviceID == "mac-A" }))
        let macB = try? #require(result.first(where: { $0.deviceID == "mac-B" }))
        #expect(macA?.syncTimestamp == t2)
        #expect(macB?.syncTimestamp == t1) // Mac B stays until its own push
    }

    @Test("Scenario 3: Both Macs legacy-only — per-provider bucket stays empty")
    func scenario3_bothLegacy() {
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [],
            legacySnapshots: [
                snapshot(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providers: [provider(id: "codex", lastUpdated: t1)],
                    timestamp: t1),
                snapshot(
                    deviceID: "mac-B", deviceName: "Mac B",
                    providers: [provider(id: "claude", lastUpdated: t1)],
                    timestamp: t1),
            ])

        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 2)
        #expect(cache.perProviderByDevice.isEmpty)
    }

    @Test("Token-expired replay REPLACES per-provider bucket (doesn't mix)")
    func tokenExpiredReplay() {
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [envelope(
                deviceID: "mac-A", deviceName: "Mac A",
                providerID: "codex", providerLastUpdated: t1, syncTimestamp: t1)],
            deletedRecordNames: [])

        // Token expires; server replays everything. Say Mac A's codex is
        // gone (user disabled it) and only Mac B exists now.
        cache.replacePerProviderFromReplay([
            envelope(
                deviceID: "mac-B", deviceName: "Mac B",
                providerID: "claude", providerLastUpdated: t2, syncTimestamp: t2),
        ])

        #expect(cache.perProviderByDevice["mac-A"] == nil) // gone
        #expect(cache.perProviderByDevice["mac-B"]?.count == 1)
    }

    // MARK: - recordName parser round-trip

    @Test("splitRecordName matches CloudSyncManager.perProviderRecordName")
    func recordNameRoundTrip() {
        let generated = CloudSyncManager.perProviderRecordName(
            deviceID: "mac-A", providerID: "codex", accountEmail: nil)
        let parsed = SnapshotCache.splitRecordName(generated)
        #expect(parsed?.deviceID == "mac-A")
        #expect(parsed?.composite == "codex|_")

        let withEmail = CloudSyncManager.perProviderRecordName(
            deviceID: "mac-A", providerID: "codex", accountEmail: "user@example.com")
        let parsed2 = SnapshotCache.splitRecordName(withEmail)
        #expect(parsed2?.deviceID == "mac-A")
        #expect(parsed2?.composite == "codex|user@example.com")
    }

    @Test("splitRecordName rejects malformed input")
    func splitRecordNameMalformed() {
        #expect(SnapshotCache.splitRecordName("too|few") == nil)
        #expect(SnapshotCache.splitRecordName("way|too|many|pieces|here") == nil)
    }

    // MARK: - Ghost filter (Build 66 · bug #2 fix)

    @Test("Ghost envelope (all fields empty) is dropped from per-provider bucket")
    func ghostEnvelopeDroppedFromFullFetch() {
        var cache = SnapshotCache()
        // Mac A wrote two codex records in CloudKit with different accountEmail:
        // one early (ghost: nil email + no data) and one later (real data).
        let ghost = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: t1,
            rateWindows: [])
        let real = provider(id: "codex", email: "user@example.com", lastUpdated: t3)
        let fake = SyncedUsageSnapshot(
            providers: [ghost, real],
            syncTimestamp: t3,
            deviceName: "Mac A",
            deviceID: "mac-A")

        cache.replaceFromFullFetch(perProviderSnapshots: [fake], legacySnapshots: [])

        #expect(cache.perProviderByDevice["mac-A"]?.count == 1)
        #expect(cache.perProviderByDevice["mac-A"]?.keys.contains("codex|user@example.com") == true)
        #expect(cache.perProviderByDevice["mac-A"]?.keys.contains("codex|_") == false)
    }

    @Test("Ghost envelope is dropped from delta apply")
    func ghostEnvelopeDroppedFromDelta() {
        var cache = SnapshotCache()
        let ghostEnv = ProviderUsageEnvelope(
            deviceID: "mac-A", deviceName: "Mac A",
            appVersion: nil, mobileVersion: nil,
            syncTimestamp: t1, notificationPushEnabled: nil,
            provider: ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil, secondary: nil,
                accountEmail: nil,
                loginMethod: nil, statusMessage: nil,
                isError: false,
                lastUpdated: t1,
                rateWindows: []))
        cache.applyDelta(upserted: [ghostEnv], deletedRecordNames: [])
        #expect(cache.perProviderByDevice["mac-A"] == nil)
    }

    // MARK: - Codex review P1 — preserve on transient fetch error

    @Test("Nil perProviderSnapshots preserves existing per-provider bucket")
    func nilPerProviderArgPreserves() {
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [provider(id: "codex", lastUpdated: t3)],
                timestamp: t3)],
            legacySnapshots: [])
        let before = cache.perProviderByDevice["mac-A"]?.count
        #expect(before == 1)

        // Transient legacy error: pass nil for legacy. Per-provider bucket
        // is refreshed with empty, legacy bucket preserved.
        cache.replaceFromFullFetch(
            perProviderSnapshots: nil,  // transient error on per-provider zone
            legacySnapshots: [])        // legacy authoritatively empty

        // Per-provider bucket preserved as-is.
        #expect(cache.perProviderByDevice["mac-A"]?.count == 1)
        // Legacy bucket cleared (authoritative empty from pass).
        #expect(cache.legacyByDevice.isEmpty)
    }

    @Test("Nil legacySnapshots preserves existing legacy bucket")
    func nilLegacyArgPreserves() {
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [],
            legacySnapshots: [snapshot(
                deviceID: "mac-B", deviceName: "Mac B",
                providers: [provider(id: "claude", lastUpdated: t1)],
                timestamp: t1)])
        #expect(cache.legacyByDevice["mac-B"] != nil)

        cache.replaceFromFullFetch(
            perProviderSnapshots: [],
            legacySnapshots: nil) // transient legacy error

        // Legacy preserved.
        #expect(cache.legacyByDevice["mac-B"] != nil)
    }

    // MARK: - Ghost filter

    @Test("Provider with just an error message is NOT a ghost (keep)")
    func errorProviderNotGhost() {
        var cache = SnapshotCache()
        let erroring = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil, secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: "Auth failed",
            isError: true,
            lastUpdated: t1,
            rateWindows: [])
        let snap = SyncedUsageSnapshot(
            providers: [erroring], syncTimestamp: t1,
            deviceName: "Mac A", deviceID: "mac-A")
        cache.replaceFromFullFetch(perProviderSnapshots: [snap], legacySnapshots: [])
        #expect(cache.perProviderByDevice["mac-A"]?.count == 1)
    }
}
