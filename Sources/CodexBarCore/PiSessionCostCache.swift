import Foundation

enum PiSessionCostCacheIO {
    /// Artifact version 2 is shared by both upstream's stale-cache rebuild fix
    /// (78e186d4) and our pricing-fingerprint invalidation (fork 0.23.1):
    /// pi-session cache stores per-(day, provider, model) packed usage with
    /// `costNanos` baked in at parse time. Pre-0.23 entries used pricing
    /// without `gpt-5.5` and without the fallback resolver, so cached
    /// `costNanos` are stale. Bumping the file version sidesteps the
    /// migration entirely (old cache file ignored, fresh scan at next launch).
    private static let artifactVersion = 2

    private static func defaultCacheRoot() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("CodexBar", isDirectory: true)
    }

    static func cacheFileURL(cacheRoot: URL? = nil) -> URL {
        let root = cacheRoot ?? self.defaultCacheRoot()
        return root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("pi-sessions-v\(Self.artifactVersion).json", isDirectory: false)
    }

    static func load(cacheRoot: URL? = nil) -> PiSessionCostCache {
        let url = self.cacheFileURL(cacheRoot: cacheRoot)
        let expectedFingerprint = CostUsagePricing.pricingFingerprint
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PiSessionCostCache.self, from: data),
              decoded.version == Self.artifactVersion,
              // Same fingerprint-mismatch invalidation as CostUsageCacheIO.
              // See `CostUsagePricing.pricingFingerprint` doc-comment for
              // why baked-in costNanos can't be retroactively re-priced.
              decoded.pricingFingerprint == expectedFingerprint
        else {
            return PiSessionCostCache(
                version: Self.artifactVersion,
                pricingFingerprint: expectedFingerprint)
        }
        return decoded
    }

    static func save(cache: PiSessionCostCache, cacheRoot: URL? = nil) {
        let url = self.cacheFileURL(cacheRoot: cacheRoot)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Stamp the current fingerprint so a future launch can validate.
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

struct PiSessionCostCache: Codable {
    var version: Int
    var lastScanUnixMs: Int64 = 0
    var scanSinceKey: String?
    var scanUntilKey: String?
    /// Pricing fingerprint at the moment this cache was written. Mismatches
    /// trigger full re-scan in `load`. See
    /// `CostUsagePricing.pricingFingerprint`.
    var pricingFingerprint: String?
    var daysByProvider: [String: [String: [String: PiPackedUsage]]] = [:]
    var files: [String: PiSessionFileUsage] = [:]

    init(version: Int = 2, pricingFingerprint: String? = nil) {
        self.version = version
        self.pricingFingerprint = pricingFingerprint
    }
}

struct PiSessionFileUsage: Codable {
    var mtimeUnixMs: Int64
    var size: Int64
    var parsedBytes: Int64
    var lastModelContext: PiModelContext?
    var contributions: [String: [String: [String: PiPackedUsage]]]
}

struct PiModelContext: Codable, Equatable {
    var providerRawValue: String
    var modelName: String
}

struct PiPackedUsage: Codable, Equatable {
    var inputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
    var outputTokens: Int = 0
    var totalTokens: Int = 0
    var costNanos: Int64 = 0
    var costSampleCount: Int = 0
    var usageSampleCount: Int?

    var isZero: Bool {
        self.inputTokens == 0
            && self.cacheReadTokens == 0
            && self.cacheWriteTokens == 0
            && self.outputTokens == 0
            && self.totalTokens == 0
            && self.costNanos == 0
            && self.costSampleCount == 0
            && (self.usageSampleCount ?? 0) == 0
    }
}
