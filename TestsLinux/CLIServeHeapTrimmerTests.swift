#if canImport(Glibc)
import CodexBarCore
import Foundation
import Glibc
import Testing
@testable import CodexBarCLI

/// Isolated allocator trimming is asserted separately from real serve liveness: Codex scan-store
/// state remains intentionally retained after a cost response, so serve RSS is only diagnostic.
@Suite(.serialized)
struct CLIServeHeapTrimmerTests {
    @Test
    func `timer trims released pages from a controlled fragmented glibc heap`() throws {
        let blockSize = 64 * 1024
        var blocks: [UnsafeMutableRawPointer?] = []
        defer {
            for block in blocks {
                if let block { Glibc.free(block) }
            }
        }

        for _ in 0..<256 {
            let block = try #require(Glibc.malloc(blockSize))
            _ = Glibc.memset(block, 0xA5, blockSize)
            blocks.append(block)
        }
        for index in stride(from: 0, to: blocks.count, by: 2) {
            Glibc.free(blocks[index])
            blocks[index] = nil
        }

        let trimmed = DispatchSemaphore(value: 0)
        let timer = try #require(
            CLIServeHeapTrimmer.startForTesting(interval: .milliseconds(20)) { releasedPages in
                if releasedPages { trimmed.signal() }
            })
        defer { timer.cancel() }

        #expect(
            trimmed.wait(timeout: .now() + .seconds(5)) == .success,
            "malloc_trim did not release pages from the controlled fragmented heap")
    }

    @Test
    func `serve remains healthy across synthetic cost scans and heap maintenance`() async throws {
        let binary = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent().appendingPathComponent("CodexBarCLI")
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/test_linux_serve_memory.py")
        let result = try await SubprocessRunner.run(
            binary: "/usr/bin/python3",
            arguments: [script.path, binary.path],
            environment: ["PATH": "/usr/bin:/bin"],
            timeout: 300,
            label: "quotakit-serve-heap-fixture")
        if !result.stderr.isEmpty {
            FileHandle.standardError.write(Data(result.stderr.utf8))
        }
        #expect(result.stdout.contains("serve-fixture-ok"))
    }
}
#endif
