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
        try? self.readIfPresent(at: url)
    }

    /// Returns nil for a missing path and throws when an existing source cannot be inspected.
    static func readIfPresent(at url: URL) throws -> Self? {
        var info = stat()
        guard url.path.withCString({ fstatat(AT_FDCWD, $0, &info, 0) }) == 0 else {
            let code = errno
            if code == ENOENT || code == ENOTDIR { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: url.path])
        }
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

    static func isMissingFileError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain {
            return error.code == Int(ENOENT) || error.code == Int(ENOTDIR)
        }
        if error.domain == NSCocoaErrorDomain,
           error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError
        {
            return true
        }
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error else { return false }
        return self.isMissingFileError(underlying)
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
    @TaskLocal static var observeWireEntriesForTesting: (@Sendable (Int) -> Void)?
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
        var quotaSlices: QuotaSlices?
        var hasWindowScopedRows: Bool?
    }

    private struct QuotaSlices: Codable {
        let values: [CostUsageTimedEntry]

        init(values: [CostUsageTimedEntry]) {
            self.values = values
        }

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            var values: [CostUsageTimedEntry] = []
            values.reserveCapacity(container.count ?? 0)
            while !container.isAtEnd {
                let wire = try container.decode(CostUsageCodexPreviousReport.QuotaSlice.self)
                #if DEBUG
                CostUsageClaudeReportMemo.observeWireEntriesForTesting?(1)
                #endif
                values.append(wire.timedValue)
            }
            self.values = values
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            for value in self.values {
                let wire = CostUsageCodexPreviousReport.QuotaSlice(value)
                #if DEBUG
                CostUsageClaudeReportMemo.observeWireEntriesForTesting?(1)
                #endif
                try container.encode(wire)
            }
        }
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
        guard let loaded = try? CostUsageClaudeFragments.shared.load(at: url, legacy: { data in
            var envelope = try JSONDecoder().decode(PersistedEnvelope.self, from: data)
            let inventory = envelope.sourceInventory
            envelope.sourceInventory = [:]
            return (envelope, inventory)
        }) else { return nil }
        var envelope: PersistedEnvelope = loaded.0
        envelope.sourceInventory = loaded.1
        guard envelope.version == Self.persistedVersion,
              envelope.reportSemanticsVersion == Self.reportSemanticsVersion,
              Self.hasValidIncompleteCounts(envelope.report)
        else { return nil }
        return Entry(
            sourceInventory: envelope.sourceInventory,
            reportKey: envelope.reportKey,
            report: CostUsageDailyReport(
                data: envelope.report.data,
                summary: envelope.report.summary,
                hourly: (envelope.hourly ?? []).map(\.hourlyValue),
                quotaSlices: envelope.quotaSlices?.values ?? []),
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
            sourceInventory: [:],
            reportKey: entry.reportKey,
            report: entry.report,
            hourly: entry.report.hourly.map(CostUsageCodexPreviousReport.HourlyEntry.init),
            quotaSlices: QuotaSlices(values: entry.report.quotaSlices),
            hasWindowScopedRows: entry.hasWindowScopedRows)
        _ = try? CostUsageClaudeFragments.shared.save(header: envelope, values: entry.sourceInventory, at: url)
    }
}

#if DEBUG
extension CostUsageScanner {
    enum ClaudeScanWork: Sendable {
        case cacheDecode
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

    @TaskLocal static var observeClaudeScanWorkForTesting: (@Sendable (ClaudeScanWork) -> Void)?

    static func recordClaudeScanWork(_ work: ClaudeScanWork) {
        self.observeClaudeScanWorkForTesting?(work)
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

    final class File: Codable, Equatable {
        let usage: CostUsageFileUsage?
        let sourceID: String?
        let sourceKey: String?
        private let metadata: Data
        private enum CodingKeys: CodingKey { case usage, sourceID, sourceKey }

        init(usage: CostUsageFileUsage?, sourceID: String?, sourceKey: String?, encoder: JSONEncoder) throws {
            self.usage = usage
            self.sourceID = sourceID
            self.sourceKey = sourceKey
            var metadata = usage
            metadata?.claudeRows = nil
            self.metadata = try encoder.encode(metadata)
        }

        convenience init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try self.init(
                usage: container.decodeIfPresent(CostUsageFileUsage.self, forKey: .usage),
                sourceID: container.decodeIfPresent(String.self, forKey: .sourceID),
                sourceKey: container.decodeIfPresent(String.self, forKey: .sourceKey),
                encoder: encoder)
        }

        static func == (lhs: File, rhs: File) -> Bool {
            guard lhs.metadata == rhs.metadata, self.sameString(lhs.sourceID, rhs.sourceID),
                  self.sameString(lhs.sourceKey, rhs.sourceKey) else { return false }
            let left = lhs.usage?.claudeRows, right = rhs.usage?.claudeRows
            guard let left, let right else { return left == nil && right == nil }
            guard left.count == right.count else { return false }
            if left.withUnsafeBufferPointer({ buffer in
                right.withUnsafeBufferPointer { buffer.baseAddress == $0.baseAddress }
            }) { return true }
            return zip(left, right).allSatisfy { a, b in
                a == b && Self.sameString(a.dayKey, b.dayKey) && Self.sameString(a.model, b.model)
                    && Self.sameString(a.sessionId, b.sessionId) && Self.sameString(a.messageId, b.messageId)
                    && Self.sameString(a.requestId, b.requestId)
            }
        }

        private static func sameString(_ lhs: String?, _ rhs: String?) -> Bool {
            guard let lhs, let rhs else { return lhs == nil && rhs == nil }
            return lhs.utf8.elementsEqual(rhs.utf8)
        }
    }

    private(set) var contentID = UUID() // Swift string equality is not byte identity for JSON.

    private enum CodingKeys: String, CodingKey { case sourceFileIDs }

    init() {}

    init(usage: CostUsageCache, sourceFileIDs: [String: String]) {
        self.usage = usage
        self.sourceFileIDs = sourceFileIDs
    }

    func split() throws -> (Self, [String: File]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var files: [String: File] = [:]
        for path in self.usage.files.keys {
            let sourceKey = self.sourceFileIDs.index(forKey: path).map { self.sourceFileIDs[$0].key }
            files[path] = try File(
                usage: self.usage.files[path],
                sourceID: self.sourceFileIDs[path],
                sourceKey: sourceKey,
                encoder: encoder)
        }
        for (path, identity) in self.sourceFileIDs where self.usage.files[path] == nil {
            files[path] = try File(usage: nil, sourceID: identity, sourceKey: path, encoder: encoder)
        }
        var header = self
        header.usage.files = [:]
        header.sourceFileIDs = [:]
        header.contentID = self.contentID
        return (header, files)
    }

    mutating func join(_ files: [String: File]) {
        let contentID = self.contentID
        self.usage.files = files.compactMapValues(\.usage)
        self.sourceFileIDs = files.reduce(into: [:]) { identities, entry in
            if let identity = entry.value.sourceID { identities[entry.value.sourceKey ?? entry.key] = identity }
        }
        self.contentID = contentID
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

    #if DEBUG
    @TaskLocal static var readForTesting: (@Sendable (URL, Data.ReadingOptions) -> Data?)?
    #endif

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

    // Provider-specific by design: Claude/Vertex share shards but keep separate artifacts and report windows.

    static func cacheFileURL(
        provider: UsageProvider,
        cacheRoot: URL? = nil,
        reportContext: CostUsageReportContext = .regular) -> URL
    {
        precondition(provider == .claude || provider == .vertexai)
        let root = cacheRoot ?? self.defaultCacheRoot()
        let generation = switch provider {
        case .claude: 18
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
        let key = url.standardizedFileURL.resolvingSymlinksInPath()
        guard let loaded = try? CostUsageClaudeFragments.shared.load(at: key, legacy: { data in
            let decoder = JSONDecoder()
            decoder.userInfo[ClaudeRowStringPool.key] = ClaudeRowStringPool()
            return try decoder.decode(CostUsageClaudeCacheArtifact.self, from: data).split()
        }) else { return CostUsageClaudeCacheArtifact() }
        var artifact: CostUsageClaudeCacheArtifact = loaded.0
        artifact.join(loaded.1)
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
        let key = url.standardizedFileURL.resolvingSymlinksInPath()
        try checkCancellation?()
        if let stamp = CostUsageClaudeFragments.shared.currentStamp(contentID: artifact.contentID, at: key) {
            return stamp
        }
        #if DEBUG
        CostUsageScanner.recordClaudeScanWork(.cacheEncode)
        #endif
        let (header, files) = try artifact.split()
        return try CostUsageClaudeFragments.shared.save(
            header: header,
            values: files,
            at: key,
            contentID: artifact.contentID,
            checkCancellation: checkCancellation)
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

    static func read(at url: URL, options: Data.ReadingOptions = []) -> Data? {
        #if DEBUG
        CostUsageScanner.recordClaudeScanWork(.artifactRead)
        if let readForTesting { return readForTesting(url, options) }
        #endif
        return try? Data(contentsOf: url, options: options)
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
