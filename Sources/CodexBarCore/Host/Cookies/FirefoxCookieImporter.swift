#if os(macOS)
import Foundation
import SQLite3

/// Reads cookies from Firefox profile cookie DBs (macOS).
enum FirefoxCookieImporter {
    enum ImportError: LocalizedError {
        case cookieDBNotFound(path: String)
        case cookieDBNotReadable(path: String)
        case sqliteFailed(message: String)

        var errorDescription: String? {
            switch self {
            case let .cookieDBNotFound(path): "Firefox cookie DB not found at \(path)."
            case let .cookieDBNotReadable(path):
                "Firefox cookie DB exists but is not readable (\(path))."
            case let .sqliteFailed(message): "Failed to read Firefox cookies: \(message)"
            }
        }
    }

    struct CookieRecord: Sendable {
        let host: String
        let name: String
        let path: String
        let value: String
        let expires: Date?
        let isSecure: Bool
        let isHTTPOnly: Bool
    }

    struct CookieSource: Sendable {
        let label: String
        let records: [CookieRecord]
    }

    static func loadChatGPTCookiesFromAllProfiles() throws -> [CookieSource] {
        try self.loadCookiesFromAllProfiles(matchingDomains: ["chatgpt.com", "openai.com"])
    }

    static func loadCookiesFromAllProfiles(matchingDomains domains: [String]) throws -> [CookieSource] {
        let roots: [(url: URL, labelPrefix: String)] = self.candidateHomes().map { home in
            let root = home
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent("Firefox")
                .appendingPathComponent("Profiles")
            return (root, "Firefox")
        }

        var candidates: [FirefoxProfileCandidate] = []
        for root in roots {
            candidates.append(contentsOf: Self.firefoxProfileCookieDBs(root: root.url, labelPrefix: root.labelPrefix))
        }
        if candidates.isEmpty {
            let display = roots.map(\.url.path).joined(separator: " • ")
            throw ImportError.cookieDBNotFound(path: display)
        }

        return try candidates.compactMap { candidate in
            guard FileManager.default.fileExists(atPath: candidate.cookiesDB.path) else { return nil }
            let records = try Self.readCookiesFromLockedFirefoxDB(
                sourceDB: candidate.cookiesDB,
                matchingDomains: domains)
            guard !records.isEmpty else { return nil }
            return CookieSource(label: candidate.label, records: records)
        }
    }

    // MARK: - DB copy helper

    private static func readCookiesFromLockedFirefoxDB(
        sourceDB: URL,
        matchingDomains: [String]) throws -> [CookieRecord]
    {
        guard FileManager.default.isReadableFile(atPath: sourceDB.path) else {
            throw ImportError.cookieDBNotReadable(path: sourceDB.path)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-firefox-cookies-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let copiedDB = tempDir.appendingPathComponent("cookies.sqlite")
        try FileManager.default.copyItem(at: sourceDB, to: copiedDB)

        for suffix in ["-wal", "-shm"] {
            let src = URL(fileURLWithPath: sourceDB.path + suffix)
            if FileManager.default.fileExists(atPath: src.path) {
                let dst = URL(fileURLWithPath: copiedDB.path + suffix)
                try? FileManager.default.copyItem(at: src, to: dst)
            }
        }

        defer { try? FileManager.default.removeItem(at: tempDir) }

        return try Self.readCookies(fromDB: copiedDB.path, matchingDomains: matchingDomains)
    }

    // MARK: - SQLite read

    private static func readCookies(fromDB path: String, matchingDomains: [String]) throws -> [CookieRecord] {
        var db: OpaquePointer?
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            throw ImportError.sqliteFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_close(db) }

        let conditions = matchingDomains.map { "host LIKE '%\($0)%'" }.joined(separator: " OR ")
        let sql = """
        SELECT host, name, path, value, expiry, isSecure, isHttpOnly
        FROM moz_cookies
        WHERE \(conditions)
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw ImportError.sqliteFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var out: [CookieRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let host = Self.readTextColumn(stmt, index: 0),
                  let name = Self.readTextColumn(stmt, index: 1),
                  let path = Self.readTextColumn(stmt, index: 2),
                  let value = Self.readTextColumn(stmt, index: 3)
            else { continue }

            let expiry = sqlite3_column_int64(stmt, 4)
            let isSecure = sqlite3_column_int(stmt, 5) != 0
            let isHTTPOnly = sqlite3_column_int(stmt, 6) != 0

            let expiresDate = expiry > 0 ? Date(timeIntervalSince1970: TimeInterval(expiry)) : nil

            out.append(CookieRecord(
                host: Self.normalizeDomain(host),
                name: name,
                path: path,
                value: value,
                expires: expiresDate,
                isSecure: isSecure,
                isHTTPOnly: isHTTPOnly))
        }

        return out
    }

    private static func readTextColumn(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    // MARK: - Conversion

    static func makeHTTPCookies(_ records: [CookieRecord]) -> [HTTPCookie] {
        records.compactMap { record in
            let domain = Self.normalizeDomain(record.host)
            guard !domain.isEmpty else { return nil }
            var props: [HTTPCookiePropertyKey: Any] = [
                .domain: domain,
                .path: record.path,
                .name: record.name,
                .value: record.value,
                .secure: record.isSecure,
            ]
            props[.originURL] = Self.originURL(forDomain: domain)
            if record.isHTTPOnly {
                props[.init("HttpOnly")] = "TRUE"
            }
            if let expires = record.expires {
                props[.expires] = expires
            }
            return HTTPCookie(properties: props)
        }
    }

    private static func normalizeDomain(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(".") { return String(trimmed.dropFirst()) }
        return trimmed
    }

    private static func originURL(forDomain domain: String) -> URL {
        let d = domain.lowercased()
        if d.contains("openai.com") {
            return URL(string: "https://openai.com")!
        }
        return URL(string: "https://chatgpt.com")!
    }

    // MARK: - Profile discovery

    private struct FirefoxProfileCandidate: Sendable {
        let label: String
        let cookiesDB: URL
    }

    private static func firefoxProfileCookieDBs(root: URL, labelPrefix: String) -> [FirefoxProfileCandidate] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        let profileDirs = entries.filter { url in
            guard let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory), isDir else {
                return false
            }
            return true
        }
        .sorted { lhs, rhs in
            let left = Self.profileSortKey(lhs.lastPathComponent)
            let right = Self.profileSortKey(rhs.lastPathComponent)
            if left.rank != right.rank { return left.rank < right.rank }
            return left.name < right.name
        }

        return profileDirs.map { dir in
            let label = "\(labelPrefix) \(dir.lastPathComponent)"
            let cookiesDB = dir.appendingPathComponent("cookies.sqlite")
            return FirefoxProfileCandidate(label: label, cookiesDB: cookiesDB)
        }
    }

    private static func profileSortKey(_ name: String) -> (rank: Int, name: String) {
        let lower = name.lowercased()
        if lower.contains("default-release") { return (0, lower) }
        if lower.contains("default") { return (1, lower) }
        return (2, lower)
    }

    private static func candidateHomes() -> [URL] {
        var homes: [URL] = []
        homes.append(FileManager.default.homeDirectoryForCurrentUser)
        if let userHome = NSHomeDirectoryForUser(NSUserName()) {
            homes.append(URL(fileURLWithPath: userHome))
        }
        if let envHome = ProcessInfo.processInfo.environment["HOME"], !envHome.isEmpty {
            homes.append(URL(fileURLWithPath: envHome))
        }
        var seen = Set<String>()
        return homes.filter { home in
            let path = home.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }
}
#endif
