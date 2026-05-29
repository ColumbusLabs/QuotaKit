import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

/// T1 — `DailyCostPoint` registered in `CodexBarSwiftDataSchema.models`,
/// `ModelContainerFactory` loads it, empty fetch works, and the new entity
/// coexists with the existing 4 models. Round 1 / P1 of research doc 024.
@Suite("CWL Schema — DailyCostPoint registration + container load (T1)")
@MainActor
struct CWLSchemaTests {
    private func makeTempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CodexBarTests-CWLSchema-\(UUID().uuidString)",
                isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Store.sqlite")
    }

    @Test("Container builds successfully with DailyCostPoint registered + empty fetch works")
    func testContainerIncludesDailyCostPoint() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        // Empty fetch on the new entity must not throw.
        let results = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(results.isEmpty)
    }

    @Test("DailyCostPoint coexists with existing 4 models in same container")
    func testCoexistenceWithExistingModels() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        // All 5 model types fetchable — confirms ModelContainer registered them all.
        #expect(try context.fetch(FetchDescriptor<DeviceRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ProviderSnapshotModel>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<UtilizationEntryModel>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SyncStateRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DailyCostPoint>()).isEmpty)
    }

    @Test("DailyCostPoint insert + save + fetch round-trips all fields")
    func testInsertAndFieldRoundTrip() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let lastUpdated = Date(timeIntervalSince1970: 1_700_000_000)
        let breakdownsBlob = Data("[{\"label\":\"x\"}]".utf8)

        let point = DailyCostPoint(
            deviceID: "dev-A",
            providerID: "codex",
            accountEmail: "alice@codex.test",
            dayKey: "2026-05-28",
            costUSD: 1.23,
            totalTokens: 4567,
            isEstimated: false,
            modelBreakdownsData: breakdownsBlob,
            serviceBreakdownsData: nil,
            lastUpdated: lastUpdated)
        context.insert(point)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(fetched.count == 1)
        let row = try #require(fetched.first)
        #expect(row.compositeKey == "dev-A|codex|alice@codex.test|2026-05-28")
        #expect(row.deviceID == "dev-A")
        #expect(row.providerID == "codex")
        #expect(row.accountEmail == "alice@codex.test")
        #expect(row.dayKey == "2026-05-28")
        #expect(row.costUSD == 1.23)
        #expect(row.totalTokens == 4567)
        #expect(row.isEstimated == false)
        #expect(row.modelBreakdownsData == breakdownsBlob)
        #expect(row.serviceBreakdownsData == nil)
        #expect(row.lastUpdated == lastUpdated)
    }

    @Test("makeCompositeKey format pinned to deviceID|providerID|accountEmail|dayKey")
    func testCompositeKeyFormat() {
        let withEmail = DailyCostPoint.makeCompositeKey(
            deviceID: "dev-A",
            providerID: "codex",
            accountEmail: "alice@codex.test",
            dayKey: "2026-05-28")
        #expect(withEmail == "dev-A|codex|alice@codex.test|2026-05-28")

        // nil accountEmail → "_" sentinel, matching ProviderSnapshotModel.
        let nilEmail = DailyCostPoint.makeCompositeKey(
            deviceID: "dev-A",
            providerID: "codex",
            accountEmail: nil,
            dayKey: "2026-05-28")
        #expect(nilEmail == "dev-A|codex|_|2026-05-28")
    }
}
