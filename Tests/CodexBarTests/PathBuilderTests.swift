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
