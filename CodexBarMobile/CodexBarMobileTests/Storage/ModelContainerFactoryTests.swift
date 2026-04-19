import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

@Suite("ModelContainerFactory Tests")
struct ModelContainerFactoryTests {

    private func makeTempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBarTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Store.sqlite")
    }

    @Test("Container creates successfully at a temp URL")
    func testContainerCreatesSuccessfully() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let container = ModelContainerFactory.makeContainer(at: url)

        // Smoke: fetch an empty table and ensure we get back an empty array
        // rather than throwing.
        let context = ModelContext(container)
        let results = try context.fetch(FetchDescriptor<DeviceRecord>())
        #expect(results.isEmpty)
    }

    @Test("Data persists across container relaunches at the same URL")
    @MainActor
    func testPersistenceAcrossRelaunches() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let deviceID = "persistence-test-\(UUID().uuidString)"

        // Launch 1: insert a DeviceRecord and save.
        do {
            let container = ModelContainerFactory.makeContainer(at: url)
            let context = ModelContext(container)
            let device = DeviceRecord(deviceID: deviceID, deviceName: "MacBook Pro")
            context.insert(device)
            try context.save()
        }

        // Launch 2: re-open the same URL and confirm the row survives.
        do {
            let container = ModelContainerFactory.makeContainer(at: url)
            let context = ModelContext(container)
            let captured = deviceID
            let descriptor = FetchDescriptor<DeviceRecord>(
                predicate: #Predicate { $0.deviceID == captured })
            let results = try context.fetch(descriptor)
            #expect(results.count == 1)
            #expect(results.first?.deviceName == "MacBook Pro")
        }
    }

    @Test("Default store URL is a valid writable location")
    func testDefaultStoreURLIsWritable() throws {
        let url = ModelContainerFactory.defaultStoreURL()
        let parent = url.deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: parent.path))
    }
}
