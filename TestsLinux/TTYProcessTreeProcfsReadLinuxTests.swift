import Foundation
import Testing
@testable import CodexBarCore

#if os(Linux)
struct TTYProcessTreeProcfsReadLinuxTests {
    @Test
    func `procfs reader returns file content`() throws {
        let stat = try #require(TTYProcessTreeTerminator.readProcFile("/proc/self/stat"))
        #expect(stat.hasPrefix("\(getpid()) "))
    }

    @Test
    func `procfs reader reads past a single chunk`() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let content = String(repeating: "0123456789", count: 1000)
        try content.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(TTYProcessTreeTerminator.readProcFile(file.path) == content)
    }

    @Test
    func `procfs reader tells an empty file from a missing one`() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(TTYProcessTreeTerminator.readProcFile(file.path)?.isEmpty == true)
        #expect(TTYProcessTreeTerminator.readProcFile(file.path + ".missing") == nil)
    }

    @Test
    func `child lookup finds a running child`() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }

        #expect(TTYProcessTreeTerminator.currentChildPIDs(of: getpid()).contains(process.processIdentifier))
    }
}
#endif
