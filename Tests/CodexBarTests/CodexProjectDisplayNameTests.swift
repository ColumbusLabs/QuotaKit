import Foundation
@testable import CodexBarCore
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif
import Testing

#if canImport(SQLite3) || canImport(CSQLite3)
struct CodexProjectDisplayNameTests {
    @Test
    func `saved names choose the nearest root and reject ambiguous or partial matches`() throws {
        try Self.withDatabase { database in
            try Self.execute(database, """
            INSERT INTO projects VALUES ('outer', 'My Workspace'), ('inner', 'Nested Project'),
                ('other', 'Other'), ('blank', '  ');
            INSERT INTO project_roots VALUES ('outer', '/work'), ('inner', '/work/nested'),
                ('other', '/ambiguous'), ('outer', '/ambiguous'), ('blank', '/blank');
            """)

            let names = CodexThreadMetadataReader(databaseURL: database).projectNames(for: [
                "/work", "/work/sub", "/work/nested/src", "/worker", "/ambiguous", "/blank",
            ])
            #expect(names == [
                "/work": "My Workspace",
                "/work/sub": "My Workspace",
                "/work/nested/src": "Nested Project",
            ])

            try Self.execute(database, "UPDATE projects SET name = 'Renamed' WHERE id = 'outer'")
            #expect(CodexThreadMetadataReader(databaseURL: database).projectNames(for: ["/work"])["/work"]
                == "Renamed")
        }
    }

    @Test
    func `saved labels update cached presentation without changing accounting`() throws {
        try Self.withDatabase { database in
            try Self.execute(database, """
            INSERT INTO projects VALUES ('project', 'Saved Workspace');
            INSERT INTO project_roots VALUES ('project', '/work');
            """)

            let project = CostUsageProjectBreakdown(
                name: "work",
                path: "/work",
                totalTokens: 13,
                totalCostUSD: 1,
                daily: [],
                modelBreakdowns: [],
                sources: [CostUsageProjectSourceBreakdown(
                    name: "work",
                    path: "/work",
                    totalTokens: 13,
                    totalCostUSD: 1,
                    daily: [],
                    modelBreakdowns: [])])
            var session = CostUsageSessionBreakdown(
                sessionID: "session",
                lastActivity: Date(timeIntervalSince1970: 0),
                inputTokens: 10,
                cachedInputTokens: 2,
                outputTokens: 3,
                totalTokens: 13,
                requestCount: 1,
                costUSD: 1,
                modelBreakdowns: [],
                projectPath: "/work",
                projectName: "work",
                title: "Existing title")
            session.workingDirectory = "/work"

            let sessionsRoot = database.deletingLastPathComponent().appendingPathComponent("sessions")
            let result = CostUsageFetcher.codexBreakdownsWithMetadata(
                [session],
                projects: [project],
                sessionsRoot: sessionsRoot,
                environment: [:])

            #expect(result.projects[0].name == "Saved Workspace")
            #expect(result.projects[0].path == project.path)
            #expect(result.projects[0].totalTokens == project.totalTokens)
            #expect(result.projects[0].totalCostUSD == project.totalCostUSD)
            #expect(result.sessions[0].projectName == "Saved Workspace")
            #expect(result.sessions[0].title == session.title)
            #expect(result.sessions[0].totalTokens == session.totalTokens)
            #expect(result.sessions[0].costUSD == session.costUSD)
        }
    }

    @Test
    func `relative database homes preserve conflicting and unproven project labels`() throws {
        try Self.withDatabase { database in
            let home = database.deletingLastPathComponent()
            var sources: [CostUsageProjectSourceBreakdown] = []
            for label in ["First", "Second"] {
                let workingDirectory = home.appendingPathComponent(label, isDirectory: true)
                let sqliteHome = workingDirectory.appendingPathComponent("state", isDirectory: true)
                try FileManager.default.createDirectory(at: sqliteHome, withIntermediateDirectories: true)
                try Self.execute(sqliteHome.appendingPathComponent("state_5.sqlite"), """
                CREATE TABLE projects (id TEXT, name TEXT);
                CREATE TABLE project_roots (project_id TEXT, path TEXT);
                INSERT INTO projects VALUES ('project', '\(label)');
                INSERT INTO project_roots VALUES ('project', '/work'), ('project', '\(workingDirectory.path)');
                """)
                sources.append(CostUsageProjectSourceBreakdown(
                    name: label,
                    path: workingDirectory.path,
                    totalTokens: 13,
                    totalCostUSD: 1,
                    daily: [],
                    modelBreakdowns: []))
            }
            func project(
                _ sources: [CostUsageProjectSourceBreakdown],
                path: String = "/work") -> CostUsageProjectBreakdown
            {
                CostUsageProjectBreakdown(
                    name: "work",
                    path: path,
                    totalTokens: 26,
                    totalCostUSD: 2,
                    daily: [],
                    modelBreakdowns: [],
                    sources: sources)
            }
            let first = project([sources[0]])
            let combined = project(sources)
            let mixed = project([sources[0], CostUsageProjectSourceBreakdown(
                name: "Unknown",
                path: nil,
                totalTokens: nil,
                totalCostUSD: nil,
                daily: [],
                modelBreakdowns: nil)])
            let unproven = try project([], path: #require(sources[0].path))
            var lookupPaths: [URL: Set<String>] = [:]
            let renamed = CostUsageFetcher.codexBreakdownsWithMetadata(
                [],
                projects: [first, combined, mixed, unproven],
                sessionsRoot: home.appendingPathComponent("sessions"),
                environment: ["CODEX_SQLITE_HOME": "state"],
                projectNameLookup: { url, paths in
                    #expect(lookupPaths[url] == nil, "Each SQLite database should be queried once per load")
                    lookupPaths[url] = paths
                    return CodexThreadMetadataReader(databaseURL: url).projectNames(for: paths)
                }).projects
            var expectedFirst = first
            expectedFirst.name = "First"
            #expect(renamed == [expectedFirst, combined, mixed, unproven])
            #expect(lookupPaths.count == 2)
            #expect(lookupPaths.values.allSatisfy { !$0.isEmpty })
            #expect(CostUsageFetcher.codexBreakdownsWithMetadata(
                [], projects: [combined], sessionsRoot: nil, environment: [:]).projects == [combined])
        }
    }

    @Test
    func `missing project tables or databases preserve folder labels without creating files`() throws {
        try Self.withDatabase { database in
            try Self.execute(database, "DROP TABLE project_roots; DROP TABLE projects;")
            #expect(CodexThreadMetadataReader(databaseURL: database).projectNames(for: ["/work"]).isEmpty)

            let missing = database.deletingLastPathComponent().appendingPathComponent("missing.sqlite")
            #expect(CodexThreadMetadataReader(databaseURL: missing).projectNames(for: ["/work"]).isEmpty)
            #expect(!FileManager.default.fileExists(atPath: missing.path))
        }
    }

    private static func withDatabase(_ body: (URL) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-project-names-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appendingPathComponent("state_5.sqlite")
        try Self.execute(database, """
        CREATE TABLE projects (id TEXT PRIMARY KEY, name TEXT);
        CREATE TABLE project_roots (project_id TEXT, path TEXT);
        """)
        try body(database)
    }

    private static func execute(_ databaseURL: URL, _ sql: String) throws {
        var database: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        let handle = try #require(database)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
    }
}
#endif
