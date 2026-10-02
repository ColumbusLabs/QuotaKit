import Foundation
import Testing
@testable import CodexBarCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct GeminiStdoutHolderFixtureTests {
    @Test(.timeLimit(.minutes(1)))
    func `producer times out while its acknowledged holder stays owned`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let holder = try GeminiStdoutHolderFixture(root: root)
        defer { holder.cleanup() }
        #expect(holder.runProducer(blockAfterAcknowledgment: true) == nil)
        let publishedPID = try String(contentsOf: holder.pidFile, encoding: .utf8)
        #expect(pid_t(publishedPID) == holder.process.processIdentifier)
        #expect(holder.process.isRunning)
    }
}
