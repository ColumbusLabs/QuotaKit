import CodexBarSync
import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

/// P6 — tests for SwiftDataBridge's change-token + delta-apply APIs.
@Suite("Per-provider delta apply")
struct PerProviderDeltaTests {
    private func makeContainer() -> ModelContainer {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBarDeltaTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Store.sqlite")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        return ModelContainerFactory.makeContainer(at: url)
    }

    private let ts1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let ts2 = Date(timeIntervalSince1970: 1_700_003_600)

    private func makeEnvelope(
        deviceID: String,
        deviceName: String = "Mac",
        providerID: String,
        providerName: String? = nil,
        email: String? = nil,
        lastUpdated: Date,
        syncTimestamp: Date? = nil
    ) -> ProviderUsageEnvelope {
        let provider = ProviderUsageSnapshot(
            providerID: providerID,
            providerName: providerName ?? providerID.capitalized,
            primary: nil,
            secondary: nil,
            accountEmail: email,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated)
        return ProviderUsageEnvelope(
            deviceID: deviceID,
            deviceName: deviceName,
            appVersion: "0.20.1",
            mobileVersion: "1.3.0",
            syncTimestamp: syncTimestamp ?? lastUpdated,
            notificationPushEnabled: true,
            provider: provider)
    }

    // MARK: - applyPerProviderDelta

    @Test("Upserts new envelopes as fresh rows")
    func upsertNewEnvelope() throws {
        let container = makeContainer()
        let context = ModelContext(container)

        let envelope = makeEnvelope(
            deviceID: "mac-A", providerID: "codex", lastUpdated: ts1)
        try SwiftDataBridge.applyPerProviderDelta(
            envelopes: [envelope], deletedRecordNames: [], context: context)

        let devices = try context.fetch(FetchDescriptor<DeviceRecord>())
        let providers = try context.fetch(FetchDescriptor<ProviderSnapshotModel>())
        #expect(devices.count == 1)
        #expect(providers.count == 1)
        #expect(providers.first?.providerID == "codex")
    }

    @Test("Upserting the same composite key updates in place")
    func upsertUpdatesExisting() throws {
        let container = makeContainer()
        let context = ModelContext(container)

        let e1 = makeEnvelope(
            deviceID: "mac-A", providerID: "codex", lastUpdated: ts1)
        let e2 = makeEnvelope(
            deviceID: "mac-A", providerID: "codex",
            providerName: "Codex Updated", lastUpdated: ts2)

        try SwiftDataBridge.applyPerProviderDelta(
            envelopes: [e1], deletedRecordNames: [], context: context)
        try SwiftDataBridge.applyPerProviderDelta(
            envelopes: [e2], deletedRecordNames: [], context: context)

        let providers = try context.fetch(FetchDescriptor<ProviderSnapshotModel>())
        #expect(providers.count == 1)
        #expect(providers.first?.providerName == "Codex Updated")
        #expect(providers.first?.lastUpdated == ts2)
    }

    @Test("Deletes rows by composite recordName")
    func deletesByRecordName() throws {
        let container = makeContainer()
        let context = ModelContext(container)

        let e1 = makeEnvelope(
            deviceID: "mac-A", providerID: "codex", lastUpdated: ts1)
        let e2 = makeEnvelope(
            deviceID: "mac-A", providerID: "claude", lastUpdated: ts1)
        try SwiftDataBridge.applyPerProviderDelta(
            envelopes: [e1, e2], deletedRecordNames: [], context: context)

        let codexRecordName = CloudSyncManager.perProviderRecordName(
            deviceID: "mac-A", providerID: "codex", accountEmail: nil)
        try SwiftDataBridge.applyPerProviderDelta(
            envelopes: [],
            deletedRecordNames: [codexRecordName],
            context: context)

        let providers = try context.fetch(FetchDescriptor<ProviderSnapshotModel>())
        #expect(providers.count == 1)
        #expect(providers.first?.providerID == "claude")
    }

    @Test("Empty delta is a no-op")
    func emptyDelta() throws {
        let container = makeContainer()
        let context = ModelContext(container)

        try SwiftDataBridge.applyPerProviderDelta(
            envelopes: [], deletedRecordNames: [], context: context)

        let devices = try context.fetch(FetchDescriptor<DeviceRecord>())
        #expect(devices.isEmpty)
    }

    @Test("Multiple providers on same device share one DeviceRecord")
    func multiProviderSameDevice() throws {
        let container = makeContainer()
        let context = ModelContext(container)

        let e1 = makeEnvelope(
            deviceID: "mac-A", providerID: "codex", lastUpdated: ts1)
        let e2 = makeEnvelope(
            deviceID: "mac-A", providerID: "claude", lastUpdated: ts1)
        try SwiftDataBridge.applyPerProviderDelta(
            envelopes: [e1, e2], deletedRecordNames: [], context: context)

        let devices = try context.fetch(FetchDescriptor<DeviceRecord>())
        let providers = try context.fetch(FetchDescriptor<ProviderSnapshotModel>())
        #expect(devices.count == 1)
        #expect(providers.count == 2)
    }

    // MARK: - Change token persistence

    @Test("Token is nil for zones with no SyncStateRecord")
    func tokenInitiallyNil() throws {
        let container = makeContainer()
        let context = ModelContext(container)

        let token = try SwiftDataBridge.loadChangeToken(
            forZone: "DeviceProvidersZone", from: context)
        #expect(token == nil)
    }

    @Test("Save then load round-trips token bytes")
    func tokenRoundTrip() throws {
        let container = makeContainer()
        let context = ModelContext(container)

        let payload = Data([0xde, 0xad, 0xbe, 0xef])
        try SwiftDataBridge.saveChangeToken(
            forZone: "DeviceProvidersZone", tokenData: payload, context: context)

        let loaded = try SwiftDataBridge.loadChangeToken(
            forZone: "DeviceProvidersZone", from: context)
        #expect(loaded == payload)
    }

    @Test("Different zones track independent tokens")
    func tokensAreZoneScoped() throws {
        let container = makeContainer()
        let context = ModelContext(container)

        try SwiftDataBridge.saveChangeToken(
            forZone: "DeviceProvidersZone",
            tokenData: Data([0x01]), context: context)
        try SwiftDataBridge.saveChangeToken(
            forZone: "DeviceSnapshotsZone",
            tokenData: Data([0x02]), context: context)

        let a = try SwiftDataBridge.loadChangeToken(
            forZone: "DeviceProvidersZone", from: context)
        let b = try SwiftDataBridge.loadChangeToken(
            forZone: "DeviceSnapshotsZone", from: context)
        #expect(a == Data([0x01]))
        #expect(b == Data([0x02]))
    }

    @Test("Saving nil clears the stored token (token-expiry recovery)")
    func clearTokenOnExpiry() throws {
        let container = makeContainer()
        let context = ModelContext(container)

        try SwiftDataBridge.saveChangeToken(
            forZone: "DeviceProvidersZone",
            tokenData: Data([0xaa]), context: context)
        try SwiftDataBridge.saveChangeToken(
            forZone: "DeviceProvidersZone",
            tokenData: nil, context: context)

        let loaded = try SwiftDataBridge.loadChangeToken(
            forZone: "DeviceProvidersZone", from: context)
        #expect(loaded == nil)
    }
}
