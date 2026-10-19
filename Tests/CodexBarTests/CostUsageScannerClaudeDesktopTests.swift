import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageScannerClaudeDesktopTests {
    @Test
    func `reports unreadable claude swap session inventory to the cost refresh`() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CostUsageScanner-ClaudeSwapUnreadable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let sessions = home.appendingPathComponent(".claude-swap-backup/sessions", isDirectory: true)
        let fileManager = FailingDirectoryListingFileManager(path: sessions.path)
        var errors: [Error] = []
        _ = ClaudeConfigPaths.costProjectsRoots(
            environment: ["HOME": home.path],
            homeDirectory: home,
            fileManager: fileManager)
        { error in errors.append(error) }

        #expect(errors.count == 1)
        #expect((errors.first as NSError?)?.code == 13)
    }

    @Test
    func `keeps claude swap shared projects directory symlinks as roots`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CostUsageScanner-ClaudeSwapSymlink-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let sharedProjects = root.appendingPathComponent("shared-projects", isDirectory: true)
        let sessions = home.appendingPathComponent(".claude-swap-backup/sessions", isDirectory: true)
        let slot = sessions.appendingPathComponent("2-personal", isDirectory: true)
        let linkedProjects = slot.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: sharedProjects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: linkedProjects, withDestinationURL: sharedProjects)

        let roots = ClaudeConfigPaths.costProjectsRoots(
            environment: ["HOME": home.path],
            homeDirectory: home)

        #expect(roots.contains { $0.standardizedFileURL.path == linkedProjects.standardizedFileURL.path })
    }

    @Test
    func `desktop project discovery keeps symlinked projects roots`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let localAgentRoot = env.root
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent("local-agent-mode-sessions", isDirectory: true)
            .appendingPathComponent("workspace-id", isDirectory: true)
            .appendingPathComponent("session-id", isDirectory: true)
            .appendingPathComponent("local_agent", isDirectory: true)
        let projectsLink = localAgentRoot
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        let projectsTarget = env.root.appendingPathComponent("shared-projects", isDirectory: true)
        try FileManager.default.createDirectory(
            at: projectsLink.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectsTarget, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: projectsLink, withDestinationURL: projectsTarget)

        let roots = ClaudeDesktopProjectsLocator.roots(homeDirectory: env.root)
        #expect(roots.contains(projectsLink.standardizedFileURL))
    }

    @Test(.enabled(if: getuid() != 0, "root ignores directory permissions"))
    func `desktop discovery surfaces unreadable project parents`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let audit = try env.writeClaudeDesktopLocalAgentFile(relativePath: "audit.jsonl", contents: "")
        let unreadableParent = audit.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadableParent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unreadableParent.path)
        }

        var errors: [Error] = []
        _ = ClaudeDesktopProjectsLocator.roots(homeDirectory: env.root) { errors.append($0) }

        #expect(!errors.isEmpty)
    }

    @Test
    func `Cowork audit usage shares native response deduplication`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 10, day: 16)
        func assistant(session: String, output: Int) -> [String: Any] {
            [
                "type": "assistant", "timestamp": env.isoString(for: day), "session_id": session,
                "message": [
                    "id": "response-a", "model": "claude-test-model",
                    "usage": ["input_tokens": 10, "output_tokens": output],
                ],
            ]
        }
        let response = assistant(session: "cowork-a", output: 5)
        let audit = try env.writeClaudeDesktopLocalAgentFile(
            relativePath: "audit.jsonl",
            contents: env.jsonl([
                assistant(session: "cowork-a", output: 1), response,
                assistant(session: "cowork-b", output: 7),
                [
                    "type": "result",
                    "timestamp": env.isoString(for: day),
                    "usage": ["input_tokens": 999, "output_tokens": 999],
                ],
            ]))
        _ = try env.writeClaudeDesktopSharedProjectFile(
            relativePath: "mirror/session.jsonl", contents: env.jsonl([response]))
        _ = try env.writeClaudeDesktopLocalAgentFile(
            relativePath: "outputs/ignored/audit.jsonl",
            contents: env.jsonl([assistant(session: "ignored", output: 99)]))
        let roots = CostUsageScanner.defaultClaudeProjectsRoots(
            options: .init(cacheRoot: env.cacheRoot), environment: [:], homeDirectory: env.root)
        #expect(roots.contains(audit.standardizedFileURL))
        #expect(!ClaudeDesktopProjectsLocator.roots(homeDirectory: env.root).contains(audit.standardizedFileURL))
        var options = CostUsageScanner.Options(claudeProjectsRoots: roots, cacheRoot: env.cacheRoot)
        options.refreshMinIntervalSeconds = 0
        for _ in 0..<2 {
            let report = CostUsageScanner.loadDailyReport(
                provider: .claude, since: day, until: day, now: day, options: options)
            #expect(report.data.first?.inputTokens == 20)
            #expect(report.data.first?.outputTokens == 12)
        }
    }

    @Test(.enabled(if: getuid() != 0, "root ignores directory permissions"))
    func `unreadable Cowork audit parent preserves cached history`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 10, day: 16)
        let audit = try env.writeClaudeDesktopLocalAgentFile(
            relativePath: "audit.jsonl",
            contents: env.jsonl([[
                "type": "assistant",
                "timestamp": env.isoString(for: day),
                "session_id": "cowork-a",
                "message": [
                    "id": "response-a", "model": "claude-test-model",
                    "usage": ["input_tokens": 10, "output_tokens": 5],
                ],
            ]]))
        var options = CostUsageScanner.Options(cacheRoot: env.cacheRoot)
        options.claudeProjectsRoots = [audit]
        options.refreshMinIntervalSeconds = 0

        func load() throws -> CostUsageDailyReport {
            try CostUsageScanner.loadDailyReportCancellable(
                provider: .claude,
                since: day,
                until: day,
                now: day,
                options: options,
                reportContext: nil,
                checkCancellation: nil)
        }

        #expect(try load().summary?.totalInputTokens == 10)
        let cacheURL = CostUsageClaudeCacheIO.cacheFileURL(provider: .claude, cacheRoot: env.cacheRoot)
        let memoURL = CostUsageClaudeReportMemo.reportMemoFileURL(cacheFileURL: cacheURL)
        let cacheBefore = try Data(contentsOf: cacheURL)
        let memoBefore = try Data(contentsOf: memoURL)
        let unreadableParent = audit.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadableParent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unreadableParent.path)
        }

        #expect(throws: (any Error).self) { try load() }
        #expect(try Data(contentsOf: cacheURL) == cacheBefore)
        #expect(try Data(contentsOf: memoURL) == memoBefore)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unreadableParent.path)
        #expect(try load().summary?.totalInputTokens == 10)
    }

    @Test
    func `claude daily report includes nested desktop local agent projects`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 5)
        let iso0 = env.isoString(for: day)
        let assistant: [String: Any] = [
            "type": "assistant",
            "timestamp": iso0,
            "message": [
                "model": "claude-test-model",
                "usage": [
                    "input_tokens": 120,
                    "cache_creation_input_tokens": 30,
                    "cache_read_input_tokens": 20,
                    "output_tokens": 40,
                ],
            ],
        ]
        let nestedAssistant: [String: Any] = [
            "type": "assistant",
            "timestamp": iso0,
            "message": [
                "model": "claude-test-model",
                "usage": [
                    "input_tokens": 10,
                    "output_tokens": 5,
                ],
            ],
        ]
        let currentAssistant: [String: Any] = [
            "type": "assistant",
            "timestamp": iso0,
            "message": [
                "model": "claude-test-model",
                "usage": [
                    "input_tokens": 7,
                    "output_tokens": 3,
                ],
            ],
        ]
        let decoyAssistant: [String: Any] = [
            "type": "assistant",
            "timestamp": iso0,
            "message": [
                "model": "claude-test-model",
                "usage": [
                    "input_tokens": 999,
                    "output_tokens": 999,
                ],
            ],
        ]
        let projectsRoot = try env.writeClaudeDesktopLocalAgentProjectFile(
            relativePath: "project-a/session-a.jsonl",
            contents: env.jsonl([assistant]))
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let nestedProjectsRoot = try env.writeNestedClaudeDesktopLocalAgentProjectFile(
            relativePath: "project-b/session-b.jsonl",
            contents: env.jsonl([nestedAssistant]))
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let currentProjectsRoot = try env.writeClaudeDesktopCodeSessionProjectFile(
            relativePath: "project-c/session-c.jsonl",
            contents: env.jsonl([currentAssistant]))
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let decoyProjectsRoot = try env.writeClaudeDesktopLocalAgentFile(
            relativePath: "outputs/node_modules/package/.claude/projects/project-decoy/session-decoy.jsonl",
            contents: env.jsonl([decoyAssistant]))
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let discovered = CostUsageScanner.defaultClaudeProjectsRoots(
            options: CostUsageScanner.Options(cacheRoot: env.cacheRoot),
            environment: [:],
            homeDirectory: env.root)
        #expect(discovered.contains(projectsRoot.standardizedFileURL))
        #expect(discovered.contains(nestedProjectsRoot.standardizedFileURL))
        #expect(discovered.contains(currentProjectsRoot.standardizedFileURL))
        #expect(!discovered.contains(decoyProjectsRoot.standardizedFileURL))

        var options = CostUsageScanner.Options(
            codexSessionsRoot: nil,
            claudeProjectsRoots: discovered,
            cacheRoot: env.cacheRoot)
        options.refreshMinIntervalSeconds = 0

        let report = CostUsageScanner.loadDailyReport(
            provider: .claude,
            since: day,
            until: day,
            now: day,
            options: options)

        #expect(report.data.count == 1)
        #expect(report.data[0].inputTokens == 137)
        #expect(report.data[0].cacheCreationTokens == 30)
        #expect(report.data[0].cacheReadTokens == 20)
        #expect(report.data[0].outputTokens == 48)
        #expect(report.data[0].totalTokens == 235)
    }

    @Test
    func `current desktop shared claude projects root remains discovered`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 5)
        let sessionID = "desktop-cli-session"
        let assistant: [String: Any] = [
            "type": "assistant",
            "timestamp": env.isoString(for: day),
            "message": [
                "model": "claude-test-model",
                "usage": [
                    "input_tokens": 11,
                    "cache_read_input_tokens": 13,
                    "output_tokens": 4,
                ],
            ],
        ]
        // Current Desktop's cliSessionId points to the matching JSONL in this shared root.
        let sharedProjectsRoot = try env.writeClaudeDesktopSharedProjectFile(
            relativePath: "desktop-project/\(sessionID).jsonl",
            contents: env.jsonl([assistant]))
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let discovered = CostUsageScanner.defaultClaudeProjectsRoots(
            options: CostUsageScanner.Options(cacheRoot: env.cacheRoot),
            environment: [:],
            homeDirectory: env.root)
        #expect(discovered.contains(sharedProjectsRoot.standardizedFileURL))

        var options = CostUsageScanner.Options(
            codexSessionsRoot: nil,
            claudeProjectsRoots: discovered,
            cacheRoot: env.cacheRoot)
        options.refreshMinIntervalSeconds = 0

        let report = CostUsageScanner.loadDailyReport(
            provider: .claude,
            since: day,
            until: day,
            now: day,
            options: options)

        #expect(report.data.count == 1)
        #expect(report.data[0].inputTokens == 11)
        #expect(report.data[0].cacheReadTokens == 13)
        #expect(report.data[0].outputTokens == 4)
        #expect(report.data[0].totalTokens == 28)
    }

    @Test
    func `Claude config root is one relative literal and always owns a projects child`() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CostUsageScanner-ClaudePaths-\(UUID().uuidString)", isDirectory: true)
        let workingDirectory = root.appendingPathComponent("probe", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let literal = " first, second "
        let roots = CostUsageScanner.defaultClaudeProjectsRoots(
            options: CostUsageScanner.Options(cacheRoot: root.appendingPathComponent("cache")),
            environment: [ClaudeConfigPaths.configDirectoryEnvironmentKey: literal],
            homeDirectory: root.appendingPathComponent("home"),
            workingDirectory: workingDirectory)
        #expect(roots == [workingDirectory
                .appendingPathComponent(literal, isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
                .standardizedFileURL])

        let projectsNamedRoot = CostUsageScanner.defaultClaudeProjectsRoots(
            options: CostUsageScanner.Options(cacheRoot: root.appendingPathComponent("cache")),
            environment: [ClaudeConfigPaths.configDirectoryEnvironmentKey: "projects"],
            homeDirectory: root.appendingPathComponent("home"),
            workingDirectory: workingDirectory)
        #expect(projectsNamedRoot == [workingDirectory
                .appendingPathComponent("projects/projects", isDirectory: true)
                .standardizedFileURL])

        let relativeHomeRoots = CostUsageScanner.defaultClaudeProjectsRoots(
            options: CostUsageScanner.Options(cacheRoot: root.appendingPathComponent("cache")),
            environment: ["HOME": "relative-home", ClaudeConfigPaths.configDirectoryEnvironmentKey: ""],
            homeDirectory: root.appendingPathComponent("ignored-home"),
            workingDirectory: workingDirectory)
        #expect(relativeHomeRoots.contains(workingDirectory
                .appendingPathComponent("relative-home/.claude/projects", isDirectory: true)
                .standardizedFileURL))
    }
}

private final class FailingDirectoryListingFileManager: FileManager, @unchecked Sendable {
    private let failedPath: String

    init(path: String) {
        self.failedPath = path
        super.init()
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []) throws -> [URL]
    {
        if url.path == self.failedPath {
            throw NSError(domain: NSPOSIXErrorDomain, code: 13)
        }
        return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
    }
}
