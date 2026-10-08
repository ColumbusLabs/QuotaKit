import CodexBarSync
import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

struct ClaudeSubscriptionSyncTests {
    private func snapshot(details: [SyncProviderDetailSection]?) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "Claude Pro",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 100),
            providerDetails: details)
    }

    @Test
    func `billing detail dates preserve wire precision and legacy snapshots remain empty`() throws {
        let details = [SyncProviderDetailSection(title: "Subscription", rows: [
            .init(label: "Renews", value: "2026-11-05"),
        ])]
        let encoded = try JSONEncoder().encode(self.snapshot(details: details))
        let decoded = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: encoded)
        #expect(decoded.providerDetails == details)
        #expect(decoded.accountEmail == nil)
        #expect(decoded.rateWindows.isEmpty)
        let displayed = ProviderDetailSectionDispatcher.displayProviderDetails(for: decoded)
        #expect(displayed?.first?.rows.first?.label == String(
            localized: "elevenlabs_renews_label", defaultValue: "Renews"))
        #expect(displayed?.first?.rows.first?.value == ProviderDetailSectionDispatcher
            .subscriptionDateDisplay("2026-11-05"))

        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "providerDetails")
        let older = try JSONDecoder().decode(
            ProviderUsageSnapshot.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        #expect(ProviderDetailSectionDispatcher.displayProviderDetails(for: older) == nil)
        #expect(ProviderDetailSectionDispatcher.displayProviderDetails(for: self.snapshot(details: [])) == [])
    }

    @Test
    func `calendar date never shifts while timestamp follows local timezone`() throws {
        let locale = Locale(identifier: "en_US")
        let west = try #require(TimeZone(secondsFromGMT: -8 * 3600))
        let east = try #require(TimeZone(secondsFromGMT: 9 * 3600))
        #expect(ProviderDetailSectionDispatcher.subscriptionDateDisplay("2026-11-05", locale: locale, timeZone: west)
            == "Nov 5, 2026")
        #expect(ProviderDetailSectionDispatcher.subscriptionDateDisplay("2026-11-05", locale: locale, timeZone: east)
            == "Nov 5, 2026")
        #expect(ProviderDetailSectionDispatcher.subscriptionDateDisplay(
            "2026-11-05T00:00:00.000Z", locale: locale, timeZone: west) == "Nov 4, 2026")
        #expect(ProviderDetailSectionDispatcher.subscriptionDateDisplay("2026-02-30") == nil)
        #expect(ProviderDetailSectionDispatcher.subscriptionDateDisplay("private-account@example.com") == nil)
    }

    @Test
    func `only recognized billing rows render and plan label cannot invent a date`() {
        let snapshot = self.snapshot(details: [.init(title: "Subscription", rows: [
            .init(label: "Email", value: "private@example.com"),
            .init(label: "Plan expires", value: "invalid"),
        ])])
        #expect(ProviderDetailSectionDispatcher.displayProviderDetails(for: snapshot) == [])
        #expect(ProviderDetailSectionDispatcher.displayProviderDetails(for: self.snapshot(details: nil)) == nil)
    }

    @Test
    func `new empty billing details clear older device data while legacy nil preserves it`() throws {
        let details = [SyncProviderDetailSection(title: "Subscription", rows: [
            .init(label: "Renews", value: "2026-11-05"),
        ])]
        func device(_ id: String, _ seconds: Double, _ rows: [SyncProviderDetailSection]?) -> SyncedUsageSnapshot {
            let date = Date(timeIntervalSince1970: seconds)
            let provider = ProviderUsageSnapshot(
                providerID: "claude",
                providerName: "Claude",
                primary: nil,
                secondary: nil,
                accountEmail: "fixture@example.com",
                loginMethod: "Claude Pro",
                statusMessage: nil,
                isError: false,
                lastUpdated: date,
                providerDetails: rows)
            return SyncedUsageSnapshot(providers: [provider], syncTimestamp: date, deviceName: id, deviceID: id)
        }
        let old = device("older", 100, details)
        let cleared = try #require(CloudSyncReader.mergeSnapshots([old, device("newer", 200, [])]))
        #expect(cleared.providers.first?.providerDetails == [])
        let legacy = try #require(CloudSyncReader.mergeSnapshots([old, device("legacy", 200, nil)]))
        #expect(legacy.providers.first?.providerDetails == details)
    }

    @MainActor
    @Test
    func `billing dates survive existing persistent detail storage and clear without schema changes`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("Store.sqlite")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)
        let details = [SyncProviderDetailSection(title: "Subscription", rows: [
            .init(label: "Plan expires", value: "2026-11-05"),
        ])]
        let device = SyncedUsageSnapshot(
            providers: [self.snapshot(details: details)],
            syncTimestamp: Date(timeIntervalSince1970: 100),
            deviceName: "Fixture Mac",
            deviceID: "fixture-device")
        try SwiftDataBridge.upsert(deviceSnapshots: [device], into: context)
        let hydrated = try #require(SwiftDataBridge.readAllDeviceSnapshots(from: context).first)
        #expect(hydrated.providers.first?.providerDetails == details)
        let empty = SyncedUsageSnapshot(
            providers: [self.snapshot(details: [])],
            syncTimestamp: Date(timeIntervalSince1970: 200),
            deviceName: "Fixture Mac",
            deviceID: "fixture-device")
        try SwiftDataBridge.upsert(deviceSnapshots: [empty], into: context)
        #expect(try SwiftDataBridge.readAllDeviceSnapshots(from: context).first?.providers.first?.providerDetails == [])
    }
}
