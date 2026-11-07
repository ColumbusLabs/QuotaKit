#if os(macOS)

import Foundation
import SQLite3
import Testing
@testable import CodexBarCore

struct OpenCodeGoLiteralPartTests {
    @Test
    func `literal nonbillable root types skip JSON parsing and other shapes retain accounting`() throws {
        var db: OpaquePointer?
        try #require(sqlite3_open(":memory:", &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        try Self.exec(db: db, sql: """
        CREATE TABLE message(id TEXT PRIMARY KEY, data TEXT, time_created INTEGER);
        CREATE TABLE part(id TEXT PRIMARY KEY, message_id TEXT, data TEXT, time_created INTEGER);
        """)
        let fixtures: [(json: String, expected: Double, skipsJSON: Bool)] = [
            (#"{"type":"tool","state":{"output":"synthetic"}}"#, 1, true),
            (#"{"type":"text","text":"synthetic","cost":9}"#, 1, true),
            (#"{"type":"tool","type":"step-finish","cost":9}"#, 1, true),
            (#"{"type":"tool","\u0074ype":"step-finish","cost":9}"#, 1, true),
            (#"{"type":"tool","state":{"type":"step-finish","cost":9}}"#, 1, true),
            (#"{"type":"tool","state":"#, 1, true),
            (#"{"type":"step-finish","type":"tool","cost":4}"#, 4, false),
            (#"{"\u0074ype":"step-finish","cost":5}"#, 5, false),
            (#"{"cost":6,"type":"step-finish"}"#, 6, false),
            (#"{ "type" : "step-finish", "cost" : 7 }"#, 7, false),
            (#"{"type":"step-\u0066inish","cost":8}"#, 8, false),
            (#"{"type":"step-finish","cost":0}"#, 0, false),
            (#"{"type":"step-finish","cost":"#, 1, false),
        ]
        var insertion: OpaquePointer?
        try #require(sqlite3_prepare_v2(
            db,
            "INSERT INTO part VALUES(?, ?, ?, 1772798399000)",
            -1,
            &insertion,
            nil) == SQLITE_OK)
        defer { sqlite3_finalize(insertion) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, fixture) in fixtures.enumerated() {
            try Self.exec(db: db, sql: """
            INSERT INTO message VALUES('\(index)',
            '{"role":"assistant","providerID":"opencode-go","cost":1}',1772798399000)
            """)
            sqlite3_reset(insertion)
            sqlite3_bind_text(insertion, 1, String(index), -1, transient)
            sqlite3_bind_text(insertion, 2, String(index), -1, transient)
            sqlite3_bind_text(insertion, 3, fixture.json, -1, transient)
            try #require(sqlite3_step(insertion) == SQLITE_DONE)
        }
        let probe = try JSONValidityProbe()
        try #require(sqlite3_create_function_v2(
            db,
            "json_valid",
            1,
            SQLITE_UTF8 | SQLITE_DETERMINISTIC,
            Unmanaged.passUnretained(probe).toOpaque(),
            { context, _, arguments in
                guard let context, let pointer = sqlite3_user_data(context), let value = arguments?[0] else { return }
                let probe = Unmanaged<JSONValidityProbe>.fromOpaque(pointer).takeUnretainedValue()
                if let text = sqlite3_value_text(value) {
                    probe.calls[String(cString: text), default: 0] += 1
                }
                sqlite3_reset(probe.statement)
                sqlite3_bind_value(probe.statement, 1, value)
                guard sqlite3_step(probe.statement) == SQLITE_ROW else {
                    sqlite3_result_error(context, "JSON validity probe failed", -1)
                    return
                }
                sqlite3_result_int(context, sqlite3_column_int(probe.statement, 0))
            },
            nil,
            nil,
            nil) == SQLITE_OK)
        defer {
            _ = withExtendedLifetime(probe) {
                sqlite3_create_function_v2(db, "json_valid", 1, SQLITE_UTF8, nil, nil, nil, nil, nil)
            }
        }
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(
            db,
            OpenCodeGoLocalUsageReader.messageAndPartUsageSQL,
            -1,
            &statement,
            nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var costs: [String: Double] = [:]
        var rowCount = 0
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            rowCount += 1
            let id = try #require(sqlite3_column_text(statement, 4))
            costs[String(cString: id)] = sqlite3_column_double(statement, 1)
            step = sqlite3_step(statement)
        }
        #expect(step == SQLITE_DONE)
        #expect(costs.count == fixtures.count)
        #expect(rowCount == fixtures.count)
        for (index, fixture) in fixtures.enumerated() {
            #expect(costs[String(index)] == fixture.expected)
            if fixture.skipsJSON {
                #expect(probe.calls[fixture.json, default: 0] == 0)
            } else {
                #expect(probe.calls[fixture.json, default: 0] > 0)
            }
        }
    }

    private final class JSONValidityProbe {
        private var database: OpaquePointer?
        var statement: OpaquePointer?
        var calls: [String: Int] = [:]

        init() throws {
            guard sqlite3_open(":memory:", &self.database) == SQLITE_OK else {
                sqlite3_close(self.database)
                self.database = nil
                throw SQLiteTestError.open
            }
            guard sqlite3_prepare_v2(self.database, "SELECT json_valid(?)", -1, &self.statement, nil) == SQLITE_OK
            else {
                sqlite3_finalize(self.statement)
                self.statement = nil
                sqlite3_close(self.database)
                self.database = nil
                throw SQLiteTestError.prepare
            }
        }

        deinit {
            sqlite3_finalize(self.statement)
            sqlite3_close(self.database)
        }
    }

    private static func exec(db: OpaquePointer?, sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            sqlite3_free(message)
            throw SQLiteTestError.exec
        }
    }

    private enum SQLiteTestError: Error {
        case open
        case prepare
        case exec
    }
}

#endif
