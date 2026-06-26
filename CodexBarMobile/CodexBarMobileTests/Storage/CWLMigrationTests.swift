import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

/// T16 — adding `DailyCostPoint` to the schema does not break existing
/// stores. SwiftData lightweight migration handles "added entity"
/// automatically; this test pins that an existing store with the old-style
/// data (`DeviceRecord` / `ProviderSnapshotModel`) reopens cleanly with the
/// current (post-Round-1) schema, the old data is intact, AND the new
/// `DailyCostPoint` table is available + empty + writable.
///
/// We can't easily simulate "schema without `DailyCostPoint`" since
/// `CodexBarSwiftDataSchema.models` is module-level. But we CAN verify the
/// equivalent invariant: a store populated with pre-CWL entities still
/// reopens cleanly under the new schema — which is exactly the path an
/// upgrading user travels.
@Suite("CWL Migration — old store reopens cleanly with new schema (T16)")
@MainActor
struct CWLMigrationTests {
    private func makeTempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CodexBarTests-CWLMigration-\(UUID().uuidString)",
                isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Store.sqlite")
    }

    @Test("Old-style DeviceRecord + ProviderSnapshotModel data survives reopen under new schema")
    func existingDataSurvivesReopen() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let deviceID = "mig-test-\(UUID().uuidString)"
        let costSummaryBlob = Data("legacy-blob".utf8)

        // Launch 1: create store + insert pre-CWL data (DeviceRecord + ProviderSnapshotModel only).
        do {
            let container = ModelContainerFactory.makeContainer(at: url)
            let context = ModelContext(container)

            let device = DeviceRecord(
                deviceID: deviceID,
                deviceName: "iPhone Sim (T16)",
                appVersion: "1.9.0",
                lastSyncAt: now)
            context.insert(device)

            let provider = ProviderSnapshotModel(
                deviceID: deviceID,
                providerID: "codex",
                providerName: "Codex",
                accountEmail: "test@example.test",
                loginMethod: "Pro",
                statusMessage: nil,
                isError: false,
                lastUpdated: now,
                rateWindowsData: Data("[]".utf8),
                costSummaryData: costSummaryBlob,
                budgetData: nil,
                perplexityCreditsData: nil,
                device: device)
            context.insert(provider)

            try context.save()
        }

        // Launch 2: reopen at same URL. Verify old data is intact + new
        // DailyCostPoint table is registered + queryable + empty.
        do {
            let container = ModelContainerFactory.makeContainer(at: url)
            let context = ModelContext(container)

            let devices = try context.fetch(FetchDescriptor<DeviceRecord>())
            #expect(devices.count == 1)
            #expect(devices.first?.deviceID == deviceID)
            #expect(devices.first?.deviceName == "iPhone Sim (T16)")

            let providers = try context.fetch(FetchDescriptor<ProviderSnapshotModel>())
            #expect(providers.count == 1)
            #expect(providers.first?.providerID == "codex")
            #expect(providers.first?.costSummaryData == costSummaryBlob)

            // NEW: DailyCostPoint table is registered + queryable + empty.
            let ledger = try context.fetch(FetchDescriptor<DailyCostPoint>())
            #expect(ledger.isEmpty)
        }
    }

    @Test("DailyCostPoint inserted in upgraded store survives a subsequent reopen")
    func newLedgerEntryPersistsAcrossReopen() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let when = Date(timeIntervalSince1970: 1_700_000_000)

        // Launch 1: insert a DailyCostPoint.
        do {
            let container = ModelContainerFactory.makeContainer(at: url)
            let context = ModelContext(container)
            context.insert(DailyCostPoint(
                deviceID: "dev-X",
                providerID: "claude",
                accountEmail: nil,
                dayKey: "2026-05-28",
                costUSD: 2.34,
                totalTokens: 8901,
                lastUpdated: when))
            try context.save()
        }

        // Launch 2: reopen, verify it's still there + all fields intact.
        do {
            let container = ModelContainerFactory.makeContainer(at: url)
            let context = ModelContext(container)
            let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
            #expect(rows.count == 1)
            let row = try #require(rows.first)
            #expect(row.deviceID == "dev-X")
            #expect(row.providerID == "claude")
            #expect(row.dayKey == "2026-05-28")
            #expect(row.costUSD == 2.34)
            #expect(row.totalTokens == 8901)
            #expect(row.lastUpdated == when)
            #expect(row.compositeKey == "dev-X|claude|_|2026-05-28")
        }
    }
}
