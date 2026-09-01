import Foundation

struct CostUsageStoreTotals: Codable, Equatable, Sendable {
    var input: Int64
    var cached: Int64
    var output: Int64
    var reasoning: Int64?

    static let zero = Self(input: 0, cached: 0, output: 0, reasoning: nil)
}

struct CostUsageStoreValidationAnchor: Codable, Equatable, Sendable {
    var indexedBytes: Int64
    var windowStart: Int64
    var sha256: String
}

struct CostUsageStoreScanState: Codable, Equatable, Sendable {
    var targetSize: Int64?
    var isComplete: Bool
    var resumePayload: Data?
    var tokenTimestampsMonotonic: Bool?
    var nextUsageRowIndex: Int?
    var lastModel: String?
    var lastTurnID: String?
    var fileIdentity: String?
    var detailsPayload: Data?
    var inventoryValidationGeneration: String?
}

struct CostUsageStoreFile: Codable, Equatable, Sendable {
    var path: String
    var inode: Int64?
    var mtimeUnixMs: Int64
    var size: Int64
    var parsedBytes: Int64?
    var anchor: CostUsageStoreValidationAnchor?
    var scanState: CostUsageStoreScanState
    var sessionID: String?
    var coverageSinceDay: String?
    var coverageUntilDay: String?
    var updatedAtUnixMs: Int64
    var hasBufferedSubagentLines: Bool?
    var hasBufferedUnresolvedForkLines: Bool?
}

struct CostUsageStoreTokenSnapshot: Codable, Equatable, Sendable {
    var path: String
    var eventIndex: Int
    var timestamp: String
    var timestampUnixMs: Int64?
    var day: String?
    var last: CostUsageStoreTotals?
    var total: CostUsageStoreTotals?
    var endOffset: Int64?
}

struct CostUsageStoreUsageRow: Codable, Equatable, Sendable {
    var path: String
    var rowIndex: Int
    var payload: Data
}

struct CostUsageStoreDayAggregate: Codable, Equatable, Sendable {
    var day: String
    var model: String
    var inputTokens: Int64
    var cachedTokens: Int64
    var outputTokens: Int64
    var reasoningTokens: Int64
    var requestCount: Int64
    var unpricedRequestCount: Int64
    var authoritativeCostNanos: Int64
    var standardAuthoritativeCostNanos: Int64
    var priorityAuthoritativeCostNanos: Int64
    var standardInputTokens: Int64
    var standardCachedTokens: Int64
    var standardOutputTokens: Int64
    var priorityInputTokens: Int64
    var priorityCachedTokens: Int64
    var priorityOutputTokens: Int64
    var standardTokens: Int64
    var priorityTokens: Int64
    var standardResolvedCostNanos: Int64 = 0
    var priorityResolvedCostNanos: Int64 = 0
    var standardUnresolvedPricingCount: Int64 = 0
    var priorityUnresolvedPricingCount: Int64 = 0

    static func zero(day: String, model: String) -> Self {
        Self(
            day: day,
            model: model,
            inputTokens: 0,
            cachedTokens: 0,
            outputTokens: 0,
            reasoningTokens: 0,
            requestCount: 0,
            unpricedRequestCount: 0,
            authoritativeCostNanos: 0,
            standardAuthoritativeCostNanos: 0,
            priorityAuthoritativeCostNanos: 0,
            standardInputTokens: 0,
            standardCachedTokens: 0,
            standardOutputTokens: 0,
            priorityInputTokens: 0,
            priorityCachedTokens: 0,
            priorityOutputTokens: 0,
            standardTokens: 0,
            priorityTokens: 0,
            standardResolvedCostNanos: 0,
            priorityResolvedCostNanos: 0,
            standardUnresolvedPricingCount: 0,
            priorityUnresolvedPricingCount: 0)
    }
}

struct CostUsageStoreFileDayAggregate: Codable, Equatable, Sendable {
    var path: String
    var aggregate: CostUsageStoreDayAggregate
}

struct CostUsageStoreForkLineage: Codable, Equatable, Sendable {
    var path: String
    var sessionID: String?
    var forkedFromID: String?
    var forkTimestamp: String?
    var dependencyKey: String?
    var subagentState: Data?
    var accountingState: Data?
}

enum CostUsageStoreBufferedLineKind: String, Codable, CaseIterable, Sendable {
    case subagent
    case unresolvedFork
    case deferredReplay
}

struct CostUsageStoreBufferedLine: Codable, Equatable, Sendable {
    var path: String
    var kind: CostUsageStoreBufferedLineKind
    var lineIndex: Int
    var ordinal: Int?
    var endOffset: Int64?
    var payload: Data
}

struct CostUsageStoreDiscoveryState: Codable, Equatable, Sendable {
    var roots: [String]
    var generation: String?
    var directoryPaths: [String]
    var nextDirectoryIndex: Int
    var filePaths: [String]
    var nextFileIndex: Int
    var filePathBySessionID: [String: String]
    var missingSessionIDs: [String]
    var pendingSessionIDs: [String]
    var validationDirectoryIndex: Int
    var isComplete: Bool
    var payload: Data?
}

struct CostUsageStoreLookbackState: Codable, Equatable, Sendable {
    var scanSinceDay: String
    var rootPaths: [String]
    var nextDayByRoot: [String: String]
    var nextDirectoryOffsetByRoot: [String: Int64]?
    var completedRootPaths: [String]
    var pendingFilePaths: [String]
    var legacyRecursivePendingRootPaths: [String]
    var currentWindowNextDayKeyByRoot: [String: String]?
    var currentWindowDirectoryOffsetByRoot: [String: Int64]?
    var completedCurrentWindowRootPaths: [String]?
    var currentWindowFlatDirectoryOffsetByRoot: [String: Int64]?
    var completedCurrentWindowFlatRootPaths: [String]?
    var directoryCursorVersion: Int?
    var directoryPendingNamesByCursor: [String: [String]]?
    var legacyRecursiveDirectoryPathsByRoot: [String: [String]]?
    var legacyRecursiveDirectoryOffsetByPath: [String: Int64]?
    var exactInventoryPendingRootPaths: [String]?
    var exactInventoryDirectoryPathsByRoot: [String: [String]]?
    var exactInventoryDirectoryOffsetByPath: [String: Int64]?
    var exactInventoryVisitedDirectoryPaths: [String]?
    var exactValidationPaths: [String]?
    var exactValidationNextIndex: Int?
    var exactValidationProcessedBytes: Int64?
    var exactValidationTotalBytes: Int64?
    var exactValidationCompletedFiles: Int?
    var exactValidationTotalFiles: Int?
    var exactValidationSeenIdentities: [String]?
    var exactValidationInventoryPaths: [String]?
    var exactInventoryGeneration: String?
    var exactInventoryScanSinceDay: String?
    var exactInventoryScanUntilDay: String?
    var exactInventoryNextDayByRoot: [String: String]?
    var exactInventoryDirectoryOffsetByRoot: [String: Int64]?
    var exactInventoryCompletedRootPaths: [String]?
    var exactInventoryFlatDirectoryOffsetByRoot: [String: Int64]?
    var exactInventoryCompletedFlatRootPaths: [String]?
    var exactCachedValidationLastPath: String?
    var cacheWideMigrationQueueActive: Bool?
    var priorityMigrationGenerationKey: String?
}

struct CostUsageStoreAccumulator: Codable, Equatable, Sendable {
    var path: String
    var eventCount: Int
    var nextUsageRowIndex: Int?
    var countedTotals: CostUsageStoreTotals?
    var rawTotalsBaseline: CostUsageStoreTotals?
    var rawTotalsWatermark: CostUsageStoreTotals?
    var sawDivergentTotals: Bool
    var sawInterleavedTotals: Bool
    var seenRawTotals: [CostUsageStoreTotals]
    var updatedAtUnixMs: Int64
}

struct CostUsageStoreMetadata: Codable, Equatable, Sendable {
    var lastScanUnixMs: Int64
    var scanSinceDay: String?
    var scanUntilDay: String?
    var retainedLookbackDays: Int?
    var timeZoneIdentifier: String?
    var pricingKey: String?
    var priorityMetadataKey: String?
    var catchUpPending: Bool
    var processedBytes: Int64?
    var totalBytes: Int64?
    var completedFiles: Int?
    var totalFiles: Int?
    var scanInventoryPaths: [String]?
    var rootMtimes: [String: Int64]?
    var previousReportPayload: Data?
    /// Coverage of the last complete, consumer-safe aggregate snapshot. This is deliberately
    /// independent of the currently requested report window so a bounded catch-up cannot make
    /// another consumer's established history unavailable.
    var verifiedScanSinceDay: String?
    var verifiedScanUntilDay: String?
    var verifiedUpdatedAtUnixMs: Int64?
    var verifiedTimeZoneIdentifier: String?
    var verifiedRootPaths: [String]?
    var verifiedLedgerVersion: Int?
    var priorityTurnStatePayload: Data?
    var projectMetadataVersion: Int?

    static let empty = Self(
        lastScanUnixMs: 0,
        scanSinceDay: nil,
        scanUntilDay: nil,
        retainedLookbackDays: nil,
        timeZoneIdentifier: nil,
        pricingKey: nil,
        priorityMetadataKey: nil,
        catchUpPending: false,
        processedBytes: nil,
        totalBytes: nil,
        completedFiles: nil,
        totalFiles: nil,
        scanInventoryPaths: nil,
        rootMtimes: nil,
        previousReportPayload: nil,
        verifiedScanSinceDay: nil,
        verifiedScanUntilDay: nil,
        verifiedUpdatedAtUnixMs: nil,
        verifiedTimeZoneIdentifier: nil,
        verifiedRootPaths: nil,
        verifiedLedgerVersion: nil,
        priorityTurnStatePayload: nil,
        projectMetadataVersion: nil)
}

struct CostUsageStoreReport: Equatable, Sendable {
    var metadata: CostUsageStoreMetadata
    var aggregates: [CostUsageStoreDayAggregate]
}

/// The small persisted surface needed to report bounded Codex scan progress.
/// Keep this separate from `CostUsageStoreSnapshot`: status polling must not retain usage ledgers.
struct CostUsageStoreCatchUpFile: Equatable, Sendable {
    var path: String
    var inode: Int64?
    var mtimeUnixMs: Int64
    var size: Int64
    var fileIdentity: String?
    var parsedBytes: Int64?
    var scanTargetSize: Int64?
    var resumeOffset: Int64?
    var scanComplete: Bool
    var forkedFromID: String?
    var forkBaselineDependencyKey: String?
    var hasBufferedSubagentLines: Bool
    var hasBufferedUnresolvedForkLines: Bool

    var hasBufferedForkRetryLines: Bool {
        self.hasBufferedSubagentLines || self.hasBufferedUnresolvedForkLines
    }
}

struct CostUsageStoreCatchUpProjection: Equatable, Sendable {
    var rootMtimes: [String: Int64]?
    var catchUpPending: Bool
    var processedBytes: Int64?
    var totalBytes: Int64?
    var completedFiles: Int?
    var totalFiles: Int?
    var scanInventoryPaths: [String]?
    var previousReportUpdatedAtUnixMs: Int64?
    var files: [CostUsageStoreCatchUpFile]
    var discoveryState: CostUsageStoreDiscoveryState?
    var lookbackState: CostUsageStoreLookbackState?

    static let empty = Self(
        rootMtimes: nil,
        catchUpPending: false,
        processedBytes: nil,
        totalBytes: nil,
        completedFiles: nil,
        totalFiles: nil,
        scanInventoryPaths: nil,
        previousReportUpdatedAtUnixMs: nil,
        files: [],
        discoveryState: nil,
        lookbackState: nil)
}

struct CostUsageStoreSnapshot: Equatable, Sendable {
    var metadata: CostUsageStoreMetadata
    var files: [CostUsageStoreFile]
    var tokenSnapshots: [CostUsageStoreTokenSnapshot]
    var usageRows: [CostUsageStoreUsageRow] = []
    var fileDayAggregates: [CostUsageStoreFileDayAggregate]
    var dayAggregates: [CostUsageStoreDayAggregate]
    var verifiedDayAggregates: [CostUsageStoreDayAggregate] = []
    var forkLineage: [CostUsageStoreForkLineage]
    var bufferedLines: [CostUsageStoreBufferedLine]
    var discoveryState: CostUsageStoreDiscoveryState?
    var lookbackState: CostUsageStoreLookbackState?
    var accumulators: [CostUsageStoreAccumulator]
}

struct CostUsageStoreRetentionResult: Equatable, Sendable {
    var deletedFiles: Int
    var deletedTokenSnapshots: Int
    var deletedFileDayAggregates: Int
    var deletedDayAggregates: Int
}

struct CostUsageStoreBudgetResult: Equatable, Sendable {
    var deletedRows: Int
    var rowCount: Int
    var fileBytes: Int64
    var catchUpRequired: Bool = false
}

struct CostUsageStoreConfiguration: Equatable, Sendable {
    var journalMode: String
    var busyTimeoutMilliseconds: Int
    var foreignKeysEnabled: Bool
    var autoVacuumMode: Int
    var userVersion: Int
}
