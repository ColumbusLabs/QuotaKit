import Foundation
import Testing
@testable import CodexBarCore

struct CodexDirectForkBaselineTests {
    @Test(arguments: [0, 3, 8], [false, true])
    func `direct fork chains preserve cumulative inheritance`(parentEventTime: Int, bounded: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 17)
        func metadata(_ id: String, parent: String?, time: Int) -> [String: Any] {
            var payload: [String: Any] = [
                "id": id, "source": "vscode", "thread_source": "user",
                "timestamp": env.isoString(for: day.addingTimeInterval(Double(time))),
            ]
            payload["forked_from_id"] = parent
            return ["type": "session_meta", "payload": payload]
        }
        func tokens(_ input: Int, last: Int?, time: Int) -> [String: Any] {
            var info: [String: Any] = [
                "model": "gpt-5.4",
                "total_token_usage": ["input_tokens": input, "output_tokens": 0],
            ]
            if let last {
                info["last_token_usage"] = ["input_tokens": last, "output_tokens": 0]
            }
            return [
                "type": "event_msg",
                "timestamp": env.isoString(for: day.addingTimeInterval(Double(time))),
                "payload": ["type": "token_count", "info": info],
            ]
        }
        let rootFile = try env.writeCodexSessionFile(day: day, filename: "root.jsonl", contents: env.jsonl([
            metadata("root", parent: nil, time: 0), tokens(1000, last: 1000, time: 1),
        ]))
        var parent = [metadata("parent", parent: "root", time: 2)]
        if parentEventTime > 0 { parent.append(tokens(1040, last: 40, time: parentEventTime)) }
        let parentFile = try env.writeCodexSessionFile(
            day: day, filename: "parent.jsonl", contents: env.jsonl(parent))
        let inherited = parentEventTime == 3 ? 1040 : 1000
        let childPath = try env.writeCodexSessionFile(day: day, filename: "child.jsonl", contents: env.jsonl([
            metadata("child", parent: "parent", time: 4),
            tokens(inherited, last: parentEventTime == 3 ? 40 : nil, time: 5),
            tokens(inherited + 20, last: 20, time: 6),
            tokens(inherited + 20, last: 20, time: 7),
        ]))
        let direct = CostUsageScanner.parseCodexFile(
            fileURL: childPath,
            range: .init(since: day, until: day),
            inheritedTotalsResolver: { _, _ in .resolved(.init(input: inherited, cached: 0, output: 0)) })
        #expect(direct.rows.map(\.input) == [20])
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"))
        options.refreshMinIntervalSeconds = 0
        if bounded { options.maxCodexScanBytesPerRefresh = 512 }
        var clock = day
        for pass in 0..<4 {
            if pass == 2 {
                var legacy = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
                for path in legacy.files.keys {
                    legacy.files[path]?.codexParserRevision = 5
                }
                CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: legacy)
            }
            options.forceRescan = pass == 3
            let report = try self.completedScan(env: env, day: day, options: options, clock: &clock)
            let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
            let child = try #require(cache.files.values.first { $0.sessionId == "child" })
            let expected = 1020 + (parentEventTime > 0 ? 40 : 0)
            #expect(child.codexRows?.map(\.input) == [20])
            #expect(report.data.reduce(0) { $0 + ($1.totalTokens ?? 0) } == expected)
            #expect(Self.inputTokens(in: cache.days) == expected)
            #expect(cache.files.values.reduce(0) { $0 + Self.inputTokens(in: $1.days) } == expected)
        }
        // The unbounded resolver shares the scanner, including forks with no token events.
        let resolver = CostUsageScanner.CodexInheritedTotalsResolver(
            fileIndex: .init(files: [rootFile, parentFile], roots: []), checkCancellation: nil)
        let baseline = try resolver.inheritedTotals(
            for: "parent", atOrBefore: env.isoString(for: day.addingTimeInterval(4)))
        guard case let .resolved(totals) = baseline else {
            Issue.record("Expected a resolved direct-fork baseline")
            return
        }
        #expect(totals?.input == inherited)
        if parentEventTime == 3, !bounded {
            let cached = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
            var independent = try #require(cached.files[parentFile.path])
            #expect(independent.codexForkAccountingState != nil)
            independent.forkBaselineDependencyKey = CostUsageScanner.codexForkDependencyNotRequiredKey
            let cachedResolver = CostUsageScanner.CodexInheritedTotalsResolver(
                fileIndex: .init(files: [rootFile, parentFile], roots: []), checkCancellation: nil)
            cachedResolver.updateCachedUsage(fileURL: parentFile, usage: independent)
            cachedResolver.updateCachedUsage(fileURL: rootFile, usage: cached.files[rootFile.path])
            if case .resolved = try cachedResolver.inheritedTotals(
                for: "parent", atOrBefore: env.isoString(for: day.addingTimeInterval(4)))
            {
                let currentKey = try cachedResolver.currentDependencyKey(for: "parent")
                #expect(cachedResolver.dependencyKeyUsed(for: "parent") == currentKey)
            } else {
                Issue.record("Independent fork parent must resolve from cached snapshots")
            }
        }
        if parentEventTime == 0 {
            let previousDependency = resolver.dependencyKeyUsed(for: "parent")
            try env.jsonl([
                metadata("root", parent: nil, time: 0), tokens(1010, last: 1010, time: 1),
            ]).write(to: rootFile, atomically: true, encoding: .utf8)
            #expect(try resolver.currentDependencyKey(for: "parent") != previousDependency)
            resolver.updateCachedUsage(fileURL: rootFile, usage: nil)
            if case let .resolved(updated) = try resolver.inheritedTotals(
                for: "parent", atOrBefore: env.isoString(for: day.addingTimeInterval(4)))
            {
                #expect(updated?.input == 1010)
            } else {
                Issue.record("Changed empty-fork ancestry should resolve again")
            }
            options.forceRescan = false
            _ = try self.completedScan(env: env, day: day, options: options, clock: &clock)
            let child = try #require(CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
                .files.values.first { $0.sessionId == "child" })
            #expect(child.codexRows?.map(\.input) == [10])
        }
    }

    @Test
    func `cyclic empty fork ancestry remains unresolved`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 17)
        var files: [URL] = []
        for (id, parent) in [("a", "b"), ("b", "a")] {
            try files.append(env.writeCodexSessionFile(day: day, filename: "\(id).jsonl", contents: env.jsonl([
                ["type": "session_meta", "payload": [
                    "id": id, "forked_from_id": parent, "timestamp": env.isoString(for: day),
                ]],
            ])))
        }
        let resolver = CostUsageScanner.CodexInheritedTotalsResolver(
            fileIndex: .init(files: files, roots: []), checkCancellation: nil)
        if case .resolved = try resolver.inheritedTotals(for: "a", atOrBefore: env.isoString(for: day)) {
            Issue.record("Cyclic ancestry cannot establish a baseline")
        }
    }

    @Test(arguments: [1000, 1200], [false, true])
    func `first fork total equal to last stays incomplete when it may be copied`(
        firstTotal: Int,
        bounded: Bool) throws
    {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 17)
        func metadata(_ id: String, parent: String?, time: Int) -> [String: Any] {
            var payload: [String: Any] = [
                "id": id, "source": "vscode", "thread_source": "user",
                "timestamp": env.isoString(for: day.addingTimeInterval(Double(time))),
            ]
            payload["forked_from_id"] = parent
            return ["type": "session_meta", "payload": payload]
        }
        func tokens(_ input: Int, last: Int, time: Int) -> [String: Any] {
            [
                "type": "event_msg",
                "timestamp": env.isoString(for: day.addingTimeInterval(Double(time))),
                "payload": ["type": "token_count", "info": [
                    "model": "gpt-5.4",
                    "total_token_usage": ["input_tokens": input, "output_tokens": 0],
                    "last_token_usage": ["input_tokens": last, "output_tokens": 0],
                ]],
            ]
        }
        _ = try env.writeCodexSessionFile(day: day, filename: "parent.jsonl", contents: env.jsonl([
            metadata("parent", parent: nil, time: 0), tokens(1000, last: 1000, time: 1),
        ]))
        let childFile = try env.writeCodexSessionFile(day: day, filename: "child.jsonl", contents: env.jsonl([
            metadata("child", parent: "parent", time: 2),
            // This exact observation could be a copied parent snapshot or a new child turn.
            tokens(firstTotal, last: firstTotal, time: 3),
            tokens(firstTotal + 20, last: 20, time: 4),
        ]))
        let range = CostUsageScanner.CostUsageDayRange(since: day, until: day)
        let parsed = CostUsageScanner.parseCodexFile(
            fileURL: childFile,
            range: range,
            inheritedTotalsResolver: { _, _ in .resolved(.init(input: 1000, cached: 0, output: 0)) })
        #expect(parsed.rows.isEmpty)
        #expect(parsed.days.isEmpty)
        #expect(parsed.forkBaselineResolved == false)
        #expect(parsed.bufferedUnresolvedForkLines?.count == 3)

        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"))
        options.refreshMinIntervalSeconds = 0
        if bounded { options.maxCodexScanBytesPerRefresh = 512 }
        var clock = day
        for _ in 0..<8 {
            clock.addTimeInterval(1)
            _ = CostUsageScanner.loadDailyReport(
                provider: .codex, since: day, until: day, now: clock, options: options)
        }
        let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let child = try #require(cache.files.values.first { $0.sessionId == "child" })
        #expect(child.codexRows?.isEmpty != false)
        #expect(child.hasBufferedCodexForkRetryLines)
        #expect(child.forkBaselineDependencyKey == nil)
        #expect(cache.codexScanCatchUpPending == true)
    }

    private func completedScan(
        env: CostUsageTestEnvironment,
        day: Date,
        options: CostUsageScanner.Options,
        clock: inout Date) throws -> CostUsageDailyReport
    {
        var options = options
        for _ in 0..<80 {
            clock.addTimeInterval(1)
            let report = CostUsageScanner.loadDailyReport(
                provider: .codex, since: day, until: day, now: clock, options: options)
            options.forceRescan = false
            let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
            if cache.files.count == 3, cache.codexScanCatchUpPending != true,
               cache.files.values.allSatisfy({
                   $0.codexScanComplete == true && $0.hasCurrentCodexParser && !$0.hasBufferedCodexForkRetryLines
               })
            {
                return report
            }
        }
        throw NSError(domain: "DirectForkBaselineTests", code: 1)
    }

    private static func inputTokens(in days: [String: [String: [Int]]]) -> Int {
        days.values.flatMap(\.values).reduce(0) { $0 + ($1.first ?? 0) }
    }
}
