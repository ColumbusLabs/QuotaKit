#if canImport(SQLite3)
import Foundation
import SQLite3
import Testing
@testable import CodexBarCore

/// A Codex trace database that has closed cleanly can be a WAL database without sidecars.
/// The fallback must read its checkpointed main file without creating or changing files.
struct CostUsageScannerCodexPriorityImmutableFallbackTests {
    private static let priorityBody = "thread_id=thread-a turn.id=turn-a websocket request: "
        + #"{"type":"response.create","model":"request-model","service_tier":"priority"}"#

    @Test
    func `wal database without sidecars resolves priority turns without changing files`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let dbURL = env.root.appendingPathComponent("logs_2.sqlite")
        defer { CostUsageScanner.dropCodexPriorityTurnsMemo(databaseURL: dbURL) }
        try Self.createWALLogsDatabase(at: dbURL)
        try CostUsageSQLiteFixtures.insertTestLog(
            dbURL: dbURL,
            timestamp: "2026-05-10T12:00:00Z",
            body: Self.priorityBody)
        try Self.removeSidecars(of: dbURL)

        let contents = try Data(contentsOf: dbURL)
        let resolution = CostUsageScanner.resolveCodexPriorityTurns(databaseURL: dbURL)

        #expect(!resolution.validationPending)
        #expect(resolution.turns.keys.sorted() == ["turn-a"])
        #expect(try Data(contentsOf: dbURL) == contents)
        #expect(!FileManager.default.fileExists(atPath: dbURL.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: dbURL.path + "-shm"))
    }

    @Test
    func `bounded historical window reads a wal database without sidecars`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let dbURL = env.root.appendingPathComponent("logs_2.sqlite")
        try Self.createWALLogsDatabase(at: dbURL)
        try CostUsageSQLiteFixtures.insertTestLog(
            dbURL: dbURL,
            timestamp: "2026-05-10T12:00:00Z",
            body: Self.priorityBody)
        try Self.removeSidecars(of: dbURL)

        let resolution = CostUsageScanner.resolveCodexPriorityTurns(
            databaseURL: dbURL,
            sinceDayKey: "2026-05-09",
            untilDayKey: "2026-05-11")

        #expect(!resolution.validationPending)
        #expect(resolution.turns.keys.sorted() == ["turn-a"])
    }

    @Test
    func `idle database state changes with main file content and rejects sidecars`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let dbURL = env.root.appendingPathComponent("logs_2.sqlite")
        try Self.createWALLogsDatabase(at: dbURL)
        try Self.removeSidecars(of: dbURL)
        let before = try #require(SQLiteIdleDatabaseState.read(at: dbURL))
        #expect(SQLiteIdleDatabaseState.read(at: dbURL) == before)

        try CostUsageSQLiteFixtures.insertTestLog(
            dbURL: dbURL,
            timestamp: "2026-05-10T12:00:00Z",
            body: Self.priorityBody)
        try Self.removeSidecars(of: dbURL)
        let after = try #require(SQLiteIdleDatabaseState.read(at: dbURL))
        #expect(after != before)

        try Data().write(to: URL(fileURLWithPath: dbURL.path + "-wal"))
        #expect(SQLiteIdleDatabaseState.read(at: dbURL) == nil)
    }

    @Test
    func `older immutable read invalidation preserves a newer memo`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let dbURL = env.root.appendingPathComponent("logs_2.sqlite")
        CostUsageScanner.dropCodexPriorityTurnsMemo(databaseURL: dbURL)
        defer {
            CostUsageScanner._test_setCodexPriorityBeforeImmutableReadHook(databaseURL: dbURL, nil)
            CostUsageScanner.dropCodexPriorityTurnsMemo(databaseURL: dbURL)
        }

        try Self.createWALLogsDatabase(at: dbURL)
        let epoch = Int64(Date().timeIntervalSince1970)
        try CostUsageSQLiteFixtures.insertTestLogs(
            dbURL: dbURL,
            rows: [(epochSeconds: epoch, body: Self.priorityBody)]
                + (1..<8).map { _ in (epochSeconds: epoch, body: "routine trace row") })
        try Self.removeSidecars(of: dbURL)

        let probe = try #require(CostUsageScanner.openCodexPriorityDatabase(at: dbURL))
        let usesImmutableFallback = probe.idleState != nil
        sqlite3_close(probe.db)
        // Some SQLite builds can read a sidecar-less WAL normally and do not need invalidation.
        guard usesImmutableFallback else { return }

        let initial = CostUsageScanner.resolveCodexPriorityTurns(databaseURL: dbURL)
        #expect(!initial.validationPending)
        #expect(initial.turns.keys.sorted() == ["turn-a"])

        var newerCursor: CostUsageScanner.CodexPriorityTurnsPersistedCursor?
        CostUsageScanner._test_setCodexPriorityBeforeImmutableReadHook(databaseURL: dbURL) { _ in
            CostUsageScanner._test_setCodexPriorityBeforeImmutableReadHook(databaseURL: dbURL, nil)
            do {
                try CostUsageSQLiteFixtures.insertTestLog(
                    dbURL: dbURL,
                    epochSeconds: epoch,
                    body: Self.priorityBody.replacingOccurrences(of: "turn-a", with: "turn-b"))
                try Self.removeSidecars(of: dbURL)
                let attributes = try FileManager.default.attributesOfItem(atPath: dbURL.path)
                let modified = try #require(attributes[.modificationDate] as? Date)
                try FileManager.default.setAttributes(
                    [.modificationDate: modified.addingTimeInterval(2)],
                    ofItemAtPath: dbURL.path)

                let newer = CostUsageScanner.resolveCodexPriorityTurns(databaseURL: dbURL)
                #expect(!newer.validationPending)
                #expect(newer.turns.keys.sorted() == ["turn-a", "turn-b"])
                newerCursor = CostUsageScanner.codexPriorityTurnsPersistedCursor(databaseURL: dbURL)
            } catch {
                Issue.record(error)
            }
        }

        let older = CostUsageScanner.resolveCodexPriorityTurns(databaseURL: dbURL)
        #expect(older.validationPending)
        let expectedCursor = try #require(newerCursor)
        let actualCursor = try #require(CostUsageScanner.codexPriorityTurnsPersistedCursor(databaseURL: dbURL))
        #expect(actualCursor == expectedCursor)
    }

    private static func createWALLogsDatabase(at dbURL: URL) throws {
        try CostUsageSQLiteFixtures.createTestLogsDatabase(at: dbURL)
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { throw FixtureError.open }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "pragma journal_mode=wal", nil, nil, nil) == SQLITE_OK else {
            throw FixtureError.execute
        }
    }

    private static func removeSidecars(of dbURL: URL) throws {
        for suffix in ["-wal", "-shm"] {
            let path = dbURL.path + suffix
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        }
    }

    private enum FixtureError: Error {
        case open
        case execute
    }
}
#endif
