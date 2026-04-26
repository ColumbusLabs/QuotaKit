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

    // MARK: - Hardening Phase 3 · multi-account scenarios

    @Test("Same provider with two account emails on one device — both kept")
    func multiAccountSameProvider() {
        var cache = SnapshotCache()
        let codexAlice = provider(id: "codex", email: "alice@example.com", lastUpdated: t1)
        let codexBob   = provider(id: "codex", email: "bob@example.com",   lastUpdated: t2)
        let snap = SyncedUsageSnapshot(
            providers: [codexAlice, codexBob],
            syncTimestamp: t2,
            deviceName: "Mac A",
            deviceID: "mac-A",
            appVersion: "0.20.2",
            mobileVersion: "1.3.0")

        cache.replaceFromFullFetch(perProviderSnapshots: [snap], legacySnapshots: [])

        // Both Codex accounts kept as separate entries (different composite keys).
        #expect(cache.perProviderByDevice["mac-A"]?.count == 2)
        #expect(cache.perProviderByDevice["mac-A"]?.keys.contains("codex|alice@example.com") == true)
        #expect(cache.perProviderByDevice["mac-A"]?.keys.contains("codex|bob@example.com") == true)

        // Buildback also keeps both.
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].providers.count == 2)
    }

    @Test("Per-provider zone with both nil-email and emailed records for same providerID — both kept")
    func nilEmailAndEmailedCoexist() {
        var cache = SnapshotCache()
        // BOTH have data (both pass ghost filter). They're different composite
        // keys, so cache treats them as separate accounts of the same
        // provider. (Real-world this might be a stale legacy record from
        // before account-email-aware code; behavior under test is "no
        // collapse, no overwrite".)
        let codexNoEmail = provider(id: "codex", email: nil, lastUpdated: t1)
        let codexEmailed = provider(id: "codex", email: "user@example.com", lastUpdated: t2)
        let snap = SyncedUsageSnapshot(
            providers: [codexNoEmail, codexEmailed],
            syncTimestamp: t2,
            deviceName: "Mac A",
            deviceID: "mac-A",
            appVersion: "0.20.2",
            mobileVersion: "1.3.0")

        cache.replaceFromFullFetch(perProviderSnapshots: [snap], legacySnapshots: [])

        #expect(cache.perProviderByDevice["mac-A"]?.count == 2)
        #expect(cache.perProviderByDevice["mac-A"]?.keys.contains("codex|_") == true)
        #expect(cache.perProviderByDevice["mac-A"]?.keys.contains("codex|user@example.com") == true)
    }

    @Test("compositeKey for nil-email matches `_` everywhere (no `\"\"` drift)")
    func compositeKeyNilEmailFormat() {
        // Build 67 hardening: SwiftDataSchema.makeCompositeKey was using ""
        // while SnapshotCache + CloudSyncManager.perProviderRecordName used
        // "_" — silent format mismatch. This test pins the contract.
        let p = provider(id: "codex", email: nil, lastUpdated: t1)
        let cacheKey = SnapshotCache.compositeKey(for: p)
        let cloudKitName = CloudSyncManager.perProviderRecordName(
            deviceID: "ignored", providerID: "codex", accountEmail: nil)
        #expect(cacheKey == "codex|_")
        // CloudKit record name is `{deviceID}|{rest}`, so trailing portion
        // must match the cache's composite key format.
        #expect(cloudKitName.hasSuffix("|" + cacheKey))
    }

    @Test("Delta-applied envelope with an email replaces nil-email ghost only if cache had it (independent keys)")
    func deltaWithEmailDoesNotTouchNilEmailEntry() {
        var cache = SnapshotCache()
        // Seed cache with a real (non-ghost) nil-email codex entry first.
        let nilSnap = SyncedUsageSnapshot(
            providers: [provider(id: "codex", email: nil, lastUpdated: t1)],
            syncTimestamp: t1,
            deviceName: "Mac A",
            deviceID: "mac-A")
        cache.replaceFromFullFetch(perProviderSnapshots: [nilSnap], legacySnapshots: [])
        #expect(cache.perProviderByDevice["mac-A"]?.count == 1)

        // Apply delta: same providerID but with an email. Different composite
        // key — should ADD an entry, not replace.
        cache.applyDelta(
            upserted: [envelope(
                deviceID: "mac-A", deviceName: "Mac A",
                providerID: "codex", email: "u@x.com",
                providerLastUpdated: t2, syncTimestamp: t2)],
            deletedRecordNames: [])

        #expect(cache.perProviderByDevice["mac-A"]?.count == 2)
    }

    // MARK: - Realistic-distribution regression (Build 83 · Agent C)

    @Test("Bursty active device + idle stale device: cache keeps both, sort order intact")
    func burstyActiveAndIdleStaleBothPresent() {
        var cache = SnapshotCache()
        // Mac A is active: recent timestamp + bursty 30-day Codex history.
        let mac_a_env = envelope(
            deviceID: "mac-a", deviceName: "Mac A (active)",
            providerID: "codex", email: "alice@example.com",
            providerLastUpdated: t3, syncTimestamp: t3)
        // Mac B is idle: 20-day-old timestamp, same codex account seen there.
        let mac_b_env = envelope(
            deviceID: "mac-b", deviceName: "Mac B (stale)",
            providerID: "codex", email: "alice@example.com",
            providerLastUpdated: t1, syncTimestamp: t1)

        cache.applyDelta(upserted: [mac_a_env, mac_b_env], deletedRecordNames: [])

        // Both devices present in the per-provider cache.
        #expect(cache.perProviderByDevice["mac-a"]?.count == 1)
        #expect(cache.perProviderByDevice["mac-b"]?.count == 1)

        let snapshots = cache.buildDeviceSnapshots()
        #expect(snapshots.count == 2)
        // A regression that dropped the idle device (e.g. "stale filter on
        // lastUpdated") would show 1 here and Mac B's data would vanish.
        #expect(Set(snapshots.map(\.deviceID)) == ["mac-a", "mac-b"])
    }

    @Test("Multi-account delta on pre-existing cache preserves the untouched account")
    func multiAccountDeltaOnlyUpdatesTargetAccount() {
        var cache = SnapshotCache()

        // Seed: two Codex accounts on Mac A, both at t1.
        cache.applyDelta(
            upserted: [
                envelope(deviceID: "mac-a", deviceName: "Mac A",
                         providerID: "codex", email: "alice@example.com",
                         providerLastUpdated: t1, syncTimestamp: t1),
                envelope(deviceID: "mac-a", deviceName: "Mac A",
                         providerID: "codex", email: "bob@example.com",
                         providerLastUpdated: t1, syncTimestamp: t1),
            ],
            deletedRecordNames: [])
        #expect(cache.perProviderByDevice["mac-a"]?.count == 2)

        // Delta: alice gets fresh data at t2. Bob untouched.
        cache.applyDelta(
            upserted: [
                envelope(deviceID: "mac-a", deviceName: "Mac A",
                         providerID: "codex", email: "alice@example.com",
                         providerLastUpdated: t2, syncTimestamp: t2),
            ],
            deletedRecordNames: [])

        let aliceCodex = cache.perProviderByDevice["mac-a"]?.values.first(where: {
            $0.accountEmail == "alice@example.com"
        })
        let bobCodex = cache.perProviderByDevice["mac-a"]?.values.first(where: {
            $0.accountEmail == "bob@example.com"
        })
        #expect(aliceCodex?.lastUpdated == t2)
        #expect(bobCodex?.lastUpdated == t1)
        // Regression: a cache that re-keys by providerID alone would
        // overwrite bob's entry with alice's on delta apply.
        #expect(cache.perProviderByDevice["mac-a"]?.count == 2)
    }

    // MARK: - Build 94 hotfix · ghost orphan + stale TTL

    @Test("Orphan-with-nil-email is dropped when sibling with email exists for same providerID")
    func orphanNilEmailDroppedWhenRealEmailSiblingExists() {
        // Reproduces user-reported bug: after Mac upgrade, Codex internal
        // identity logic shifted, leaving a nil-email orphan record alongside
        // the new account record. Both display as Codex on iOS but with
        // different ordinal labels ("Hidden" + "Codex 2").
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                envelope( // orphan from pre-upgrade Mac, no email
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    providerID: "codex", email: nil,
                    providerLastUpdated: t3, syncTimestamp: t3),
                envelope( // real account from post-upgrade Mac
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    providerID: "codex", email: "user@example.com",
                    providerLastUpdated: t3, syncTimestamp: t3),
            ],
            deletedRecordNames: [])

        // Cache holds both raw entries (filter applies at read time only).
        #expect(cache.perProviderByDevice["mbp"]?.count == 2)

        // But buildDeviceSnapshots filters the orphan out.
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        let providers = result[0].providers
        #expect(providers.count == 1)
        #expect(providers[0].accountEmail == "user@example.com")
    }

    @Test("Multiple nil-email entries with same providerID stay if no sibling has email")
    func multipleNilEmailLegitWhenNoRealEmailSibling() {
        // Legit accountless providers (e.g., Claude with hide-email setting on
        // both accounts) — both entries have nil email but represent distinct
        // accounts at the recordName level. Keep both; the dedupe rule only
        // fires when AT LEAST ONE sibling has a real email.
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                ProviderUsageEnvelope(
                    deviceID: "mac-a", deviceName: "Mac A",
                    appVersion: "0.20.1", mobileVersion: "1.3.0",
                    syncTimestamp: t3, notificationPushEnabled: true,
                    provider: ProviderUsageSnapshot(
                        providerID: "codex", providerName: "Codex",
                        primary: SyncRateWindow(
                            usedPercent: 23.0, windowMinutes: 60,
                            resetsAt: nil, resetDescription: nil),
                        secondary: nil, accountEmail: nil, loginMethod: nil,
                        statusMessage: nil, isError: false, lastUpdated: t3)),
                ProviderUsageEnvelope(
                    deviceID: "mac-a", deviceName: "Mac A",
                    appVersion: "0.20.1", mobileVersion: "1.3.0",
                    syncTimestamp: t3, notificationPushEnabled: true,
                    provider: ProviderUsageSnapshot(
                        providerID: "codex", providerName: "Codex",
                        primary: SyncRateWindow(
                            usedPercent: 50.0, windowMinutes: 60,
                            resetsAt: nil, resetDescription: nil),
                        secondary: nil, accountEmail: nil, loginMethod: nil,
                        statusMessage: nil, isError: false, lastUpdated: t3)),
            ],
            deletedRecordNames: [])

        // Both entries occupy the same composite key "codex|_" — second
        // upsert overwrites first in the cache, so we only have 1 actually.
        // This test demonstrates that the dedupe rule doesn't accidentally
        // drop the surviving entry. (The "two accountless providers"
        // scenario can't occur via our composite-key cache anyway, but we
        // still want the read-side filter to keep what's there.)
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].providers.count == 1)
    }

    @Test("Stale-TTL drops provider record lagging >30min behind device freshest")
    func staleTTLDropsLaggingProvider() {
        // Reproduces user-reported Perplexity ghost: user enabled then
        // disabled Perplexity on Mac. Mac stopped refreshing the record but
        // the CloudKit envelope persists with its last-known timestamp.
        // After 30 minutes of the device's other providers continuing to
        // refresh, the stale Perplexity record is filtered at read time.
        let now = Date()
        let fresh = now
        let stale = now.addingTimeInterval(-45 * 60) // 45 min behind
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                envelope( // active Codex, just refreshed
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    providerID: "codex", email: "user@example.com",
                    providerLastUpdated: fresh, syncTimestamp: fresh),
                envelope( // disabled Perplexity ghost, never refreshed since
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    providerID: "perplexity", email: nil,
                    providerLastUpdated: stale, syncTimestamp: stale),
            ],
            deletedRecordNames: [])

        // Cache holds both.
        #expect(cache.perProviderByDevice["mbp"]?.count == 2)

        // buildDeviceSnapshots drops the stale one.
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        let providers = result[0].providers
        #expect(providers.count == 1)
        #expect(providers[0].providerID == "codex")
    }

    @Test("Stale-TTL leaves single-record device alone (offline Mac scenario)")
    func staleTTLPreservesSingleRecordDevice() {
        // Mac has been offline; its only provider's lastUpdated is hours old.
        // deviceFreshest = that single entry's lastUpdated, so TTL window is
        // [hours-30min, hours] which still contains the entry. Don't drop it.
        let now = Date()
        let staleSingle = now.addingTimeInterval(-3 * 60 * 60) // 3 hours ago
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [envelope(
                deviceID: "mac-offline", deviceName: "Offline Mac",
                providerID: "claude", email: nil,
                providerLastUpdated: staleSingle, syncTimestamp: staleSingle)],
            deletedRecordNames: [])

        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].providers.count == 1)
    }

    @Test("Stale-TTL keeps providers refreshed within 30 min of device freshest")
    func staleTTLKeepsRecentlyRefreshedProviders() {
        // Mac alternates refresh sequencing — 5 sec between providers in the
        // same cycle. Both well within 30 min threshold.
        let now = Date()
        let codexUpdated = now.addingTimeInterval(-5)
        let claudeUpdated = now.addingTimeInterval(-10)
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                envelope(
                    deviceID: "mbp", deviceName: "Mac",
                    providerID: "codex", email: "u@x.com",
                    providerLastUpdated: codexUpdated, syncTimestamp: now),
                envelope(
                    deviceID: "mbp", deviceName: "Mac",
                    providerID: "claude", email: nil,
                    providerLastUpdated: claudeUpdated, syncTimestamp: now),
            ],
            deletedRecordNames: [])

        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].providers.count == 2)
    }

    @Test("Both rules combined: orphan Codex + stale Perplexity (user's reported scenario)")
    func combinedOrphanAndStale() {
        // Reproduces the exact symptom user reported on iOS 1.3.0 Build 93
        // after upgrading both Macs to 0.20.3:
        //   - mbp shows 4 provider cards but only Codex + Claude are active
        //   - "Codex" + "Codex 2" duplicates from upgrade-induced identity drift
        //   - Perplexity ghost from disable
        // After Build 94 hotfix, only the 2 active providers remain.
        let now = Date()
        let active = now
        let postUpgradeOrphan = now.addingTimeInterval(-31 * 60) // 31 min ago
        let perplexityGhost = now.addingTimeInterval(-39 * 60) // 39 min ago
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                // Real active Codex with email
                envelope(
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    providerID: "codex", email: "user@example.com",
                    providerLastUpdated: active, syncTimestamp: now),
                // Real active Claude (accountless)
                envelope(
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    providerID: "claude", email: nil,
                    providerLastUpdated: active, syncTimestamp: now),
                // Orphan Codex from pre-upgrade (different recordName, nil
                // email in payload — Build 66 ghost filter doesn't catch it
                // because it has cost data)
                ProviderUsageEnvelope(
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    appVersion: "0.20.3", mobileVersion: "1.3.0",
                    syncTimestamp: postUpgradeOrphan,
                    notificationPushEnabled: true,
                    provider: ProviderUsageSnapshot(
                        providerID: "codex",
                        providerName: "Codex",
                        primary: SyncRateWindow(
                            usedPercent: 23.0, windowMinutes: 60,
                            resetsAt: nil, resetDescription: nil),
                        secondary: nil, accountEmail: nil,
                        loginMethod: nil,
                        statusMessage: "Codex returned invalid data: codex app-server closed stdout",
                        isError: true, lastUpdated: postUpgradeOrphan)),
                // Perplexity ghost (disabled but record persists)
                envelope(
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    providerID: "perplexity", email: nil,
                    providerLastUpdated: perplexityGhost,
                    syncTimestamp: perplexityGhost),
            ],
            deletedRecordNames: [])

        // Cache holds all 4.
        // Note: orphan-Codex|_ and the ghost-codex (no email) are different
        // composites only if their accountEmail differs. Here both are nil
        // → composite "codex|_" — the orphan upsert REPLACES the existing
        // codex|_ if any. So with this fixture we have 3 cache entries:
        //   codex|user@example.com (real)
        //   codex|_ (orphan with error)
        //   claude|_ (real)
        //   perplexity|_ (ghost)
        #expect(cache.perProviderByDevice["mbp"]?.count == 4)

        // After filter:
        //   - Rule 1 drops codex|_ (sibling codex|user@example.com has email)
        //   - Rule 2 drops perplexity|_ (39 min ago > 30 min threshold)
        //   - Real Codex + Claude remain
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        let providerIDs = Set(result[0].providers.map { $0.providerID })
        #expect(providerIDs == ["codex", "claude"])
        let codex = result[0].providers.first(where: { $0.providerID == "codex" })
        #expect(codex?.accountEmail == "user@example.com")
    }
}
