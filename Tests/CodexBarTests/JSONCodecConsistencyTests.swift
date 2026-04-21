import CodexBarSync
import Foundation
import Testing

/// Hardening Phase 3 (Build 68 review).
///
/// Build 65/66 root cause: a `JSONEncoder()` constructed with the default
/// `dateEncodingStrategy` (`.deferredToDate` → `Double` since 2001) was
/// paired with a `JSONDecoder()` configured with `.iso8601` (expecting a
/// String). Every payload that contained a non-nil `Date` failed to decode,
/// `try?` swallowed the throw, and the user lost data on every hydrate.
///
/// These tests pin down the factory contract — `CloudSyncConstants.makeJSONEncoder/Decoder`
/// must produce a matched pair, and every CodexBar `Sync*` type that contains
/// `Date` must round-trip through it. New types added to the wire format MUST
/// add a round-trip test here.
@Suite("JSON codec factory consistency")
struct JSONCodecConsistencyTests {
    private let date1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let date2 = Date(timeIntervalSince1970: 1_700_086_400)

    // MARK: - Factory baseline

    @Test("Factory encoder and decoder agree on a Date")
    func factoryAgreesOnDate() throws {
        struct Box: Codable, Equatable { let when: Date }
        let original = Box(when: date1)
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(Box.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("Default JSONDecoder cannot read what factory encoder produced — proves factory ISN'T the default")
    func defaultDecoderRejectsFactoryOutput() throws {
        struct Box: Codable, Equatable { let when: Date }
        let original = Box(when: date1)
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        // Default JSONDecoder uses `.deferredToDate` → expects Double, will
        // fail to decode an ISO8601 string.
        let defaultDecoded = try? JSONDecoder().decode(Box.self, from: encoded)
        #expect(defaultDecoded == nil) // proves the factory is NOT the default
    }

    @Test("Default JSONEncoder produces output the factory decoder CANNOT read")
    func factoryDecoderRejectsDefaultOutput() throws {
        // This is the literal Build 66 bug shape. If this test ever starts
        // succeeding, someone has changed the factory to default — investigate.
        struct Box: Codable, Equatable { let when: Date }
        let original = Box(when: date1)
        let encoded = try JSONEncoder().encode(original)
        let factoryDecoded = try? CloudSyncConstants.makeJSONDecoder().decode(
            Box.self, from: encoded)
        #expect(factoryDecoded == nil)
    }

    // MARK: - Per-type round-trip (every Sync* type with a Date field)

    @Test("SyncRateWindow round-trips with non-nil resetsAt")
    func syncRateWindowRoundTrip() throws {
        let original = SyncRateWindow(
            label: "Session",
            usedPercent: 42.0,
            windowMinutes: 300,
            resetsAt: date1,
            resetDescription: "Resets in 2h")
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(SyncRateWindow.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("SyncBudgetSnapshot round-trips with non-nil resetsAt (the field that broke Build 66)")
    func syncBudgetRoundTrip() throws {
        let original = SyncBudgetSnapshot(
            usedAmount: 12.34,
            limitAmount: 100,
            currencyCode: "USD",
            period: "monthly",
            resetsAt: date2)
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(SyncBudgetSnapshot.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("SyncUtilizationEntry round-trips with both Date fields")
    func syncUtilizationEntryRoundTrip() throws {
        let original = SyncUtilizationEntry(
            capturedAt: date1, usedPercent: 50, resetsAt: date2)
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(SyncUtilizationEntry.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("ProviderUsageSnapshot round-trips with all Date-bearing children populated")
    func providerUsageSnapshotRoundTrip() throws {
        let window = SyncRateWindow(
            usedPercent: 30, windowMinutes: 300, resetsAt: date1, resetDescription: nil)
        let budget = SyncBudgetSnapshot(
            usedAmount: 5, limitAmount: 100, currencyCode: "USD", period: nil, resetsAt: date2)
        let utilEntry = SyncUtilizationEntry(capturedAt: date1, usedPercent: 25, resetsAt: date2)
        let utilSeries = SyncUtilizationSeries(
            name: "session", windowMinutes: 300, entries: [utilEntry])
        let original = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: window,
            secondary: nil,
            accountEmail: "u@x.com",
            loginMethod: "oauth",
            statusMessage: nil,
            isError: false,
            lastUpdated: date1,
            costSummary: nil,
            budget: budget,
            rateWindows: [window],
            utilizationHistory: [utilSeries])
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(ProviderUsageSnapshot.self, from: encoded)
        // Spot-check: most relevant Date fields landed.
        #expect(decoded.lastUpdated == original.lastUpdated)
        #expect(decoded.primary?.resetsAt == original.primary?.resetsAt)
        #expect(decoded.budget?.resetsAt == original.budget?.resetsAt)
        let decodedUtil = decoded.utilizationHistory?.first?.entries.first?.capturedAt
        let originalUtil = original.utilizationHistory?.first?.entries.first?.capturedAt
        #expect(decodedUtil == originalUtil)
        #expect(decoded.rateWindows.count == original.rateWindows.count)
    }

    @Test("SyncedUsageSnapshot round-trips with syncTimestamp")
    func syncedUsageSnapshotRoundTrip() throws {
        let original = SyncedUsageSnapshot(
            providers: [],
            syncTimestamp: date1,
            deviceName: "Mac",
            deviceID: "abc-123",
            appVersion: "0.20.2",
            mobileVersion: "1.3.0",
            notificationPushEnabled: true)
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(SyncedUsageSnapshot.self, from: encoded)
        #expect(decoded.syncTimestamp == original.syncTimestamp)
    }

    @Test("ProviderUsageEnvelope round-trips with syncTimestamp")
    func providerUsageEnvelopeRoundTrip() throws {
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "u@x.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: date1)
        let original = ProviderUsageEnvelope(
            deviceID: "abc-123",
            deviceName: "Mac",
            appVersion: "0.20.2",
            mobileVersion: "1.3.0",
            syncTimestamp: date2,
            notificationPushEnabled: true,
            provider: provider)
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(ProviderUsageEnvelope.self, from: encoded)
        #expect(decoded.syncTimestamp == original.syncTimestamp)
        #expect(decoded.provider.lastUpdated == original.provider.lastUpdated)
    }

    // MARK: - Compressed round-trip (envelope → zlib → CKRecord-like blob → decode)

    @Test("Envelope survives encode → zlib → decompress → decode pipeline (CloudKit-faithful)")
    func envelopeCompressionRoundTrip() throws {
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: SyncRateWindow(
                usedPercent: 70,
                windowMinutes: 300,
                resetsAt: date1,
                resetDescription: nil),
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: date1)
        let envelope = ProviderUsageEnvelope(
            deviceID: "mac-A",
            deviceName: "Mac A",
            appVersion: nil,
            mobileVersion: nil,
            syncTimestamp: date1,
            notificationPushEnabled: nil,
            provider: provider)

        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(envelope)
        let compressed = try PayloadCompression.compress(encoded)
        let decompressed = try PayloadCompression.decompress(compressed)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(
            ProviderUsageEnvelope.self, from: decompressed)

        #expect(decoded.provider.lastUpdated == envelope.provider.lastUpdated)
        #expect(decoded.provider.primary?.resetsAt == envelope.provider.primary?.resetsAt)
    }
}
