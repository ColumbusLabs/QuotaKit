import Foundation
import Testing
@testable import CodexBarCore

#if os(Linux)
@Suite(.serialized)
struct ProcessExitReleaseLinuxTests {
    private struct LaunchedChild {
        let isProcessRetained: () -> Bool
        let pipes: Set<String>
    }

    @Test
    func `RPC child teardown releases the process and its output pipes`() async throws {
        let child = try Self.launch { process, stdin in
            RPCChildProcessTeardown.terminate(process: process, stdin: stdin)
        }

        #expect(await Self.waitUntil { !child.isProcessRetained() }, "Process stayed retained after teardown")
        #expect(
            await Self.waitUntil { Self.openPipes().isDisjoint(with: child.pipes) },
            "Output pipe descriptors stayed open after teardown")
    }

    @Test
    func `process requested for release while running is released after it exits`() async throws {
        let child = try Self.launch { process, stdin in
            #expect(process.isRunning)
            ProcessExitRelease.afterExit(process)
            ProcessExitRelease.afterExit(process)
            stdin.close()
        }

        #expect(await Self.waitUntil { !child.isProcessRetained() }, "Process stayed retained after it exited")
        #expect(
            await Self.waitUntil { Self.openPipes().isDisjoint(with: child.pipes) },
            "Output pipe descriptors stayed open after the process exited")
    }

    @Test
    func `repeated RPC teardown returns every output descriptor`() async throws {
        let children = try (0..<60).map { _ in
            try Self.launch { process, stdin in
                RPCChildProcessTeardown.terminate(process: process, stdin: stdin)
            }
        }
        let pipes = Set(children.flatMap(\.pipes))
        #expect(await Self.waitUntil { children.allSatisfy { !$0.isProcessRetained() } })
        #expect(await Self.waitUntil { Self.openPipes().isDisjoint(with: pipes) })
    }

    /// Mirrors the RPC clients: callers retain the pipes and process only during launch.
    private static func launch(body: (Process, RPCChildProcessInput) -> Void) throws -> LaunchedChild {
        let stdin = RPCChildProcessInput()
        let stdout = Pipe()
        let stderr = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        process.standardInput = stdin.pipe
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        let pipes = Set([stdout, stderr].compactMap { self.pipeName(of: $0.fileHandleForReading.fileDescriptor) })
        try #require(pipes.count == 2)
        body(process, stdin)
        return LaunchedChild(isProcessRetained: { [weak process] in process != nil }, pipes: pipes)
    }

    private static func pipeName(of fileDescriptor: Int32) -> String? {
        let target = try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/fd/\(fileDescriptor)")
        return target.flatMap { $0.hasPrefix("pipe:") ? $0 : nil }
    }

    private static func openPipes() -> Set<String> {
        let descriptors = (try? FileManager.default.contentsOfDirectory(atPath: "/proc/self/fd")) ?? []
        return Set(descriptors.compactMap { Int32($0) }.compactMap(self.pipeName(of:)))
    }

    private static func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }
}
#endif
