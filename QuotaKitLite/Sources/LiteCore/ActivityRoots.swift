import Foundation

/// Which directories show that a provider's CLI or app is being used, and how to map a changed path back to
/// its provider (068 §5.1). Pure path logic: it never touches the file system and never reads a file.
///
/// FSEvents without the file-level flag reports the directory that contains a change. So a write to
/// `auth.json` arrives as its directory (`~/.codex`), and a session log write arrives as the session's
/// subdirectory. Two kinds of root follow from that:
///
/// - an *activity root* (session logs, projects): any change at or below it counts;
/// - a *credential directory* (where `auth.json` or `.credentials.json` lives): only changes directly in it
///   count, not changes in its other subdirectories, so unrelated churn there doesn't wake Lite.
public struct ActivityRoots: Sendable, Equatable {
    public struct Root: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            /// Changes at or below this path count.
            case tree
            /// Only changes whose directory is exactly this path count.
            case directoryOnly
        }

        public var path: String
        public var provider: LiteProvider
        public var kind: Kind
    }

    public let roots: [Root]

    /// - Parameters:
    ///   - homeDirectory: the user's home, without a trailing slash.
    ///   - environment: process environment, for `CODEX_HOME` and `CLAUDE_CONFIG_DIR`.
    ///   - resolve: normalises each root, for example by resolving symlinks, because FSEvents reports real
    ///     paths. It must not read file contents.
    public init(
        homeDirectory: String,
        environment: [String: String] = [:],
        resolve: (String) -> String = { $0 })
    {
        let claudeHome = Self.directory(
            environment["CLAUDE_CONFIG_DIR"],
            default: "\(homeDirectory)/.claude",
            home: homeDirectory)
        let codexHome = Self.directory(
            environment["CODEX_HOME"],
            default: "\(homeDirectory)/.codex",
            home: homeDirectory)
        let raw: [Root] = [
            Root(path: "\(claudeHome)/projects", provider: .claude, kind: .tree),
            Root(path: claudeHome, provider: .claude, kind: .directoryOnly),
            Root(path: "\(codexHome)/sessions", provider: .codex, kind: .tree),
            Root(path: codexHome, provider: .codex, kind: .directoryOnly),
            Root(path: "\(homeDirectory)/.gemini/antigravity", provider: .antigravity, kind: .tree),
        ]
        self.roots = raw.map { root in
            var resolved = root
            resolved.path = Self.trimmed(resolve(root.path))
            return resolved
        }
    }

    /// The paths to hand to FSEvents. FSEvents watches recursively, so a root inside another is dropped.
    public var watchPaths: [String] {
        let unique = Array(Set(self.roots.map(\.path))).sorted()
        return unique.filter { path in
            !unique.contains { other in other != path && Self.isInside(path, of: other) }
        }
    }

    /// The provider an FSEvents path belongs to, or nil if it matches no root.
    public func provider(forEventPath eventPath: String) -> LiteProvider? {
        let path = Self.trimmed(eventPath)
        for root in self.roots {
            switch root.kind {
            case .tree where path == root.path || Self.isInside(path, of: root.path):
                return root.provider
            case .directoryOnly where path == root.path:
                return root.provider
            default:
                continue
            }
        }
        return nil
    }

    /// The providers with activity among a batch of event paths, in `LiteProvider.allCases` order.
    public func providers(forEventPaths eventPaths: [String]) -> [LiteProvider] {
        let found = Set(eventPaths.compactMap { self.provider(forEventPath: $0) })
        return LiteProvider.allCases.filter { found.contains($0) }
    }

    // MARK: - Paths

    private static func directory(_ value: String?, default fallback: String, home: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }
        if value == "~" { return home }
        if value.hasPrefix("~/") { return home + String(value.dropFirst(1)) }
        return self.trimmed(value)
    }

    private static func trimmed(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    private static func isInside(_ path: String, of root: String) -> Bool {
        path.hasPrefix(root + "/")
    }
}
