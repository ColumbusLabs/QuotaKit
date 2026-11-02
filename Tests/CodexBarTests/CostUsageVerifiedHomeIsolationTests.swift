import Foundation
import SQLite3
import Testing
@testable import CodexBarCore

struct CostUsageVerifiedHomeIsolationTests {
    @Test
    func `verified evidence and temporal aggregates remain isolated across homes`() throws {
        var connection: OpaquePointer?
        #expect(sqlite3_open(":memory:", &connection) == SQLITE_OK)
        let database = try #require(connection)
        defer { sqlite3_close(database) }
        let setup = """
        CREATE TABLE files(id INTEGER PRIMARY KEY, home TEXT NOT NULL, path TEXT NOT NULL);
        CREATE TABLE usage_rows(file_id INTEGER NOT NULL);
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE verified_day_aggregates(home TEXT NOT NULL, day TEXT NOT NULL, model TEXT NOT NULL);
        INSERT INTO files(id, home, path) VALUES (1, 'home-a', '/a'), (2, 'home-b', '/b');
        INSERT INTO usage_rows(file_id) VALUES (1), (2);
        """
        #expect(sqlite3_exec(database, setup, nil, nil, nil) == SQLITE_OK)
        try CostUsageStore.ensureTemporalAggregateTables(database)
        let fixtures = """
        INSERT INTO file_temporal_aggregates VALUES (1, 0, 100, '2026-10-01', 10, 1, 1, 1);
        INSERT INTO file_temporal_aggregates VALUES (2, 0, 100, '2026-10-01', 99, 9, 1, 1);
        INSERT INTO file_temporal_status(file_id) VALUES (1), (2);
        """
        #expect(sqlite3_exec(database, fixtures, nil, nil, nil) == SQLITE_OK)

        for home in ["home-a", "home-b"] {
            try CostUsageStore.markVerifiedDayStatus(database, home: home, day: "2026-10-01")
            _ = try CostUsageStore.persistVerifiedDayEvidence(
                database, home: home, days: ["2026-10-01"], scopeID: home)
            try CostUsageStore.replaceVerifiedTemporalAggregates(
                database, home: home, sinceDay: "2026-10-01", untilDay: "2026-10-01")
            try CostUsageStore.markVerifiedTemporalCoverageComplete(database, home: home)
        }
        let first = try CostUsageStore.readTemporalAggregates(
            database, home: "home-a", verified: true, sinceDay: "2026-10-01", untilDay: "2026-10-01")
        let second = try CostUsageStore.readTemporalAggregates(
            database, home: "home-b", verified: true, sinceDay: "2026-10-01", untilDay: "2026-10-01")
        #expect(first.first?.totalTokens == 10)
        #expect(second.first?.totalTokens == 99)
        #expect(try CostUsageStore.readVerifiedDayEvidence(database, home: "home-a")["2026-10-01"]?.scopeID == "home-a")
        #expect(try CostUsageStore.readVerifiedDayEvidence(database, home: "home-b")["2026-10-01"]?.scopeID == "home-b")

        try CostUsageStore.clearVerifiedDayAggregates(database, home: "home-a", days: ["2026-10-01"])
        #expect(try CostUsageStore.readVerifiedDayStatus(database, home: "home-a").isEmpty)
        #expect(try CostUsageStore.readVerifiedDayStatus(database, home: "home-b") == ["2026-10-01"])
        #expect(try CostUsageStore.readVerifiedDayEvidence(database, home: "home-b").count == 1)
        #expect(try CostUsageStore.verifiedTemporalCoverageIsComplete(database, home: "home-b"))
        #expect(try !CostUsageStore.verifiedTemporalCoverageIsComplete(database, home: "home-a"))
        #expect(try CostUsageStore.readTemporalAggregates(
            database, home: "home-b", verified: true, sinceDay: "2026-10-01", untilDay: "2026-10-01") == second)
    }
}
