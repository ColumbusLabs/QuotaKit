import Foundation

enum PiSessionCostCacheIO {
    /// Artifact schema version. Pricing changes are tracked separately by `pricingKey`.
    /// v10 adds per-session project, title and last-reply metadata, which requires one full reparse.
    static let artifactVersion = 10

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
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PiSessionCostCache.self, from: data),
              decoded.version == Self.artifactVersion
        else {
            return PiSessionCostCache(version: Self.artifactVersion)
        }
        return decoded
    }

    /// A released v9 artifact can preserve the last known totals during an unsuccessful upgrade scan.
    /// Its file checkpoints must never be used to construct v10 session metadata.
    static func loadLegacyFallback(cacheRoot: URL? = nil) -> PiSessionCostCache? {
        let url = self.cacheFileURL(cacheRoot: cacheRoot)
            .deletingLastPathComponent().appendingPathComponent("pi-sessions-v9.json")
        guard let data = try? Data(contentsOf: url),
              let legacy = try? JSONDecoder().decode(LegacyCache.self, from: data),
              legacy.version == 9
        else { return nil }
        var cache = PiSessionCostCache()
        cache.lastScanUnixMs = legacy.lastScanUnixMs
        cache.scanSinceKey = legacy.scanSinceKey
        cache.scanUntilKey = legacy.scanUntilKey
        cache.timeZoneIdentifier = legacy.timeZoneIdentifier
        cache.pricingKey = legacy.pricingKey
        cache.sessionRootsFingerprint = legacy.sessionRootsFingerprint
        cache.daysByProvider = legacy.daysByProvider
        cache.files = legacy.files
        return cache
    }

    private struct LegacyCache: Decodable {
        let version: Int
        let lastScanUnixMs: Int64
        let scanSinceKey: String?
        let scanUntilKey: String?
        let timeZoneIdentifier: String?
        let pricingKey: String?
        let sessionRootsFingerprint: String?
        let daysByProvider: [String: [String: [String: PiPackedUsage]]]
        let files: [String: PiSessionFileUsage]
    }

    static func save(
        cache: PiSessionCostCache,
        cacheRoot: URL? = nil,
        calendar: Calendar = .current)
    {
        let url = self.cacheFileURL(cacheRoot: cacheRoot)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var cache = cache
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        guard let data = try? JSONEncoder().encode(cache) else { return }
        // Write at the final path: FileManager replacement can lose the destination on Linux.
        try? data.write(to: url, options: [.atomic])
    }
}

struct PiSessionCostCache: Codable {
    var version: Int
    var lastScanUnixMs: Int64 = 0
    var scanSinceKey: String?
    var scanUntilKey: String?
    var timeZoneIdentifier: String?
    var pricingKey: String?
    var sessionRootsFingerprint: String?
    var daysByProvider: [String: [String: [String: PiPackedUsage]]] = [:]
    /// Deduped usage per session key; written only by the rebuild that writes `daysByProvider`.
    var sessions: [String: PiSessionUsage] = [:]
    var files: [String: PiSessionFileUsage] = [:]

    init(version: Int = PiSessionCostCacheIO.artifactVersion) {
        self.version = version
    }
}

struct PiSessionUsage: Codable, Equatable {
    var projectPath: String?
    /// Pi `--…--` project folder name, kept only when the header has no usable `cwd`.
    var projectSlug: String?
    var title: String?
    var lastActivityUnixMs: Int64
    var contributions: [String: [String: [String: PiPackedUsage]]]
}

struct PiSessionFileUsage: Codable {
    var mtimeUnixMs: Int64
    var size: Int64
    var parsedBytes: Int64
    var fileIdentity: String?
    var sessionID: String?
    var projectPath: String?
    var title: String?
    var lastModelContext: PiModelContext?
    /// Newest assistant reply in the scan window; nil in early v10 artifacts or when no reply has a timestamp.
    var lastAssistantUnixMs: Int64?
    var contributions: [String: [String: [String: PiPackedUsage]]]
    var unkeyedContributions: [String: [String: [String: PiPackedUsage]]]
    var entryUsages: [String: PiSessionEntryUsage]
    var unsupportedAssistantDayKeys: Set<String>
    var hasUndatedUnsupportedAssistant: Bool

    init(
        mtimeUnixMs: Int64,
        size: Int64,
        parsedBytes: Int64,
        fileIdentity: String? = nil,
        sessionID: String? = nil,
        projectPath: String? = nil,
        title: String? = nil,
        lastModelContext: PiModelContext?,
        lastAssistantUnixMs: Int64? = nil,
        contributions: [String: [String: [String: PiPackedUsage]]],
        unkeyedContributions: [String: [String: [String: PiPackedUsage]]] = [:],
        entryUsages: [String: PiSessionEntryUsage] = [:],
        unsupportedAssistantDayKeys: Set<String> = [],
        hasUndatedUnsupportedAssistant: Bool = false)
    {
        self.mtimeUnixMs = mtimeUnixMs
        self.size = size
        self.parsedBytes = parsedBytes
        self.fileIdentity = fileIdentity
        self.sessionID = sessionID
        self.projectPath = projectPath
        self.title = title
        self.lastModelContext = lastModelContext
        self.lastAssistantUnixMs = lastAssistantUnixMs
        self.contributions = contributions
        self.unkeyedContributions = unkeyedContributions
        self.entryUsages = entryUsages
        self.unsupportedAssistantDayKeys = unsupportedAssistantDayKeys
        self.hasUndatedUnsupportedAssistant = hasUndatedUnsupportedAssistant
    }

    var requiresFullReparseOnChange: Bool {
        self.hasUndatedUnsupportedAssistant || !self.unsupportedAssistantDayKeys.isEmpty ||
            self.contributions.values.contains { days in
                days.values.contains { models in
                    models.values.contains { ($0.usageSampleCount ?? 0) > $0.costSampleCount }
                }
            }
    }
}

struct PiSessionEntryUsage: Codable, Equatable {
    var providerRawValue: String
    var dayKey: String
    var modelName: String
    var usage: PiPackedUsage
}

struct PiModelContext: Codable, Equatable {
    var providerRawValue: String
    var modelName: String
    var isUnsupportedBackend: Bool = false
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
