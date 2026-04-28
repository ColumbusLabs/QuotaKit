import Foundation

enum CostUsageCacheIO {
    private static func artifactVersion(for provider: UsageProvider) -> Int {
        switch provider {
        case .codex:
            // Bumped 4 → 5 in fork 0.23.1 hotfix: the 0.20.3 → 0.23 upgrade
            // added gpt-5.5 to pricing + introduced the fallback resolver,
            // but `codex-v4.json` cache from 0.20.3 era kept stale model
            // attributions (tokens under `gpt-5` instead of `gpt-5.5`).
            5
        case .claude, .vertexai:
            // Bumped 2 → 3 alongside the codex bump for consistency: the
            // claude pricing table also gained `claude-opus-4-7` and the
            // fallback resolver, so any cached cost rows from 0.20.3 era
            // need to be re-derived under the new pricing.
            3
        default:
            1
        }
    }

    private static func defaultCacheRoot() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("CodexBar", isDirectory: true)
    }

    static func cacheFileURL(provider: UsageProvider, cacheRoot: URL? = nil) -> URL {
        let root = cacheRoot ?? self.defaultCacheRoot()
        let artifactVersion = self.artifactVersion(for: provider)
        return root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("\(provider.rawValue)-v\(artifactVersion).json", isDirectory: false)
    }

    static func load(provider: UsageProvider, cacheRoot: URL? = nil) -> CostUsageCache {
        let url = self.cacheFileURL(provider: provider, cacheRoot: cacheRoot)
        let expectedFingerprint = CostUsagePricing.pricingFingerprint
        if let decoded = self.loadCache(at: url, expectedFingerprint: expectedFingerprint) {
            return decoded
        }
        // Fresh cache stamps the current fingerprint so subsequent saves
        // carry it forward — no separate "first save" path needed.
        var fresh = CostUsageCache()
        fresh.pricingFingerprint = expectedFingerprint
        return fresh
    }

    private static func loadCache(at url: URL, expectedFingerprint: String) -> CostUsageCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded = try? JSONDecoder().decode(CostUsageCache.self, from: data)
        else { return nil }
        guard decoded.version == 1 else { return nil }
        // Fingerprint mismatch means the pricing tables OR parser logic
        // changed since this cache was written. Token attributions are
        // baked in at parse time and can't be retroactively fixed —
        // safest action is to discard and force a fresh scan. See
        // `CostUsagePricing.pricingFingerprint` for the fingerprint
        // composition.
        guard decoded.pricingFingerprint == expectedFingerprint else { return nil }
        return decoded
    }

    static func save(provider: UsageProvider, cache: CostUsageCache, cacheRoot: URL? = nil) {
        let url = self.cacheFileURL(provider: provider, cacheRoot: cacheRoot)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Always stamp the current fingerprint on save so a subsequent
        // app launch will validate the match. Callers building a cache
        // from scratch via `load(...)` already get the right fingerprint;
        // this guard catches paths that synthesize a `CostUsageCache()`
        // directly without going through `load`.
        var stamped = cache
        stamped.pricingFingerprint = CostUsagePricing.pricingFingerprint

        let tmp = dir.appendingPathComponent(".tmp-\(UUID().uuidString).json", isDirectory: false)
        let data = (try? JSONEncoder().encode(stamped)) ?? Data()
        do {
            try data.write(to: tmp, options: [.atomic])
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}

struct CostUsageCache: Codable {
    var version: Int = 1
    var lastScanUnixMs: Int64 = 0

    /// Pricing-table + parser fingerprint at the moment this cache was
    /// written. `CostUsageCacheIO.load` invalidates any cache whose
    /// fingerprint doesn't match the current `CostUsagePricing.pricingFingerprint`.
    /// **Optional** so old caches without the field still decode (they
    /// then mismatch nil ≠ current → invalidated, re-scan, win-win).
    var pricingFingerprint: String?

    /// filePath -> file usage
    var files: [String: CostUsageFileUsage] = [:]

    /// dayKey -> model -> packed usage
    var days: [String: [String: [Int]]] = [:]

    /// rootPath -> mtime (for Claude roots)
    var roots: [String: Int64]?
}

struct CostUsageFileUsage: Codable {
    var mtimeUnixMs: Int64
    var size: Int64
    var days: [String: [String: [Int]]]
    var parsedBytes: Int64?
    var lastModel: String?
    var lastTotals: CostUsageCodexTotals?
    var sessionId: String?
    var forkedFromId: String?
    var claudeRows: [CostUsageScanner.ClaudeUsageRow]?
}

struct CostUsageCodexTotals: Codable {
    var input: Int
    var cached: Int
    var output: Int
}
