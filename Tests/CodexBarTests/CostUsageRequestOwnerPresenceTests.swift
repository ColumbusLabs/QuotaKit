import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageRequestOwnerPresenceTests {
    @Test
    func `owner retries retain archived or unavailable targets and owners`() throws {
        for unavailableTarget in [false, true] {
            for compressed in [false, true] {
                let env = try CostUsageTestEnvironment()
                defer { env.cleanup() }
                let target = env.root.appendingPathComponent("target.jsonl")
                let owner = env.root.appendingPathComponent("owner.jsonl")
                let unavailable = unavailableTarget ? target : owner
                let plain = unavailableTarget ? owner : target
                try Data("fixture".utf8).write(to: plain)
                if compressed {
                    try Data("archive".utf8).write(to: unavailable.appendingPathExtension("zst"))
                } else {
                    // A directory at a rollout path represents a source that cannot be inspected.
                    try FileManager.default.createDirectory(at: unavailable, withIntermediateDirectories: true)
                }
                let usage = CostUsageScanner.makeFileUsage(
                    mtimeUnixMs: 1, size: 1, days: ["2026-08-29": ["gpt-5": [100, 20, 10]]], parsedBytes: 1)
                var cache = CostUsageCache()
                cache.files[target.path] = usage
                cache.files[owner.path] = usage
                let retry = CodexHistoryHydrationRetry(
                    retainedPaths: [owner.path, target.path], forceFullRescan: true, requestOwnerPaths: [owner.path])
                var retries = [target.path: retry]
                let retired = CostUsageScanner.completeCodexRequestOwnerRetries(
                    processedPaths: [target.path],
                    observedOwnerRetries: [target.path: [owner.path]],
                    retries: &retries,
                    cache: &cache)
                #expect(retired.isEmpty)
                #expect(retries[target.path] == retry)
                #expect(cache.files[owner.path] == usage)
                #expect(cache.files[target.path] == usage)
            }
        }
    }

    @Test
    func `missing owner remains protected when its only sibling cannot be read`() throws {
        for compressed in [false, true] {
            let env = try CostUsageTestEnvironment()
            defer { env.cleanup() }
            let owner = env.root.appendingPathComponent("missing-owner.jsonl")
            let sibling = env.root.appendingPathComponent("survivor.jsonl")
            if compressed {
                try Data("archive".utf8).write(to: sibling.appendingPathExtension("zst"))
            } else {
                try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
            }
            var usage = CostUsageScanner.makeFileUsage(
                mtimeUnixMs: 1,
                size: 1,
                days: ["2026-08-29": ["gpt-5": [100, 20, 10]]],
                parsedBytes: 1,
                sessionId: "shared-session")
            usage.codexHasTypedResponseIdentity = true
            var cache = CostUsageCache()
            cache.files[owner.path] = usage
            cache.files[sibling.path] = usage
            #expect(CostUsageScanner.deferMissingCodexRequestOwner(path: owner.path, cache: &cache))
            #expect(cache.files[owner.path] == usage)
            #expect(cache.codexHistoryHydrationRetries?[sibling.path]?.requestOwnerPaths == [owner.path])
        }
    }
}
