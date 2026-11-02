import Foundation
import Testing
@testable import CodexBarCore
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

@Suite(.serialized)
struct CostUsageSafeRebuildTests {
    @Test(arguments: [
        "present", "disappears", "missing", "compressed", "imported", "directory", "unreadable", "unknown-hash",
        "snapshot-failure",
    ])
    func `only present native source files permit a recovery rebuild`(scenario: String) async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let plain = env.codexSessionsRoot.appendingPathComponent("rollout.jsonl")
        switch scenario {
        case "present", "disappears", "unreadable", "unknown-hash", "snapshot-failure":
            try Data("fixture".utf8).write(to: plain)
        case "directory":
            try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        case "compressed":
            try Data("compressed fixture".utf8).write(to: plain.appendingPathExtension("zst"))
        case "imported":
            try Data("fixture".utf8).write(to: plain)
        default: break
        }
        let store = CostUsageStore(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        let databaseURL = store.databaseURL
        let source = scenario == "imported" ? "opencodeLocalHistory" : "nativeCodexSessionLogs"
        let fixtureHome = env.codexStoreHome
        let seeded = await store.withDatabase(default: false) { database in
            let statement = try CostUsageStore.prepare(database, """
            INSERT INTO files(home, path, mtime_ms, size, scan_state, scan_complete, updated_at_ms)
            VALUES (?, ?, 1, 1, ?, 1, 1)
            """)
            defer { sqlite3_finalize(statement) }
            CostUsageStore.bind(fixtureHome, to: statement, at: 1)
            CostUsageStore.bind(plain.path, to: statement, at: 2)
            CostUsageStore.bind(Data("{\"source\":\"\(source)\",\"isComplete\":true}".utf8), to: statement, at: 3)
            try CostUsageStore.stepDone(statement, database: database)
            if scenario == "unknown-hash" {
                let unknownHash = "unknown-synthetic-parser"
                try CostUsageStore.writeMetaValue(unknownHash, key: "parser_hash", database: database)
                let version = CostUsageStore.combinedSchemaVersion(
                    base: CostUsageStore.baseSchemaVersion, parserHash: unknownHash)
                try CostUsageStore.execute(database, "PRAGMA user_version = \(version)")
            }
            return true
        }
        try #require(seeded)
        // Keep a reader pinned so SQLite cannot checkpoint away the existing WAL while the
        // recovery attempt closes and reopens the writer connection.
        var reader: OpaquePointer?
        try #require(sqlite3_open(databaseURL.path, &reader) == SQLITE_OK)
        guard let reader else { throw CostUsageStore.StoreError.invalidData }
        defer { sqlite3_close(reader) }
        try CostUsageStore.execute(reader, "BEGIN")
        #expect(try CostUsageStore.scalarInt(reader, "SELECT COUNT(*) FROM files") == 1)
        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
        let beforeDatabase = try Data(contentsOf: databaseURL)
        let beforeWAL = try Data(contentsOf: walURL)

        let openProbe = RebuildOpenProbe()
        var hooks = CostUsageStoreTestHooks.current
        if scenario == "disappears" {
            hooks.rebuildAfterFileValidation = { try? FileManager.default.removeItem(at: plain) }
        } else if scenario == "unreadable" {
            hooks.rebuildSourceOpenFailure = { path in
                guard path == plain.path else { return false }
                openProbe.record()
                return true
            }
        } else if scenario == "snapshot-failure" {
            let directory = databaseURL.deletingLastPathComponent()
            hooks.rebuildAfterFileValidation = {
                try? FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            }
        }
        let recoveryStore = CostUsageStore(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        let result = await CostUsageStoreTestHooks.$current.withValue(hooks) {
            await recoveryStore.withDatabase(default: false) { database in
                if try CostUsageStore.scalarInt(database, "SELECT COUNT(*) FROM files") > 0 {
                    throw CostUsageStore.StoreError.invalidData
                }
                return true
            }
        }
        if scenario == "unreadable" {
            #expect(openProbe.wasCalled)
            #expect(try FileManager.default.attributesOfItem(atPath: plain.path)[.type] as? FileAttributeType
                == .typeRegular)
        }
        if scenario == "snapshot-failure" {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: databaseURL.deletingLastPathComponent().path)
        }
        if scenario == "present" || scenario == "disappears" || scenario == "unknown-hash" {
            if scenario == "disappears" { #expect(!FileManager.default.fileExists(atPath: plain.path)) }
            #expect(result)
            #expect(await recoveryStore.rebuildCount == 1)
            let recovery = try FileManager.default.contentsOfDirectory(
                at: databaseURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil).filter {
                $0.lastPathComponent.hasPrefix("cost-usage-recovery-") && $0.pathExtension == "sqlite"
            }
            let backupURL = try #require(recovery.first)
            #expect(recovery.count == 1)
            let permissions = try #require(
                FileManager.default.attributesOfItem(atPath: backupURL.path)[.posixPermissions] as? NSNumber)
            #expect(permissions.intValue & 0o777 == 0o600)
            var backup: OpaquePointer?
            try #require(sqlite3_open_v2(backupURL.path, &backup, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
            guard let backup else { throw CostUsageStore.StoreError.invalidData }
            defer { sqlite3_close(backup) }
            #expect(try CostUsageStore.scalarInt(backup, "SELECT COUNT(*) FROM files") == 1)
        } else {
            #expect(!result)
            #expect(await recoveryStore.rebuildCount == 0)
            #expect(try Data(contentsOf: databaseURL) == beforeDatabase)
            #expect(try Data(contentsOf: walURL) == beforeWAL)
            #expect(try CostUsageStore.scalarInt(reader, "SELECT COUNT(*) FROM files") == 1)
        }
        try CostUsageStore.execute(reader, "ROLLBACK")
    }

    @Test
    func `unknown v6 parser rebuilds only after saving the old ledger`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let plain = env.codexSessionsRoot.appendingPathComponent("old.jsonl")
        try Data("fixture".utf8).write(to: plain)
        let url = CostUsageStore.databaseURL(cacheRoot: env.cacheRoot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var raw: OpaquePointer?
        try #require(sqlite3_open(url.path, &raw) == SQLITE_OK)
        guard let raw else { throw CostUsageStore.StoreError.invalidData }
        try CostUsageStore.execute(raw, "PRAGMA auto_vacuum = INCREMENTAL")
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CostUsage/store-v6-schema.sql")
        try CostUsageStore.execute(raw, String(contentsOf: fixture, encoding: .utf8))
        let unknownHash = "unknown-synthetic-v6-parser"
        let version = CostUsageStore.combinedSchemaVersion(base: 6, parserHash: unknownHash)
        try CostUsageStore.writeMetaValue(unknownHash, key: "parser_hash", database: raw)
        try CostUsageStore.execute(raw, "PRAGMA user_version = \(version)")
        let insert = try CostUsageStore.prepare(raw, """
        INSERT INTO files(id, path, mtime_ms, size, scan_state, scan_complete, updated_at_ms)
        VALUES (31, ?, 1, 1, ?, 1, 1)
        """)
        CostUsageStore.bind(plain.path, to: insert, at: 1)
        CostUsageStore.bind(Data("{\"isComplete\":true}".utf8), to: insert, at: 2)
        try CostUsageStore.stepDone(insert, database: raw)
        sqlite3_finalize(insert)
        sqlite3_close(raw)

        let store = CostUsageStore(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        #expect(await store.configuration()?.userVersion == Int(CostUsageStore.schemaVersion))
        #expect(await store.rebuildCount == 1)
        let recoveries = try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter {
            $0.lastPathComponent.hasPrefix("cost-usage-recovery-") && $0.pathExtension == "sqlite"
        }
        let backupURL = try #require(recoveries.first)
        #expect(recoveries.count == 1)
        let permissions = try #require(
            FileManager.default.attributesOfItem(atPath: backupURL.path)[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)
        var backup: OpaquePointer?
        try #require(sqlite3_open_v2(backupURL.path, &backup, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        guard let backup else { throw CostUsageStore.StoreError.invalidData }
        defer { sqlite3_close(backup) }
        #expect(try CostUsageStore.scalarInt(backup, "PRAGMA user_version") == Int64(version))
        #expect(try CostUsageStore.scalarInt(backup, "SELECT id FROM files") == 31)
    }

    @Test
    func `a damaged store and its WAL remain available after failed recovery`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let url = CostUsageStore.databaseURL(cacheRoot: env.cacheRoot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let damaged = Data("unreadable synthetic database".utf8)
        let wal = Data("preserve synthetic wal".utf8)
        let walURL = URL(fileURLWithPath: url.path + "-wal")
        try damaged.write(to: url)
        try wal.write(to: walURL)
        let store = CostUsageStore(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        #expect(await store.configuration() == nil)
        #expect(await store.rebuildCount == 0)
        #expect(try Data(contentsOf: url) == damaged)
        #expect(try Data(contentsOf: walURL) == wal)
    }
}

private final class RebuildOpenProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func record() { self.lock.withLock { self.count += 1 } }
    var wasCalled: Bool {
        self.lock.withLock { self.count > 0 }
    }
}
