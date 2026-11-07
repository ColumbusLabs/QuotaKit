import Foundation
import Testing
import WebKit
@testable import CodexBarCore

@MainActor
struct OpenAIDashboardCacheMaintenanceTests {
    @Test
    func `launch maintenance is inert in test processes`() async {
        #expect(TestProcessSafety.isRunningUnderTests())
        await OpenAIDashboardWebsiteDataStore.clearNetworkCaches()
    }

    @Test
    func `cold enumeration initializes before listing named stores`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var calls: [String] = []
        let identifier = UUID()
        func identifiers() async -> [UUID] {
            await OpenAIDashboardWebsiteDataStore.existingIdentifiers(
                in: directory,
                initialize: { calls.append("initialize") },
                enumerate: {
                    calls.append("enumerate")
                    return [identifier]
                })
        }
        #expect(await identifiers().isEmpty)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(await identifiers().isEmpty)
        #expect(calls.isEmpty)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(identifier.uuidString), withIntermediateDirectories: true)
        #expect(await identifiers() == [identifier])
        #expect(calls == ["initialize", "enumerate"])
    }

    @Test
    func `daily sweep waits a full day`() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(OpenAIDashboardWebsiteDataStore.sweepIsDue(lastSweep: nil, now: start))
        #expect(!OpenAIDashboardWebsiteDataStore.sweepIsDue(lastSweep: start, now: start.addingTimeInterval(86399)))
        #expect(OpenAIDashboardWebsiteDataStore.sweepIsDue(lastSweep: start, now: start.addingTimeInterval(86400)))
    }

    @Test
    func `daily maintenance bounds cache growth and retains session data`() async {
        let maintenance = OpenAIDashboardCacheMaintenance()
        let store = FakeStore()
        let start = Date(timeIntervalSince1970: 0)
        for day in 0..<4 {
            store.data[WKWebsiteDataTypeDiskCache, default: 0] += 1024
            await maintenance.clearIfNeeded(store, now: start.addingTimeInterval(Double(day) * 86400))
            #expect(store.data[WKWebsiteDataTypeDiskCache] == nil)
            store.data[WKWebsiteDataTypeDiskCache] = 64
            await maintenance.clearIfNeeded(store, now: start.addingTimeInterval(Double(day) * 86400 + 1))
            #expect(store.data[WKWebsiteDataTypeDiskCache] == 64)
        }
        #expect(store.removals == 4)
        #expect(store.data[WKWebsiteDataTypeCookies] == 1)
        #expect(store.data[WKWebsiteDataTypeLocalStorage] == 1)
        #expect(store.data[WKWebsiteDataTypeIndexedDBDatabases] == 1)
    }

    @Test
    func `default and account stores are maintained independently and ephemeral stores are skipped`() async {
        let maintenance = OpenAIDashboardCacheMaintenance()
        let stores = [FakeStore(identifier: nil), FakeStore(), FakeStore(isPersistent: false)]
        for store in stores {
            await maintenance.clearIfNeeded(store)
        }
        #expect(stores.map(\.removals) == [1, 1, 0])
        let reopened = FakeStore(identifier: stores[1].identifier)
        await maintenance.clearIfNeeded(reopened)
        #expect(reopened.removals == 0)
    }

    private final class FakeStore: OpenAIDashboardWebsiteCacheStore {
        let identifier: UUID?
        let isPersistent: Bool
        var removals = 0
        var data = [
            WKWebsiteDataTypeDiskCache: 1024,
            WKWebsiteDataTypeMemoryCache: 128,
            WKWebsiteDataTypeCookies: 1,
            WKWebsiteDataTypeLocalStorage: 1,
            WKWebsiteDataTypeIndexedDBDatabases: 1,
        ]

        init(identifier: UUID? = UUID(), isPersistent: Bool = true) {
            self.identifier = identifier
            self.isPersistent = isPersistent
        }

        func removeData(ofTypes types: Set<String>, modifiedSince date: Date) async {
            #expect(types == [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache])
            #expect(date == .distantPast)
            self.removals += 1
            for type in types {
                self.data.removeValue(forKey: type)
            }
        }
    }
}
