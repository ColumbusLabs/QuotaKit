import Foundation
import LiteCore
import Testing

struct LiteStateStoreTests {
    private static func makeStore() -> LiteStateStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiteStateStoreTests-\(UUID().uuidString)", isDirectory: true)
        // A nested, not-yet-existing directory checks that `save` creates it.
        return LiteStateStore(fileURL: directory.appendingPathComponent("nested/state.json"))
    }

    private static let states = [
        ProviderState(
            provider: .claude,
            windows: [
                QuotaWindow(
                    label: "Session",
                    lane: .session,
                    usedPercent: 37.5,
                    windowMinutes: 300,
                    resetsAt: Date(timeIntervalSince1970: 1_000_000.25)),
            ],
            plan: "Max 20x",
            accountEmail: "person@example.com",
            accountIdentities: ["claude:email:person@example.com"],
            lastFetched: Date(timeIntervalSince1970: 999_000.5),
            status: .ok),
        ProviderState(provider: .antigravity, status: .error("Unrecognized response")),
    ]

    @Test
    func `saved states load back identically`() throws {
        let store = Self.makeStore()

        #expect(try store.save(Self.states))
        #expect(store.load() == Self.states)
    }

    @Test
    func `saving identical states leaves the file alone`() throws {
        let store = Self.makeStore()
        try store.save(Self.states)

        #expect(try store.save(Self.states) == false)

        var changed = Self.states
        changed[0].windows[0].usedPercent = 40
        #expect(try store.save(changed))
    }

    @Test
    func `missing or corrupt file loads as empty`() throws {
        let store = Self.makeStore()
        #expect(store.load().isEmpty)

        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.load().isEmpty)
    }

    @Test
    func `file from another format version is ignored`() throws {
        let store = Self.makeStore()
        try store.save(Self.states)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        try text.replacingOccurrences(of: "\"version\":1", with: "\"version\":99")
            .write(to: store.fileURL, atomically: true, encoding: .utf8)

        #expect(store.load().isEmpty)
    }
}
