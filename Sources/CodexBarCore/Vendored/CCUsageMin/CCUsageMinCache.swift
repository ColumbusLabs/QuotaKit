import Foundation

enum CCUsageMinCacheIO {
    private static func defaultCacheRoot() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("CodexBar", isDirectory: true)
    }

    static func cacheFileURL(provider: UsageProvider, cacheRoot: URL? = nil) -> URL {
        let root = cacheRoot ?? self.defaultCacheRoot()
        return root
            .appendingPathComponent("ccusage-min", isDirectory: true)
            .appendingPathComponent("\(provider.rawValue)-v1.json", isDirectory: false)
    }

    static func load(provider: UsageProvider, cacheRoot: URL? = nil) -> CCUsageMinCache {
        let url = self.cacheFileURL(provider: provider, cacheRoot: cacheRoot)
        guard let data = try? Data(contentsOf: url) else { return CCUsageMinCache() }
        guard let decoded = try? JSONDecoder().decode(CCUsageMinCache.self, from: data)
        else { return CCUsageMinCache() }
        guard decoded.version == 1 else { return CCUsageMinCache() }
        return decoded
    }

    static func save(provider: UsageProvider, cache: CCUsageMinCache, cacheRoot: URL? = nil) {
        let url = self.cacheFileURL(provider: provider, cacheRoot: cacheRoot)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmp = dir.appendingPathComponent(".tmp-\(UUID().uuidString).json", isDirectory: false)
        let data = (try? JSONEncoder().encode(cache)) ?? Data()
        do {
            try data.write(to: tmp, options: [.atomic])
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}

struct CCUsageMinCache: Codable, Sendable {
    var version: Int = 1
    var lastScanUnixMs: Int64 = 0

    // filePath -> file usage
    var files: [String: CCUsageMinFileUsage] = [:]

    // dayKey -> model -> packed usage
    var days: [String: [String: [Int]]] = [:]
}

struct CCUsageMinFileUsage: Codable, Sendable {
    var mtimeUnixMs: Int64
    var size: Int64
    var days: [String: [String: [Int]]]
}
