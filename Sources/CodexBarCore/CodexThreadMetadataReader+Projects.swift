#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif
import Foundation

extension CodexThreadMetadataReader {
    /// Saved project names are presentation metadata, never ledger keys. Older Codex databases
    /// may not have these tables; missing, ambiguous, or unreadable metadata keeps the folder label.
    func projectNames(for paths: Set<String>) -> [String: String] {
        guard !paths.isEmpty else { return [:] }
        #if canImport(SQLite3) || canImport(CSQLite3)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(self.databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database = handle
        else {
            if let handle { sqlite3_close(handle) }
            return [:]
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)
        sqlite3_progress_handler(database, 100_000, { _ in 1 }, nil)
        let query = """
        SELECT p.id, p.name, r.path FROM projects p
        JOIN project_roots r ON r.project_id = p.id LIMIT 1025
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }
        var roots: [(id: String, name: String, path: String)] = []
        var count = 0
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW, count < 1024 else { return [:] }
            count += 1
            guard let id = Self.string(statement, column: 0),
                  let name = Self.string(statement, column: 1),
                  let rawPath = Self.string(statement, column: 2),
                  (rawPath as NSString).isAbsolutePath
            else { continue }
            roots.append((id, name, URL(fileURLWithPath: rawPath).standardizedFileURL.path))
        }
        var result: [String: String] = [:]
        for path in paths where (path as NSString).isAbsolutePath {
            let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
            let matches = roots.filter {
                normalized == $0.path || normalized.hasPrefix($0.path == "/" ? "/" : $0.path + "/")
            }
            guard let length = matches.map(\.path.count).max() else { continue }
            let closest = matches.filter { $0.path.count == length }
            guard Set(closest.map(\.id)).count == 1 else { continue }
            result[path] = closest.first?.name
        }
        return result
        #else
        return [:]
        #endif
    }
}
