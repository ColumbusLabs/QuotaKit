import Foundation
import Testing
@testable import CodexBarCore

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct CostUsageClaudeArtifactWriterTests {
    private final class ByteCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func add(_ value: Int) {
            self.lock.withLock { self.count += value }
        }

        var value: Int {
            self.lock.withLock { self.count }
        }
    }

    @Test(arguments: [false, true])
    func `replacement keeps exact bytes across growth shrink and fallback`(disableCloning: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.json")
        let original = Data((0..<(1024 * 1024)).map { UInt8($0 % 251) })
        try original.write(to: source)
        var edited = original
        edited[0] = 98
        edited[70000] = 99
        edited[edited.count - 1] = 100

        for (index, expected) in [
            original,
            original + Data("tail".utf8),
            Data("prefix".utf8) + original,
            edited,
            Data("short".utf8),
            Data(),
        ].enumerated() {
            let temporary = root.appendingPathComponent("private-\(index)")
            try CostUsageClaudeArtifactWriter.$disableCloningForTesting.withValue(disableCloning) {
                let writer = try #require(CostUsageClaudeArtifactWriter(temporaryURL: temporary, replacing: source))
                var bytes = 0
                let split = min(70003, expected.count)
                bytes += try writer.append(expected[..<split])
                bytes += try writer.append(expected[split...])
                try writer.finish()
                #expect(try Data(contentsOf: temporary) == expected)
                #expect(try Data(contentsOf: source) == original)
                if disableCloning { #expect(bytes == expected.count) }
            }
        }
    }

    @Test
    func `clone reuses unchanged blocks without changing replacement bytes`() throws {
        #if os(macOS)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.json")
        let probe = root.appendingPathComponent("clone-probe")
        let temporary = root.appendingPathComponent("private.json")
        let original = Data(repeating: 97, count: 1024 * 1024)
        try original.write(to: source)
        let canClone = clonefile(source.path, probe.path, 0) == 0
        try? FileManager.default.removeItem(at: probe)

        var replacement = original
        replacement[1] = 98
        replacement[70000] = 99
        replacement[replacement.count - 1] = 100
        let bytes = ByteCounter()
        let observeBytes: @Sendable (Int) -> Void = { count in bytes.add(count) }
        try CostUsageClaudeArtifactWriter.$observeWrittenBytesForTesting.withValue(observeBytes) {
            let writer = try #require(CostUsageClaudeArtifactWriter(temporaryURL: temporary, replacing: source))
            _ = try writer.append(replacement)
            try writer.finish()
        }

        #expect(try Data(contentsOf: temporary) == replacement)
        #expect(try Data(contentsOf: source) == original)
        if canClone { #expect(bytes.value < replacement.count) }
        #endif
    }

    @Test
    func `read only source falls back and sequential replacements preserve contents`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.json")
        var current = Data(repeating: 97, count: 128_000)
        try current.write(to: source)
        #expect(chmod(source.path, mode_t(0o444)) == 0)
        for cycle in 1...3 {
            let temporary = root.appendingPathComponent("private-\(cycle)")
            let writer = try #require(CostUsageClaudeArtifactWriter(temporaryURL: temporary, replacing: source))
            let next = current + Data("next-\(cycle)".utf8)
            let bytes = try writer.append(next)
            if cycle == 1 { #expect(bytes == next.count) }
            try writer.finish()
            #expect(try Data(contentsOf: source) == current)
            #expect(rename(temporary.path, source.path) == 0)
            #expect(try Data(contentsOf: source) == next)
            var metadata = stat()
            #expect(stat(source.path, &metadata) == 0)
            #expect(metadata.st_mode & mode_t(0o777) == mode_t(0o600))
            current = next
        }
    }

    @Test
    func `source symlinks and occupied temporary paths cannot mutate existing files`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.json")
        let link = root.appendingPathComponent("source-link.json")
        let temporary = root.appendingPathComponent("private.json")
        let original = Data(repeating: 97, count: 128_000)
        try original.write(to: source)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let writer = try #require(CostUsageClaudeArtifactWriter(temporaryURL: temporary, replacing: link))
        #expect(try writer.append(original) == original.count)
        try writer.finish()
        #expect(try Data(contentsOf: temporary) == original)
        #expect(CostUsageClaudeArtifactWriter(temporaryURL: temporary, replacing: source) == nil)
        #expect(try Data(contentsOf: temporary) == original)
        #expect(try Data(contentsOf: source) == original)
    }

    @Test
    func `reset discards cloned suffix before fallback output`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.json")
        let temporary = root.appendingPathComponent("private.json")
        let original = Data(repeating: 97, count: 128_000)
        try original.write(to: source)
        let writer = try #require(CostUsageClaudeArtifactWriter(temporaryURL: temporary, replacing: source))
        _ = try writer.append(original)
        try writer.reset()
        let fallback = Data("replacement".utf8)
        #expect(try writer.append(fallback) == fallback.count)
        try writer.finish()
        #expect(try Data(contentsOf: temporary) == fallback)
        #expect(try Data(contentsOf: source) == original)
    }
}
