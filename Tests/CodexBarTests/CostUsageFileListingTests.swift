import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageFileListingTests {
    @Test
    func `listing preserves path keys across normalized and symlinked roots`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let fm = FileManager.default
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 30)
        for relative in [
            "2026/09/29/older.jsonl",
            "2026/09/30/one.jsonl",
            "2026/09/30/two.jsonl",
            "flat.jsonl",
            "legacy/nested.jsonl",
        ] {
            let file = env.codexSessionsRoot.appendingPathComponent(relative, isDirectory: false)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(relative.utf8).write(to: file)
            try fm.setAttributes([.modificationDate: day], ofItemAtPath: file.path)
        }
        let alias = env.codexSessionsRoot.appendingPathComponent("alias.jsonl", isDirectory: false)
        try fm.createSymbolicLink(
            at: alias,
            withDestinationURL: env.codexSessionsRoot.appendingPathComponent("2026/09/30/one.jsonl"))

        let linkedHome = env.root.appendingPathComponent("linked-home", isDirectory: true)
        try fm.createSymbolicLink(at: linkedHome, withDestinationURL: env.codexHomeRoot)
        let plainRoot = env.codexSessionsRoot.path
        let linkedRoot = linkedHome.appendingPathComponent("sessions", isDirectory: true)
        let roots = [
            URL(fileURLWithPath: plainRoot + "/", isDirectory: true),
            URL(fileURLWithPath: plainRoot + "/../sessions///", isDirectory: true),
            linkedRoot,
        ]

        for root in roots {
            let expected = try Self.legacyListing(root: root)
            let recorder = CostUsageScanner.CodexScanWorkRecorder()
            let actual = CostUsageScanner.listCodexSessionFiles(
                root: root,
                scanSinceKey: "2026-09-29",
                scanUntilKey: "2026-09-30",
                includeRecursive: true,
                workRecorder: recorder)
            let actualKeys = actual.map { CostUsageScanner.codexPathKey($0) }
            let expectedKeys = expected.map { CostUsageScanner.codexPathKey($0) }
            #expect(actualKeys == expectedKeys)
            #expect(recorder.snapshot().codexListingRootStandardizations == 1)
        }
    }

    @Test
    func `refresh shares listing metadata across queue checks and sorts`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 30)
        for index in 0..<12 {
            _ = try env.writeCodexSessionFile(day: day, filename: "listing-\(index).jsonl", contents: "{}\n")
        }
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite", isDirectory: false),
            maxCodexSessionFileBytes: 1,
            maxCodexScanBytesPerRefresh: 1)
        options.refreshMinIntervalSeconds = 0

        for pass in 0..<2 {
            let recorder = CostUsageScanner.CodexScanWorkRecorder()
            options.codexScanWorkRecorderForTesting = recorder
            _ = CostUsageScanner.loadDailyReport(
                provider: .codex,
                since: day,
                until: day,
                now: day.addingTimeInterval(Double(pass)),
                options: options)
            #expect(recorder.snapshot().codexListingMetadataReads == 12)
            #expect(recorder.snapshot().codexListingRootStandardizations == 2)
        }
    }

    private static func legacyListing(root: URL) throws -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        for day in ["29", "30"] {
            files += try fm.contentsOfDirectory(
                at: root.appendingPathComponent("2026/09/\(day)", isDirectory: true),
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "jsonl" }
        }
        files += try fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
            .filter { $0.pathExtension.lowercased() == "jsonl" }
        let enumerator = try #require(fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]))
        while let item = enumerator.nextObject() as? URL {
            let relative = item.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1)
            if relative == "2026" { enumerator.skipDescendants(); continue }
            if item.pathExtension.lowercased() == "jsonl" { files.append(item) }
        }
        var seen: Set<String> = []
        return files.filter { seen.insert(CostUsageScanner.codexPathKey($0)).inserted }
    }
}
