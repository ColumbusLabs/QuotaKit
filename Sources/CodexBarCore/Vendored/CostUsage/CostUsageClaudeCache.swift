#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

struct CostUsageClaudeFileStamp: Equatable, Sendable, Codable {
    let fileID: String
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64

    var mtimeUnixMs: Int64 {
        self.modifiedSeconds * 1000 + self.modifiedNanoseconds / 1_000_000
    }

    static func read(at url: URL) -> Self? {
        var info = stat()
        guard url.path.withCString({ fstatat(AT_FDCWD, $0, &info, 0) }) == 0 else { return nil }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { return nil }
        #if os(Linux)
        let modifiedSeconds = Int64(info.st_mtim.tv_sec)
        let modifiedNanoseconds = Int64(info.st_mtim.tv_nsec)
        #else
        let modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
        let modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
        #endif
        return Self(
            fileID: "\(info.st_dev):\(info.st_ino)",
            size: Int64(info.st_size),
            modifiedSeconds: modifiedSeconds,
            modifiedNanoseconds: modifiedNanoseconds)
    }
}

struct CostUsageClaudeReportMemoKey: Equatable, Sendable, Codable {
    let provider: UsageProvider
    let providerFilter: String
    let sinceKey: String
    let untilKey: String
    let scanSinceKey: String
    let scanUntilKey: String
    let timeZoneIdentifier: String
    let roots: [String]
    var cacheArtifactStamp: CostUsageClaudeFileStamp?
    let pricingArtifactStamp: CostUsageClaudeFileStamp?

    var scanConfiguration: ScanConfiguration {
        ScanConfiguration(
            provider: self.provider,
            providerFilter: self.providerFilter,
            timeZoneIdentifier: self.timeZoneIdentifier,
            roots: self.roots)
    }

    struct ScanConfiguration: Equatable, Sendable {
        let provider: UsageProvider
        let providerFilter: String
        let timeZoneIdentifier: String
        let roots: [String]
    }
}

final class CostUsageClaudeReportMemo: @unchecked Sendable {
    struct Entry {
        let sourceInventory: [String: CostUsageClaudeFileStamp]
        let reportKey: CostUsageClaudeReportMemoKey
        let report: CostUsageDailyReport
        let hasWindowScopedRows: Bool

        func certifiesWindow(reportKey: CostUsageClaudeReportMemoKey, cache: CostUsageCache) -> Bool {
            self.hasWindowScopedRows
                && self.reportKey.cacheArtifactStamp == reportKey.cacheArtifactStamp
                && self.reportKey.scanConfiguration == reportKey.scanConfiguration
                && self.reportKey.scanSinceKey == reportKey.scanSinceKey
                && self.reportKey.scanUntilKey == reportKey.scanUntilKey
                && cache.scanSinceKey == reportKey.scanSinceKey
                && cache.scanUntilKey == reportKey.scanUntilKey
        }
    }

    #if DEBUG
    @TaskLocal static var shared = CostUsageClaudeReportMemo()
    #else
    static let shared = CostUsageClaudeReportMemo()
    #endif
    static let persistedVersion = 1
    /// Bump when pricing, aliases, or report aggregation changes without new artifact stamps.
    static let reportSemanticsVersion = 6

    private struct StoredEntry {
        let entry: Entry
        let generation: UInt64
    }

    private struct PersistedEnvelope: Codable {
        var version: Int
        var reportSemanticsVersion: Int
        var sourceInventory: [String: CostUsageClaudeFileStamp]
        var reportKey: CostUsageClaudeReportMemoKey
        var report: CostUsageDailyReport
        var hourly: [CostUsageCodexPreviousReport.HourlyEntry]?
        var quotaSlices: [CostUsageCodexPreviousReport.QuotaSlice]?
        var hasWindowScopedRows: Bool?
    }

    private let lock = NSLock()
    private let capacity = 8
    private var generation: UInt64 = 0
    private var entries: [String: StoredEntry] = [:]

    func entry(provider: UsageProvider, canonicalCachePath: String) -> Entry? {
        let key = Self.key(provider: provider, canonicalCachePath: canonicalCachePath)
        self.lock.lock()
        if let memory = self.entries[key]?.entry {
            self.lock.unlock()
            return memory
        }
        self.lock.unlock()

        guard let persisted = Self.loadPersisted(canonicalCachePath: canonicalCachePath) else { return nil }
        self.lock.lock()
        defer { self.lock.unlock() }
        if let memory = self.entries[key]?.entry { return memory }
        self.installUnlocked(key: key, entry: persisted)
        return persisted
    }

    func store(
        provider: UsageProvider,
        canonicalCachePath: String,
        sourceInventory: [String: CostUsageClaudeFileStamp],
        reportKey: CostUsageClaudeReportMemoKey,
        report: CostUsageDailyReport,
        hasWindowScopedRows: Bool = false)
    {
        let key = Self.key(provider: provider, canonicalCachePath: canonicalCachePath)
        let entry = Entry(
            sourceInventory: sourceInventory,
            reportKey: reportKey,
            report: report,
            hasWindowScopedRows: hasWindowScopedRows)
        self.lock.lock()
        self.installUnlocked(key: key, entry: entry)
        self.lock.unlock()
        Self.persist(entry, canonicalCachePath: canonicalCachePath)
    }

    private func installUnlocked(key: String, entry: Entry) {
        self.generation &+= 1
        self.entries[key] = StoredEntry(
            entry: entry,
            generation: self.generation)
        if self.entries.count > self.capacity,
           let oldest = self.entries.min(by: { $0.value.generation < $1.value.generation })?.key
        {
            self.entries.removeValue(forKey: oldest)
        }
    }

    #if DEBUG
    func evict(provider: UsageProvider, canonicalCachePath: String) {
        let key = Self.key(provider: provider, canonicalCachePath: canonicalCachePath)
        self.lock.lock()
        defer { self.lock.unlock() }
        self.entries.removeValue(forKey: key)
    }
    #endif

    private static func key(provider: UsageProvider, canonicalCachePath: String) -> String {
        "\(provider.rawValue)|\(canonicalCachePath)"
    }

    static func reportMemoFileURL(cacheFileURL: URL) -> URL {
        let stem = cacheFileURL.deletingPathExtension().lastPathComponent
        return cacheFileURL.deletingLastPathComponent()
            .appendingPathComponent("\(stem).report-memo.json", isDirectory: false)
    }

    private static func loadPersisted(canonicalCachePath: String) -> Entry? {
        let url = Self.reportMemoFileURL(cacheFileURL: URL(fileURLWithPath: canonicalCachePath))
        let stamp = CostUsageClaudeFileStamp.read(at: url)
        guard let data = CostUsageClaudeCacheIO.read(at: url),
              let envelope = try? JSONDecoder().decode(PersistedEnvelope.self, from: data),
              envelope.version == Self.persistedVersion,
              envelope.reportSemanticsVersion == Self.reportSemanticsVersion,
              Self.hasValidIncompleteCounts(envelope.report)
        else { return nil }
        CostUsageClaudeCacheIO.remember(data: data, at: url, stamp: stamp)
        return Entry(
            sourceInventory: envelope.sourceInventory,
            reportKey: envelope.reportKey,
            report: CostUsageDailyReport(
                data: envelope.report.data,
                summary: envelope.report.summary,
                hourly: (envelope.hourly ?? []).map(\.hourlyValue),
                quotaSlices: (envelope.quotaSlices ?? []).map(\.timedValue)),
            hasWindowScopedRows: envelope.hasWindowScopedRows == true)
    }

    private static func hasValidIncompleteCounts(_ report: CostUsageDailyReport) -> Bool {
        let counts = report.data.flatMap { $0.modelBreakdowns ?? [] }.compactMap(\.incompleteRequestCount)
        return counts.allSatisfy { $0 >= 0 } && CheckedSum.integers(counts) != nil
    }

    private static func persist(_ entry: Entry, canonicalCachePath: String) {
        let url = Self.reportMemoFileURL(cacheFileURL: URL(fileURLWithPath: canonicalCachePath))
        let envelope = PersistedEnvelope(
            version: Self.persistedVersion,
            reportSemanticsVersion: Self.reportSemanticsVersion,
            sourceInventory: entry.sourceInventory,
            reportKey: entry.reportKey,
            report: entry.report,
            hourly: entry.report.hourly.map(CostUsageCodexPreviousReport.HourlyEntry.init),
            quotaSlices: entry.report.quotaSlices.map(CostUsageCodexPreviousReport.QuotaSlice.init),
            hasWindowScopedRows: entry.hasWindowScopedRows)
        _ = try? CostUsageClaudeCacheIO.write(envelope, to: url)
    }
}

#if DEBUG
extension CostUsageScanner {
    enum ClaudeScanWork: Sendable {
        case cacheDecode
        case fragmentFallback
        case fragmentEncode
        case transcriptParse(startOffset: Int64)
        case reconcile
        case cacheEncode
        case artifactRead
        case artifactWrite
        case reprice
        case normalizationCacheMiss
        case vertexMetadataWalk
        case claudeLineDecode
        case claudeCostCalculation
        case catalogModelLookup(found: Bool)
    }

    struct ClaudeScanWorkMetrics: Equatable, Sendable {
        var cacheDecodes = 0
        var fragmentEncodes = 0
        var fragmentFallbacks = 0
        var transcriptParses = 0
        var incrementalTranscriptParses = 0
        var reconciliations = 0
        var cacheEncodes = 0
        var repricedRows = 0
        var normalizationCacheMisses = 0
        var vertexMetadataWalks = 0
        var claudeLineDecodes = 0
        var claudeCostCalculations = 0
        var catalogModelLookups = 0
        var catalogModelHits = 0
        var catalogModelMisses = 0
    }

    final class ClaudeScanWorkRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var metrics = ClaudeScanWorkMetrics()
        private var artifactIO = (reads: 0, writes: 0)

        func record(_ work: ClaudeScanWork) {
            self.lock.lock()
            defer { self.lock.unlock() }
            switch work {
            case .cacheDecode: self.metrics.cacheDecodes += 1
            case .fragmentFallback: self.metrics.fragmentFallbacks += 1
            case .fragmentEncode: self.metrics.fragmentEncodes += 1
            case let .transcriptParse(startOffset):
                self.metrics.transcriptParses += 1
                if startOffset > 0 { self.metrics.incrementalTranscriptParses += 1 }
            case .reconcile: self.metrics.reconciliations += 1
            case .cacheEncode: self.metrics.cacheEncodes += 1
            case .artifactRead: self.artifactIO.reads += 1
            case .artifactWrite: self.artifactIO.writes += 1
            case .reprice: self.metrics.repricedRows += 1
            case .normalizationCacheMiss: self.metrics.normalizationCacheMisses += 1
            case .vertexMetadataWalk: self.metrics.vertexMetadataWalks += 1
            case .claudeLineDecode: self.metrics.claudeLineDecodes += 1
            case .claudeCostCalculation: self.metrics.claudeCostCalculations += 1
            case let .catalogModelLookup(found):
                self.metrics.catalogModelLookups += 1
                if found {
                    self.metrics.catalogModelHits += 1
                } else {
                    self.metrics.catalogModelMisses += 1
                }
            }
        }

        func snapshot() -> ClaudeScanWorkMetrics {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.metrics
        }

        func persistenceSnapshot() -> (reads: Int, writes: Int) {
            self.lock.withLock { self.artifactIO }
        }
    }

    @TaskLocal private static var claudeScanWorkRecorder: ClaudeScanWorkRecorder?

    static func withClaudeScanWorkRecorderForTesting<T>(
        _ recorder: ClaudeScanWorkRecorder,
        operation: () throws -> T) rethrows -> T
    {
        try self.$claudeScanWorkRecorder.withValue(recorder) {
            try operation()
        }
    }

    static func recordClaudeScanWork(_ work: ClaudeScanWork) {
        self.claudeScanWorkRecorder?.record(work)
    }

    static func evictClaudeReportMemoForTesting(
        provider: UsageProvider,
        cacheRoot: URL?,
        reportContext: CostUsageReportContext = .regular)
    {
        let cacheURL = CostUsageClaudeCacheIO.cacheFileURL(
            provider: provider, cacheRoot: cacheRoot, reportContext: reportContext)
        let canonicalCachePath = cacheURL.standardizedFileURL.resolvingSymlinksInPath().path
        CostUsageClaudeReportMemo.shared.evict(
            provider: provider,
            canonicalCachePath: canonicalCachePath)
    }
}
#endif

struct CostUsageClaudeCacheArtifact: Codable {
    var usage = CostUsageCache() {
        didSet { self.contentID = UUID() }
    }

    var sourceFileIDs: [String: String] = [:] {
        didSet { self.contentID = UUID() }
    }

    private(set) var contentID = UUID() // Swift string equality is not byte identity for JSON.

    private enum CodingKeys: String, CodingKey { case sourceFileIDs }

    init() {}

    init(usage: CostUsageCache, sourceFileIDs: [String: String]) {
        self.usage = usage
        self.sourceFileIDs = sourceFileIDs
    }

    mutating func updateUsageIfChanged(to usage: CostUsageCache) {
        if self.usage != usage {
            self.usage = usage
        }
    }

    mutating func updateSourceFileIDs(
        _ sourceFileIDs: [String: String],
        presentIn inventory: [String: CostUsageClaudeFileStamp])
    {
        let retained = sourceFileIDs.filter { inventory[$0.key] != nil }
        if self.sourceFileIDs != retained {
            self.sourceFileIDs = retained
        }
    }

    init(from decoder: any Decoder) throws {
        self.usage = try CostUsageCache(from: decoder)
        self.sourceFileIDs = try decoder.container(keyedBy: CodingKeys.self)
            .decodeIfPresent([String: String].self, forKey: .sourceFileIDs) ?? [:]
    }

    func encode(to encoder: any Encoder) throws {
        try self.usage.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.sourceFileIDs, forKey: .sourceFileIDs)
    }
}

/// Claude and Vertex retain their small transcript cache. Codex deliberately has no route
/// through this JSON I/O boundary; its only persistence authority is `CostUsageStore`.
enum CostUsageClaudeCacheIO {
    /// Compact row keys; older artifacts rebuild from their source transcripts.
    private static let schemaVersion = 3

    /// Decoded rows may be evicted under pressure; eight small persistence identities survive independently.
    /// Full stamps prevent replacement files from inheriting stale rows or write identities.
    private final class ArtifactMemo: @unchecked Sendable {
        final class Entry {
            let stamp: CostUsageClaudeFileStamp
            let artifact: CostUsageClaudeCacheArtifact

            init(stamp: CostUsageClaudeFileStamp, artifact: CostUsageClaudeCacheArtifact) {
                self.stamp = stamp
                self.artifact = artifact
            }
        }

        #if DEBUG
        @TaskLocal static var shared = ArtifactMemo()
        #else
        static let shared = ArtifactMemo()
        #endif
        let entries = NSCache<NSURL, Entry>()

        private let lock = NSLock()
        private typealias Identity = (stamp: CostUsageClaudeFileStamp, digest: SHA256.Digest, contentID: UUID?)
        private var identities: [(url: URL, value: Identity)] = []

        func identity(at url: URL) -> (stamp: CostUsageClaudeFileStamp, digest: SHA256.Digest, contentID: UUID?)? {
            self.lock.withLock { self.identities.last(where: { $0.url == url })?.value }
        }

        func remember(at url: URL, stamp: CostUsageClaudeFileStamp, digest: SHA256.Digest, contentID: UUID?) {
            self.lock.withLock {
                self.identities.removeAll { $0.url == url }
                self.identities.append((url, (stamp, digest, contentID)))
                if self.identities.count > 8 { self.identities.removeFirst() }
            }
        }

        init() {
            self.entries.countLimit = 4
        }
    }

    #if DEBUG
    static func withIsolatedCachesForTesting(operation: @Sendable () async throws -> Void) async throws {
        try await ArtifactMemo.$shared.withValue(ArtifactMemo()) {
            try await CostUsageClaudeReportMemo.$shared.withValue(CostUsageClaudeReportMemo()) {
                try await CostUsageClaudeFragments.$shared.withValue(CostUsageClaudeFragments()) {
                    try await operation()
                }
            }
        }
    }

    static func evictArtifactMemoForTesting(at url: URL) {
        ArtifactMemo.shared.entries.removeObject(forKey: self.memoKey(for: url))
    }
    #endif

    private static func memoKey(for url: URL) -> NSURL {
        url.standardizedFileURL.resolvingSymlinksInPath() as NSURL
    }

    /// Apply the same format and calendar checks on memo hits and fresh decodes.
    private static func validated(
        _ artifact: CostUsageClaudeCacheArtifact,
        calendar: Calendar?) -> CostUsageClaudeCacheArtifact?
    {
        guard artifact.usage.version == self.schemaVersion else { return nil }
        if let calendar, artifact.usage.timeZoneIdentifier != calendar.timeZone.identifier {
            return nil
        }
        return artifact
    }

    private static func defaultCacheRoot() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("CodexBar", isDirectory: true)
    }

    // Provider-specific by design: Claude/Vertex cost caching still uses the legacy JSON artifact pending its own
    // migration (see #2760).

    static func cacheFileURL(
        provider: UsageProvider,
        cacheRoot: URL? = nil,
        reportContext: CostUsageReportContext = .regular) -> URL
    {
        precondition(provider == .claude || provider == .vertexai)
        let root = cacheRoot ?? self.defaultCacheRoot()
        let generation = switch provider {
        case .claude: 16
        case .vertexai: 7
        default: preconditionFailure("unsupported cost cache provider")
        }
        let suffix = reportContext == .spendDashboard ? "-history" : ""
        return root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("\(provider.rawValue)\(suffix)-v\(generation).json", isDirectory: false)
    }

    static func load(
        provider: UsageProvider,
        cacheRoot: URL? = nil,
        reportContext: CostUsageReportContext = .regular,
        calendar: Calendar? = nil) -> CostUsageCache
    {
        self.loadArtifact(
            provider: provider,
            cacheRoot: cacheRoot,
            reportContext: reportContext,
            calendar: calendar).usage
    }

    static func loadArtifact(
        provider: UsageProvider,
        cacheRoot: URL? = nil,
        reportContext: CostUsageReportContext = .regular,
        calendar: Calendar? = nil) -> CostUsageClaudeCacheArtifact
    {
        let url = self.cacheFileURL(provider: provider, cacheRoot: cacheRoot, reportContext: reportContext)
        let key = Self.memoKey(for: url)
        let stamp = CostUsageClaudeFileStamp.read(at: url)
        if let stamp,
           let memoized = ArtifactMemo.shared.entries.object(forKey: key),
           memoized.stamp == stamp
        {
            if CostUsageClaudeFileStamp.read(at: url) == stamp {
                return Self.validated(memoized.artifact, calendar: calendar) ?? CostUsageClaudeCacheArtifact()
            }
        }
        guard let data = self.read(at: url) else { return CostUsageClaudeCacheArtifact() }
        #if DEBUG
        CostUsageScanner.recordClaudeScanWork(.cacheDecode)
        #endif
        guard let artifact = try? JSONDecoder().decode(CostUsageClaudeCacheArtifact.self, from: data) else {
            return CostUsageClaudeCacheArtifact()
        }
        // Memoize only when the bytes read still belong to the pre-read stamp.
        if let stamp, CostUsageClaudeFileStamp.read(at: url) == stamp {
            self.remember(data: data, at: url, stamp: stamp, contentID: artifact.contentID)
            ArtifactMemo.shared.entries.setObject(ArtifactMemo.Entry(stamp: stamp, artifact: artifact), forKey: key)
        }
        return Self.validated(artifact, calendar: calendar) ?? CostUsageClaudeCacheArtifact()
    }

    static func save(
        provider: UsageProvider,
        cache: CostUsageClaudeCacheArtifact,
        usage: CostUsageCache? = nil,
        cacheRoot: URL? = nil,
        reportContext: CostUsageReportContext = .regular,
        calendar: Calendar = .current,
        checkCancellation: CostUsageScanner.CancellationCheck? = nil) throws -> CostUsageClaudeFileStamp?
    {
        let url = self.cacheFileURL(provider: provider, cacheRoot: cacheRoot, reportContext: reportContext)
        var artifact = cache
        if let usage {
            artifact.updateUsageIfChanged(to: usage)
        }
        if artifact.usage.version != self.schemaVersion { artifact.usage.version = self.schemaVersion }
        let timeZoneID = calendar.timeZone.identifier
        if artifact.usage.timeZoneIdentifier?.utf8.elementsEqual(timeZoneID.utf8) != true {
            artifact.usage.timeZoneIdentifier = timeZoneID
        }
        let key = Self.memoKey(for: url)
        let stamp = try self.write(
            artifact, to: url, contentID: artifact.contentID, checkCancellation: checkCancellation)
        if let stamp, CostUsageClaudeFileStamp.read(at: url) == stamp {
            ArtifactMemo.shared.entries.setObject(ArtifactMemo.Entry(stamp: stamp, artifact: artifact), forKey: key)
        }
        return stamp
    }

    /// Preserve the existing cache-only call shape for focused callers and tests.
    static func save(
        provider: UsageProvider,
        cache: CostUsageCache,
        sourceFileIDs: [String: String] = [:],
        cacheRoot: URL? = nil,
        reportContext: CostUsageReportContext = .regular,
        calendar: Calendar = .current,
        checkCancellation: CostUsageScanner.CancellationCheck? = nil) throws -> CostUsageClaudeFileStamp?
    {
        try self.save(
            provider: provider,
            cache: CostUsageClaudeCacheArtifact(usage: cache, sourceFileIDs: sourceFileIDs),
            cacheRoot: cacheRoot,
            reportContext: reportContext,
            calendar: calendar,
            checkCancellation: checkCancellation)
    }

    fileprivate static func write(
        _ value: some Encodable,
        to url: URL,
        contentID: UUID? = nil,
        checkCancellation: CostUsageScanner.CancellationCheck? = nil) throws -> CostUsageClaudeFileStamp?
    {
        let key = url.standardizedFileURL.resolvingSymlinksInPath()
        try checkCancellation?()
        let identity = ArtifactMemo.shared.identity(at: key)
        if let identity, let contentID, identity.contentID == contentID,
           CostUsageClaudeFileStamp.read(at: url) == identity.stamp { return identity.stamp }
        #if DEBUG
        if contentID != nil { CostUsageScanner.recordClaudeScanWork(.cacheEncode) }
        #endif
        let encoder = JSONEncoder()
        // Stable fingerprints preserve stamps when a rescan rebuilds byte-identical content with a new UUID.
        encoder.outputFormatting = [.sortedKeys]
        let data: Data? = if let artifact = value as? CostUsageClaudeCacheArtifact {
            try? CostUsageClaudeFragments.shared.encode(artifact, at: key, encoder: encoder)
        } else {
            try? encoder.encode(value)
        }
        guard let data else { return nil }
        try checkCancellation?()
        let digest = SHA256.hash(data: data)
        if let identity, identity.digest == digest, CostUsageClaudeFileStamp.read(at: url) == identity.stamp {
            ArtifactMemo.shared.remember(at: key, stamp: identity.stamp, digest: digest, contentID: contentID)
            return identity.stamp
        }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".claude-cache-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard (try? data.write(to: temporaryURL)) != nil,
              let stamp = CostUsageClaudeFileStamp.read(at: temporaryURL),
              rename(temporaryURL.path, url.path) == 0
        else {
            return nil
        }
        ArtifactMemo.shared.remember(at: key, stamp: stamp, digest: digest, contentID: contentID)
        #if DEBUG
        CostUsageScanner.recordClaudeScanWork(.artifactWrite)
        #endif
        return stamp
    }

    fileprivate static func read(at url: URL) -> Data? {
        #if DEBUG
        CostUsageScanner.recordClaudeScanWork(.artifactRead)
        #endif
        return try? Data(contentsOf: url)
    }

    fileprivate static func remember(
        data: Data,
        at url: URL,
        stamp: CostUsageClaudeFileStamp?,
        contentID: UUID? = nil)
    {
        guard let stamp, CostUsageClaudeFileStamp.read(at: url) == stamp else { return }
        ArtifactMemo.shared.remember(
            at: url.standardizedFileURL.resolvingSymlinksInPath(),
            stamp: stamp,
            digest: SHA256.hash(data: data),
            contentID: contentID)
    }
}

/// Compact retained rows while preserving the full row model in memory.
extension CostUsageScanner.ClaudeUsageRow {
    enum CodingKeys: String, CodingKey {
        case dayKey = "d"
        case model = "m"
        case sessionId = "s"
        case messageId = "i"
        case requestId = "r"
        case timestampUnixMs = "t"
        case isSidechain = "b"
        case pathRole = "p"
        case input = "in"
        case cacheRead = "cr"
        case cacheCreate = "cc"
        case cacheCreate1h = "ch"
        case output = "out"
        case costNanos = "c"
        case costPriced = "priced"
        case isIncomplete = "partial"
    }
}
