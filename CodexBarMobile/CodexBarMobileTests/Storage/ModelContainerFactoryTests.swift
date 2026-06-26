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
    func containerCreatesSuccessfully() throws {
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
    func persistenceAcrossRelaunches() throws {
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
    func defaultStoreURLIsWritable() {
        let url = ModelContainerFactory.defaultStoreURL()
        let parent = url.deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: parent.path))
    }

    @Test("Legacy store discovery finds Application Support CodexBar store")
    func legacyStoreURLFindsCodexBarDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaKitTests-Legacy-\(UUID().uuidString)", isDirectory: true)
        let legacyDir = root.appendingPathComponent("CodexBar", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyStore = legacyDir.appendingPathComponent(ModelContainerFactory.storeFilename)
        FileManager.default.createFile(atPath: legacyStore.path, contents: Data([0x01]))

        let discovered = ModelContainerFactory.legacyStoreURL(
            applicationSupportRoot: root)

        #expect(discovered?.lastPathComponent == ModelContainerFactory.storeFilename)
        #expect(discovered?.deletingLastPathComponent().lastPathComponent == "CodexBar")
    }

    @Test("Copy store files duplicates sqlite sidecars")
    func copyStoreFilesDuplicatesSidecars() throws {
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaKitTests-CopySource-\(UUID().uuidString)", isDirectory: true)
        let targetRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaKitTests-CopyTarget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let sourceURL = sourceRoot.appendingPathComponent(ModelContainerFactory.storeFilename)
        for suffix in ["", "-wal", "-shm"] {
            FileManager.default.createFile(
                atPath: sourceURL.path + suffix,
                contents: Data([0xAB]))
        }

        let targetURL = targetRoot
            .appendingPathComponent("QuotaKit", isDirectory: true)
            .appendingPathComponent(ModelContainerFactory.storeFilename)

        try ModelContainerFactory.copyStoreFiles(from: sourceURL, to: targetURL)

        for suffix in ["", "-wal", "-shm"] {
            #expect(FileManager.default.fileExists(atPath: targetURL.path + suffix))
        }
    }
}
