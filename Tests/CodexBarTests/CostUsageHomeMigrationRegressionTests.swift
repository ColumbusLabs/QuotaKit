import Foundation
import Testing
@testable import CodexBarCore
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

@Suite(.serialized)
struct CostUsageHomeMigrationRegressionTests {
    @Test
    func `missing roots keep the same home scope when archives and sessions appear`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let home = env.root.appendingPathComponent("uncreated-home", isDirectory: true)
        let sessions = home.appendingPathComponent("sessions", isDirectory: true)
        let archives = home.appendingPathComponent("archived_sessions", isDirectory: true)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: sessions,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"))
        options.refreshMinIntervalSeconds = 0
        let expectedScope = CodexHomeCostStoreScope.key(sessionsRoot: sessions)
        #expect(CostUsageScanner.codexSessionsRoots(options: options).isEmpty)
        #expect(CodexHomeCostStoreScope.key(options: options) == expectedScope)

        let day = try env.makeLocalNoon(year: 2026, month: 10, day: 2)
        _ = CostUsageScanner.loadDailyReport(provider: .codex, since: day, until: day, now: day, options: options)
        try FileManager.default.createDirectory(at: archives, withIntermediateDirectories: true)
        #expect(CodexHomeCostStoreScope.key(options: options) == expectedScope)
        #expect(CostUsageScanner.codexSessionsRoots(options: options).map(\.lastPathComponent) == ["archived_sessions"])
        _ = CostUsageScanner.loadDailyReport(provider: .codex, since: day, until: day, now: day, options: options)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        #expect(CodexHomeCostStoreScope.key(options: options) == expectedScope)
        #expect(Set(CostUsageScanner.codexSessionsRoots(options: options).map(\.lastPathComponent))
            == Set(["sessions", "archived_sessions"]))
    }

    @Test(arguments: ["missing", "directory", "present"])
    func `v6 mixed source proof is cleared only when native history can be rebuilt`(scenario: String) async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let customHome = env.root.appendingPathComponent("custom-home", isDirectory: true)
        let archivedRoot = customHome.appendingPathComponent("archived_sessions", isDirectory: true)
        let sessionsRoot = customHome.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: archivedRoot, withIntermediateDirectories: true)
        let nativePath = archivedRoot.appendingPathComponent("prior.jsonl").path
        if scenario == "present" {
            try Data("native fixture".utf8).write(to: URL(fileURLWithPath: nativePath))
        } else if scenario == "directory" {
            try FileManager.default.createDirectory(atPath: nativePath, withIntermediateDirectories: true)
        }
        let openCodePath = env.root.appendingPathComponent("opencode.db").path
        let databaseURL = CostUsageStore.databaseURL(cacheRoot: env.cacheRoot)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var database: OpaquePointer?
        try #require(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        guard let database else { throw CostUsageStore.StoreError.invalidData }
        defer { sqlite3_close(database) }
        try CostUsageStore.execute(database, "PRAGMA auto_vacuum = INCREMENTAL")
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CostUsage/store-v6-schema.sql")
        try CostUsageStore.execute(database, String(contentsOf: fixture, encoding: .utf8))
        let predecessorHash = "7d66d60c44b88609"
        let oldVersion = CostUsageStore.combinedSchemaVersion(base: 6, parserHash: predecessorHash)
        try CostUsageStore.execute(database, "PRAGMA user_version = \(oldVersion)")
        try CostUsageStore.writeMetaValue(predecessorHash, key: "parser_hash", database: database)
        var metadata = CostUsageStoreMetadata.empty
        metadata.rootMtimes = [archivedRoot.path: 0]
        metadata.verifiedScanSinceDay = "2026-10-01"
        metadata.verifiedScanUntilDay = "2026-10-01"
        metadata.verifiedUpdatedAtUnixMs = 1234
        let metadataStatement = try CostUsageStore.prepare(
            database, "INSERT INTO scan_metadata(id, payload) VALUES (1, ?)")
        try CostUsageStore.bind(JSONEncoder().encode(metadata), to: metadataStatement, at: 1)
        try CostUsageStore.stepDone(metadataStatement, database: database)
        sqlite3_finalize(metadataStatement)
        let insert = try CostUsageStore.prepare(database, """
        INSERT INTO files(id, path, mtime_ms, size, scan_state, scan_complete, updated_at_ms)
        VALUES (?, ?, 1, 1, ?, 1, 1)
        """)
        defer { sqlite3_finalize(insert) }
        for (id, path, source) in [
            (Int64(101), nativePath, "nativeCodexSessionLogs"),
            (Int64(102), openCodePath, "opencodeLocalHistory"),
        ] {
            sqlite3_reset(insert)
            sqlite3_clear_bindings(insert)
            sqlite3_bind_int64(insert, 1, id)
            CostUsageStore.bind(path, to: insert, at: 2)
            CostUsageStore.bind(Data("{\"source\":\"\(source)\",\"isComplete\":true}".utf8), to: insert, at: 3)
            try CostUsageStore.stepDone(insert, database: database)
        }
        sqlite3_reset(insert)
        try CostUsageStore.execute(database, """
        INSERT INTO usage_rows(file_id, row_index, payload) VALUES
          (101, 0, CAST('{"native":true}' AS BLOB)),
          (102, 0, CAST('{"imported":true}' AS BLOB))
        """)
        try CostUsageStore.execute(database, """
        CREATE TABLE verified_day_status(day TEXT PRIMARY KEY);
        INSERT INTO verified_day_status(day) VALUES ('2026-10-01')
        """)

        let customScope = CodexHomeCostStoreScope.key(sessionsRoot: sessionsRoot)
        let nativeStore = CostUsageStore(cacheRoot: env.cacheRoot, home: customScope)
        let sharedStore = CostUsageStore(cacheRoot: env.cacheRoot, home: CodexHomeCostStoreScope.openCodeSource)
        let native = await nativeStore.readSnapshot()
        if scenario != "present" {
            #expect(await nativeStore.configuration() == nil)
            #expect(await nativeStore.rebuildCount == 0)
            #expect(try CostUsageStore.scalarInt(database, "PRAGMA user_version") == Int64(oldVersion))
            #expect(try CostUsageStore.scalarInt(database, "SELECT COUNT(*) FROM usage_rows") == 2)
            #expect(try CostUsageStore.scalarInt(database, "SELECT COUNT(*) FROM verified_day_status") == 1)
            return
        }
        let shared = await sharedStore.readSnapshot()
        #expect(native.metadata.rootMtimes == [archivedRoot.path: 0])
        #expect(native.metadata.verifiedScanSinceDay == nil)
        #expect(native.metadata.verifiedScanUntilDay == nil)
        #expect(native.metadata.verifiedUpdatedAtUnixMs == nil)
        #expect(native.metadata.catchUpPending)
        #expect(try CostUsageStore.scalarInt(database, "SELECT COUNT(*) FROM verified_day_status") == 0)
        #expect(try CostUsageStore.scalarInt(database, "SELECT COUNT(*) FROM usage_rows") == 2)
        #expect(native.files.map(\.path) == [nativePath])
        #expect(shared.files.map(\.path) == [openCodePath])
        #expect(await nativeStore.configuration()?.userVersion == Int(CostUsageStore.schemaVersion))
        #expect(await nativeStore.rebuildCount == 0)
        let identity = try CostUsageStore.prepare(database, "SELECT id, home FROM files WHERE path = ?")
        defer { sqlite3_finalize(identity) }
        for (path, expectedID, expectedHome) in [
            (nativePath, Int64(101), customScope),
            (openCodePath, Int64(102), CodexHomeCostStoreScope.openCodeSource),
        ] {
            sqlite3_reset(identity)
            sqlite3_clear_bindings(identity)
            CostUsageStore.bind(path, to: identity, at: 1)
            try #require(sqlite3_step(identity) == SQLITE_ROW)
            #expect(sqlite3_column_int64(identity, 0) == expectedID)
            #expect(CostUsageStore.columnText(identity, at: 1) == expectedHome)
        }
    }

    @Test(arguments: ["wrong-root", "missing-roots", "empty-roots"])
    func `v6 ambiguous native ownership fails without rewriting the store`(scenario: String) async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let rootA = env.root.appendingPathComponent("home-a/sessions", isDirectory: true)
        let rootB = env.root.appendingPathComponent("home-b/sessions", isDirectory: true)
        let databaseURL = CostUsageStore.databaseURL(cacheRoot: env.cacheRoot)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var rawDatabase: OpaquePointer?
        try #require(sqlite3_open(databaseURL.path, &rawDatabase) == SQLITE_OK)
        guard let database = rawDatabase else { throw CostUsageStore.StoreError.invalidData }
        defer { sqlite3_close(database) }
        try CostUsageStore.execute(database, "PRAGMA auto_vacuum = INCREMENTAL")
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CostUsage/store-v6-schema.sql")
        try CostUsageStore.execute(database, String(contentsOf: fixture, encoding: .utf8))
        let predecessorHash = "7d66d60c44b88609"
        let oldVersion = CostUsageStore.combinedSchemaVersion(base: 6, parserHash: predecessorHash)
        try CostUsageStore.execute(database, "PRAGMA user_version = \(oldVersion)")
        try CostUsageStore.writeMetaValue(predecessorHash, key: "parser_hash", database: database)
        var metadata = CostUsageStoreMetadata.empty
        metadata.rootMtimes = switch scenario {
        case "wrong-root": [rootB.path: 0]
        case "empty-roots": [:]
        default: nil
        }
        let metadataStatement = try CostUsageStore.prepare(
            database, "INSERT INTO scan_metadata(id, payload) VALUES (1, ?)")
        try CostUsageStore.bind(JSONEncoder().encode(metadata), to: metadataStatement, at: 1)
        try CostUsageStore.stepDone(metadataStatement, database: database)
        sqlite3_finalize(metadataStatement)
        let insert = try CostUsageStore.prepare(database, """
        INSERT INTO files(id, path, mtime_ms, size, scan_state, scan_complete, updated_at_ms)
        VALUES (?, ?, 1, 1, ?, 1, 1)
        """)
        for (id, root) in [(Int64(201), rootA), (Int64(202), rootB)] {
            sqlite3_reset(insert)
            sqlite3_clear_bindings(insert)
            sqlite3_bind_int64(insert, 1, id)
            CostUsageStore.bind(root.appendingPathComponent("history.jsonl").path, to: insert, at: 2)
            CostUsageStore.bind(Data("{\"isComplete\":true}".utf8), to: insert, at: 3)
            try CostUsageStore.stepDone(insert, database: database)
        }
        sqlite3_finalize(insert)

        let store = CostUsageStore(cacheRoot: env.cacheRoot, home: CodexHomeCostStoreScope.key(sessionsRoot: rootB))
        #expect(await store.configuration() == nil)
        #expect(await store.rebuildCount == 0)
        #expect(try CostUsageStore.scalarInt(database, "PRAGMA user_version") == Int64(oldVersion))
        #expect(try CostUsageStore.scalarInt(database, "SELECT COUNT(*) FROM files") == 2)
        #expect(try CostUsageStore.scalarInt(
            database,
            "SELECT COUNT(*) FROM pragma_table_info('files') WHERE name = 'home'") == 0)
        let statement = try CostUsageStore.prepare(database, "SELECT payload FROM scan_metadata WHERE id = 1")
        defer { sqlite3_finalize(statement) }
        try #require(sqlite3_step(statement) == SQLITE_ROW)
        let original = try #require(CostUsageStore.columnData(statement, at: 0))
        #expect(try JSONDecoder().decode(CostUsageStoreMetadata.self, from: original).rootMtimes == metadata.rootMtimes)
    }
}
