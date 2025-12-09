import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite
struct PathBuilderTests {
    @Test
    func usesExistingPathFirstAndDedupes() {
        let seeded = PathBuilder.effectivePATH(
            purposes: [.rpc],
            env: ["PATH": "/custom/bin:/usr/bin"],
            loginPATH: nil,
            resolvedBinaryPaths: ["/tmp/codex/bin"],
            home: "/home/test")
        let parts = seeded.split(separator: ":").map(String.init)
        #expect(parts.first == "/custom/bin")
        #expect(parts.contains("/opt/homebrew/bin"))
        #expect(parts.contains("/tmp/codex/bin"))
        #expect(parts.count(where: { $0 == "/usr/bin" }) == 1)
    }

    @Test
    func appendsLoginShellPathWhenAvailable() {
        let seeded = PathBuilder.effectivePATH(
            purposes: [.tty],
            env: [:],
            loginPATH: ["/login/path/bin"],
            resolvedBinaryPaths: [],
            home: "/home/test")
        let parts = seeded.split(separator: ":").map(String.init)
        #expect(parts.first == "/usr/bin")
        #expect(parts.contains("/login/path/bin"))
    }

    @Test
    func addsResolvedBinaryDirectory() {
        let seeded = PathBuilder.effectivePATH(
            purposes: [.rpc],
            env: ["PATH": "/existing/bin"],
            loginPATH: nil,
            resolvedBinaryPaths: ["/detected/codex"],
            home: "/home/test")
        let parts = seeded.split(separator: ":").map(String.init)
        #expect(parts.contains("/detected/codex"))
    }

    @Test
    func resolvesCodexFromEnvOverride() throws {
        let temp = try makeTempDir()
        let overridePath = temp.appendingPathComponent("codex").path
        let fm = MockFileManager(
            executables: [overridePath],
            directories: [:])

        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["CODEX_CLI_PATH": overridePath],
            loginPATH: nil,
            fileManager: fm,
            home: temp.path)
        #expect(resolved == overridePath)
    }

    @Test
    func resolvesCodexFromNvmVersion() throws {
        let temp = try makeTempDir()
        let nvmBin = temp
            .appendingPathComponent(".nvm")
            .appendingPathComponent("versions")
            .appendingPathComponent("node")
            .appendingPathComponent("v18.0.0")
            .appendingPathComponent("bin")
        let codexPath = nvmBin.appendingPathComponent("codex").path
        let fm = MockFileManager(
            executables: [codexPath],
            directories: [
                nvmBin.deletingLastPathComponent().deletingLastPathComponent().path: ["v18.0.0"],
            ])

        let resolved = BinaryLocator.resolveCodexBinary(
            env: [:],
            loginPATH: nil,
            fileManager: fm,
            home: temp.path)
        #expect(resolved == codexPath)
    }

    @Test
    func resolvesCodexFromFnmNodeVersions() throws {
        let temp = try makeTempDir()
        let nodeVersions = temp
            .appendingPathComponent(".local")
            .appendingPathComponent("share")
            .appendingPathComponent("fnm")
            .appendingPathComponent("node-versions")
        let codexPath = nodeVersions
            .appendingPathComponent("v20.8.0")
            .appendingPathComponent("installation")
            .appendingPathComponent("bin")
            .appendingPathComponent("codex")
            .path
        let fm = MockFileManager(
            executables: [codexPath],
            directories: [
                nodeVersions.path: ["v20.8.0"],
            ])

        let resolved = BinaryLocator.resolveCodexBinary(
            env: [:],
            loginPATH: nil,
            fileManager: fm,
            home: temp.path)
        #expect(resolved == codexPath)
    }

    @Test
    func resolvesCodexFromFnmAliasDefault() throws {
        let temp = try makeTempDir()
        let aliases = temp
            .appendingPathComponent(".local")
            .appendingPathComponent("share")
            .appendingPathComponent("fnm")
            .appendingPathComponent("aliases")
        let codexPath = aliases
            .appendingPathComponent("default")
            .appendingPathComponent("bin")
            .appendingPathComponent("codex")
            .path
        let fm = MockFileManager(
            executables: [codexPath],
            directories: [
                aliases.path: ["default"],
            ])

        let resolved = BinaryLocator.resolveCodexBinary(
            env: [:],
            loginPATH: nil,
            fileManager: fm,
            home: temp.path)
        #expect(resolved == codexPath)
    }

    @Test
    func resolvesCodexFromFnmEnvOverride() throws {
        let temp = try makeTempDir()
        let fnmDir = temp.appendingPathComponent("fnmdir")
        let nodeVersions = fnmDir.appendingPathComponent("node-versions")
        let codexPath = nodeVersions
            .appendingPathComponent("v18.0.0")
            .appendingPathComponent("installation")
            .appendingPathComponent("bin")
            .appendingPathComponent("codex")
            .path
        let fm = MockFileManager(
            executables: [codexPath],
            directories: [
                nodeVersions.path: ["v18.0.0"],
            ])

        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["FNM_DIR": fnmDir.path],
            loginPATH: nil,
            fileManager: fm,
            home: temp.path)
        #expect(resolved == codexPath)
    }

    @Test
    func prefersHigherSemverForNvm() throws {
        let temp = try makeTempDir()
        let nvmBin = temp
            .appendingPathComponent(".nvm")
            .appendingPathComponent("versions")
            .appendingPathComponent("node")
        let oldPath = nvmBin
            .appendingPathComponent("v9.0.0")
            .appendingPathComponent("bin")
            .appendingPathComponent("codex")
            .path
        let newPath = nvmBin
            .appendingPathComponent("v20.0.0")
            .appendingPathComponent("bin")
            .appendingPathComponent("codex")
            .path
        let fm = MockFileManager(
            executables: [oldPath, newPath],
            directories: [
                nvmBin.path: ["v9.0.0", "v20.0.0"],
            ])

        let resolved = BinaryLocator.resolveCodexBinary(
            env: [:],
            loginPATH: nil,
            fileManager: fm,
            home: temp.path)
        #expect(resolved == newPath)
    }

    @Test
    func includesLoginPathWhenNoExistingPath() {
        let seeded = PathBuilder.effectivePATH(
            purposes: [.tty],
            env: [:],
            loginPATH: ["/login/bin"],
            resolvedBinaryPaths: [],
            home: "/home/test")
        let parts = seeded.split(separator: ":").map(String.init)
        #expect(parts.contains("/login/bin"))
    }

    @Test
    func resolvesClaudeFromDotClaudeLocal() throws {
        let temp = try makeTempDir()
        let claudePath = temp
            .appendingPathComponent(".claude")
            .appendingPathComponent("local")
            .appendingPathComponent("claude")
            .path
        let fm = MockFileManager(
            executables: [claudePath],
            directories: [:])

        let resolved = BinaryLocator.resolveClaudeBinary(
            env: [:],
            loginPATH: nil,
            fileManager: fm,
            home: temp.path)
        #expect(resolved == claudePath)
    }

    @Test
    func resolvesClaudeFromDotClaudeBin() throws {
        let temp = try makeTempDir()
        let claudePath = temp
            .appendingPathComponent(".claude")
            .appendingPathComponent("bin")
            .appendingPathComponent("claude")
            .path
        let fm = MockFileManager(
            executables: [claudePath],
            directories: [:])

        let resolved = BinaryLocator.resolveClaudeBinary(
            env: [:],
            loginPATH: nil,
            fileManager: fm,
            home: temp.path)
        #expect(resolved == claudePath)
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class MockFileManager: FileManager {
    private let executables: Set<String>
    private let dirs: [String: [String]]

    init(executables: Set<String>, directories: [String: [String]]) {
        self.executables = executables
        self.dirs = directories
    }

    override func isExecutableFile(atPath path: String) -> Bool {
        self.executables.contains(path)
    }

    override func contentsOfDirectory(atPath path: String) throws -> [String] {
        self.dirs[path] ?? []
    }
}
