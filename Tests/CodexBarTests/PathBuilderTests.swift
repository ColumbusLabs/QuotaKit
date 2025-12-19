import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite
struct PathBuilderTests {
    @Test
    func prefersLoginShellPathWhenAvailable() {
        let seeded = PathBuilder.effectivePATH(
            purposes: [.rpc],
            env: ["PATH": "/custom/bin:/usr/bin"],
            loginPATH: ["/login/bin", "/login/alt"])
        #expect(seeded == "/login/bin:/login/alt")
    }

    @Test
    func fallsBackToExistingPathWhenNoLoginPath() {
        let seeded = PathBuilder.effectivePATH(
            purposes: [.tty],
            env: ["PATH": "/custom/bin:/usr/bin"],
            loginPATH: nil)
        #expect(seeded == "/custom/bin:/usr/bin")
    }

    @Test
    func usesFallbackWhenNoPathAvailable() {
        let seeded = PathBuilder.effectivePATH(
            purposes: [.tty],
            env: [:],
            loginPATH: nil)
        #expect(seeded == "/usr/bin:/bin:/usr/sbin:/sbin")
    }

    @Test
    func resolvesCodexFromEnvOverride() {
        let overridePath = "/custom/bin/codex"
        let fm = MockFileManager(executables: [overridePath])

        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["CODEX_CLI_PATH": overridePath],
            loginPATH: nil,
            fileManager: fm,
            home: "/home/test")
        #expect(resolved == overridePath)
    }

    @Test
    func resolvesCodexFromLoginPath() {
        let fm = MockFileManager(executables: ["/login/bin/codex"])
        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["PATH": "/env/bin"],
            loginPATH: ["/login/bin"],
            fileManager: fm,
            home: "/home/test")
        #expect(resolved == "/login/bin/codex")
    }

    @Test
    func resolvesCodexFromEnvPath() {
        let fm = MockFileManager(executables: ["/env/bin/codex"])
        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["PATH": "/env/bin:/usr/bin"],
            loginPATH: nil,
            fileManager: fm,
            home: "/home/test")
        #expect(resolved == "/env/bin/codex")
    }

    @Test
    func resolvesClaudeFromLoginPath() {
        let fm = MockFileManager(executables: ["/login/bin/claude"])
        let resolved = BinaryLocator.resolveClaudeBinary(
            env: ["PATH": "/env/bin"],
            loginPATH: ["/login/bin"],
            fileManager: fm,
            home: "/home/test")
        #expect(resolved == "/login/bin/claude")
    }
}

private final class MockFileManager: FileManager {
    private let executables: Set<String>

    init(executables: Set<String>) {
        self.executables = executables
    }

    override func isExecutableFile(atPath path: String) -> Bool {
        self.executables.contains(path)
    }
}
