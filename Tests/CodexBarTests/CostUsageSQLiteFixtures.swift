#if canImport(SQLite3)
import Foundation
import SQLite3

enum CostUsageSQLiteFixtures {
    static func createTestLogsDatabase(at dbURL: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { throw FixtureError.open }
        defer { sqlite3_close(db) }

        try self.execute(
            db,
            "create table logs (id integer primary key autoincrement, ts integer not null, feedback_log_body text)")
        try self.execute(db, "create index idx_logs_ts on logs(ts desc, id desc)")
    }

    static func insertTestLog(dbURL: URL, timestamp: String, body: String) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let epochSeconds = formatter.date(from: timestamp).map { Int64($0.timeIntervalSince1970) } ?? 0
        try self.insertTestLog(dbURL: dbURL, epochSeconds: epochSeconds, body: body)
    }

    static func insertTestLog(dbURL: URL, epochSeconds: Int64, body: String) throws {
        try self.insertTestLogs(dbURL: dbURL, rows: [(epochSeconds: epochSeconds, body: body)])
    }

    static func insertTestLogs(dbURL: URL, rows: [(epochSeconds: Int64, body: String)]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { throw FixtureError.open }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "insert into logs (ts, feedback_log_body) values (?, ?)", -1, &statement, nil)
            == SQLITE_OK
        else { throw FixtureError.prepare }
        defer { sqlite3_finalize(statement) }

        try self.execute(db, "begin transaction")
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for row in rows {
            sqlite3_bind_int64(statement, 1, row.epochSeconds)
            sqlite3_bind_text(statement, 2, row.body, -1, transient)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw FixtureError.step }
            sqlite3_reset(statement)
        }
        try self.execute(db, "commit")
    }

    private static func execute(_ db: OpaquePointer?, _ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            sqlite3_free(message)
            throw FixtureError.execute
        }
    }

    private enum FixtureError: Error {
        case open
        case prepare
        case step
        case execute
    }
}
#endif
