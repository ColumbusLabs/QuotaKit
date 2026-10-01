import Foundation
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif
import Testing
@testable import CodexBarCore

#if canImport(SQLite3) || canImport(CSQLite3)
struct CostUsageThreadTitleTests {
    @Test
    func `sessions reuse database discovery for each distinct sqlite home`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let fileManager = ListingFileManager()

        let result = CostUsageFetcher.codexSessionsWithThreadTitles(
            fixture.sessions,
            sessionsRoot: fixture.home.appendingPathComponent("sessions", isDirectory: true),
            environment: ["CODEX_SQLITE_HOME": ".codex"],
            fileManager: fileManager)

        #expect(result == fixture.expected)
        #expect(fileManager.listings.count == fixture.sqliteHomes.count)
        #expect(Set(fileManager.listings) == Set(fixture.sqliteHomes))
    }

    @Test
    func `a later call discovers a newer state database and session index edit`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sessions = Array(fixture.sessions.prefix(2))
        let sessionsRoot = fixture.home.appendingPathComponent("sessions", isDirectory: true)
        let environment = ["CODEX_SQLITE_HOME": fixture.sqliteHomes[0].path]

        let first = CostUsageFetcher.codexSessionsWithThreadTitles(
            sessions, sessionsRoot: sessionsRoot, environment: environment)
        #expect(first.map(\.title) == ["Indexed title", "Home 0 session-1"])

        try Self.createDatabase(
            at: fixture.sqliteHomes[0].appendingPathComponent("state_10.sqlite"),
            titlePrefix: "Updated")
        try "{\"id\":\"session-0\",\"thread_name\":\"Renamed in index\"}\n".write(
            to: fixture.home.appendingPathComponent("session_index.jsonl"),
            atomically: true,
            encoding: .utf8)

        let second = CostUsageFetcher.codexSessionsWithThreadTitles(
            sessions, sessionsRoot: sessionsRoot, environment: environment)
        #expect(second.map(\.title) == ["Renamed in index", "Updated session-1"])
    }

    private struct Fixture {
        let root: URL
        let home: URL
        let sqliteHomes: [URL]
        let sessions: [CostUsageSessionBreakdown]
        let expected: [CostUsageSessionBreakdown]

        init() throws {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("cost-thread-titles-\(UUID().uuidString)", isDirectory: true)
            self.root = root
            self.home = root.appendingPathComponent("codex", isDirectory: true)
            let projects = (1...2).map { root.appendingPathComponent("project-\($0)", isDirectory: true) }
            self.sqliteHomes = [self.home] + projects.map { $0.appendingPathComponent(".codex", isDirectory: true) }
            try FileManager.default.createDirectory(at: self.home, withIntermediateDirectories: true)
            for (index, sqliteHome) in self.sqliteHomes.enumerated() {
                try FileManager.default.createDirectory(at: sqliteHome, withIntermediateDirectories: true)
                try CostUsageThreadTitleTests.createDatabase(
                    at: sqliteHome.appendingPathComponent("state_5.sqlite"),
                    titlePrefix: "Home \(index)")
            }
            try "{\"id\":\"session-0\",\"thread_name\":\"Indexed title\"}\n".write(
                to: self.home.appendingPathComponent("session_index.jsonl"),
                atomically: true,
                encoding: .utf8)
            self.sessions = (0..<30).map { index in
                var session = CostUsageSessionBreakdown(
                    sessionID: "session-\(index)",
                    lastActivity: Date(timeIntervalSince1970: Double(index)),
                    inputTokens: index,
                    cachedInputTokens: 1,
                    outputTokens: 2,
                    reasoningTokens: 1,
                    totalTokens: index + 2,
                    requestCount: 1,
                    costUSD: 0.01,
                    modelBreakdowns: [],
                    projectPath: "/synthetic/canonical",
                    projectName: "Synthetic",
                    title: "Original")
                session.workingDirectory = index % 3 == 0 ? nil : projects[index % 3 - 1].path
                return session
            }
            self.expected = self.sessions.enumerated().map { index, session in
                session.withTitle(index == 0 ? "Indexed title" : "Home \(index % 3) \(session.sessionID)")
            }
        }

        func remove() {
            try? FileManager.default.removeItem(at: self.root)
        }
    }

    private static func createDatabase(at url: URL, titlePrefix: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw NSError(domain: "CostUsageThreadTitleTests", code: 1)
        }
        defer { sqlite3_close(database) }
        let rows = (0..<30).map { index in
            "('session-\(index)', '\(titlePrefix) session-\(index)')"
        }.joined(separator: ",")
        let sql = "CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT); INSERT INTO threads VALUES \(rows);"
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "CostUsageThreadTitleTests", code: 2)
        }
    }
}

private final class ListingFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URL] = []

    var listings: [URL] {
        self.lock.withLock { self.recorded }
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []) throws -> [URL]
    {
        self.lock.withLock { self.recorded.append(url) }
        return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
    }
}
#endif
