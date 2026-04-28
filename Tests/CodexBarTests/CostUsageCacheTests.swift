import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageCacheTests {
    @Test
    func `cache file URL uses provider-specific artifact version`() {
        let root = URL(fileURLWithPath: "/tmp/codexbar-cost-cache", isDirectory: true)

        let codexURL = CostUsageCacheIO.cacheFileURL(provider: .codex, cacheRoot: root)
        let claudeURL = CostUsageCacheIO.cacheFileURL(provider: .claude, cacheRoot: root)
        let vertexURL = CostUsageCacheIO.cacheFileURL(provider: .vertexai, cacheRoot: root)

        // Bumped 4→5 (codex) and 2→3 (claude/vertex) in fork 0.23.1 to
        // invalidate stale token attributions from 0.20.3 era. If you
        // bump again, also bump these expectations.
        #expect(codexURL.lastPathComponent == "codex-v5.json")
        #expect(claudeURL.lastPathComponent == "claude-v3.json")
        #expect(vertexURL.lastPathComponent == "vertexai-v3.json")
    }

    // MARK: - Pricing fingerprint mechanism

    @Test
    func `pricingFingerprint is stable across calls`() {
        let f1 = CostUsagePricing.pricingFingerprint
        let f2 = CostUsagePricing.pricingFingerprint
        #expect(f1 == f2, "Fingerprint must be deterministic — cache validation depends on it.")
        #expect(!f1.isEmpty, "Fingerprint must be non-empty.")
    }

    @Test
    func `pricingFingerprint includes parser logic version`() {
        // The string format is contract: it starts with `v{N}|` where N is
        // `parserLogicVersion`. Tests below rely on this prefix to detect
        // when the parser version was bumped.
        #expect(CostUsagePricing.pricingFingerprint.hasPrefix("v\(CostUsagePricing.parserLogicVersion)|"))
    }

    @Test
    func `pricingFingerprint mentions both codex and claude tables`() {
        let f = CostUsagePricing.pricingFingerprint
        #expect(f.contains("codex="), "Codex pricing keys must be in the fingerprint.")
        #expect(f.contains("claude="), "Claude pricing keys must be in the fingerprint.")
    }

    @Test
    func `pricingFingerprint includes known pricing keys`() {
        let f = CostUsagePricing.pricingFingerprint
        // Sanity: a few keys that MUST be in the table for this build.
        // If these checks fail, somebody dropped a row from
        // CostUsagePricing — fingerprint will roll for users (cache
        // invalidated, full rescan) which is probably the right behavior,
        // but flagging here so the change is intentional.
        #expect(
            f.contains("gpt-5,") || f.hasSuffix("gpt-5"),
            "gpt-5 should be in codex pricing table.")
        #expect(
            f.contains("gpt-5.5"),
            "gpt-5.5 should be in codex pricing table (added in fork 0.23).")
        #expect(
            f.contains("claude-opus-4-7"),
            "claude-opus-4-7 should be in claude pricing table (added in fork 0.23).")
    }

    // MARK: - Cache load/save fingerprint validation

    @Test
    func `loading a cache with no fingerprint returns empty`() throws {
        let root = try Self.tempCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Simulate a pre-0.23.1 cache file: valid version=1 but no
        // fingerprint field. JSON decode succeeds, but load() rejects it
        // because pricingFingerprint==nil mismatches the current expected
        // value, forcing a fresh re-scan.
        let url = CostUsageCacheIO.cacheFileURL(provider: .codex, cacheRoot: root)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let legacyJSON = #"{"version":1,"lastScanUnixMs":12345,"files":{},"days":{}}"#
        try Data(legacyJSON.utf8).write(to: url)

        let loaded = CostUsageCacheIO.load(provider: .codex, cacheRoot: root)
        #expect(
            loaded.lastScanUnixMs == 0,
            "Cache from a build with no fingerprint must be invalidated on load.")
        #expect(
            loaded.pricingFingerprint == CostUsagePricing.pricingFingerprint,
            "Fresh cache must carry the current fingerprint so subsequent saves stamp it.")
    }

    @Test
    func `loading a cache with a stale fingerprint returns empty`() throws {
        let root = try Self.tempCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = CostUsageCacheIO.cacheFileURL(provider: .codex, cacheRoot: root)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let staleJSON = """
        {"version":1,"lastScanUnixMs":99999,"pricingFingerprint":"v0|codex=stale|claude=stale","files":{},"days":{}}
        """
        try Data(staleJSON.utf8).write(to: url)

        let loaded = CostUsageCacheIO.load(provider: .codex, cacheRoot: root)
        #expect(loaded.lastScanUnixMs == 0)
    }

    @Test
    func `saving a cache stamps the current fingerprint, even if caller forgot`() throws {
        let root = try Self.tempCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Caller synthesizes a CostUsageCache without going through load(),
        // forgetting to set the fingerprint. save() must still stamp it so
        // a future launch can validate.
        var cache = CostUsageCache()
        cache.lastScanUnixMs = 42
        cache.pricingFingerprint = nil

        CostUsageCacheIO.save(provider: .codex, cache: cache, cacheRoot: root)

        let reloaded = CostUsageCacheIO.load(provider: .codex, cacheRoot: root)
        #expect(
            reloaded.lastScanUnixMs == 42,
            "Save+load roundtrip should preserve data when fingerprint matches.")
        #expect(reloaded.pricingFingerprint == CostUsagePricing.pricingFingerprint)
    }

    @Test
    func `saving and reloading roundtrips lastScanUnixMs`() throws {
        let root = try Self.tempCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var fresh = CostUsageCacheIO.load(provider: .codex, cacheRoot: root)
        fresh.lastScanUnixMs = 1_700_000_000
        CostUsageCacheIO.save(provider: .codex, cache: fresh, cacheRoot: root)

        let reloaded = CostUsageCacheIO.load(provider: .codex, cacheRoot: root)
        #expect(reloaded.lastScanUnixMs == 1_700_000_000)
    }

    // MARK: - Helpers

    private static func tempCacheRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "codexbar-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
