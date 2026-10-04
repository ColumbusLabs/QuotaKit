#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import CoreFoundation
import Dispatch
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if os(macOS)
@_silgen_name("__getdirentries64")
private func codexGetDirectoryEntries64(
    _ descriptor: Int32,
    _ buffer: UnsafeMutableRawPointer,
    _ bufferSize: Int,
    _ basePosition: UnsafeMutablePointer<Int64>) -> Int
#endif

// swiftlint:disable type_body_length file_length
enum CostUsageScanner {
    static let codexProjectMetadataVersion = 1
    typealias CancellationCheck = () throws -> Void
    typealias CodexListingMetadataReader = (URL) -> CodexFileMetadata

    static let log = CodexBarLog.logger(LogCategories.tokenCost)
    static let codexActiveSessionLookbackDays = 30
    static let codexCatchUpScanCandidateLimit = 512
    /// Detail rows are materially larger than their compact manifest entries. Keep one catch-up
    /// pass from decoding a broad set of sessions even when the byte budget allows it.
    static let codexCatchUpHydrationPathLimit = 4
    static let costScale = 1_000_000_000.0
    /// Reserved cache marker. Resolver-produced dependencies use `file|...` or `missing:...`;
    /// this value records that lineage exists but this rollout owns its counter or suffix.
    static let codexForkDependencyNotRequiredKey = "mode:lineage-only:v1"

    static func resetCodexDirectoryCursorsForTesting(under root: URL) {
        self.codexDirectoryCursorRegistry.reset(under: root)
    }

    static func setUnavailableCodexDirectoriesForTesting(_ paths: Set<String>) {
        self.codexDirectoryCursorRegistry.setUnavailablePathsForTesting(paths)
    }

    final class CodexSessionHeadParseObserverStore: @unchecked Sendable {
        let observer: () -> Void

        init(observer: @escaping () -> Void) {
            self.observer = observer
        }
    }

    @TaskLocal private static var codexSessionHeadParseObserverStore: CodexSessionHeadParseObserverStore?

    static func withCodexSessionHeadParseObserverForTesting<T>(
        _ observer: @escaping () -> Void,
        operation: () throws -> T) rethrows -> T
    {
        try self.$codexSessionHeadParseObserverStore.withValue(.init(observer: observer)) {
            try operation()
        }
    }

    enum ClaudeLogProviderFilter {
        case all
        case vertexAIOnly
        case excludeVertexAI
    }

    /// Bounded diagnostics for why a local day cannot be published as independently proven.
    /// Pricing is intentionally not part of this gate: an indexed, inventory-complete day can
    /// carry source proof even when some of its usage has no price.
    enum CodexDayEvidenceGateReason: String, Sendable, Equatable {
        case scope
        case inventory
        case unindexed
        case stale
        case fork
    }

    struct CodexScanWorkMetrics: Equatable, Sendable {
        var usageRowsProcessed: Int
        var usageRowsRepriced: Int
        var tokenTimestampComparisons: Int
        var cacheAliasEntriesIndexed: Int
        var cacheAliasLookups: Int
        var cacheAliasCandidatesVisited: Int
        var activeLookbackCompletionCandidates: Int
        var codexDiscoveryVisits: Int
        var codexDirectoryEntryReads: Int
        var codexCandidateSelectionVisits: Int
        var codexHydratedFiles: Int
        var codexFileScanAttempts: Int
        var codexProgressAccountingVisits: Int
        var codexPriorityMetadataDayVisits: Int
        var codexListingMetadataReads: Int
        var codexListingRootStandardizations: Int
    }

    final class CodexScanWorkRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var processed = 0
        private var repriced = 0
        private var tokenTimestampComparisons = 0
        private var cacheAliasEntriesIndexed = 0
        private var cacheAliasLookups = 0
        private var cacheAliasCandidatesVisited = 0
        private var activeLookbackCompletionCandidates = 0
        private var codexDiscoveryVisits = 0
        private var codexDirectoryEntryReads = 0
        private var codexCandidateSelectionVisits = 0
        private var codexHydratedFiles = 0
        private var codexFileScanAttempts = 0
        private var codexFileScanAttemptPaths: Set<String> = []
        private var codexProgressAccountingVisits = 0
        private var codexPriorityMetadataDayVisits = 0
        private var codexListingMetadataReads = 0
        private var codexListingRootStandardizations = 0

        func record(processed: Int, repriced: Int) {
            self.lock.lock()
            self.processed += max(0, processed)
            self.repriced += max(0, repriced)
            self.lock.unlock()
        }

        func recordTokenTimestampComparison() {
            self.lock.withLock { self.tokenTimestampComparisons += 1 }
        }

        func recordCacheAliasIndex(entries: Int) {
            self.lock.lock()
            self.cacheAliasEntriesIndexed += max(0, entries)
            self.lock.unlock()
        }

        func recordCacheAliasLookup(candidatesVisited: Int) {
            self.lock.lock()
            self.cacheAliasLookups += 1
            self.cacheAliasCandidatesVisited += max(0, candidatesVisited)
            self.lock.unlock()
        }

        func recordActiveLookbackFinalization(completionCandidates: Int) {
            self.lock.lock()
            self.activeLookbackCompletionCandidates += max(0, completionCandidates)
            self.lock.unlock()
        }

        func recordCodexDiscoveryVisit() {
            self.lock.lock()
            self.codexDiscoveryVisits += 1
            self.lock.unlock()
        }

        func recordCodexDirectoryEntryRead() {
            self.lock.lock()
            self.codexDirectoryEntryReads += 1
            self.lock.unlock()
        }

        func recordCodexCandidateSelectionVisit() {
            self.lock.lock()
            self.codexCandidateSelectionVisits += 1
            self.lock.unlock()
        }

        func recordCodexHydration(files: Int) {
            self.lock.lock()
            self.codexHydratedFiles += max(0, files)
            self.lock.unlock()
        }

        func recordCodexFileScanAttempt(path: String) {
            self.lock.lock()
            self.codexFileScanAttempts += 1
            self.codexFileScanAttemptPaths.insert(path)
            self.lock.unlock()
        }

        func attemptedCodexFilePaths() -> Set<String> {
            self.lock.withLock { self.codexFileScanAttemptPaths }
        }

        func recordCodexProgressAccountingVisit() {
            self.lock.lock()
            self.codexProgressAccountingVisits += 1
            self.lock.unlock()
        }

        func recordCodexPriorityMetadataDayVisit() {
            self.lock.lock()
            self.codexPriorityMetadataDayVisits += 1
            self.lock.unlock()
        }

        func recordCodexListingMetadataRead() {
            self.lock.withLock { self.codexListingMetadataReads += 1 }
        }

        func recordCodexListingRootStandardization() {
            self.lock.withLock { self.codexListingRootStandardizations += 1 }
        }

        func snapshot() -> CodexScanWorkMetrics {
            self.lock.lock()
            defer { self.lock.unlock() }
            return CodexScanWorkMetrics(
                usageRowsProcessed: self.processed,
                usageRowsRepriced: self.repriced,
                tokenTimestampComparisons: self.tokenTimestampComparisons,
                cacheAliasEntriesIndexed: self.cacheAliasEntriesIndexed,
                cacheAliasLookups: self.cacheAliasLookups,
                cacheAliasCandidatesVisited: self.cacheAliasCandidatesVisited,
                activeLookbackCompletionCandidates: self.activeLookbackCompletionCandidates,
                codexDiscoveryVisits: self.codexDiscoveryVisits,
                codexDirectoryEntryReads: self.codexDirectoryEntryReads,
                codexCandidateSelectionVisits: self.codexCandidateSelectionVisits,
                codexHydratedFiles: self.codexHydratedFiles,
                codexFileScanAttempts: self.codexFileScanAttempts,
                codexProgressAccountingVisits: self.codexProgressAccountingVisits,
                codexPriorityMetadataDayVisits: self.codexPriorityMetadataDayVisits,
                codexListingMetadataReads: self.codexListingMetadataReads,
                codexListingRootStandardizations: self.codexListingRootStandardizations)
        }
    }

    struct Options {
        var codexSessionsRoot: URL?
        var claudeProjectsRoots: [URL]?
        var cacheRoot: URL?
        var codexTraceDatabaseURL: URL?
        var codexScanBudgetForTesting: CodexScanBudget?
        var calendar: Calendar
        var refreshMinIntervalSeconds: TimeInterval = 60
        var claudeLogProviderFilter: ClaudeLogProviderFilter = .all
        /// Force a full rescan, ignoring per-file cache and incremental offsets.
        var forceRescan: Bool = false
        /// Maximum bounded slice read from one Codex rollout per refresh. Larger files
        /// resume from cached progress on later refreshes. Default 16 MiB.
        var maxCodexSessionFileBytes: Int64 = 16 * 1024 * 1024
        /// Soft budget for newly-read Codex session bytes in one refresh.
        /// Remaining dirty files are deferred to later refreshes. Default 64 MiB.
        var maxCodexScanBytesPerRefresh: Int64 = 64 * 1024 * 1024
        /// Optional wall-clock budget for newly-read Codex bytes in one refresh. The reader
        /// finishes its current 256 KiB chunk, persists resume state, and continues later.
        var maxCodexScanDurationPerRefresh: TimeInterval?
        /// Prefer newest session files first so recent usage lands before catch-up work.
        var preferNewestCodexSessionsFirst: Bool = true
        /// Use the manifest/aggregate-backed working set for bounded Codex catch-up. Regular
        /// reports and explicit migrations retain the full compatibility cache path.
        var useCodexCatchUpWorkingSet: Bool = false
        var codexScanWorkRecorderForTesting: CodexScanWorkRecorder?

        init(
            codexSessionsRoot: URL? = nil,
            claudeProjectsRoots: [URL]? = nil,
            cacheRoot: URL? = nil,
            codexTraceDatabaseURL: URL? = nil,
            calendar: Calendar = .current,
            claudeLogProviderFilter: ClaudeLogProviderFilter = .all,
            forceRescan: Bool = false,
            maxCodexSessionFileBytes: Int64 = 16 * 1024 * 1024,
            maxCodexScanBytesPerRefresh: Int64 = 64 * 1024 * 1024,
            maxCodexScanDurationPerRefresh: TimeInterval? = nil,
            preferNewestCodexSessionsFirst: Bool = true,
            useCodexCatchUpWorkingSet: Bool = false,
            codexScanWorkRecorderForTesting: CodexScanWorkRecorder? = nil)
        {
            self.codexSessionsRoot = codexSessionsRoot
            self.claudeProjectsRoots = claudeProjectsRoots
            self.cacheRoot = cacheRoot
            self.codexTraceDatabaseURL = codexTraceDatabaseURL
            self.calendar = calendar
            self.claudeLogProviderFilter = claudeLogProviderFilter
            self.forceRescan = forceRescan
            self.maxCodexSessionFileBytes = max(0, maxCodexSessionFileBytes)
            self.maxCodexScanBytesPerRefresh = max(0, maxCodexScanBytesPerRefresh)
            self.maxCodexScanDurationPerRefresh = maxCodexScanDurationPerRefresh.map { max(0, $0) }
            self.preferNewestCodexSessionsFirst = preferNewestCodexSessionsFirst
            self.useCodexCatchUpWorkingSet = useCodexCatchUpWorkingSet
            self.codexScanWorkRecorderForTesting = codexScanWorkRecorderForTesting
        }
    }

    /// Per-refresh work limiter for Codex cost scans. Prevents multi-GB rollout corpora from
    /// monopolizing a core for hours while still allowing progressive catch-up.
    final class CodexScanBudget: @unchecked Sendable {
        let maxFileBytes: Int64
        let maxBytesPerRefresh: Int64
        private(set) var bytesConsumed: Int64 = 0
        private(set) var resumedPartialFileCount = 0
        private(set) var deferredByBudgetFileCount = 0
        private(set) var deferredByTimeBudgetFileCount = 0
        private var bytesReserved: Int64 = 0
        private let deadline: ContinuousClock.Instant?
        private let now: @Sendable () -> ContinuousClock.Instant
        private var recordedTimeDeferral = false

        init(
            maxFileBytes: Int64,
            maxBytesPerRefresh: Int64,
            maxDuration: TimeInterval? = nil,
            now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now })
        {
            self.maxFileBytes = max(0, maxFileBytes)
            self.maxBytesPerRefresh = max(0, maxBytesPerRefresh)
            self.now = now
            if let maxDuration, maxDuration > 0 {
                self.deadline = now().advanced(by: .seconds(maxDuration))
            } else {
                self.deadline = nil
            }
        }

        var hasTimeLimit: Bool {
            self.deadline != nil
        }

        /// A side-effect-free view used to size the detail working set before decoding it. Actual
        /// file reads still call `admit`, so time expiry and concurrent reservations remain enforced
        /// at the I/O boundary.
        var planningRemainingBytes: Int64 {
            self.maxBytesPerRefresh > 0
                ? max(0, self.maxBytesPerRefresh - self.bytesConsumed - self.bytesReserved)
                : Int64.max
        }

        enum Admission {
            case allow(Int64)
            case deferBudget
        }

        func admit(workBytes: Int64) -> Admission {
            let work = max(0, workBytes)
            if work > 0, self.shouldYield(additionalBytes: 0) {
                self.deferredByBudgetFileCount += 1
                return .deferBudget
            }
            let refreshRemaining = self.maxBytesPerRefresh > 0
                ? max(0, self.maxBytesPerRefresh - self.bytesConsumed - self.bytesReserved)
                : Int64.max
            if work > 0, refreshRemaining == 0 {
                self.deferredByBudgetFileCount += 1
                return .deferBudget
            }
            let fileAllowance = self.maxFileBytes > 0 ? self.maxFileBytes : Int64.max
            let allowance = min(work, fileAllowance, refreshRemaining)
            if allowance < work {
                self.resumedPartialFileCount += 1
            }
            self.bytesReserved += allowance
            return .allow(allowance)
        }

        func consume(workBytes: Int64) {
            let work = max(0, workBytes)
            self.bytesReserved = max(0, self.bytesReserved - work)
            self.bytesConsumed += work
        }

        func release(workBytes: Int64) {
            self.bytesReserved = max(0, self.bytesReserved - max(0, workBytes))
        }

        func complete(admittedWorkBytes: Int64, actualWorkBytes: Int64) {
            let admitted = max(0, admittedWorkBytes)
            let actual = min(admitted, max(0, actualWorkBytes))
            self.consume(workBytes: actual)
            self.release(workBytes: admitted - actual)
        }

        func shouldYield(additionalBytes: Int64) -> Bool {
            guard let deadline else { return false }
            guard self.bytesConsumed + self.bytesReserved + max(0, additionalBytes) > 0 else { return false }
            guard self.now() >= deadline else { return false }
            if !self.recordedTimeDeferral {
                self.recordedTimeDeferral = true
                self.deferredByTimeBudgetFileCount += 1
            }
            return true
        }

        func shouldStopBeforeNextFile() -> Bool {
            self.shouldYield(additionalBytes: 1)
        }
    }

    struct CodexParseResult {
        let days: [String: [String: [Int]]]
        var parsedBytes: Int64
        let lastModel: String?
        let lastTotals: CostUsageCodexTotals?
        let lastCountedTotals: CostUsageCodexTotals?
        let lastRawTotalsBaseline: CostUsageCodexTotals?
        let lastRawTotalsWatermark: CostUsageCodexTotals?
        let seenRawTotals: [CostUsageCodexTotals]
        let hasDivergentTotals: Bool
        let hasInterleavedTotals: Bool
        let lastCodexTurnID: String?
        let sessionId: String?
        let forkedFromId: String?
        let dependsOnParentTotals: Bool
        let forkBaselineResolved: Bool
        let projectPath: String?
        let codexSession: CostUsageCodexSessionMetadata
        let rows: [CodexUsageRow]
        let tokenSnapshots: [CostUsageCodexTokenSnapshot]
        let jsonlResumeState: CostUsageJsonl.ResumeState?
        let bufferedSubagentLines: [CodexBufferedFastLine]?
        let bufferedUnresolvedForkLines: [CodexBufferedFastLine]?
        var rowSourceEndOffsets: [Int: Int64] = [:]
        var nextUsageRowIndex: Int = 0
        var forkAccountingState: CodexForkAccountingState?
        var requestLedgerState: CodexRequestLedgerState?
        var replacedLegacyRowIndices: Set<Int> = []
    }

    struct CodexRequestLedgerState: Codable, Equatable {
        var responseIDs: Set<String> = []
        var mirroredResponses: [String: String]? = [:]
        var legacyRowIndices: [String: Int] = [:]
        var turnModels: [String: String] = [:]
        var activeTurnID: String?
        var sessionID: String?
        var pendingLedgerMirrors: Set<String>?
        var pendingLedgerResponseID: String?
        var pendingLegacyMirrors: Set<String>?
        var pendingLegacyRowIndex: Int?
        var countedUsage: CostUsageCodexTotals?

        mutating func clearPendingMirrors(when shouldClear: Bool = true) {
            guard shouldClear else { return }
            self.pendingLedgerMirrors = nil
            self.pendingLedgerResponseID = nil
            self.pendingLegacyMirrors = nil
            self.pendingLegacyRowIndex = nil
        }

        mutating func beginLegacyObservation(keys: Set<String>?, snapshot: String?) {
            defer { self.clearPendingMirrors() }
            guard let keys, let pending = self.pendingLedgerMirrors, !keys.isDisjoint(with: pending),
                  let snapshot, let responseID = self.pendingLedgerResponseID else { return }
            self.rememberMirrors([snapshot], responseID: responseID)
        }

        mutating func rememberMirrors(_ keys: [String], responseID: String) {
            if self.mirroredResponses == nil { self.mirroredResponses = [:] }
            for key in keys {
                self.mirroredResponses?[key] = responseID
            }
        }
    }

    struct CodexForkAccountingState: Codable, Equatable {
        let metadata: CodexSessionMetadata
        let inheritedTotals: CostUsageCodexTotals?
        let remainingInheritedTotals: CostUsageCodexTotals?
    }

    struct CodexPricingEvidence: Codable, Equatable {
        let pricingModel: String?
        let pricingMode: String?
    }

    struct CodexUsageRow: Codable, Equatable {
        let day: String
        let model: String
        let rawModel: String?
        let turnID: String?
        let eventIndex: Int?
        let timestampUnixMs: Int64?
        let input: Int
        let cached: Int
        let output: Int
        let reasoning: Int?
        let responseID: String?
        let requestMirrorKeys: [String]?
        /// Set only when the source supplied an authoritative monetary cost.
        /// Estimated model-table pricing is resolved from token classes when reports are read.
        var knownCostNanos: Int64?
        var unpricedTokens: Int?
        var pricingModel: String?
        var pricingMode: String?

        init(
            day: String,
            model: String,
            rawModel: String? = nil,
            turnID: String?,
            eventIndex: Int?,
            timestampUnixMs: Int64? = nil,
            input: Int,
            cached: Int,
            output: Int,
            reasoning: Int? = nil,
            knownCostNanos: Int64? = nil,
            unpricedTokens: Int? = nil,
            pricingModel: String? = nil,
            pricingMode: String? = nil,
            responseID: String? = nil,
            requestMirrorKeys: [String]? = nil)
        {
            self.day = day
            self.model = model
            self.rawModel = rawModel
            self.turnID = turnID
            self.eventIndex = eventIndex
            self.timestampUnixMs = timestampUnixMs
            self.input = input
            self.cached = cached
            self.output = output
            self.reasoning = reasoning.map { min(max(0, $0), max(0, output)) }
            self.responseID = responseID
            self.requestMirrorKeys = requestMirrorKeys
            self.knownCostNanos = knownCostNanos
            self.unpricedTokens = unpricedTokens
            self.pricingModel = pricingModel
            self.pricingMode = pricingMode
        }
    }

    struct CodexScanState {
        var contributingSessionIds: Set<String> = []
        var seenFileIds: Set<String> = []
        var seenCodexUsageRowKeys: Set<String> = []
        var committedCodexResponseRows: [String: CodexUsageRow] = [:]
        var retainCandidateResponseDuplicates = false
        var deferredCachePaths: Set<String> = []
        var historyHydrationRetries: [String: CodexHistoryHydrationRetry] = [:]
        var completedHistoryRetryTargets: Set<String> = []
        var confirmedAbsentHistoryRetryPaths: Set<String> = []
    }

    struct CodexScannedSession {
        let id: String?
        let contributedUsage: Bool

        init(id: String?, days: [String: [String: [Int]]]) {
            self.id = id
            self.contributedUsage = !days.isEmpty
        }
    }

    enum CodexForkBaseline {
        case resolved(CostUsageCodexTotals?)
        case unresolved
    }

    private static func codexTotalsEqual(_ lhs: CostUsageCodexTotals?, _ rhs: CostUsageCodexTotals?) -> Bool {
        lhs?.input == rhs?.input && lhs?.cached == rhs?.cached && lhs?.output == rhs?.output
    }

    private static func codexTotalsAtLeast(_ lhs: CostUsageCodexTotals, _ rhs: CostUsageCodexTotals) -> Bool {
        lhs.input >= rhs.input && lhs.cached >= rhs.cached && lhs.output >= rhs.output
    }

    private static func codexTotalsAtMost(_ lhs: CostUsageCodexTotals, _ rhs: CostUsageCodexTotals) -> Bool {
        lhs.input <= rhs.input && lhs.cached <= rhs.cached && lhs.output <= rhs.output
    }

    private static func codexLooksLikeStaleRegression(
        current: CostUsageCodexTotals,
        previous: CostUsageCodexTotals,
        last: CostUsageCodexTotals) -> Bool
    {
        // Mirrors tokscale: staleness applies only after an actual field-level
        // regression, including the optional reasoning subset. Compare reasoning
        // only when both snapshots provide it; an omitted field is unknown, not zero.
        let reasoningRegressed: Bool = switch (current.reasoning, previous.reasoning) {
        case let (.some(currentReasoning), .some(previousReasoning)):
            currentReasoning < previousReasoning
        case (.some, .none), (.none, .some), (.none, .none):
            false
        }
        guard current.input < previous.input
            || current.cached < previous.cached
            || current.output < previous.output
            || reasoningRegressed
        else { return false }
        func magnitude(_ totals: CostUsageCodexTotals) -> Decimal {
            Decimal(totals.input)
                + Decimal(totals.output)
                + Decimal(totals.cached)
                + Decimal(totals.reasoning ?? 0)
        }
        let previousTotal = magnitude(previous)
        let currentTotal = magnitude(current)
        let lastTotal = magnitude(last)
        if previousTotal <= 0 || currentTotal <= 0 || lastTotal <= 0 {
            return false
        }
        return currentTotal * 100 >= previousTotal * 98
            || currentTotal + lastTotal * 2 >= previousTotal
    }

    private static func codexShouldPreferTotalDelta(
        rawBaseline: CostUsageCodexTotals?,
        currentTotal: CostUsageCodexTotals,
        totalDelta: CostUsageCodexTotals,
        lastDelta: CostUsageCodexTotals,
        sawDivergentTotals: Bool) -> Bool
    {
        guard !sawDivergentTotals, let rawBaseline else { return false }
        return Self.codexTotalsAtLeast(currentTotal, rawBaseline)
            && Self.codexTotalsAtMost(totalDelta, lastDelta)
    }

    private static func codexAddTotals(
        _ lhs: CostUsageCodexTotals,
        _ rhs: CostUsageCodexTotals) -> CostUsageCodexTotals
    {
        CostUsageCodexTotals(
            input: lhs.input + rhs.input,
            cached: lhs.cached + rhs.cached,
            output: lhs.output + rhs.output,
            reasoning: self.codexAddOptional(lhs.reasoning, rhs.reasoning))
    }

    private static func codexMinTotals(
        _ lhs: CostUsageCodexTotals,
        _ rhs: CostUsageCodexTotals) -> CostUsageCodexTotals
    {
        CostUsageCodexTotals(
            input: min(lhs.input, rhs.input),
            cached: min(lhs.cached, rhs.cached),
            output: min(lhs.output, rhs.output),
            reasoning: self.codexMinOptional(lhs.reasoning, rhs.reasoning))
    }

    private static func codexTotalDelta(
        from baseline: CostUsageCodexTotals?,
        to current: CostUsageCodexTotals) -> CostUsageCodexTotals
    {
        let reasoning = Self.codexOptionalDelta(
            from: baseline?.reasoning,
            to: current.reasoning,
            hasBaseline: baseline != nil)
        let baseline = baseline ?? .init(input: 0, cached: 0, output: 0)
        return CostUsageCodexTotals(
            input: max(0, current.input - baseline.input),
            cached: max(0, current.cached - baseline.cached),
            output: max(0, current.output - baseline.output),
            reasoning: reasoning)
    }

    private static func codexDivergentTotalDelta(
        rawBaseline: CostUsageCodexTotals?,
        countedBaseline: CostUsageCodexTotals?,
        current: CostUsageCodexTotals) -> CostUsageCodexTotals
    {
        let rawBaseline = rawBaseline ?? .init(input: 0, cached: 0, output: 0)
        let countedBaseline = countedBaseline ?? .init(input: 0, cached: 0, output: 0)

        func delta(raw: Int, counted: Int, current: Int) -> Int {
            if current >= raw {
                return max(0, current - raw)
            }
            return max(0, current - counted)
        }

        return CostUsageCodexTotals(
            input: delta(raw: rawBaseline.input, counted: countedBaseline.input, current: current.input),
            cached: delta(raw: rawBaseline.cached, counted: countedBaseline.cached, current: current.cached),
            output: delta(raw: rawBaseline.output, counted: countedBaseline.output, current: current.output),
            reasoning: Self.codexDivergentOptionalDelta(
                raw: rawBaseline.reasoning,
                counted: countedBaseline.reasoning,
                current: current.reasoning))
    }

    private static func codexMaxTotals(
        _ lhs: CostUsageCodexTotals?,
        _ rhs: CostUsageCodexTotals) -> CostUsageCodexTotals
    {
        guard let lhs else { return rhs }
        return CostUsageCodexTotals(
            input: max(lhs.input, rhs.input),
            cached: max(lhs.cached, rhs.cached),
            output: max(lhs.output, rhs.output),
            reasoning: Self.codexMaxOptional(lhs.reasoning, rhs.reasoning))
    }

    /// Post-latch totals containment for interleaved cumulative counters (issue #2037 Phase 1).
    ///
    /// - When `current` is below the watermark, resume from the counted baseline so #968-style
    ///   recovery still works (`current - counted`).
    /// - When `current` is at/above the watermark, advance from `max(watermark, counted)` so a
    ///   high/low lineage flip cannot re-count the gap between lineages.
    private static func codexContainedTotalDelta(
        watermark: CostUsageCodexTotals?,
        counted: CostUsageCodexTotals?,
        current: CostUsageCodexTotals) -> CostUsageCodexTotals
    {
        let watermark = watermark ?? .init(input: 0, cached: 0, output: 0)
        let counted = counted ?? .init(input: 0, cached: 0, output: 0)

        func component(water: Int, counted: Int, current: Int) -> Int {
            if current >= water {
                return max(0, current - max(water, counted))
            }
            return max(0, current - counted)
        }

        return CostUsageCodexTotals(
            input: component(water: watermark.input, counted: counted.input, current: current.input),
            cached: component(water: watermark.cached, counted: counted.cached, current: current.cached),
            output: component(water: watermark.output, counted: counted.output, current: current.output),
            reasoning: Self.codexContainedOptionalDelta(
                water: watermark.reasoning,
                counted: counted.reasoning,
                current: current.reasoning))
    }

    private static func codexAddOptional(_ lhs: Int?, _ rhs: Int?) -> Int? {
        guard let lhs, let rhs else { return nil }
        return lhs + rhs
    }

    private static func codexMinOptional(_ lhs: Int?, _ rhs: Int?) -> Int? {
        guard let lhs, let rhs else { return nil }
        return min(lhs, rhs)
    }

    private static func codexMaxOptional(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): max(lhs, rhs)
        case let (lhs?, nil): lhs
        case let (nil, rhs?): rhs
        case (nil, nil): nil
        }
    }

    private static func codexSubtractOptional(_ value: Int?, _ baseline: Int?) -> Int? {
        guard let value, let baseline else { return nil }
        return max(0, value - baseline)
    }

    private static func codexOptionalDelta(from baseline: Int?, to current: Int?, hasBaseline: Bool) -> Int? {
        guard let current else { return nil }
        if !hasBaseline {
            return current
        }
        guard let baseline else { return nil }
        return max(0, current - baseline)
    }

    private static func codexDivergentOptionalDelta(raw: Int?, counted: Int?, current: Int?) -> Int? {
        guard let raw, let counted, let current else { return nil }
        if current >= raw {
            return max(0, current - raw)
        }
        return max(0, current - counted)
    }

    private static func codexContainedOptionalDelta(water: Int?, counted: Int?, current: Int?) -> Int? {
        guard let water, let counted, let current else { return nil }
        if current >= water {
            return max(0, current - max(water, counted))
        }
        return max(0, current - counted)
    }

    /// Post-latch event delta: contained totals growth, optionally capped by `last`.
    ///
    /// `last` alone must never increase counted usage when the contained totals delta is zero
    /// (smaller lineage below the watermark is an accepted Phase 1 undercount).
    private static func codexPostLatchEventDelta(
        watermark: CostUsageCodexTotals?,
        counted: CostUsageCodexTotals?,
        current: CostUsageCodexTotals,
        adjustedLast: CostUsageCodexTotals?) -> CostUsageCodexTotals
    {
        let contained = Self.codexContainedTotalDelta(
            watermark: watermark,
            counted: counted,
            current: current)
        guard let adjustedLast else { return contained }
        return Self.codexMinTotals(adjustedLast, contained)
    }

    /// Shared accounting guard for cumulative Codex token counters (issue #2037).
    ///
    /// Ultra-mode sessions interleave cumulative snapshots from several fork lineages inside one
    /// session file. The tracker keeps a monotonic high watermark (never lowered). After a drop
    /// latches interleaved mode, deltas use `codexPostLatchEventDelta` so gap recounting is
    /// impossible. `seenRawTotals` is an optional precision optimization for exact re-emissions;
    /// correctness does not depend on it once post-latch containment is active.
    struct CodexTotalsTracker {
        static let seenRawTotalsLimit = 64

        private(set) var watermark: CostUsageCodexTotals?
        private(set) var seenRawTotals: [CostUsageCodexTotals]
        private(set) var sawInterleavedTotals: Bool

        init(
            watermark: CostUsageCodexTotals? = nil,
            seenRawTotals: [CostUsageCodexTotals] = [],
            sawInterleavedTotals: Bool = false)
        {
            self.watermark = watermark
            self.seenRawTotals = Array(seenRawTotals.suffix(Self.seenRawTotalsLimit))
            self.sawInterleavedTotals = sawInterleavedTotals
        }

        func isSeen(_ totals: CostUsageCodexTotals) -> Bool {
            self.seenRawTotals.contains { CostUsageScanner.codexTotalsEqual($0, totals) }
        }

        /// Latches interleaved mode when any component of an observed cumulative snapshot drops
        /// strictly below the watermark. A monotonic counter cannot decrease, so a drop means either
        /// a second lineage or a reset; both must stop trusting gap-sized totals deltas.
        mutating func latchIfBelowWatermark(_ totals: CostUsageCodexTotals) {
            guard let watermark = self.watermark else { return }
            if totals.input < watermark.input
                || totals.cached < watermark.cached
                || totals.output < watermark.output
            {
                self.sawInterleavedTotals = true
            }
        }

        /// Records an observed cumulative snapshot: raises the watermark and remembers the exact
        /// value for best-effort re-emission suppression. Call after computing the event's delta.
        mutating func commitObserved(_ totals: CostUsageCodexTotals) {
            self.raiseWatermark(to: totals)
            if !self.seenRawTotals.contains(where: { CostUsageScanner.codexTotalsEqual($0, totals) }) {
                self.seenRawTotals.append(totals)
                if self.seenRawTotals.count > Self.seenRawTotalsLimit {
                    self.seenRawTotals.removeFirst(self.seenRawTotals.count - Self.seenRawTotalsLimit)
                }
            }
        }

        /// Raises the watermark for baseline assignments that are not observed raw snapshots
        /// (for example counted totals in last-only streams). Never lowers it.
        mutating func raiseWatermark(to totals: CostUsageCodexTotals) {
            self.watermark = CostUsageScanner.codexMaxTotals(self.watermark, totals)
        }
    }

    /// Cumulative-totals accounting for parent-session snapshot building. Applies the same
    /// containment policy as `parseCodexFileCancellable` so fork children inherit baselines
    /// computed under identical rules.
    struct CodexSnapshotAccumulator {
        var countedTotals: CostUsageCodexTotals?
        var rawTotalsBaseline: CostUsageCodexTotals?
        var sawDivergentTotals = false
        var tracker = CodexTotalsTracker()

        init(state: CostUsageCodexTokenAccumulatorState? = nil) {
            guard let state else { return }
            self.countedTotals = state.countedTotals
            self.rawTotalsBaseline = state.rawTotalsBaseline
            self.sawDivergentTotals = state.sawDivergentTotals
            self.tracker = CodexTotalsTracker(
                watermark: state.rawTotalsWatermark,
                seenRawTotals: state.seenRawTotals,
                sawInterleavedTotals: state.sawInterleavedTotals)
        }

        var state: CostUsageCodexTokenAccumulatorState {
            CostUsageCodexTokenAccumulatorState(
                countedTotals: self.countedTotals,
                rawTotalsBaseline: self.rawTotalsBaseline,
                sawDivergentTotals: self.sawDivergentTotals,
                rawTotalsWatermark: self.tracker.watermark,
                seenRawTotals: self.tracker.seenRawTotals,
                sawInterleavedTotals: self.tracker.sawInterleavedTotals)
        }

        /// Applies one token-count event and returns the counted cumulative totals afterwards.
        mutating func apply(
            last: CostUsageCodexTotals?,
            total: CostUsageCodexTotals?) -> CostUsageCodexTotals
        {
            // Parent snapshots retain the counter's inherited origin; it is not new billed usage.
            if self.countedTotals == nil, let total, let last {
                self.countedTotals = CostUsageScanner.codexTotalDelta(from: last, to: total)
            }
            let hasReasoning = last?.reasoning != nil || total?.reasoning != nil
            let base = self.countedTotals ?? .init(
                input: 0,
                cached: 0,
                output: 0,
                reasoning: hasReasoning ? 0 : nil)
            if let total {
                // Best-effort exact re-emission suppression (precision only; containment is load-bearing).
                if self.tracker.isSeen(total) {
                    return base
                }
                let staleBaseline = self.tracker.watermark ?? self.rawTotalsBaseline
                if let previousTotal = staleBaseline,
                   CostUsageScanner.codexLooksLikeStaleRegression(
                       current: total,
                       previous: previousTotal,
                       last: last ?? .init(input: 0, cached: 0, output: 0))
                {
                    // Mirrors tokscale: a cumulative snapshot that regressed by roughly
                    // one recent increment is stale, not a second lineage or hard reset.
                    return base
                }
                self.tracker.latchIfBelowWatermark(total)
            }
            let watermarkBaseline = self.tracker.watermark ?? self.rawTotalsBaseline
            defer {
                if let total {
                    self.tracker.commitObserved(total)
                }
            }

            if let last {
                var countedDelta = last
                if let total {
                    if self.tracker.sawInterleavedTotals {
                        countedDelta = CostUsageScanner.codexPostLatchEventDelta(
                            watermark: watermarkBaseline,
                            counted: self.countedTotals,
                            current: total,
                            adjustedLast: last)
                    } else {
                        let totalDelta = CostUsageScanner.codexTotalDelta(from: watermarkBaseline, to: total)
                        if CostUsageScanner.codexShouldPreferTotalDelta(
                            rawBaseline: watermarkBaseline,
                            currentTotal: total,
                            totalDelta: totalDelta,
                            lastDelta: last,
                            sawDivergentTotals: self.sawDivergentTotals)
                        {
                            countedDelta = totalDelta
                        }
                    }
                    let next = CostUsageScanner.codexAddTotals(base, countedDelta)
                    self.countedTotals = next
                    self.rawTotalsBaseline = total
                    if !CostUsageScanner.codexTotalsEqual(total, next) {
                        self.sawDivergentTotals = true
                    }
                    return next
                }
                let next = CostUsageScanner.codexAddTotals(base, countedDelta)
                self.countedTotals = next
                self.rawTotalsBaseline = next
                self.tracker.raiseWatermark(to: next)
                return next
            }

            if let total {
                let delta: CostUsageCodexTotals = if self.tracker.sawInterleavedTotals {
                    CostUsageScanner.codexContainedTotalDelta(
                        watermark: watermarkBaseline,
                        counted: self.countedTotals,
                        current: total)
                } else if self.sawDivergentTotals {
                    CostUsageScanner.codexDivergentTotalDelta(
                        rawBaseline: watermarkBaseline,
                        countedBaseline: self.countedTotals,
                        current: total)
                } else {
                    CostUsageScanner.codexTotalDelta(from: watermarkBaseline, to: total)
                }
                let counted = CostUsageScanner.codexAddTotals(base, delta)
                self.countedTotals = counted
                self.rawTotalsBaseline = total
                if !CostUsageScanner.codexTotalsEqual(total, counted) {
                    self.sawDivergentTotals = true
                }
                return counted
            }

            return base
        }
    }

    static let codexTokenCheckpointStride: Int64 = 4 * 1024 * 1024

    static func codexTokenCheckpoints(
        for events: [CostUsageCodexTokenSnapshot]) -> [CostUsageCodexTokenCheckpoint]
    {
        guard !events.isEmpty else { return [] }
        var accumulator = CodexSnapshotAccumulator()
        var checkpoints: [CostUsageCodexTokenCheckpoint] = []
        var lastCheckpointOffset: Int64 = 0

        for (eventIndex, event) in events.enumerated() {
            _ = accumulator.apply(last: event.last, total: event.total)
            guard let endOffset = event.endOffset else { continue }
            let reachedStride = endOffset - lastCheckpointOffset >= Self.codexTokenCheckpointStride
            let isLastEvent = eventIndex == events.index(before: events.endIndex)
            guard reachedStride || isLastEvent else { continue }
            checkpoints.append(CostUsageCodexTokenCheckpoint(
                eventIndex: eventIndex,
                timestamp: event.timestamp,
                endOffset: endOffset,
                state: accumulator.state))
            lastCheckpointOffset = endOffset
        }

        return checkpoints
    }

    /// Extends sparse checkpoints from the persisted terminal accumulator. Only the appended
    /// token events are folded; the already-indexed prefix is never replayed.
    static func appendingCodexTokenCheckpoints(
        _ events: [CostUsageCodexTokenSnapshot],
        to checkpoints: [CostUsageCodexTokenCheckpoint],
        startingEventIndex: Int,
        initialState: CostUsageCodexTokenAccumulatorState) -> [CostUsageCodexTokenCheckpoint]
    {
        guard !events.isEmpty else { return checkpoints }
        var accumulator = CodexSnapshotAccumulator(state: initialState)
        var appended: [CostUsageCodexTokenCheckpoint] = []
        var lastCheckpointOffset = checkpoints.last?.endOffset ?? 0
        for (offset, event) in events.enumerated() {
            _ = accumulator.apply(last: event.last, total: event.total)
            guard let endOffset = event.endOffset else { continue }
            let reachedStride = endOffset - lastCheckpointOffset >= Self.codexTokenCheckpointStride
            let isLastEvent = offset == events.index(before: events.endIndex)
            guard reachedStride || isLastEvent else { continue }
            appended.append(CostUsageCodexTokenCheckpoint(
                eventIndex: startingEventIndex + offset,
                timestamp: event.timestamp,
                endOffset: endOffset,
                state: accumulator.state))
            lastCheckpointOffset = endOffset
        }
        return checkpoints + appended
    }

    struct CodexScanResources {
        let fileIndex: CodexSessionFileIndex
        let inheritedResolver: CodexInheritedTotalsResolver
        let cachePathAliasIndex: CodexCachePathAliasIndex
        let historyHydrator: CodexScanHistoryHydrator?
        let projectPathResolver: CodexCanonicalProjectPathResolver
        let modelsDevCatalog: ModelsDevCatalog?
        let modelsDevCacheRoot: URL?
        let priorityTurns: [String: CodexPriorityTurnMetadata]
    }

    final class CodexCachePathAliasIndex {
        private var pathsByFileID: [String: Set<String>] = [:]
        private var fileIDByPath: [String: String] = [:]
        private let workRecorder: CodexScanWorkRecorder?

        init(files: [String: CostUsageFileUsage], workRecorder: CodexScanWorkRecorder? = nil) {
            self.workRecorder = workRecorder
            var indexedEntries = 0
            for (path, usage) in files {
                guard let fileID = Self.aliasIdentityKey(usage.codexScanFileId) else { continue }
                self.pathsByFileID[fileID, default: []].insert(path)
                self.fileIDByPath[path] = fileID
                indexedEntries += 1
            }
            workRecorder?.recordCacheAliasIndex(entries: indexedEntries)
        }

        func aliases(fileID: String, excludingPath path: String) -> [String] {
            let candidates = Self.aliasIdentityKey(fileID).flatMap { self.pathsByFileID[$0] } ?? []
            self.workRecorder?.recordCacheAliasLookup(candidatesVisited: candidates.count)
            return candidates.filter { $0 != path }.sorted()
        }

        func update(path: String, fileID: String?) {
            let fileID = Self.aliasIdentityKey(fileID)
            if let previousFileID = self.fileIDByPath[path], previousFileID != fileID {
                self.pathsByFileID[previousFileID]?.remove(path)
                if self.pathsByFileID[previousFileID]?.isEmpty == true {
                    self.pathsByFileID.removeValue(forKey: previousFileID)
                }
                self.fileIDByPath.removeValue(forKey: path)
            }
            guard let fileID else { return }
            self.pathsByFileID[fileID, default: []].insert(path)
            self.fileIDByPath[path] = fileID
        }

        private static func aliasIdentityKey(_ identity: String?) -> String? {
            identity?.split(separator: ":").last.map(String.init)
        }

        func remove(path: String) {
            self.update(path: path, fileID: nil)
        }
    }

    struct CodexFileScanContext {
        let range: CostUsageDayRange
        let forceFullScan: Bool
        let forceFullScanPathKeys: Set<String>
        let sourceRowRecoveryPathKeys: Set<String>
        let preserveUnavailableHistoryDuringRecovery: Bool
        let dropDeferredCodexRows: Bool
        let requiresTurnIDCache: Bool
        let changedPriorityTurnIDs: Set<String>
        let resources: CodexScanResources
        let checkCancellation: CancellationCheck?
        let scanBudget: CodexScanBudget?
        let workRecorder: CodexScanWorkRecorder?
        var requestReconciliationCandidatePaths: Set<String> = []
    }

    final class CodexCanonicalProjectPathResolver {
        private var cache: [String: String] = [:]
        private let homeCodexWorktreesPrefix: String

        init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
            // Provider-specific by design: Codex worktree sessions canonicalize to their source project path.
            self.homeCodexWorktreesPrefix = homeDirectory
                .appendingPathComponent(".codex/worktrees", isDirectory: true)
                .standardizedFileURL
                .path
        }

        func canonicalProjectPath(for projectPath: String?) -> String? {
            guard let projectPath else { return nil }
            if let cached = self.cache[projectPath] {
                return cached
            }
            let resolved = self.resolveCanonicalProjectPath(projectPath) ?? projectPath
            self.cache[projectPath] = resolved
            return resolved
        }

        private func resolveCanonicalProjectPath(_ projectPath: String) -> String? {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: projectPath, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return nil }
            guard let output = self.gitWorktreeList(projectPath: projectPath) else { return nil }
            let worktrees = output
                .split(separator: "\n")
                .compactMap { line -> String? in
                    guard line.hasPrefix("worktree ") else { return nil }
                    let rawPath = line.dropFirst("worktree ".count)
                    return Self.standardizedAbsolutePath(String(rawPath))
                }
            guard !worktrees.isEmpty else { return nil }
            return worktrees.first { !self.isEphemeralWorktreePath($0) }
        }

        private func gitWorktreeList(projectPath: String) -> String? {
            let process = Process()
            process.environment = TTYCommandRunner.enrichedEnvironment()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git", "-C", projectPath, "worktree", "list", "--porcelain"]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            let outputCapture = ProcessPipeCapture(pipe: outputPipe)
            let errorCapture = ProcessPipeCapture(pipe: errorPipe)

            let semaphore = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in semaphore.signal() }
            do {
                try process.run()
            } catch {
                return nil
            }
            outputCapture.start()
            errorCapture.start()

            if semaphore.wait(timeout: .now() + .seconds(1)) == .timedOut {
                process.terminate()
                outputCapture.stop()
                errorCapture.stop()
                return nil
            }
            let data = outputCapture.finishSynchronously(timeout: 0.1)
            errorCapture.stop()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        }

        private func isEphemeralWorktreePath(_ path: String) -> Bool {
            path == self.homeCodexWorktreesPrefix
                || path.hasPrefix(self.homeCodexWorktreesPrefix + "/")
                || path.hasSuffix("/.codex/worktrees")
                || path.contains("/.codex/worktrees/")
                || path == "/private/tmp"
                || path.hasPrefix("/private/tmp/")
        }

        private static func standardizedAbsolutePath(_ path: String) -> String? {
            let expanded = (path as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
        }
    }

    struct CodexRefreshPlan {
        let refreshMs: Int64
        let roots: [URL]
        let rootsFingerprint: [String: Int64]
        let rootsChanged: Bool
        let windowExpanded: Bool
        let needsPricingMetadataMigration: Bool
        let needsProjectMetadataMigration: Bool
        let modelsDevCatalog: ModelsDevCatalog?
        let codexPricingKey: String
        let codexPriorityMetadataKey: String
        let hasPriorityMetadata: Bool
        let priorityTurns: [String: CodexPriorityTurnMetadata]
        let priorityTurnKeys: [String: String]
        let priorityTurnIDsByDay: [String: [String]]
        let inspectedPriorityTurns: Bool
        let priorityTurnsCursor: CodexPriorityTurnsPersistedCursor?
        let priorityMetadataChanged: Bool
        let priorityTurnsChanged: Bool
        let needsTurnIDCacheMigration: Bool
        let changedPriorityTurnIDs: Set<String>
        let requiresAllFilesForCacheWideMigration: Bool
        let cacheWideMigrationPendingPathKeys: Set<String>
        let sourceRowRecoveryPathKeys: Set<String>
        let historyRetryPathKeys: Set<String>
        let forceFullScanHistoryRetryPathKeys: Set<String>
        let preserveUnavailableHistoryDuringRecovery: Bool
        let requiresCacheWideFileReprocessing: Bool
        let shouldRefresh: Bool
    }

    final class CodexSessionFileIndex {
        enum Lookup {
            case found(URL)
            case missing(dependencyKey: String)
            case deferred
        }

        private enum InventoryValidation {
            case current
            case changed
            case deferred
        }

        private let files: [URL]
        private let roots: [URL]
        private let checkCancellation: CancellationCheck?
        private let scanBudget: CodexScanBudget?
        private var metadataScanBudget: CodexScanBudget?
        private let headParseObserver: (() -> Void)?
        private var discovery: CostUsageCodexSessionDiscovery
        private var knownFilePaths: Set<String> = []
        private var knownDirectoryPaths: Set<String> = []
        private var recentlyEnqueuedFilePaths: [String] = []

        init(
            files: [URL],
            roots: [URL],
            cachedSessionFiles: [String: URL] = [:],
            cachedDiscovery: CostUsageCodexSessionDiscovery? = nil,
            scanBudget: CodexScanBudget? = nil,
            headParseObserver: (() -> Void)? = nil,
            checkCancellation: CancellationCheck? = nil)
        {
            self.files = files
            self.roots = roots
            self.checkCancellation = checkCancellation
            self.scanBudget = scanBudget
            self.metadataScanBudget = nil
            self.headParseObserver = headParseObserver
            let rootPaths = roots.map(\.standardizedFileURL.path).sorted()
            if var cachedDiscovery, cachedDiscovery.roots == rootPaths {
                for (sessionId, fileURL) in cachedSessionFiles {
                    cachedDiscovery.filePathBySessionId[sessionId] = fileURL.standardizedFileURL.path
                }
                self.discovery = cachedDiscovery
                self.knownFilePaths = Set(cachedDiscovery.filePaths)
                self.knownDirectoryPaths = Set(cachedDiscovery.directoryPaths)
                if !cachedDiscovery.isComplete {
                    self.enqueueCurrentFiles()
                }
            } else {
                self.discovery = Self.makeFreshDiscovery(
                    roots: roots,
                    files: files,
                    cachedSessionFiles: cachedSessionFiles,
                    retaining: nil)
                self.knownFilePaths = Set(self.discovery.filePaths)
                self.knownDirectoryPaths = Set(self.discovery.directoryPaths)
            }
        }

        var persistedState: CostUsageCodexSessionDiscovery {
            self.discovery
        }

        var hasPendingDiscovery: Bool {
            !self.discovery.isComplete
                && (!self.discovery.pendingSessionIds.isEmpty || self.discovery.headScan != nil)
        }

        var hasPendingMetadataInventory: Bool {
            self.discovery.nextDirectoryIndex < self.discovery.directoryPaths.count
                || Set(self.discovery.directoryPaths) != Set(self.discovery.directoryStamps.keys)
                || self.discovery.validationDirectoryIndex > 0
                || (self.discovery.metadataCandidateIndex ?? 0) < self.discovery.filePaths.count
        }

        /// Advances the filesystem inventory without parsing session heads. This lets callers
        /// prove a fresh current-day projection while older session contents remain in bounded
        /// catch-up. A separate bounded budget and persisted cursor keep traversal incremental
        /// without taking time from current-day parsing.
        func advanceMetadataInventory(scanBudget: CodexScanBudget? = nil) throws {
            self.metadataScanBudget = scanBudget
            defer { self.metadataScanBudget = nil }
            let inventoryIsComplete = self.discovery.nextDirectoryIndex == self.discovery.directoryPaths.count
                && Set(self.discovery.directoryPaths) == Set(self.discovery.directoryStamps.keys)
            if inventoryIsComplete {
                switch try self.validateInventory() {
                case .current:
                    return
                case .changed:
                    let refreshedDiscovery = Self.makeFreshDiscovery(
                        roots: self.roots,
                        files: self.files,
                        cachedSessionFiles: self.cachedSessionFiles(),
                        retaining: self.discovery)
                    self.discovery = refreshedDiscovery
                    self.knownFilePaths = Set(self.discovery.filePaths)
                    self.knownDirectoryPaths = Set(self.discovery.directoryPaths)
                case .deferred:
                    return
                }
            }

            while self.discovery.nextDirectoryIndex < self.discovery.directoryPaths.count {
                guard try self.enumerateNextDirectory() else { return }
            }
        }

        // swiftlint:disable function_parameter_count
        /// Visits only a bounded page of the persisted file inventory. The cursor advances
        /// independently from session-head discovery so routine refreshes never rebuild a
        /// normalized copy of the full cache or stat every historical session in one pass.
        func takeMetadataRefreshCandidates(
            cache: CostUsageCache,
            dayKey: String,
            scanSinceKey: String,
            calendar: Calendar,
            visitLimit: Int,
            restartCompletedSweep: Bool) throws -> [URL]
        {
            guard let dayStart = CostUsageScanner.parseDayKey(dayKey, calendar: calendar) else { return [] }
            let dayStartMs = Int64(dayStart.timeIntervalSince1970 * 1000)
            let scanSinceMs = CostUsageScanner.parseDayKey(scanSinceKey, calendar: calendar)
                .map { Int64($0.timeIntervalSince1970 * 1000) } ?? dayStartMs
            let persistedCandidateIndex = self.discovery.metadataCandidateIndex ?? 0
            let priorityPaths = Array(self.recentlyEnqueuedFilePaths.prefix(max(1, visitLimit)))
            self.recentlyEnqueuedFilePaths.removeFirst(priorityPaths.count)
            if self.discovery.metadataCandidateIndex != nil,
               persistedCandidateIndex >= self.discovery.filePaths.count,
               !restartCompletedSweep,
               priorityPaths.isEmpty
            {
                return []
            }
            let startIndex = persistedCandidateIndex >= self.discovery.filePaths.count
                ? (restartCompletedSweep ? 0 : self.discovery.filePaths.count)
                : max(0, persistedCandidateIndex)
            let remainingVisitCount = max(0, visitLimit - priorityPaths.count)
            let endIndex = min(
                self.discovery.filePaths.count,
                startIndex + remainingVisitCount)
            var currentDayCandidates: [URL] = []
            var historicalCandidates: [URL] = []
            currentDayCandidates.reserveCapacity(
                min(endIndex - startIndex, CostUsageScanner.codexCatchUpHydrationPathLimit))

            let pathsToVisit = priorityPaths + self.discovery.filePaths[startIndex..<endIndex]
            var visitedPathKeys: Set<String> = []
            for path in pathsToVisit {
                try self.checkCancellation?()
                let fileURL = URL(fileURLWithPath: path)
                guard visitedPathKeys.insert(CostUsageScanner.codexPathKey(fileURL)).inserted else { continue }
                let resolvedPath = CostUsageScanner.codexResolvedPath(fileURL)
                let standardizedPath = fileURL.standardizedFileURL.path
                let usage = cache.files[resolvedPath] ?? cache.files[standardizedPath]
                let metadata = CostUsageScanner.codexFileMetadata(fileURL: fileURL)
                if let usage {
                    let canAffectDay = metadata.mtimeUnixMs >= dayStartMs
                        || usage.touchesCodexScanWindow(
                            sinceKey: dayKey,
                            untilKey: dayKey,
                            calendar: calendar)
                    let matchesPersistedSnapshot = usage.hasCurrentCodexParser
                        && usage.codexScanComplete == true
                        && !usage.hasPendingCodexForkRetry
                        && usage.mtimeUnixMs == metadata.mtimeUnixMs
                        && usage.size == metadata.size
                        && usage.codexScanFileId == metadata.fileId
                        && (usage.parsedBytes ?? usage.size) >= metadata.size
                    if !matchesPersistedSnapshot {
                        if canAffectDay {
                            currentDayCandidates.append(fileURL)
                        } else {
                            historicalCandidates.append(fileURL)
                        }
                    }
                } else if metadata.fileId != nil {
                    if metadata.mtimeUnixMs >= dayStartMs {
                        currentDayCandidates.append(fileURL)
                    } else if metadata.mtimeUnixMs >= scanSinceMs {
                        // A metadata traversal can see files outside the requested scan range.
                        // Import a previously unknown historical file only when its filesystem
                        // activity falls inside that range; established cache rows are still
                        // compared above regardless of age so appends and deletions cannot be
                        // missed during the rolling sweep.
                        historicalCandidates.append(fileURL)
                    }
                }
            }
            self.discovery.metadataCandidateIndex = endIndex
            if endIndex >= self.discovery.filePaths.count {
                self.discovery.metadataInventoryEstablished = true
            }
            return currentDayCandidates + historicalCandidates
        }

        // swiftlint:enable function_parameter_count

        func resumePendingDiscovery() throws {
            guard !self.discovery.isComplete else { return }
            guard !self.discovery.pendingSessionIds.isEmpty else {
                self.discovery.headScan = nil
                return
            }
            _ = try self.resumeDiscovery()
        }

        func remember(fileURL: URL, sessionId: String?) {
            guard let sessionId, !sessionId.isEmpty else { return }
            let path = fileURL.standardizedFileURL.path
            self.discovery.filePathBySessionId[sessionId] = path
            self.resolveRequest(sessionId: sessionId)
            self.discovery.fileStamps[path] = Self.fileStamp(fileURL: fileURL)
        }

        private func resolveRequest(sessionId: String) {
            self.discovery.missingSessionIds.removeAll { $0 == sessionId }
            self.discovery.pendingSessionIds.removeAll { $0 == sessionId }
        }

        func forgetMissingFiles(_ paths: Set<String>) {
            guard !paths.isEmpty else { return }
            let normalizedPaths = Set(paths.map {
                CostUsageScanner.codexPathKey(URL(fileURLWithPath: $0))
            })
            self.discovery.filePaths.removeAll {
                normalizedPaths.contains(CostUsageScanner.codexPathKey(URL(fileURLWithPath: $0)))
            }
            self.discovery.fileStamps = self.discovery.fileStamps.filter {
                !normalizedPaths.contains(CostUsageScanner.codexPathKey(URL(fileURLWithPath: $0.key)))
            }
            self.discovery.filePathBySessionId = self.discovery.filePathBySessionId.filter {
                !normalizedPaths.contains(CostUsageScanner.codexPathKey(URL(fileURLWithPath: $0.value)))
            }
            self.discovery.metadataCandidateIndex = min(
                self.discovery.metadataCandidateIndex ?? 0,
                self.discovery.filePaths.count)
        }

        func lookup(sessionId: String) throws -> Lookup {
            if let cached = self.cachedFileURL(for: sessionId) {
                self.resolveRequest(sessionId: sessionId)
                return .found(cached)
            }

            if self.discovery.isComplete {
                switch try self.validateInventory() {
                case .current:
                    if self.discovery.missingSessionIds.contains(sessionId),
                       let generation = self.discovery.generation
                    {
                        return .missing(dependencyKey: Self.missingDependencyKey(
                            sessionId: sessionId,
                            generation: generation))
                    }
                case .changed:
                    let refreshedDiscovery = Self.makeFreshDiscovery(
                        roots: self.roots,
                        files: self.files,
                        cachedSessionFiles: self.cachedSessionFiles(),
                        retaining: self.discovery)
                    self.discovery = refreshedDiscovery
                    self.knownFilePaths = Set(self.discovery.filePaths)
                    self.knownDirectoryPaths = Set(self.discovery.directoryPaths)
                case .deferred:
                    return .deferred
                }
            }

            let alreadyClassified = self.hasScannedInventory && self.discovery.missingSessionIds.contains(sessionId)
            if !alreadyClassified, !self.discovery.pendingSessionIds.contains(sessionId) {
                self.discovery.pendingSessionIds.append(sessionId)
                self.discovery.isComplete = false
            }
            guard try self.resumeDiscovery(requestedSessionId: sessionId) else { return .deferred }
            if let cached = self.cachedFileURL(for: sessionId) {
                self.resolveRequest(sessionId: sessionId)
                return .found(cached)
            }
            return .missing(dependencyKey: Self.missingDependencyKey(
                sessionId: sessionId,
                generation: self.discovery.generation ?? "unknown"))
        }

        private func cachedFileURL(for sessionId: String) -> URL? {
            guard let path = self.discovery.filePathBySessionId[sessionId] else { return nil }
            guard FileManager.default.fileExists(atPath: path) else {
                self.discovery.filePathBySessionId.removeValue(forKey: sessionId)
                return nil
            }
            return URL(fileURLWithPath: path)
        }

        private func cachedSessionFiles() -> [String: URL] {
            self.discovery.filePathBySessionId.reduce(into: [:]) { result, entry in
                guard FileManager.default.fileExists(atPath: entry.value) else { return }
                result[entry.key] = URL(fileURLWithPath: entry.value)
            }
        }

        private var hasScannedInventory: Bool {
            self.discovery.headScan == nil
                && self.discovery.nextFileIndex >= self.discovery.filePaths.count
                && self.discovery.nextDirectoryIndex >= self.discovery.directoryPaths.count
        }

        private func resumeDiscovery(requestedSessionId: String? = nil) throws -> Bool {
            while true {
                try self.checkCancellation?()
                if let requestedSessionId, self.cachedFileURL(for: requestedSessionId) != nil {
                    return true
                }
                if self.discovery.nextFileIndex < self.discovery.filePaths.count {
                    guard try self.scanNextFileHead() else { return false }
                    continue
                }
                if self.discovery.nextDirectoryIndex < self.discovery.directoryPaths.count {
                    guard try self.enumerateNextDirectory() else { return false }
                    continue
                }
                return try self.finishDiscovery()
            }
        }

        private func scanNextFileHead() throws -> Bool {
            let path = self.discovery.filePaths[self.discovery.nextFileIndex]
            let fileURL = URL(fileURLWithPath: path)
            let metadata = CostUsageScanner.codexFileMetadata(fileURL: fileURL)
            guard metadata.fileId != nil else {
                if let scanBudget = self.scanBudget {
                    switch scanBudget.admit(workBytes: 1) {
                    case let .allow(allowance):
                        scanBudget.complete(admittedWorkBytes: allowance, actualWorkBytes: allowance)
                    case .deferBudget:
                        return false
                    }
                }
                self.advancePastHead(path: path, stamp: nil)
                return true
            }

            var head = self.discovery.headScan
            if head?.path != path {
                head = CostUsageCodexSessionDiscovery.HeadScan(path: path, offset: 0, resumeState: nil)
            }
            let startOffset = head?.resumeState?.offset ?? head?.offset ?? 0
            let remainingBytes = max(0, metadata.size - startOffset)
            let admittedBytes: Int64
            if let scanBudget = self.scanBudget {
                switch scanBudget.admit(workBytes: max(1, remainingBytes)) {
                case let .allow(allowance): admittedBytes = allowance
                case .deferBudget: return false
                }
            } else {
                admittedBytes = remainingBytes
            }

            self.headParseObserver?()
            let result = try CostUsageScanner.scanCodexSessionIdentifier(
                fileURL: fileURL,
                offset: head?.offset ?? 0,
                maxBytesToRead: admittedBytes,
                resumeState: head?.resumeState,
                checkCancellation: self.checkCancellation)
            self.scanBudget?.complete(
                admittedWorkBytes: admittedBytes,
                actualWorkBytes: max(1, result.bytesRead))

            if let sessionId = result.sessionId, !sessionId.isEmpty {
                self.discovery.filePathBySessionId[sessionId] = path
                self.discovery.missingSessionIds.removeAll { $0 == sessionId }
                self.advancePastHead(path: path, stamp: Self.fileStamp(metadata: metadata))
                return true
            }
            if result.isComplete {
                self.advancePastHead(path: path, stamp: Self.fileStamp(metadata: metadata))
                return true
            }

            self.discovery.headScan = CostUsageCodexSessionDiscovery.HeadScan(
                path: path,
                offset: result.committedOffset,
                resumeState: result.resumeState)
            return false
        }

        private func advancePastHead(
            path: String,
            stamp: CostUsageCodexSessionDiscovery.FileStamp?)
        {
            if let stamp {
                self.discovery.fileStamps[path] = stamp
            } else {
                self.discovery.fileStamps.removeValue(forKey: path)
                self.discovery.filePathBySessionId = self.discovery.filePathBySessionId.filter { $0.value != path }
            }
            self.discovery.headScan = nil
            self.discovery.nextFileIndex += 1
        }

        private func enumerateNextDirectory() throws -> Bool {
            let directoryBudget = self.metadataScanBudget ?? self.scanBudget
            let admittedWork: Int64
            if let directoryBudget {
                switch directoryBudget.admit(workBytes: 1) {
                case let .allow(allowance): admittedWork = allowance
                case .deferBudget: return false
                }
            } else {
                admittedWork = 1
            }
            defer {
                directoryBudget?.complete(admittedWorkBytes: admittedWork, actualWorkBytes: admittedWork)
            }

            try self.checkCancellation?()
            let path = self.discovery.directoryPaths[self.discovery.nextDirectoryIndex]
            let directoryURL = URL(fileURLWithPath: path, isDirectory: true)
            let items = (try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? []
            var jsonlFileCount = 0
            for item in items {
                try self.checkCancellation?()
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if values?.isDirectory == true {
                    self.enqueueDirectory(item)
                } else if item.pathExtension.lowercased() == "jsonl" {
                    jsonlFileCount += 1
                    let path = item.standardizedFileURL.path
                    let lacksPersistedStamp = self.discovery.fileStamps[path] == nil
                    if self.enqueueFile(item) || lacksPersistedStamp {
                        self.recentlyEnqueuedFilePaths.append(path)
                    }
                }
            }
            let metadata = CostUsageScanner.codexFileMetadata(fileURL: directoryURL)
            self.discovery.directoryStamps[path] = .init(
                mtimeUnixMs: metadata.mtimeUnixMs,
                jsonlFileCount: jsonlFileCount)
            self.discovery.nextDirectoryIndex += 1
            return !self.metadataScanBudgetExhausted()
        }

        private func enqueueCurrentFiles() {
            for fileURL in self.files {
                self.enqueueFile(fileURL)
            }
        }

        @discardableResult
        private func enqueueFile(_ fileURL: URL) -> Bool {
            let path = fileURL.standardizedFileURL.path
            guard self.knownFilePaths.insert(path).inserted else { return false }
            self.discovery.filePaths.append(path)
            return true
        }

        private func enqueueDirectory(_ directoryURL: URL) {
            let path = directoryURL.standardizedFileURL.path
            guard self.knownDirectoryPaths.insert(path).inserted else { return }
            self.discovery.directoryPaths.append(path)
        }

        private func finishDiscovery() throws -> Bool {
            var processedCount = 0
            defer { self.discovery.pendingSessionIds.removeFirst(processedCount) }
            for sessionId in self.discovery.pendingSessionIds {
                try self.checkCancellation?()
                if let scanBudget = self.scanBudget {
                    switch scanBudget.admit(workBytes: 1) {
                    case let .allow(allowance):
                        scanBudget.complete(admittedWorkBytes: allowance, actualWorkBytes: allowance)
                    case .deferBudget:
                        return false
                    }
                }
                if self.cachedFileURL(for: sessionId) == nil,
                   !self.discovery.missingSessionIds.contains(sessionId)
                {
                    self.discovery.missingSessionIds.append(sessionId)
                }
                processedCount += 1
            }
            let generation = Self.discoveryGeneration(
                roots: self.discovery.roots,
                directoryStamps: self.discovery.directoryStamps)
            self.discovery.generation = generation
            self.discovery.missingSessionIds.sort()
            self.discovery.directoryPaths = self.discovery.directoryStamps.keys.sorted()
            self.discovery.nextDirectoryIndex = self.discovery.directoryPaths.count
            self.discovery.validationDirectoryIndex = 0
            self.discovery.isComplete = true
            return true
        }

        private func validateInventory() throws -> InventoryValidation {
            let directoryBudget = self.metadataScanBudget ?? self.scanBudget
            while self.discovery.validationDirectoryIndex < self.discovery.directoryPaths.count {
                let admittedWork: Int64
                if let directoryBudget {
                    switch directoryBudget.admit(workBytes: 1) {
                    case let .allow(allowance): admittedWork = allowance
                    case .deferBudget: return .deferred
                    }
                } else {
                    admittedWork = 1
                }

                try self.checkCancellation?()
                let path = self.discovery.directoryPaths[self.discovery.validationDirectoryIndex]
                let currentStamp = Self.directoryStamp(atPath: path)
                directoryBudget?.complete(admittedWorkBytes: admittedWork, actualWorkBytes: admittedWork)
                guard currentStamp == self.discovery.directoryStamps[path] else {
                    self.discovery.validationDirectoryIndex = 0
                    return .changed
                }
                self.discovery.validationDirectoryIndex += 1
                if self.metadataScanBudgetExhausted() {
                    return .deferred
                }
            }
            self.discovery.validationDirectoryIndex = 0
            return .current
        }

        private func metadataScanBudgetExhausted() -> Bool {
            guard let scanBudget = self.metadataScanBudget ?? self.scanBudget else { return false }
            switch scanBudget.admit(workBytes: 1) {
            case let .allow(allowance):
                scanBudget.release(workBytes: allowance)
                return false
            case .deferBudget:
                return true
            }
        }

        private static func makeFreshDiscovery(
            roots: [URL],
            files: [URL],
            cachedSessionFiles: [String: URL],
            retaining previous: CostUsageCodexSessionDiscovery?) -> CostUsageCodexSessionDiscovery
        {
            let rootPaths = roots.map(\.standardizedFileURL.path).sorted()
            var retainedStamps: [String: CostUsageCodexSessionDiscovery.FileStamp] = [:]
            if let previous {
                for (path, stamp) in previous.fileStamps {
                    let current = Self.fileStamp(fileURL: URL(fileURLWithPath: path))
                    if current == stamp {
                        retainedStamps[path] = stamp
                    }
                }
            }
            for fileURL in cachedSessionFiles.values {
                let path = fileURL.standardizedFileURL.path
                if let stamp = Self.fileStamp(fileURL: fileURL) {
                    if previous == nil || previous?.fileStamps[path] == stamp {
                        retainedStamps[path] = stamp
                    }
                }
            }

            let retainedPaths = retainedStamps.keys.sorted()
            var sessionFiles = previous?.filePathBySessionId.filter {
                retainedStamps[$0.value] != nil
            } ?? [:]
            for (sessionId, fileURL) in cachedSessionFiles {
                sessionFiles[sessionId] = fileURL.standardizedFileURL.path
            }
            // Keep the prior inventory until the bounded metadata sweep classifies missing or
            // changed paths. Dropping them as soon as a directory stamp changes would make a
            // deleted historical file disappear from discovery before its cached aggregate can
            // be removed transactionally.
            var filePaths = previous?.filePaths ?? retainedPaths
            let knownPriorFileCount = filePaths.count
            var knownPaths = Set(filePaths)
            for fileURL in files {
                let path = fileURL.standardizedFileURL.path
                if knownPaths.insert(path).inserted {
                    filePaths.append(path)
                }
            }
            return CostUsageCodexSessionDiscovery(
                roots: rootPaths,
                generation: nil,
                directoryStamps: [:],
                directoryPaths: rootPaths,
                nextDirectoryIndex: 0,
                filePaths: filePaths,
                nextFileIndex: knownPriorFileCount,
                metadataCandidateIndex: retainedPaths.count,
                metadataInventoryEstablished: false,
                fileStamps: retainedStamps,
                headScan: nil,
                filePathBySessionId: sessionFiles,
                missingSessionIds: [],
                pendingSessionIds: [],
                validationDirectoryIndex: 0,
                isComplete: false)
        }

        private static func directoryStamp(
            atPath path: String) -> CostUsageCodexSessionDiscovery.DirectoryStamp?
        {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            let metadata = CostUsageScanner.codexFileMetadata(fileURL: url)
            guard metadata.fileId != nil else { return nil }
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { return nil }
            let jsonlFileCount = items.lazy
                .count(where: { $0.pathExtension.lowercased() == "jsonl" })

            return .init(mtimeUnixMs: metadata.mtimeUnixMs, jsonlFileCount: jsonlFileCount)
        }

        private static func fileStamp(
            fileURL: URL) -> CostUsageCodexSessionDiscovery.FileStamp?
        {
            self.fileStamp(metadata: CostUsageScanner.codexFileMetadata(fileURL: fileURL))
        }

        private static func fileStamp(
            metadata: CodexFileMetadata) -> CostUsageCodexSessionDiscovery.FileStamp?
        {
            guard metadata.fileId != nil else { return nil }
            return .init(mtimeUnixMs: metadata.mtimeUnixMs, size: metadata.size, fileId: metadata.fileId)
        }

        private static func discoveryGeneration(
            roots: [String],
            directoryStamps: [String: CostUsageCodexSessionDiscovery.DirectoryStamp]) -> String
        {
            let directories = directoryStamps.map { path, stamp in
                "\(path)|\(stamp.mtimeUnixMs)|\(stamp.jsonlFileCount)"
            }.sorted()
            return CostUsageScanner.sha256Hex(Data((roots + directories).joined(separator: "\n").utf8))
        }

        private static func missingDependencyKey(sessionId: String, generation: String) -> String {
            "missing|\(sessionId)|discovery|\(generation)"
        }
    }

    private struct CodexSessionIdentifierScanResult {
        let sessionId: String?
        let bytesRead: Int64
        let committedOffset: Int64
        let resumeState: CostUsageJsonl.ResumeState?
        let isComplete: Bool
    }

    private static func scanCodexSessionIdentifier(
        fileURL: URL,
        offset: Int64,
        maxBytesToRead: Int64,
        resumeState: CostUsageJsonl.ResumeState?,
        checkCancellation: CancellationCheck?) throws -> CodexSessionIdentifierScanResult
    {
        var sessionId: String?
        let scanStart = resumeState?.offset ?? max(0, offset)
        let progress = try CostUsageJsonl.scanBounded(
            fileURL: fileURL,
            offset: offset,
            maxLineBytes: Self.codexSessionMetadataMaxLineBytes,
            prefixBytes: Self.codexSessionMetadataMaxLineBytes,
            maxBytesToRead: maxBytesToRead,
            resumeState: resumeState,
            shouldStop: { _ in sessionId != nil },
            checkCancellation: checkCancellation,
            onLine: { line in
                guard !line.wasTruncated else { return }
                if case let .sessionMeta(metadata) = Self.parseCodexFastLine(line.bytes) {
                    sessionId = metadata.sessionId
                }
            })
        let size = Self.codexFileMetadata(fileURL: fileURL).size
        return CodexSessionIdentifierScanResult(
            sessionId: sessionId,
            bytesRead: max(0, progress.readOffset - scanStart),
            committedOffset: progress.committedOffset,
            resumeState: progress.resumeState,
            isComplete: sessionId != nil || progress.readOffset >= size)
    }

    final class CodexInheritedTotalsResolver {
        private struct SnapshotResolution {
            let dependencyKey: String?
            let indexedEvents: [CostUsageCodexTokenSnapshot]?
            let checkpoints: [CostUsageCodexTokenCheckpoint]
            let indexedTimestampsMonotonic: Bool
            let isComplete: Bool
            let baselineResolved: Bool
            let isFork: Bool
            let requiresInheritedOrigin: Bool
            let forkOrigin: CodexForkAccountingState?
            let forkOriginDependencyKey: String?

            init(
                dependencyKey: String?,
                indexedEvents: [CostUsageCodexTokenSnapshot]? = nil,
                checkpoints: [CostUsageCodexTokenCheckpoint] = [],
                indexedTimestampsMonotonic: Bool = false,
                isComplete: Bool,
                baselineResolved: Bool = true,
                isFork: Bool = false,
                requiresInheritedOrigin: Bool = false,
                forkOrigin: CodexForkAccountingState? = nil,
                forkOriginDependencyKey: String? = nil)
            {
                self.dependencyKey = dependencyKey
                self.indexedEvents = indexedEvents
                self.checkpoints = checkpoints
                self.indexedTimestampsMonotonic = indexedTimestampsMonotonic
                self.isComplete = isComplete
                self.baselineResolved = baselineResolved
                self.isFork = isFork
                self.requiresInheritedOrigin = requiresInheritedOrigin
                self.forkOrigin = forkOrigin
                self.forkOriginDependencyKey = forkOriginDependencyKey
            }

            var lastTimestamp: String? {
                self.indexedEvents?.last?.timestamp
            }

            var hasSnapshotSource: Bool {
                self.indexedEvents != nil
            }
        }

        private let fileIndex: CodexSessionFileIndex
        private let checkCancellation: CancellationCheck?
        private let scanBudget: CodexScanBudget?
        private let historyHydrator: CodexScanHistoryHydrator?
        private var cachedFiles: [String: CostUsageFileUsage]
        private var snapshotResolutions: [String: SnapshotResolution] = [:]
        private var resolvedDependencyKeys: [String: String] = [:]
        private var pendingParentFiles: [String: URL] = [:]
        private var resolvingSessionIDs: Set<String> = []

        init(
            fileIndex: CodexSessionFileIndex,
            checkCancellation: CancellationCheck?,
            scanBudget: CodexScanBudget? = nil,
            cachedFiles: [String: CostUsageFileUsage] = [:],
            historyHydrator: CodexScanHistoryHydrator? = nil)
        {
            self.fileIndex = fileIndex
            self.checkCancellation = checkCancellation
            self.scanBudget = scanBudget
            self.cachedFiles = cachedFiles
            self.historyHydrator = historyHydrator
        }

        func updateCachedUsage(fileURL: URL, usage: CostUsageFileUsage?) {
            let path = fileURL.path
            let standardizedPath = fileURL.standardizedFileURL.path
            let previousSessionId = self.cachedFiles[path]?.sessionId
                ?? self.cachedFiles[standardizedPath]?.sessionId
            if let usage {
                self.cachedFiles[path] = usage
                self.cachedFiles[standardizedPath] = usage
            } else {
                self.cachedFiles.removeValue(forKey: path)
                self.cachedFiles.removeValue(forKey: standardizedPath)
            }
            for sessionId in Set([previousSessionId, usage?.sessionId].compactMap(\.self)) {
                self.snapshotResolutions.removeValue(forKey: sessionId)
                self.resolvedDependencyKeys.removeValue(forKey: sessionId)
            }
        }

        func inheritedTotals(for sessionId: String, atOrBefore cutoffTimestamp: String) throws -> CodexForkBaseline {
            guard self.resolvingSessionIDs.count < 64,
                  self.resolvingSessionIDs.insert(sessionId).inserted else { return .unresolved }
            defer { self.resolvingSessionIDs.remove(sessionId) }
            guard !cutoffTimestamp.isEmpty else {
                CostUsageScanner.log.warning(
                    "Codex cost usage fork timestamp missing; treating parent baseline as unresolved",
                    metadata: ["sessionId": sessionId])
                return .unresolved
            }
            let cutoffDate = CostUsageScanner.dateFromTimestamp(cutoffTimestamp)
            if cutoffDate == nil {
                CostUsageScanner.log.warning(
                    "Codex cost usage could not parse fork timestamp; falling back to lexical comparison",
                    metadata: ["sessionId": sessionId, "timestamp": cutoffTimestamp])
            }
            let resolution = try self.snapshotResolution(for: sessionId)
            let dependencyKey = resolution.dependencyKey.map {
                $0 + (resolution.forkOriginDependencyKey.map { "|inherited|" + $0 } ?? "")
            }
            guard resolution.hasSnapshotSource else {
                self.resolvedDependencyKeys[sessionId] = dependencyKey
                    .flatMap { CostUsageScanner.codexDependencyIsMissing($0) ? $0 : nil }
                return .unresolved
            }
            guard resolution.baselineResolved else { return .unresolved }
            if !resolution.isComplete {
                guard let lastTimestamp = resolution.lastTimestamp else { return .unresolved }
                let lastDate = CostUsageScanner.dateFromTimestamp(lastTimestamp)
                let coversCutoff: Bool = if let lastDate, let cutoffDate {
                    lastDate >= cutoffDate
                } else {
                    lastTimestamp >= cutoffTimestamp
                }
                guard coversCutoff else { return .unresolved }
            }
            let inherited = self.inheritedTotals(
                from: resolution,
                cutoffTimestamp: cutoffTimestamp,
                cutoffDate: cutoffDate)
            if resolution.requiresInheritedOrigin {
                guard let parentID = resolution.forkOrigin?.metadata.forkedFromId,
                      let inheritedKey = resolution.forkOriginDependencyKey,
                      try inheritedKey == self.currentDependencyKey(for: parentID)
                else { return .unresolved }
            } else if inherited == nil, resolution.isFork, resolution.forkOrigin == nil {
                return .unresolved
            }
            self.resolvedDependencyKeys[sessionId] = dependencyKey
            return .resolved(inherited)
        }

        private func inheritedTotals(
            from resolution: SnapshotResolution,
            cutoffTimestamp: String,
            cutoffDate: Date?) -> CostUsageCodexTotals?
        {
            func isAtOrBefore(_ timestamp: String, date: Date? = nil) -> Bool {
                if let date = date ?? CostUsageScanner.dateFromTimestamp(timestamp), let cutoffDate {
                    return date <= cutoffDate
                }
                return timestamp <= cutoffTimestamp
            }

            if let events = resolution.indexedEvents {
                var selectedCheckpoint: CostUsageCodexTokenCheckpoint?
                let checkpointsAreSearchable = resolution.checkpoints.enumerated().allSatisfy { index, checkpoint in
                    checkpoint.eventIndex >= 0
                        && checkpoint.eventIndex < events.count
                        && checkpoint.timestamp == events[checkpoint.eventIndex].timestamp
                        && (index == 0
                            || resolution.checkpoints[index - 1].eventIndex < checkpoint.eventIndex)
                }
                let checkpoints = checkpointsAreSearchable ? resolution.checkpoints : []
                if resolution.indexedTimestampsMonotonic {
                    var lowerBound = 0
                    var upperBound = checkpoints.count
                    while lowerBound < upperBound {
                        let middle = lowerBound + (upperBound - lowerBound) / 2
                        if isAtOrBefore(checkpoints[middle].timestamp) {
                            lowerBound = middle + 1
                        } else {
                            upperBound = middle
                        }
                    }
                    if lowerBound > 0 {
                        selectedCheckpoint = checkpoints[lowerBound - 1]
                    }
                } else {
                    for checkpoint in checkpoints where isAtOrBefore(checkpoint.timestamp) {
                        selectedCheckpoint = checkpoint
                    }
                }

                var accumulator = CodexSnapshotAccumulator(state: selectedCheckpoint?.state)
                var inherited = selectedCheckpoint?.state.countedTotals
                let startIndex = min(events.count, (selectedCheckpoint?.eventIndex ?? -1) + 1)
                for event in events[startIndex...] {
                    let eventIsAtOrBefore = isAtOrBefore(event.timestamp)
                    if resolution.indexedTimestampsMonotonic, !eventIsAtOrBefore {
                        break
                    }
                    let counted = accumulator.apply(last: event.last, total: event.total)
                    if eventIsAtOrBefore {
                        inherited = counted
                    }
                }
                return inherited ?? resolution.forkOrigin?.inheritedTotals
            }
            return nil
        }

        func currentDependencyKey(for sessionId: String) throws -> String? {
            var nextSessionID: String? = sessionId
            var visited: Set<String> = []
            var keys: [String] = []
            while let currentSessionID = nextSessionID {
                guard visited.count < 64, visited.insert(currentSessionID).inserted else { return nil }
                switch try self.fileIndex.lookup(sessionId: currentSessionID) {
                case let .found(fileURL):
                    let fileDependencyKey = self.dependencyKey(for: currentSessionID, fileURL: fileURL)
                    keys.append(fileDependencyKey)
                    let usage = self.cachedFiles[fileURL.path] ?? self.cachedFiles[fileURL.standardizedFileURL.path]
                    if let resolved = self.snapshotResolutions[currentSessionID],
                       resolved.dependencyKey == fileDependencyKey,
                       resolved.hasSnapshotSource,
                       resolved.baselineResolved
                    {
                        // A fresh resolution can repair stale cached independence metadata.
                        // Follow the ancestry actually used to produce that baseline.
                        nextSessionID = resolved.requiresInheritedOrigin
                            ? resolved.forkOrigin?.metadata.forkedFromId : nil
                    } else if usage?.forkBaselineDependencyKey == CostUsageScanner.codexForkDependencyNotRequiredKey {
                        nextSessionID = nil
                    } else {
                        nextSessionID = usage?.forkedFromId
                            ?? self.snapshotResolutions[currentSessionID]?.forkOrigin?.metadata.forkedFromId
                    }
                case let .missing(dependencyKey):
                    keys.append(dependencyKey)
                    nextSessionID = nil
                case .deferred:
                    return nil
                }
            }
            return keys.joined(separator: "|inherited|")
        }

        func dependencyKeyUsed(for sessionId: String) -> String? {
            self.resolvedDependencyKeys[sessionId]
        }

        func takePendingParentFiles() -> [URL] {
            let files = self.pendingParentFiles.values.sorted(by: { $0.path < $1.path })
            self.pendingParentFiles.removeAll(keepingCapacity: true)
            return files
        }

        private func dependencyKey(for sessionId: String, fileURL: URL) -> String {
            let metadata = CostUsageScanner.codexFileMetadata(fileURL: fileURL)
            return [
                "file",
                sessionId,
                fileURL.standardizedFileURL.path,
                metadata.fileId ?? "unknown",
                String(metadata.mtimeUnixMs),
                String(metadata.size),
            ].joined(separator: "|")
        }

        private func snapshotResolution(for sessionId: String) throws -> SnapshotResolution {
            try self.checkCancellation?()
            let lookup = try self.fileIndex.lookup(sessionId: sessionId)
            let fileURL: URL
            switch lookup {
            case let .found(foundURL):
                fileURL = foundURL
            case let .missing(dependencyKey):
                CostUsageScanner.log.warning(
                    "Codex cost usage parent session file not found",
                    metadata: ["sessionId": sessionId])
                let resolution = SnapshotResolution(
                    dependencyKey: dependencyKey,
                    isComplete: false)
                self.snapshotResolutions[sessionId] = resolution
                self.resolvedDependencyKeys[sessionId] = dependencyKey
                return resolution
            case .deferred:
                let resolution = SnapshotResolution(
                    dependencyKey: nil,
                    isComplete: false)
                self.snapshotResolutions[sessionId] = resolution
                return resolution
            }

            if let cached = self.snapshotResolutions[sessionId],
               cached.dependencyKey == self.dependencyKey(for: sessionId, fileURL: fileURL)
            {
                let missingAncestry = cached.forkOriginDependencyKey
                    .map(CostUsageScanner.codexDependencyIsMissing) == true
                let cachedUsage = self.cachedFiles[fileURL.path]
                    ?? self.cachedFiles[fileURL.standardizedFileURL.path]
                if let parentID = cached.forkOrigin?.metadata.forkedFromId
                    ?? (missingAncestry ? cachedUsage?.forkedFromId : nil)
                {
                    if try cached.forkOriginDependencyKey == self.currentDependencyKey(for: parentID) {
                        return cached
                    }
                } else {
                    return cached
                }
            }
            let parentMetadata = CostUsageScanner.codexFileMetadata(fileURL: fileURL)
            if let cachedResolution = try self.cachedSnapshotResolution(
                for: sessionId,
                fileURL: fileURL,
                metadata: parentMetadata)
            {
                if self.scanBudget != nil, !cachedResolution.isComplete {
                    self.pendingParentFiles[fileURL.standardizedFileURL.path] = fileURL
                }
                self.snapshotResolutions[sessionId] = cachedResolution
                return cachedResolution
            }
            if self.scanBudget != nil {
                // A parent discovered while parsing a child must use the same persistent,
                // resumable scan path as ordinary files. Queue it for this refresh instead of
                // opening it here and bypassing the byte or wall-clock budget.
                self.pendingParentFiles[fileURL.standardizedFileURL.path] = fileURL
                let resolution = SnapshotResolution(
                    dependencyKey: self.dependencyKey(for: sessionId, fileURL: fileURL),
                    isComplete: false)
                self.snapshotResolutions[sessionId] = resolution
                return resolution
            }

            // Direct resolver construction without a scan budget is retained for focused parser
            // tests and explicit unbounded callers. Production refreshes always install a budget.
            for _ in 0..<2 {
                let dependencyKeyBeforeParse = self.dependencyKey(for: sessionId, fileURL: fileURL)
                let parsed = try CostUsageScanner.parseCodexFileCancellable(
                    fileURL: fileURL,
                    range: .init(since: Date(), until: Date()),
                    inheritedTotalsResolver: { try self.inheritedTotals(for: $0, atOrBefore: $1) },
                    checkCancellation: self.checkCancellation)
                let dependencyKeyAfterParse = self.dependencyKey(for: sessionId, fileURL: fileURL)
                guard dependencyKeyBeforeParse == dependencyKeyAfterParse else { continue }

                guard let parsedSessionId = parsed.sessionId else {
                    CostUsageScanner.log.warning(
                        "Codex cost usage parent session missing session metadata",
                        metadata: ["sessionId": sessionId, "path": fileURL.path])
                    let resolution = SnapshotResolution(
                        dependencyKey: dependencyKeyAfterParse,
                        isComplete: false)
                    self.snapshotResolutions[sessionId] = resolution
                    self.scanBudget?.consume(workBytes: parentMetadata.size)
                    return resolution
                }
                if parsedSessionId != sessionId {
                    CostUsageScanner.log.warning(
                        "Codex cost usage parent session resolved to mismatched session id",
                        metadata: [
                            "requestedSessionId": sessionId,
                            "resolvedSessionId": parsedSessionId,
                            "path": fileURL.path,
                        ])
                    let resolution = SnapshotResolution(
                        dependencyKey: dependencyKeyAfterParse,
                        isComplete: false)
                    self.snapshotResolutions[sessionId] = resolution
                    self.scanBudget?.consume(workBytes: parentMetadata.size)
                    return resolution
                }
                let resolution = SnapshotResolution(
                    dependencyKey: dependencyKeyAfterParse,
                    indexedEvents: parsed.tokenSnapshots,
                    isComplete: parsed.parsedBytes >= parentMetadata.size
                        && parsed.bufferedUnresolvedForkLines == nil,
                    baselineResolved: parsed.forkedFromId == nil || parsed.forkBaselineResolved,
                    isFork: parsed.forkedFromId != nil,
                    requiresInheritedOrigin: parsed.dependsOnParentTotals
                        && parsed.forkAccountingState != nil,
                    forkOrigin: parsed.forkAccountingState,
                    forkOriginDependencyKey: parsed.dependsOnParentTotals && parsed.forkAccountingState != nil
                        ? parsed.forkedFromId.flatMap { self.dependencyKeyUsed(for: $0) } : nil)
                self.snapshotResolutions[sessionId] = resolution
                self.scanBudget?.consume(workBytes: parentMetadata.size)
                return resolution
            }

            CostUsageScanner.log.warning(
                "Codex cost usage parent session changed while reading; deferring inherited baseline",
                metadata: ["sessionId": sessionId, "path": fileURL.path])
            let resolution = SnapshotResolution(dependencyKey: nil, isComplete: false)
            self.snapshotResolutions[sessionId] = resolution
            return resolution
        }

        private func cachedSnapshotResolution(
            for sessionId: String,
            fileURL: URL,
            metadata: CodexFileMetadata) throws -> SnapshotResolution?
        {
            let standardizedPath = fileURL.standardizedFileURL.path
            let cachedPath = self.cachedFiles[fileURL.path] != nil ? fileURL.path : standardizedPath
            guard var usage = self.cachedFiles[fileURL.path] ?? self.cachedFiles[standardizedPath] else { return nil }
            // Keep the large cached usage temporaries in separate call frames. Hydration can
            // run inside a replacement parse and inherited-baseline resolution, where retaining
            // every phase's temporaries can exhaust a worker thread's stack in debug builds.
            if let missingResolution = try self.cachedMissingSnapshotResolution(
                for: sessionId,
                fileURL: fileURL,
                metadata: metadata,
                usage: usage)
            {
                return missingResolution
            }
            try self.hydrateCachedSnapshots(&usage, fileURL: fileURL, cachedPath: cachedPath)
            return try self.cachedBaselineSnapshotResolution(
                for: sessionId,
                fileURL: fileURL,
                metadata: metadata,
                usage: usage)
        }

        private func cachedMissingSnapshotResolution(
            for sessionId: String,
            fileURL: URL,
            metadata: CodexFileMetadata,
            usage: CostUsageFileUsage) throws -> SnapshotResolution?
        {
            // Missing ancestry is useful dependency evidence even while its replacement rows
            // remain staged. Never hydrate or expose that unresolved generation as a baseline.
            guard usage.hasSettledMissingCodexFork,
                  usage.sessionId == sessionId,
                  usage.mtimeUnixMs == metadata.mtimeUnixMs,
                  usage.size == metadata.size,
                  usage.codexScanFileId == nil || usage.codexScanFileId == metadata.fileId,
                  let parentID = usage.forkedFromId,
                  try usage.forkBaselineDependencyKey == self.currentDependencyKey(for: parentID)
            else { return nil }
            return SnapshotResolution(
                dependencyKey: self.dependencyKey(for: sessionId, fileURL: fileURL),
                isComplete: true,
                baselineResolved: false,
                isFork: true,
                forkOrigin: usage.codexForkAccountingState,
                forkOriginDependencyKey: usage.forkBaselineDependencyKey)
        }

        private func hydrateCachedSnapshots(
            _ usage: inout CostUsageFileUsage,
            fileURL: URL,
            cachedPath: String) throws
        {
            guard usage.codexTokenSnapshots == nil,
                  let historyHydrator = self.historyHydrator
            else { return }
            if case .ready = try historyHydrator.hydrate(
                paths: [cachedPath],
                retryTargetPath: cachedPath,
                retainedPaths: [cachedPath])
            {
                let hydrated = historyHydrator.usageWithHydratedSnapshots(usage, path: cachedPath)
                if hydrated.codexTokenSnapshots != nil {
                    self.updateCachedUsage(fileURL: fileURL, usage: hydrated)
                    usage = hydrated
                }
            }
        }

        private func cachedBaselineSnapshotResolution(
            for sessionId: String,
            fileURL: URL,
            metadata: CodexFileMetadata,
            usage: CostUsageFileUsage) throws -> SnapshotResolution?
        {
            guard usage.hasCurrentCodexParser,
                  usage.codexReplacementScanPending != true,
                  usage.sessionId == sessionId,
                  usage.codexScanFileId == nil || usage.codexScanFileId == metadata.fileId,
                  let cachedSnapshots = usage.codexTokenSnapshots
            else { return nil }

            let metadataMatches = usage.mtimeUnixMs == metadata.mtimeUnixMs
                && usage.size == metadata.size
            let appendSafePrefixMatches = usage.codexScanFileId == metadata.fileId
                && usage.size <= metadata.size
                && usage.codexTokenIndexAnchor.map {
                    CostUsageScanner.codexTokenIndexAnchorMatches(
                        $0,
                        fileURL: fileURL,
                        metadata: metadata)
                } == true
            guard metadataMatches || appendSafePrefixMatches else { return nil }
            let isSubagent: Bool = if usage.forkedFromId != nil, usage.codexForkAccountingState == nil {
                try CostUsageScanner.codexFileIsSubagentThread(
                    fileURL: fileURL,
                    checkCancellation: self.checkCancellation)
            } else {
                false
            }
            let missingParent = CostUsageScanner.isUnresolvedMissingParentFork(usage)
            let requiresInheritedOrigin = usage.forkedFromId != nil && !isSubagent && !missingParent
                && usage.forkBaselineDependencyKey != CostUsageScanner.codexForkDependencyNotRequiredKey
            if requiresInheritedOrigin {
                guard let parentID = usage.forkedFromId,
                      usage.codexForkAccountingState != nil,
                      let inheritedKey = usage.forkBaselineDependencyKey,
                      try inheritedKey == self.currentDependencyKey(for: parentID)
                else { return nil }
            } else if let parentID = usage.codexForkAccountingState?.metadata.forkedFromId
                ?? (missingParent ? usage.forkedFromId : nil),
                try usage.forkBaselineDependencyKey != self.currentDependencyKey(for: parentID)
            {
                return nil
            }

            let indexedBytes = usage.codexTokenIndexAnchor?.indexedBytes ?? usage.parsedBytes ?? usage.size
            let coversCurrentFile = usage.codexScanComplete != false
                && indexedBytes >= metadata.size
            return SnapshotResolution(
                dependencyKey: self.dependencyKey(for: sessionId, fileURL: fileURL),
                indexedEvents: missingParent ? nil : cachedSnapshots,
                checkpoints: usage.codexTokenCheckpoints ?? [],
                indexedTimestampsMonotonic: usage.codexTokenTimestampsMonotonic == true,
                isComplete: coversCurrentFile && !usage.hasBufferedCodexForkRetryLines,
                baselineResolved: !usage.hasBufferedCodexForkRetryLines,
                isFork: usage.forkedFromId != nil,
                requiresInheritedOrigin: requiresInheritedOrigin,
                forkOrigin: usage.codexForkAccountingState,
                forkOriginDependencyKey: requiresInheritedOrigin || (coversCurrentFile && missingParent)
                    ? usage.forkBaselineDependencyKey : nil)
        }
    }

    struct ClaudeParseResult {
        let rows: [ClaudeUsageRow]
        let parsedBytes: Int64

        /// The raw parser exposes rows; keep the packed view available to callers that
        /// validate the legacy day/model projection independently of report caching.
        var days: [String: [String: [Int]]] {
            var days: [String: [String: [Int]]] = [:]
            var overflowed: Set<String> = []
            for row in self.rows {
                let key = "\(row.dayKey)\u{0}\(row.model)"
                guard !overflowed.contains(key) else { continue }
                if row.isIncomplete == true {
                    days[row.dayKey, default: [:]][row.model] =
                        days[row.dayKey]?[row.model] ?? Array(repeating: 0, count: 8)
                    continue
                }
                let delta = [
                    row.input,
                    row.cacheRead,
                    row.cacheCreate,
                    row.output,
                    row.costNanos,
                    1,
                    (row.costPriced ?? (row.costNanos > 0)) ? 1 : 0,
                    row.cacheCreate1h ?? 0,
                ]
                let previous = days[row.dayKey]?[row.model] ?? Array(repeating: 0, count: delta.count)
                let summed = zip(previous, delta).compactMap { current, incoming -> Int? in
                    let result = current.addingReportingOverflow(incoming)
                    return result.overflow ? nil : result.partialValue
                }
                if summed.count != previous.count {
                    overflowed.insert(key)
                    days[row.dayKey]?.removeValue(forKey: row.model)
                } else {
                    days[row.dayKey, default: [:]][row.model] = summed
                }
            }
            return days
        }
    }

    enum ClaudePathRole: String, Codable, Equatable {
        case parent
        case subagent
    }

    struct ClaudeUsageRow: Codable, Equatable {
        let dayKey: String
        let model: String
        let sessionId: String?
        let messageId: String?
        let requestId: String?
        let timestampUnixMs: Int64?
        let isSidechain: Bool
        let pathRole: ClaudePathRole
        let input: Int
        let cacheRead: Int
        let cacheCreate: Int
        let cacheCreate1h: Int?
        let output: Int
        let costNanos: Int
        let costPriced: Bool?
        var isIncomplete: Bool?
    }

    static func loadDailyReport(
        provider: UsageProvider,
        since: Date,
        until: Date,
        now: Date = Date(),
        options: Options = Options()) -> CostUsageDailyReport
    {
        (
            try? self.loadDailyReportCancellable(
                provider: provider,
                since: since,
                until: until,
                now: now,
                options: options,
                checkCancellation: nil)) ?? CostUsageDailyReport(data: [], summary: nil)
    }

    static func loadDailyReportCancellable(
        provider: UsageProvider,
        since: Date,
        until: Date,
        now: Date = Date(),
        options: Options = Options(),
        checkCancellation: CancellationCheck?) throws -> CostUsageDailyReport
    {
        let range = CostUsageDayRange(since: since, until: until, calendar: options.calendar)
        let emptyReport = CostUsageDailyReport(data: [], summary: nil)
        try checkCancellation?()

        // Provider-specific by design: Codex JSONL and Claude/Vertex transcripts have distinct parsers and caches.
        switch provider {
        case .codex:
            return try self.loadCodexDaily(
                range: range,
                now: now,
                options: options,
                checkCancellation: checkCancellation)
        case .claude:
            return try self.loadClaudeDaily(
                provider: .claude,
                range: range,
                now: now,
                options: options,
                checkCancellation: checkCancellation)
        case .vertexai:
            var filtered = options
            if filtered.claudeLogProviderFilter == .all {
                filtered.claudeLogProviderFilter = .vertexAIOnly
            }
            return try self.loadClaudeDaily(
                provider: .vertexai,
                range: range,
                now: now,
                options: filtered,
                checkCancellation: checkCancellation)
        default:
            return emptyReport
        }
    }

    // MARK: - Day keys

    struct CostUsageDayRange {
        let sinceKey: String
        let untilKey: String
        private(set) var scanSinceKey: String
        let scanUntilKey: String
        let calendar: Calendar

        init(since: Date, until: Date, calendar: Calendar = .current) {
            let calendar = Self.localGregorianCalendar(matching: calendar)
            self.calendar = calendar
            self.sinceKey = Self.dayKey(from: since, calendar: calendar)
            self.untilKey = Self.dayKey(from: until, calendar: calendar)
            let scanSince = calendar.date(byAdding: .day, value: -1, to: since) ?? since
            let scanUntil = calendar.date(byAdding: .day, value: 1, to: until) ?? until
            self.scanSinceKey = Self.dayKey(from: scanSince, calendar: calendar)
            self.scanUntilKey = Self.dayKey(from: scanUntil, calendar: calendar)
        }

        init(coveringDayKeys keys: [String], calendar: Calendar) {
            self.calendar = Self.localGregorianCalendar(matching: calendar)
            self.sinceKey = keys.min() ?? "0000-01-01"
            self.untilKey = keys.max() ?? "9999-12-31"
            self.scanSinceKey = self.sinceKey
            self.scanUntilKey = self.untilKey
        }

        func retainingScanStart(_ scanSinceKey: String) -> Self {
            var retained = self
            retained.scanSinceKey = min(self.scanSinceKey, scanSinceKey)
            return retained
        }

        static func localGregorianCalendar(matching calendar: Calendar = .current) -> Calendar {
            CostUsageLocalDay.gregorianCalendar(matching: calendar)
        }

        static func dayKey(from date: Date, calendar: Calendar = .current) -> String {
            CostUsageLocalDay.key(from: date, calendar: calendar)
        }

        static func isInRange(dayKey: String, since: String, until: String) -> Bool {
            if dayKey < since {
                return false
            }
            if dayKey > until {
                return false
            }
            return true
        }
    }

    // MARK: - Codex

    private static func defaultCodexSessionsRoot(options: Options) -> URL {
        // Provider-specific by design: Codex session discovery honors CODEX_HOME before ~/.codex.
        if let override = options.codexSessionsRoot {
            return override
        }
        let env = ProcessInfo.processInfo.environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    static func codexSessionsRoots(options: Options) -> [URL] {
        let root = self.defaultCodexSessionsRoot(options: options)
        var candidates = [root]
        if let archived = self.codexArchivedSessionsRoot(sessionsRoot: root) {
            candidates.append(archived)
        }
        return candidates.filter(Self.codexSessionRootExistsOrIsUnavailable)
    }

    private static func codexSessionRootExistsOrIsUnavailable(_ root: URL) -> Bool {
        let descriptor = open(root.path, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else { return errno != ENOENT }
        close(descriptor)
        return true
    }

    private static func codexArchivedSessionsRoot(sessionsRoot: URL) -> URL? {
        guard sessionsRoot.lastPathComponent == "sessions" else { return nil }
        return sessionsRoot
            .deletingLastPathComponent()
            .appendingPathComponent("archived_sessions", isDirectory: true)
    }

    static func listCodexSessionFiles(
        root: URL,
        scanSinceKey: String,
        scanUntilKey: String,
        includeRecursive: Bool,
        calendar: Calendar = .current,
        workRecorder: CodexScanWorkRecorder? = nil) -> [URL]
    {
        workRecorder?.recordCodexListingRootStandardization()
        let root = root.standardizedFileURL
        let partitioned = self.listCodexSessionFilesByDatePartition(
            root: root,
            scanSinceKey: scanSinceKey,
            scanUntilKey: scanUntilKey,
            calendar: calendar).files
        let flat = self.listCodexSessionFilesFlat(root: root, scanSinceKey: scanSinceKey, scanUntilKey: scanUntilKey)
        let recursive = includeRecursive ? self.listCodexLegacySessionFilesRecursive(root: root) : []
        var seen: Set<String> = []
        return (partitioned + flat + recursive).filter {
            seen.insert(Self.codexPathKey(standardizedPath: $0.path)).inserted
        }
    }

    /// Proves that the compact persisted aggregates for one local day reflect every
    /// Codex session file at the same metadata inventory snapshot. Historical parsing
    /// may still be pending; only files that can affect `dayKey` must be fully parsed.
    static func codexCurrentDayProjectionCanPublish(
        cache: CostUsageCache,
        roots: [URL],
        dayKey: String,
        calendar: Calendar) -> Bool
    {
        self.codexCurrentDayProjectionGateReason(
            cache: cache,
            roots: roots,
            dayKey: dayKey,
            calendar: calendar) == nil
    }

    /// Returns a small reason code rather than exposing paths or session identifiers to
    /// diagnostics. `nil` means the same inventory, file-metadata, and parser checks used by
    /// publication all pass.
    static func codexCurrentDayProjectionGateReason(
        cache: CostUsageCache,
        roots: [URL],
        dayKey: String,
        calendar: Calendar) -> CodexDayEvidenceGateReason?
    {
        guard let dayStart = self.parseDayKey(dayKey, calendar: calendar),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
        else { return .scope }
        guard !Self.codexHistoryRangeHasUnsettledMissingParentFork(
            cache: cache,
            range: CostUsageDayRange(since: dayStart, until: dayStart, calendar: calendar))
        else { return .fork }

        let dayStartMs = Int64(dayStart.timeIntervalSince1970 * 1000)
        let dayEndMs = Int64(dayEnd.timeIntervalSince1970 * 1000)
        let scanSinceKey = CostUsageDayRange.dayKey(
            from: calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart,
            calendar: calendar)
        let scanUntilKey = CostUsageDayRange.dayKey(from: dayEnd, calendar: calendar)
        let rootPaths = roots.map(\.standardizedFileURL.path).sorted()
        guard let discovery = cache.codexSessionDiscovery else { return .inventory }
        guard discovery.roots == rootPaths,
              cache.roots == Self.codexRootsFingerprint(roots),
              cache.timeZoneIdentifier == nil
              || cache.timeZoneIdentifier == calendar.timeZone.identifier
        else { return .scope }

        guard Self.codexDirectoryInventoryIsCurrent(discovery) else { return .inventory }

        let directlyDiscovered = roots.flatMap {
            self.listCodexSessionFiles(
                root: $0,
                scanSinceKey: scanSinceKey,
                scanUntilKey: scanUntilKey,
                includeRecursive: false,
                calendar: calendar)
        }

        func cachedEntry(for fileURL: URL) -> CostUsageFileUsage? {
            cache.files[Self.codexResolvedPath(fileURL)]
                ?? cache.files[Self.codexPathKey(fileURL)]
                ?? cache.files[fileURL.standardizedFileURL.path]
        }

        func metadataCanAffectDay(_ fileURL: URL) -> Bool {
            let metadata = Self.codexFileMetadata(fileURL: fileURL)
            let filenameDayKey = Self.codexDayKeyFromPath(fileURL)
            return metadata.mtimeUnixMs >= dayStartMs
                && (metadata.mtimeUnixMs < dayEndMs || filenameDayKey.map { $0 < dayKey } == true)
        }

        func usageTouchesDay(_ usage: CostUsageFileUsage?, fileURL: URL) -> Bool {
            guard let usage else { return false }
            let hasUsageDay = usage.days.keys.contains {
                CostUsageDayRange.isInRange(dayKey: $0, since: dayKey, until: dayKey)
            }
            guard !hasUsageDay else { return true }
            // A newer partition can have a current mtime without affecting this closed day.
            // Keep the broader incomplete-fork fallback only when the path is not newer.
            if let pathDayKey = Self.codexDayKeyFromPath(fileURL), pathDayKey > dayKey {
                return false
            }
            return usage.touchesCodexScanWindow(
                sinceKey: dayKey,
                untilKey: dayKey,
                calendar: calendar)
        }

        func fileCanAffectDay(_ fileURL: URL, cached: CostUsageFileUsage?) -> Bool {
            usageTouchesDay(cached, fileURL: fileURL)
                || Self.codexDayKeyFromPath(fileURL) == dayKey
                || metadataCanAffectDay(fileURL)
        }

        let directlyDiscoveredPathKeys = Set(directlyDiscovered.compactMap { fileURL in
            fileCanAffectDay(fileURL, cached: cachedEntry(for: fileURL))
                ? Self.codexPathKey(fileURL) : nil
        })

        func matchesPersistedSnapshot(fileURL: URL, usage: CostUsageFileUsage) -> Bool {
            let metadata = Self.codexFileMetadata(fileURL: fileURL)
            guard usage.hasCurrentCodexParser,
                  usage.codexScanComplete == true,
                  !usage.hasPendingCodexScanWork,
                  usage.codexScanFileId == metadata.fileId,
                  (usage.parsedBytes ?? usage.size) >= usage.size
            else {
                return false
            }

            if usage.mtimeUnixMs == metadata.mtimeUnixMs,
               usage.size == metadata.size
            {
                return true
            }

            // Active Codex JSONL files normally grow between the scanner's commit and
            // the next publication read. The indexed prefix is still a valid, merely
            // slightly stale snapshot when its identity and trailing integrity anchor
            // remain unchanged. Rewrites, truncations, and legacy rows without an
            // anchor continue to fail closed.
            guard usage.size < metadata.size,
                  usage.mtimeUnixMs <= metadata.mtimeUnixMs,
                  usage.codexTokenIndexAnchor?.indexedBytes == usage.size
            else { return false }
            return usage.codexTokenIndexAnchor.map {
                Self.codexTokenIndexAnchorMatches(
                    $0,
                    fileURL: fileURL,
                    metadata: metadata)
            } == true
        }

        for fileURL in directlyDiscovered {
            let cached = cachedEntry(for: fileURL)
            guard fileCanAffectDay(fileURL, cached: cached) else { continue }
            guard let cached else { return .unindexed }
            guard matchesPersistedSnapshot(fileURL: fileURL, usage: cached) else {
                return Self.codexDayEvidenceMismatchReason(fileURL: fileURL, usage: cached)
            }
        }

        // Stream the persisted inventory rather than normalizing it into another dictionary
        // or Set. This preserves live fail-closed proof for an old-partition append while
        // keeping transient memory independent of the total session count.
        for path in discovery.filePaths {
            let fileURL = URL(fileURLWithPath: path)
            let cached = cachedEntry(for: fileURL)
            if fileCanAffectDay(fileURL, cached: cached),
               !(cached.map { matchesPersistedSnapshot(fileURL: fileURL, usage: $0) } ?? false)
            {
                guard let cached else { return .unindexed }
                return Self.codexDayEvidenceMismatchReason(fileURL: fileURL, usage: cached)
            }
        }

        for (path, usage) in cache.files {
            let fileURL = URL(fileURLWithPath: path)
            let canAffectDay = fileCanAffectDay(fileURL, cached: usage)
                || Self.codexSessionActivityTouchesDay(
                    usage,
                    dayStartMs: dayStartMs,
                    dayEndMs: dayEndMs)
                || directlyDiscoveredPathKeys.contains(Self.codexPathKey(fileURL))
            guard canAffectDay else { continue }
            guard matchesPersistedSnapshot(fileURL: fileURL, usage: usage) else {
                return Self.codexDayEvidenceMismatchReason(fileURL: fileURL, usage: usage)
            }
        }

        if let pendingFilePaths = cache.codexActiveLookbackState?.pendingFilePaths {
            for pendingPath in pendingFilePaths {
                let fileURL = URL(fileURLWithPath: pendingPath)
                let cached = cachedEntry(for: fileURL)
                if fileCanAffectDay(fileURL, cached: cached) {
                    guard let cached else { return .unindexed }
                    guard matchesPersistedSnapshot(fileURL: fileURL, usage: cached) else {
                        return Self.codexDayEvidenceMismatchReason(fileURL: fileURL, usage: cached)
                    }
                }
            }
        }
        return nil
    }

    private static func codexDayEvidenceMismatchReason(
        fileURL: URL,
        usage: CostUsageFileUsage) -> CodexDayEvidenceGateReason
    {
        if usage.hasPendingCodexForkRetry || usage.hasBufferedCodexForkRetryLines {
            return .fork
        }
        guard usage.hasCurrentCodexParser,
              usage.codexScanComplete == true,
              (usage.parsedBytes ?? usage.size) >= usage.size
        else { return .unindexed }
        let metadata = Self.codexFileMetadata(fileURL: fileURL)
        guard usage.codexScanFileId == metadata.fileId else { return .stale }
        return .stale
    }

    private static func codexSessionActivityTouchesDay(
        _ usage: CostUsageFileUsage,
        dayStartMs: Int64,
        dayEndMs: Int64) -> Bool
    {
        let timestamps = [
            usage.codexSession?.startedAtUnixMs,
            usage.codexSession?.latestActivityUnixMs,
            usage.codexSession?.latestAcceptedUsageUnixMs,
        ].compactMap(\.self)
        return timestamps.contains { $0 >= dayStartMs && $0 < dayEndMs }
    }

    private static func codexDirectoryInventoryIsCurrent(
        _ discovery: CostUsageCodexSessionDiscovery) -> Bool
    {
        let hasCompleteDirectoryInventory = discovery.nextDirectoryIndex == discovery.directoryPaths.count
            && !discovery.roots.isEmpty
            && discovery.roots.allSatisfy { discovery.directoryPaths.contains($0) }
            && discovery.directoryPaths.count == discovery.directoryStamps.count
            && discovery.directoryPaths.allSatisfy { discovery.directoryStamps[$0] != nil }
        guard hasCompleteDirectoryInventory else { return false }

        return discovery.directoryPaths.allSatisfy { path in
            let directoryURL = URL(fileURLWithPath: path, isDirectory: true)
            let metadata = Self.codexFileMetadata(fileURL: directoryURL)
            guard let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]),
                let stamp = discovery.directoryStamps[path]
            else { return false }
            var jsonlFileCount = 0
            for case let item as URL in enumerator where item.pathExtension.lowercased() == "jsonl" {
                jsonlFileCount += 1
            }
            return metadata.mtimeUnixMs == stamp.mtimeUnixMs
                && jsonlFileCount == stamp.jsonlFileCount
        }
    }

    /// Proves that one requested report window is safe to publish while a separate, wider
    /// cache migration remains pending. This deliberately relies on the requested date
    /// partitions and the persisted file snapshots, not on completion of the unrelated global
    /// metadata sweep.
    static func codexRequestedWindowProjectionCanPublish(
        cache: CostUsageCache,
        roots: [URL],
        sinceKey: String,
        untilKey: String,
        calendar: Calendar) -> Bool
    {
        guard let since = self.parseDayKey(sinceKey, calendar: calendar),
              let until = self.parseDayKey(untilKey, calendar: calendar),
              since <= until
        else { return false }
        let range = CostUsageDayRange(since: since, until: until, calendar: calendar)
        guard !Self.codexHistoryRangeHasUnsettledMissingParentFork(cache: cache, range: range)
        else { return false }
        let rootPaths = roots.map(\.standardizedFileURL.path).sorted()
        if let lookback = cache.codexActiveLookbackState {
            guard lookback.scanSinceKey == range.scanSinceKey,
                  Set(lookback.completedCurrentWindowRootPaths ?? []) == Set(rootPaths),
                  Set(lookback.completedCurrentWindowFlatRootPaths ?? []) == Set(rootPaths)
            else { return false }
        } else if cache.codexScanCatchUpPending == true {
            // A pending state without the current-window cursors cannot prove that no new
            // requested-window file exists outside the persisted manifest.
            return false
        }
        guard cache.roots == Self.codexRootsFingerprint(roots) else { return false }

        guard cache.codexActiveLookbackState?.pendingFilePaths.contains(where: {
            Self.codexPendingPathCanAffectRequestedWindow(
                $0,
                cache: cache,
                sinceKey: range.scanSinceKey,
                untilKey: range.scanUntilKey,
                calendar: range.calendar)
        }) != true else { return false }

        let windowStartMs = Int64(since.timeIntervalSince1970 * 1000)
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: until) ?? until
        let windowEndMs = Int64(windowEnd.timeIntervalSince1970 * 1000)
        let directlyDiscovered = roots.flatMap {
            self.listCodexSessionFiles(
                root: $0,
                scanSinceKey: range.scanSinceKey,
                scanUntilKey: range.scanUntilKey,
                includeRecursive: false,
                calendar: calendar)
        }
        let directlyDiscoveredPathKeys = Set(directlyDiscovered.map(Self.codexPathKey))

        func cachedEntry(for fileURL: URL) -> CostUsageFileUsage? {
            cache.files[Self.codexResolvedPath(fileURL)]
                ?? cache.files[Self.codexPathKey(fileURL)]
                ?? cache.files[fileURL.standardizedFileURL.path]
        }

        func matchesPersistedSnapshot(fileURL: URL, usage: CostUsageFileUsage) -> Bool {
            let metadata = Self.codexFileMetadata(fileURL: fileURL)
            guard usage.hasCurrentCodexParser,
                  usage.codexScanComplete == true,
                  !usage.hasPendingCodexForkRetry,
                  usage.codexScanFileId == metadata.fileId,
                  (usage.parsedBytes ?? usage.size) >= usage.size
            else { return false }
            guard usage.mtimeUnixMs <= metadata.mtimeUnixMs else { return false }
            if usage.mtimeUnixMs == metadata.mtimeUnixMs,
               usage.size == metadata.size
            {
                return true
            }
            guard usage.size < metadata.size,
                  usage.codexTokenIndexAnchor?.indexedBytes == usage.size
            else { return false }
            return usage.codexTokenIndexAnchor.map {
                Self.codexTokenIndexAnchorMatches(
                    $0,
                    fileURL: fileURL,
                    metadata: metadata)
            } == true
        }

        // Every file in the requested date partitions must have a complete persisted snapshot.
        // An absent row is not safe to treat as zero: it may be a newly-created session that the
        // bounded manifest has not yet committed.
        for fileURL in directlyDiscovered {
            guard let cached = cachedEntry(for: fileURL),
                  matchesPersistedSnapshot(fileURL: fileURL, usage: cached)
            else { return false }
        }

        for (path, usage) in cache.files {
            let fileURL = URL(fileURLWithPath: path)
            guard Self.isWithinCodexRoots(fileURL: fileURL, roots: roots) else { continue }
            let sessionTimestamps = [
                usage.codexSession?.startedAtUnixMs,
                usage.codexSession?.latestActivityUnixMs,
                usage.codexSession?.latestAcceptedUsageUnixMs,
            ].compactMap(\.self)
            let canAffectWindow = usage.touchesCodexScanWindow(
                sinceKey: range.scanSinceKey,
                untilKey: range.scanUntilKey,
                calendar: calendar)
                || sessionTimestamps.contains { $0 >= windowStartMs && $0 < windowEndMs }
                || usage.mtimeUnixMs >= windowStartMs
                || directlyDiscoveredPathKeys.contains(Self.codexPathKey(fileURL))
            guard !canAffectWindow || matchesPersistedSnapshot(fileURL: fileURL, usage: usage)
            else { return false }
        }

        // Old migration paths are intentionally ignored unless their persisted usage or current
        // metadata says they can contribute to the requested window.
        for pendingPath in cache.codexActiveLookbackState?.pendingFilePaths ?? [] {
            let fileURL = URL(fileURLWithPath: pendingPath)
            let metadata = Self.codexFileMetadata(fileURL: fileURL)
            guard let cached = cachedEntry(for: fileURL) else { return false }
            let pendingCanAffectWindow = cached.touchesCodexScanWindow(
                sinceKey: range.scanSinceKey,
                untilKey: range.scanUntilKey,
                calendar: calendar)
                || metadata.mtimeUnixMs >= windowStartMs
            if pendingCanAffectWindow {
                guard matchesPersistedSnapshot(fileURL: fileURL, usage: cached) else { return false }
            }
        }
        return true
    }

    private static func cachedCodexSessionFiles(
        cache: CostUsageCache,
        range: CostUsageDayRange,
        roots: [URL],
        excludingPaths: Set<String>) -> [URL]
    {
        cache.files.compactMap { path, usage in
            guard !excludingPaths.contains(path),
                  !excludingPaths.contains(Self.codexPathKey(URL(fileURLWithPath: path, isDirectory: false)))
            else { return nil }
            let hasRelevantDay = usage.days.keys.contains {
                CostUsageDayRange.isInRange(dayKey: $0, since: range.scanSinceKey, until: range.scanUntilKey)
            }
            guard hasRelevantDay || usage.hasBufferedCodexForkRetryLines || usage.hasPendingCodexScanWork
            else { return nil }
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let fileURL = URL(fileURLWithPath: path, isDirectory: false)
            guard Self.isWithinCodexRoots(fileURL: fileURL, roots: roots) else { return nil }
            return fileURL
        }
    }

    private static func cachedCodexSessionIndex(
        cache: CostUsageCache,
        roots: [URL],
        knownExistingPaths: Set<String>) -> [String: URL]
    {
        var out: [String: URL] = [:]
        for (path, usage) in cache.files {
            guard let sessionId = usage.sessionId, !sessionId.isEmpty else { continue }
            if knownExistingPaths.contains(Self.codexPathKey(URL(fileURLWithPath: path, isDirectory: false))) {
                out[sessionId] = URL(fileURLWithPath: path, isDirectory: false)
                continue
            }
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let fileURL = URL(fileURLWithPath: path, isDirectory: false)
            guard Self.isWithinCodexRoots(fileURL: fileURL, roots: roots) else { continue }
            out[sessionId] = fileURL
        }
        return out
    }

    private static func codexRootsFingerprint(_ roots: [URL]) -> [String: Int64] {
        var out: [String: Int64] = [:]
        for root in roots {
            out[root.standardizedFileURL.path] = 0
        }
        return out
    }

    /// Stable, non-identifying scope for source proof. Raw session-root paths never leave the
    /// local store; length-prefixing keeps unusual path characters from aliasing the digest
    /// input. Proof is scoped to the calendar that defines local day boundaries.
    static func codexDayEvidenceScopeID(rootPaths: [String], calendar: Calendar) -> String {
        let roots = Set(rootPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }).sorted()
        let components = [
            "source=codexLocalLedger",
            "calendar=gregorian",
            "timezone=\(calendar.timeZone.identifier)",
        ] + roots.map { "root=\($0)" }
        let material = components.map { "\($0.utf8.count):\($0)" }.joined()
        return "sha256:\(Self.sha256Hex(Data(material.utf8)))"
    }

    static func codexRootsFingerprint(options: Options) -> [String: Int64] {
        self.codexRootsFingerprint(self.codexSessionsRoots(options: options))
    }

    /// Bump when the report pricing formula changes. Rates are resolved when reports are read;
    /// this fingerprint only invalidates downstream presentation caches such as Workspaces snapshots.
    private static let codexCostFormulaVersion = 4

    static func codexPricingKey(modelsDevArtifact: ModelsDevCacheArtifact?) -> String {
        CostUsagePricingKey.codex(
            modelsDevArtifact: modelsDevArtifact,
            formulaVersion: self.codexCostFormulaVersion)
    }

    private static func codexPriorityMetadataKey(databaseURL: URL?) -> String {
        let url = self.resolvedCodexPriorityDatabaseURL(databaseURL)
        let path = url.standardizedFileURL.path
        return FileManager.default.fileExists(atPath: path) ? "sqlite:\(path)" : "missing:\(path)"
    }

    private static func codexPriorityMetadataChanged(old: String?, new: String) -> Bool {
        guard let old, old != new else { return false }
        return new.hasPrefix("sqlite:")
    }

    private static func codexPriorityTurnKeys(
        _ priorityTurns: [String: CodexPriorityTurnMetadata],
        calendar: Calendar) -> [String: String]
    {
        var partsByDay: [String: [String]] = [:]
        for (turnID, turn) in priorityTurns {
            guard let dayKey = self.codexPriorityDayKey(turn, calendar: calendar) else { continue }
            partsByDay[dayKey, default: []].append([
                turnID,
                turn.model ?? "",
                turn.timestamp ?? "",
                turn.threadID ?? "",
            ].joined(separator: "|"))
        }
        var out: [String: String] = [:]
        for (dayKey, parts) in partsByDay {
            out[dayKey] = self.sha256Hex(Data(parts.sorted().joined(separator: "\n").utf8))
        }
        return out
    }

    private static func codexPriorityTurnIDsByDay(
        _ priorityTurns: [String: CodexPriorityTurnMetadata],
        calendar: Calendar) -> [String: [String]]
    {
        var out: [String: Set<String>] = [:]
        for (turnID, turn) in priorityTurns {
            guard let dayKey = self.codexPriorityDayKey(turn, calendar: calendar) else { continue }
            out[dayKey, default: []].insert(turnID)
        }
        return out.mapValues { $0.sorted() }
    }

    private static func codexPriorityDayKey(
        _ turn: CodexPriorityTurnMetadata,
        calendar: Calendar) -> String?
    {
        guard let timestamp = turn.timestamp else { return nil }
        let dayKeyFromEpoch = Int64(timestamp).map {
            CostUsageDayRange.dayKey(
                from: Date(timeIntervalSince1970: TimeInterval($0)),
                calendar: calendar)
        }
        return dayKeyFromEpoch
            ?? self.dayKeyFromTimestamp(timestamp, calendar: calendar)
            ?? self.dayKeyFromParsedISO(timestamp, calendar: calendar)
    }

    static func codexPriorityTurnKeysChanged(
        old: [String: String]?,
        new: [String: String],
        range: CostUsageDayRange,
        workRecorder: CodexScanWorkRecorder? = nil) -> Bool
    {
        let candidateDays = Set((old ?? [:]).keys).union(new.keys)
        for dayKey in candidateDays {
            workRecorder?.recordCodexPriorityMetadataDayVisit()
            guard CostUsageDayRange.isInRange(
                dayKey: dayKey,
                since: range.scanSinceKey,
                until: range.scanUntilKey)
            else { continue }
            if old?[dayKey] != new[dayKey] { return true }
        }
        return false
    }

    static func changedPriorityTurnIDs(
        old: [String: [String]]?,
        new: [String: [String]],
        oldKeys: [String: String]?,
        newKeys: [String: String],
        range: CostUsageDayRange,
        workRecorder: CodexScanWorkRecorder? = nil) -> Set<String>
    {
        var out = Set<String>()
        let candidateDays = Set((old ?? [:]).keys)
            .union(new.keys)
            .union((oldKeys ?? [:]).keys)
            .union(newKeys.keys)
        for dayKey in candidateDays {
            workRecorder?.recordCodexPriorityMetadataDayVisit()
            guard CostUsageDayRange.isInRange(
                dayKey: dayKey,
                since: range.scanSinceKey,
                until: range.scanUntilKey)
            else { continue }
            let oldIDs = Set(old?[dayKey] ?? [])
            let newIDs = Set(new[dayKey] ?? [])
            if oldIDs != newIDs || oldKeys?[dayKey] != newKeys[dayKey] {
                out.formUnion(oldIDs)
                out.formUnion(newIDs)
            }
        }
        return out
    }

    /// Priority metadata is sparse; walking empty calendar days makes long-range history work grow with time.
    static func mergePriorityDayValues<Value>(
        existing: [String: Value]?,
        new: [String: Value],
        range: CostUsageDayRange,
        retainedSinceKey: String,
        retainedUntilKey: String,
        workRecorder: CodexScanWorkRecorder? = nil) -> [String: Value]?
    {
        var out = existing ?? [:]
        let candidateDays = Set(out.keys).union(new.keys)
        for dayKey in candidateDays {
            workRecorder?.recordCodexPriorityMetadataDayVisit()
            guard CostUsageDayRange.isInRange(
                dayKey: dayKey,
                since: range.scanSinceKey,
                until: range.scanUntilKey)
            else { continue }
            out[dayKey] = new[dayKey]
        }
        out = out.filter { key, _ in
            CostUsageDayRange.isInRange(dayKey: key, since: retainedSinceKey, until: retainedUntilKey)
        }
        return out.isEmpty ? nil : out
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func codexTokenIndexAnchor(
        fileURL: URL,
        indexedBytes: Int64) -> CostUsageCodexTokenIndexAnchor?
    {
        let indexedBytes = max(0, indexedBytes)
        guard indexedBytes > 0 else { return nil }
        let windowStart = max(0, indexedBytes - 64 * 1024)
        let byteCount = Int(indexedBytes - windowStart)
        guard byteCount > 0 else { return nil }

        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(windowStart))
            guard let data = try handle.read(upToCount: byteCount), data.count == byteCount else {
                return nil
            }
            return CostUsageCodexTokenIndexAnchor(
                indexedBytes: indexedBytes,
                windowStart: windowStart,
                sha256: Self.sha256Hex(data))
        } catch {
            return nil
        }
    }

    static func codexTokenIndexAnchorMatches(
        _ anchor: CostUsageCodexTokenIndexAnchor,
        fileURL: URL,
        metadata: CodexFileMetadata) -> Bool
    {
        guard anchor.indexedBytes > 0,
              anchor.windowStart >= 0,
              anchor.windowStart < anchor.indexedBytes,
              metadata.size >= anchor.indexedBytes
        else { return false }
        return self.codexTokenIndexAnchor(
            fileURL: fileURL,
            indexedBytes: anchor.indexedBytes) == anchor
    }

    private static func listCodexRecentlyModifiedPartitionFiles(
        root: URL,
        scanSinceKey: String,
        modifiedSince: Date,
        scanBudget: CodexScanBudget,
        resumeDayKey: String?,
        calendar: Calendar = .current) -> CodexDatePartitionListing
    {
        let lookbackSinceKey = self.dayKey(
            scanSinceKey,
            addingDays: -self.codexActiveSessionLookbackDays,
            calendar: calendar)
            ?? scanSinceKey
        let lookbackUntilKey = self.dayKey(scanSinceKey, addingDays: -1, calendar: calendar)
            ?? lookbackSinceKey
        let partitioned = self.listCodexSessionFilesByDatePartition(
            root: root,
            scanSinceKey: lookbackSinceKey,
            scanUntilKey: lookbackUntilKey,
            calendar: calendar,
            scanBudget: scanBudget,
            resumeDayKey: resumeDayKey)
        return CodexDatePartitionListing(
            files: self.filterRecentlyModified(files: partitioned.files, modifiedSince: modifiedSince),
            isComplete: partitioned.isComplete,
            nextDayKey: partitioned.nextDayKey)
    }

    private static func filterRecentlyModified(files: [URL], modifiedSince: Date) -> [URL] {
        files.filter { fileURL in
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { return false }
            guard let modifiedAt = values?.contentModificationDate else { return false }
            return modifiedAt >= modifiedSince
        }
    }

    private static func isDatePartitionComponent(_ value: String, length: Int) -> Bool {
        value.count == length && value.allSatisfy(\.isNumber)
    }

    private static func dayKey(
        _ dayKey: String,
        addingDays days: Int,
        calendar: Calendar = .current) -> String?
    {
        let calendar = CostUsageDayRange.localGregorianCalendar(matching: calendar)
        guard let date = self.parseDayKey(dayKey, calendar: calendar) else { return nil }
        guard let shifted = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return CostUsageDayRange.dayKey(from: shifted, calendar: calendar)
    }

    private static func localStartOfDay(_ dayKey: String, calendar: Calendar) -> Date? {
        let calendar = CostUsageDayRange.localGregorianCalendar(matching: calendar)
        return self.parseDayKey(dayKey, calendar: calendar).map { calendar.startOfDay(for: $0) }
    }

    private static func dayKeys(
        sinceKey: String,
        untilKey: String,
        calendar: Calendar = .current) -> [String]
    {
        let calendar = CostUsageDayRange.localGregorianCalendar(matching: calendar)
        guard let since = self.parseDayKey(sinceKey, calendar: calendar),
              self.parseDayKey(untilKey, calendar: calendar) != nil
        else { return sinceKey <= untilKey ? [sinceKey] : [] }

        var out: [String] = []
        var cursor = since
        while CostUsageDayRange.dayKey(from: cursor, calendar: calendar) <= untilKey {
            out.append(CostUsageDayRange.dayKey(from: cursor, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            if next <= cursor {
                break
            }
            cursor = next
        }
        return out
    }

    private static func listCodexRecentlyModifiedFilesRecursive(root: URL, modifiedSince: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }

        var out: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "jsonl" else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            guard let modifiedAt = values?.contentModificationDate, modifiedAt >= modifiedSince else { continue }
            out.append(fileURL)
        }
        return out
    }

    static func isWithinCodexRoots(fileURL: URL, roots: [URL]) -> Bool {
        let filePath = self.codexResolvedPath(fileURL)
        return roots.contains { root in
            let rootPath = self.codexResolvedPath(root)
            if filePath == rootPath {
                return true
            }
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            return filePath.hasPrefix(prefix)
        }
    }

    private static func codexResolvedPath(_ url: URL) -> String {
        self.codexPathKey(standardizedPath: url.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    static func codexPathKey(_ url: URL) -> String {
        self.codexPathKey(standardizedPath: url.standardizedFileURL.path)
    }

    static func codexPathKey(standardizedPath path: String) -> String {
        if path.hasPrefix("/private/var/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }

    private struct CodexDatePartitionListing {
        let files: [URL]
        let isComplete: Bool
        let nextDayKey: String?
    }

    private struct CodexDirectoryPage {
        let files: [URL]
        let nextOffset: Int64?
        let pendingNames: [String]
        let visits: Int
        let isUnavailable: Bool
    }

    private struct CodexPartitionPage {
        let files: [URL]
        let nextDayKey: String?
        let nextDirectoryOffset: Int64?
        let pendingNames: [String]
        let visits: Int
        let isUnavailable: Bool

        var isComplete: Bool {
            !self.isUnavailable && self.nextDayKey == nil && self.nextDirectoryOffset == nil
        }
    }

    #if os(macOS)
    private typealias CodexDirectoryHandle = Int32
    #elseif os(Linux)
    private typealias CodexDirectoryHandle = OpaquePointer
    #else
    private typealias CodexDirectoryHandle = UnsafeMutablePointer<DIR>
    #endif

    private final class CodexDirectoryCursor: @unchecked Sendable {
        let directory: CodexDirectoryHandle
        var position: Int64

        init(directory: CodexDirectoryHandle, position: Int64 = 0) {
            self.directory = directory
            self.position = position
        }

        deinit {
            #if os(macOS)
            close(self.directory)
            #else
            closedir(self.directory)
            #endif
        }
    }

    private final class CodexDirectoryCursorRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private var cursors: [String: CodexDirectoryCursor] = [:]
        private var unavailablePathsForTesting: Set<String> = []

        // swiftlint:disable:next function_parameter_count
        func page(
            directoryURL: URL,
            resumeOffset: Int64,
            visitLimit: Int,
            resumePendingNames: [String],
            missingIsUnavailable: Bool,
            filter: (String) -> Bool,
            shouldStop: (() -> Bool)?,
            workRecorder: CodexScanWorkRecorder?) -> CodexDirectoryPage
        {
            self.lock.lock()
            defer { self.lock.unlock() }

            let path = directoryURL.path
            let resumeOffset = max(0, resumeOffset)
            if self.unavailablePathsForTesting.contains(path) {
                self.cursors.removeValue(forKey: path)
                return CodexDirectoryPage(
                    files: [],
                    nextOffset: resumeOffset,
                    pendingNames: resumePendingNames,
                    visits: 0,
                    isUnavailable: true)
            }
            if resumeOffset == 0 || self.cursors[path]?.position != resumeOffset {
                self.cursors.removeValue(forKey: path)
            }
            if self.cursors[path] == nil {
                #if os(macOS)
                let directory = open(path, O_RDONLY | O_DIRECTORY)
                guard directory >= 0 else {
                    let unavailable = missingIsUnavailable || errno != ENOENT
                    return CodexDirectoryPage(
                        files: [],
                        nextOffset: unavailable ? resumeOffset : nil,
                        pendingNames: resumePendingNames,
                        visits: 0,
                        isUnavailable: unavailable)
                }
                if resumeOffset > 0, lseek(directory, off_t(resumeOffset), SEEK_SET) < 0 {
                    close(directory)
                    return CodexDirectoryPage(
                        files: [],
                        nextOffset: resumeOffset,
                        pendingNames: resumePendingNames,
                        visits: 0,
                        isUnavailable: true)
                }
                #else
                guard let directory = opendir(path) else {
                    let unavailable = missingIsUnavailable || errno != ENOENT
                    return CodexDirectoryPage(
                        files: [],
                        nextOffset: unavailable ? resumeOffset : nil,
                        pendingNames: resumePendingNames,
                        visits: 0,
                        isUnavailable: unavailable)
                }
                if resumeOffset > 0 {
                    seekdir(directory, Int(resumeOffset))
                }
                #endif
                self.cursors[path] = CodexDirectoryCursor(directory: directory, position: resumeOffset)
            }
            guard let cursor = self.cursors[path] else {
                return CodexDirectoryPage(
                    files: [],
                    nextOffset: resumeOffset,
                    pendingNames: resumePendingNames,
                    visits: 0,
                    isUnavailable: true)
            }

            var files: [URL] = []
            var visits = 0
            var pendingNames = resumePendingNames
            while visits < visitLimit {
                if shouldStop?() == true {
                    return CodexDirectoryPage(
                        files: files,
                        nextOffset: cursor.position,
                        pendingNames: pendingNames,
                        visits: visits,
                        isUnavailable: false)
                }
                #if os(macOS)
                if pendingNames.isEmpty {
                    do {
                        pendingNames = try Self.readDirectoryNames(descriptor: cursor.directory)
                        cursor.position = Int64(lseek(cursor.directory, 0, SEEK_CUR))
                    } catch {
                        self.cursors.removeValue(forKey: path)
                        return CodexDirectoryPage(
                            files: files,
                            nextOffset: cursor.position,
                            pendingNames: pendingNames,
                            visits: visits,
                            isUnavailable: true)
                    }
                    if pendingNames.isEmpty {
                        self.cursors.removeValue(forKey: path)
                        return CodexDirectoryPage(
                            files: files,
                            nextOffset: nil,
                            pendingNames: [],
                            visits: visits,
                            isUnavailable: false)
                    }
                }
                let name = pendingNames.removeFirst()
                #else
                guard let entry = readdir(cursor.directory) else {
                    self.cursors.removeValue(forKey: path)
                    return CodexDirectoryPage(
                        files: files,
                        nextOffset: nil,
                        pendingNames: [],
                        visits: visits,
                        isUnavailable: false)
                }
                workRecorder?.recordCodexDirectoryEntryRead()
                let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
                }
                cursor.position = Int64(telldir(cursor.directory))
                #endif
                guard name != ".", name != ".." else { continue }
                visits += 1
                workRecorder?.recordCodexDiscoveryVisit()
                guard filter(name) else { continue }
                files.append(directoryURL.appendingPathComponent(name, isDirectory: false))
            }
            return CodexDirectoryPage(
                files: files,
                nextOffset: cursor.position,
                pendingNames: pendingNames,
                visits: visits,
                isUnavailable: false)
        }

        #if os(macOS)
        private static func readDirectoryNames(descriptor: Int32) throws -> [String] {
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            var basePosition: Int64 = 0
            let byteCount = buffer.withUnsafeMutableBytes { rawBuffer in
                codexGetDirectoryEntries64(
                    descriptor,
                    rawBuffer.baseAddress!,
                    rawBuffer.count,
                    &basePosition)
            }
            guard byteCount >= 0 else { throw CocoaError(.fileReadUnknown) }
            guard byteCount > 0 else { return [] }
            return buffer.withUnsafeBytes { rawBuffer in
                var names: [String] = []
                var entryOffset = 0
                while entryOffset < byteCount, let baseAddress = rawBuffer.baseAddress {
                    let entry = baseAddress.advanced(by: entryOffset).assumingMemoryBound(to: dirent.self)
                    let entryLength = Int(entry.pointee.d_reclen)
                    guard entryLength > 0, entryOffset + entryLength <= byteCount else { break }
                    let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                        pointer.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
                    }
                    names.append(name)
                    entryOffset += entryLength
                }
                return names
            }
        }
        #endif

        func reset(under root: URL) {
            let roots = Set([root.standardizedFileURL.path, root.resolvingSymlinksInPath().standardizedFileURL.path])
            self.lock.lock()
            defer { self.lock.unlock() }
            for path in self.cursors.keys where roots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                self.cursors.removeValue(forKey: path)
            }
        }

        func setUnavailablePathsForTesting(_ paths: Set<String>) {
            self.lock.lock()
            self.unavailablePathsForTesting = paths
            self.cursors = self.cursors.filter { !paths.contains($0.key) }
            self.lock.unlock()
        }
    }

    private static let codexDirectoryCursorRegistry = CodexDirectoryCursorRegistry()

    private static func listCodexDirectoryPage(
        directoryURL: URL,
        resumeOffset: Int64,
        visitLimit: Int,
        resumePendingNames: [String] = [],
        missingIsUnavailable: Bool = true,
        filter: (String) -> Bool,
        shouldStop: (() -> Bool)? = nil,
        workRecorder: CodexScanWorkRecorder?) -> CodexDirectoryPage
    {
        guard visitLimit > 0 else {
            return CodexDirectoryPage(
                files: [],
                nextOffset: max(0, resumeOffset),
                pendingNames: resumePendingNames,
                visits: 0,
                isUnavailable: false)
        }
        return self.codexDirectoryCursorRegistry.page(
            directoryURL: directoryURL,
            resumeOffset: resumeOffset,
            visitLimit: visitLimit,
            resumePendingNames: resumePendingNames,
            missingIsUnavailable: missingIsUnavailable,
            filter: filter,
            shouldStop: shouldStop,
            workRecorder: workRecorder)
    }

    // swiftlint:disable:next function_parameter_count
    private static func listCodexSessionFilesByDatePartitionPage(
        root: URL,
        scanSinceKey: String,
        scanUntilKey: String,
        resumeDayKey: String?,
        resumeDirectoryOffset: Int64,
        resumePendingNames: [String] = [],
        visitLimit: Int,
        preferNewest: Bool,
        calendar: Calendar,
        shouldStop: (() -> Bool)? = nil,
        workRecorder: CodexScanWorkRecorder?) -> CodexPartitionPage
    {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return CodexPartitionPage(
                files: [],
                nextDayKey: nil,
                nextDirectoryOffset: nil,
                pendingNames: resumePendingNames,
                visits: 0,
                isUnavailable: false)
        }
        let calendar = CostUsageDayRange.localGregorianCalendar(matching: calendar)
        let sinceDate = Self.parseDayKey(scanSinceKey, calendar: calendar) ?? Date()
        let untilDate = Self.parseDayKey(scanUntilKey, calendar: calendar) ?? sinceDate
        let resumedDate = resumeDayKey.flatMap { Self.parseDayKey($0, calendar: calendar) }
        var date = if let resumedDate, resumedDate >= sinceDate, resumedDate <= untilDate {
            resumedDate
        } else {
            preferNewest ? untilDate : sinceDate
        }
        var directoryOffset = max(0, resumeDirectoryOffset)
        var pendingNames = resumePendingNames
        var remainingVisits = max(0, visitLimit)
        var totalVisits = 0
        var files: [URL] = []

        while date >= sinceDate, date <= untilDate {
            guard remainingVisits > 0 else {
                return CodexPartitionPage(
                    files: files,
                    nextDayKey: CostUsageDayRange.dayKey(from: date, calendar: calendar),
                    nextDirectoryOffset: directoryOffset,
                    pendingNames: pendingNames,
                    visits: totalVisits,
                    isUnavailable: false)
            }
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            let dayDirectory = root
                .appendingPathComponent(String(format: "%04d", comps.year ?? 1970), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", comps.month ?? 1), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", comps.day ?? 1), isDirectory: true)
            let page = Self.listCodexDirectoryPage(
                directoryURL: dayDirectory,
                resumeOffset: directoryOffset,
                visitLimit: remainingVisits,
                resumePendingNames: pendingNames,
                missingIsUnavailable: false,
                filter: { $0.lowercased().hasSuffix(".jsonl") },
                shouldStop: shouldStop,
                workRecorder: workRecorder)
            files.append(contentsOf: page.files)
            totalVisits += page.visits
            remainingVisits -= page.visits
            if page.isUnavailable {
                return CodexPartitionPage(
                    files: files,
                    nextDayKey: CostUsageDayRange.dayKey(from: date, calendar: calendar),
                    nextDirectoryOffset: directoryOffset,
                    pendingNames: page.pendingNames,
                    visits: totalVisits,
                    isUnavailable: true)
            }
            if let nextOffset = page.nextOffset {
                return CodexPartitionPage(
                    files: files,
                    nextDayKey: CostUsageDayRange.dayKey(from: date, calendar: calendar),
                    nextDirectoryOffset: nextOffset,
                    pendingNames: page.pendingNames,
                    visits: totalVisits,
                    isUnavailable: false)
            }
            directoryOffset = 0
            pendingNames = []
            guard let nextDate = calendar.date(byAdding: .day, value: preferNewest ? -1 : 1, to: date) else {
                break
            }
            date = nextDate
        }
        return CodexPartitionPage(
            files: files,
            nextDayKey: nil,
            nextDirectoryOffset: nil,
            pendingNames: [],
            visits: totalVisits,
            isUnavailable: false)
    }

    private static func listCodexSessionFilesByDatePartition(
        root: URL,
        scanSinceKey: String,
        scanUntilKey: String,
        calendar: Calendar = .current,
        scanBudget: CodexScanBudget? = nil,
        resumeDayKey: String? = nil) -> CodexDatePartitionListing
    {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return CodexDatePartitionListing(files: [], isComplete: true, nextDayKey: nil)
        }
        let calendar = CostUsageDayRange.localGregorianCalendar(matching: calendar)
        var out: [URL] = []
        let sinceDate = Self.parseDayKey(scanSinceKey, calendar: calendar) ?? Date()
        let untilDate = Self.parseDayKey(scanUntilKey, calendar: calendar) ?? sinceDate
        let resumedDate = resumeDayKey.flatMap { Self.parseDayKey($0, calendar: calendar) }
        var date = if let resumedDate, resumedDate >= sinceDate, resumedDate <= untilDate {
            resumedDate
        } else {
            sinceDate
        }

        while date <= untilDate {
            let admittedWork: Int64
            if let scanBudget {
                switch scanBudget.admit(workBytes: 1) {
                case let .allow(allowance): admittedWork = allowance
                case .deferBudget:
                    return CodexDatePartitionListing(
                        files: out,
                        isComplete: false,
                        nextDayKey: CostUsageDayRange.dayKey(from: date, calendar: calendar))
                }
            } else {
                admittedWork = 0
            }

            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            let y = String(format: "%04d", comps.year ?? 1970)
            let m = String(format: "%02d", comps.month ?? 1)
            let d = String(format: "%02d", comps.day ?? 1)

            let dayDir = root.appendingPathComponent(y, isDirectory: true)
                .appendingPathComponent(m, isDirectory: true)
                .appendingPathComponent(d, isDirectory: true)

            if let items = try? FileManager.default.contentsOfDirectory(
                at: dayDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
            {
                for item in items where item.pathExtension.lowercased() == "jsonl" {
                    out.append(item)
                }
            }
            scanBudget?.complete(admittedWorkBytes: admittedWork, actualWorkBytes: admittedWork)

            date = calendar.date(byAdding: .day, value: 1, to: date) ?? untilDate.addingTimeInterval(1)
        }

        return CodexDatePartitionListing(files: out, isComplete: true, nextDayKey: nil)
    }

    private static func codexActiveLookbackState(
        cache: CostUsageCache,
        roots: [URL],
        scanSinceKey: String,
        includeLegacyRecursiveScan: Bool) -> CostUsageCodexActiveLookbackState
    {
        let directoryCursorVersion = 3
        let rootPaths = roots.map(Self.codexResolvedPath).sorted()
        if let cached = cache.codexActiveLookbackState,
           cached.scanSinceKey == scanSinceKey,
           cached.rootPaths == rootPaths,
           cached.directoryCursorVersion == directoryCursorVersion
        {
            return cached
        }
        let retainedPendingFilePaths = cache.codexScanCatchUpPending == true
            ? cache.codexActiveLookbackState?.pendingFilePaths ?? []
            : []
        return CostUsageCodexActiveLookbackState(
            scanSinceKey: scanSinceKey,
            rootPaths: rootPaths,
            pendingFilePaths: retainedPendingFilePaths,
            legacyRecursivePendingRootPaths: includeLegacyRecursiveScan ? rootPaths : [],
            directoryCursorVersion: directoryCursorVersion)
    }

    private static func codexBoundedDiscoveryIsComplete(
        _ state: CostUsageCodexActiveLookbackState) -> Bool
    {
        let rootPaths = Set(state.rootPaths)
        return Set(state.completedRootPaths) == rootPaths
            && Set(state.completedCurrentWindowRootPaths ?? []) == rootPaths
            && Set(state.completedCurrentWindowFlatRootPaths ?? []) == rootPaths
            && state.pendingFilePaths.isEmpty
            && state.legacyRecursivePendingRootPaths.isEmpty
    }

    // swiftlint:disable:next function_parameter_count
    private static func advanceCodexCurrentWindow(
        root: URL,
        range: CostUsageDayRange,
        preferNewest: Bool,
        remainingDiscoveryVisits: inout Int,
        excludedPendingPathKeys: Set<String>,
        workRecorder: CodexScanWorkRecorder?,
        listingMetadata: @escaping CodexListingMetadataReader,
        state: inout CostUsageCodexActiveLookbackState)
    {
        let rootPath = Self.codexResolvedPath(root)
        let partitionCursorKey = "current-partition:\(rootPath)"
        let flatCursorKey = "current-flat:\(rootPath)"
        state.directoryPendingNamesByCursor = state.directoryPendingNamesByCursor ?? [:]
        state.currentWindowNextDayKeyByRoot = state.currentWindowNextDayKeyByRoot ?? [:]
        state.currentWindowDirectoryOffsetByRoot = state.currentWindowDirectoryOffsetByRoot ?? [:]
        state.currentWindowFlatDirectoryOffsetByRoot = state.currentWindowFlatDirectoryOffsetByRoot ?? [:]
        var completedPartitionRoots = Set(state.completedCurrentWindowRootPaths ?? [])
        var completedFlatRoots = Set(state.completedCurrentWindowFlatRootPaths ?? [])
        var discoveredFilePaths: [String] = []

        if !completedPartitionRoots.contains(rootPath), remainingDiscoveryVisits > 0 {
            let page = Self.listCodexSessionFilesByDatePartitionPage(
                root: root,
                scanSinceKey: range.scanSinceKey,
                scanUntilKey: range.scanUntilKey,
                resumeDayKey: state.currentWindowNextDayKeyByRoot?[rootPath],
                resumeDirectoryOffset: state.currentWindowDirectoryOffsetByRoot?[rootPath] ?? 0,
                resumePendingNames: state.directoryPendingNamesByCursor?[partitionCursorKey] ?? [],
                visitLimit: remainingDiscoveryVisits,
                preferNewest: preferNewest,
                calendar: range.calendar,
                workRecorder: workRecorder)
            remainingDiscoveryVisits -= page.visits
            discoveredFilePaths.append(contentsOf: page.files.compactMap { fileURL in
                let path = Self.codexResolvedPath(fileURL)
                return excludedPendingPathKeys.contains(Self.codexPathKey(
                    URL(fileURLWithPath: path, isDirectory: false)))
                    ? nil
                    : path
            })
            if page.isComplete {
                completedPartitionRoots.insert(rootPath)
                state.currentWindowNextDayKeyByRoot?.removeValue(forKey: rootPath)
                state.currentWindowDirectoryOffsetByRoot?.removeValue(forKey: rootPath)
                state.directoryPendingNamesByCursor?.removeValue(forKey: partitionCursorKey)
            } else {
                state.currentWindowNextDayKeyByRoot?[rootPath] = page.nextDayKey
                state.currentWindowDirectoryOffsetByRoot?[rootPath] = page.nextDirectoryOffset
                state.directoryPendingNamesByCursor?[partitionCursorKey] = page.pendingNames
            }
        }

        if completedPartitionRoots.contains(rootPath),
           !completedFlatRoots.contains(rootPath),
           remainingDiscoveryVisits > 0
        {
            let page = Self.listCodexDirectoryPage(
                directoryURL: root,
                resumeOffset: state.currentWindowFlatDirectoryOffsetByRoot?[rootPath] ?? 0,
                visitLimit: remainingDiscoveryVisits,
                resumePendingNames: state.directoryPendingNamesByCursor?[flatCursorKey] ?? [],
                filter: { name in
                    guard name.lowercased().hasSuffix(".jsonl") else { return false }
                    guard let dayKey = Self.dayKeyFromFilename(name) else { return true }
                    return CostUsageDayRange.isInRange(
                        dayKey: dayKey,
                        since: range.scanSinceKey,
                        until: range.scanUntilKey)
                },
                workRecorder: workRecorder)
            remainingDiscoveryVisits -= page.visits
            discoveredFilePaths.append(contentsOf: page.files.compactMap { fileURL in
                let path = Self.codexResolvedPath(fileURL)
                return excludedPendingPathKeys.contains(Self.codexPathKey(
                    URL(fileURLWithPath: path, isDirectory: false)))
                    ? nil
                    : path
            })
            if let nextOffset = page.nextOffset {
                state.currentWindowFlatDirectoryOffsetByRoot?[rootPath] = nextOffset
                state.directoryPendingNamesByCursor?[flatCursorKey] = page.pendingNames
            } else {
                completedFlatRoots.insert(rootPath)
                state.currentWindowFlatDirectoryOffsetByRoot?.removeValue(forKey: rootPath)
                state.directoryPendingNamesByCursor?.removeValue(forKey: flatCursorKey)
            }
        }

        if !discoveredFilePaths.isEmpty {
            let discoveredFiles = discoveredFilePaths.map { URL(fileURLWithPath: $0, isDirectory: false) }
            Self.appendCodexActiveLookbackPaths(
                preferNewest
                    ? Self.sortedCodexSessionFilesNewestFirst(discoveredFiles, metadata: listingMetadata)
                    : discoveredFiles,
                state: &state)
        }
        state.completedCurrentWindowRootPaths = completedPartitionRoots.sorted()
        state.completedCurrentWindowFlatRootPaths = completedFlatRoots.sorted()
    }

    private static func advanceCodexActiveLookback(
        root: URL,
        range: CostUsageDayRange,
        modifiedSince: Date,
        scanBudget: CodexScanBudget,
        state: inout CostUsageCodexActiveLookbackState)
    {
        let rootPath = Self.codexResolvedPath(root)
        var completedRootPaths = Set(state.completedRootPaths)
        if !completedRootPaths.contains(rootPath) {
            let listing = Self.listCodexRecentlyModifiedPartitionFiles(
                root: root,
                scanSinceKey: range.scanSinceKey,
                modifiedSince: modifiedSince,
                scanBudget: scanBudget,
                resumeDayKey: state.nextDayKeyByRoot[rootPath],
                calendar: range.calendar)
            Self.appendCodexActiveLookbackPaths(listing.files, state: &state)
            if listing.isComplete {
                completedRootPaths.insert(rootPath)
                state.nextDayKeyByRoot.removeValue(forKey: rootPath)
            } else if let nextDayKey = listing.nextDayKey {
                state.nextDayKeyByRoot[rootPath] = nextDayKey
            }
        }

        var legacyPendingRoots = Set(state.legacyRecursivePendingRootPaths)
        if completedRootPaths.contains(rootPath), legacyPendingRoots.remove(rootPath) != nil {
            // This recursive walk belongs only to the cold-start cycle. Later warm cycles
            // retain the bounded partition discovery above.
            let legacy = Self.listCodexRecentlyModifiedFilesRecursive(
                root: root,
                modifiedSince: modifiedSince)
            Self.appendCodexActiveLookbackPaths(legacy, state: &state)
        }
        state.completedRootPaths = completedRootPaths.sorted()
        state.legacyRecursivePendingRootPaths = legacyPendingRoots.sorted()
    }

    // swiftlint:disable:next function_parameter_count
    private static func advanceCodexActiveLookbackPage(
        root: URL,
        range: CostUsageDayRange,
        modifiedSince: Date,
        preferNewest: Bool,
        remainingDiscoveryVisits: inout Int,
        excludedPendingPathKeys: Set<String>,
        workRecorder: CodexScanWorkRecorder?,
        state: inout CostUsageCodexActiveLookbackState)
    {
        let rootPath = Self.codexResolvedPath(root)
        let cursorKey = "active-partition:\(rootPath)"
        state.directoryPendingNamesByCursor = state.directoryPendingNamesByCursor ?? [:]
        var completedRootPaths = Set(state.completedRootPaths)
        guard !completedRootPaths.contains(rootPath), remainingDiscoveryVisits > 0 else { return }
        state.nextDirectoryOffsetByRoot = state.nextDirectoryOffsetByRoot ?? [:]
        let lookbackSinceKey = Self.dayKey(
            range.scanSinceKey,
            addingDays: -Self.codexActiveSessionLookbackDays,
            calendar: range.calendar) ?? range.scanSinceKey
        let lookbackUntilKey = Self.dayKey(
            range.scanSinceKey,
            addingDays: -1,
            calendar: range.calendar) ?? lookbackSinceKey
        let page = Self.listCodexSessionFilesByDatePartitionPage(
            root: root,
            scanSinceKey: lookbackSinceKey,
            scanUntilKey: lookbackUntilKey,
            resumeDayKey: state.nextDayKeyByRoot[rootPath],
            resumeDirectoryOffset: state.nextDirectoryOffsetByRoot?[rootPath] ?? 0,
            resumePendingNames: state.directoryPendingNamesByCursor?[cursorKey] ?? [],
            visitLimit: remainingDiscoveryVisits,
            preferNewest: preferNewest,
            calendar: range.calendar,
            workRecorder: workRecorder)
        remainingDiscoveryVisits -= page.visits
        let discoveredFilePaths = Self.filterRecentlyModified(
            files: page.files,
            modifiedSince: modifiedSince).compactMap { fileURL in
            let path = Self.codexResolvedPath(fileURL)
            return excludedPendingPathKeys.contains(Self.codexPathKey(
                URL(fileURLWithPath: path, isDirectory: false)))
                ? nil
                : path
        }
        if !discoveredFilePaths.isEmpty {
            var pendingFilePaths = Set(state.pendingFilePaths)
            pendingFilePaths.formUnion(discoveredFilePaths)
            state.pendingFilePaths = pendingFilePaths.sorted()
        }
        if page.isComplete {
            completedRootPaths.insert(rootPath)
            state.nextDayKeyByRoot.removeValue(forKey: rootPath)
            state.nextDirectoryOffsetByRoot?.removeValue(forKey: rootPath)
            state.directoryPendingNamesByCursor?.removeValue(forKey: cursorKey)
        } else {
            state.nextDayKeyByRoot[rootPath] = page.nextDayKey
            state.nextDirectoryOffsetByRoot?[rootPath] = page.nextDirectoryOffset
            state.directoryPendingNamesByCursor?[cursorKey] = page.pendingNames
        }
        state.completedRootPaths = completedRootPaths.sorted()
    }

    private static func advanceCodexLegacyRecursivePage(
        root: URL,
        remainingDiscoveryVisits: inout Int,
        excludedPendingPathKeys: Set<String>,
        workRecorder: CodexScanWorkRecorder?,
        state: inout CostUsageCodexActiveLookbackState)
    {
        let rootPath = Self.codexResolvedPath(root)
        guard state.legacyRecursivePendingRootPaths.contains(rootPath),
              remainingDiscoveryVisits > 0
        else { return }

        state.legacyRecursiveDirectoryPathsByRoot = state.legacyRecursiveDirectoryPathsByRoot ?? [:]
        state.legacyRecursiveDirectoryOffsetByPath = state.legacyRecursiveDirectoryOffsetByPath ?? [:]
        var directories = state.legacyRecursiveDirectoryPathsByRoot?[rootPath] ?? [rootPath]
        var queuedDirectories = Set(directories)
        var discoveredFiles: [URL] = []

        while let directoryPath = directories.first, remainingDiscoveryVisits > 0 {
            let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
            let cursorKey = "legacy:\(directoryPath)"
            state.directoryPendingNamesByCursor = state.directoryPendingNamesByCursor ?? [:]
            let page = Self.listCodexDirectoryPage(
                directoryURL: directoryURL,
                resumeOffset: state.legacyRecursiveDirectoryOffsetByPath?[directoryPath] ?? 0,
                visitLimit: remainingDiscoveryVisits,
                resumePendingNames: state.directoryPendingNamesByCursor?[cursorKey] ?? [],
                filter: { !$0.hasPrefix(".") },
                workRecorder: workRecorder)
            remainingDiscoveryVisits -= page.visits

            for itemURL in page.files {
                let values = try? itemURL.resourceValues(
                    forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                if values?.isDirectory == true, values?.isSymbolicLink != true {
                    if Self.isCodexDatePartitionAncestor(itemURL, rootPath: rootPath) {
                        continue
                    }
                    let resolvedDirectory = Self.codexResolvedPath(itemURL)
                    guard Self.isWithinCodexRoots(
                        fileURL: URL(fileURLWithPath: resolvedDirectory, isDirectory: true),
                        roots: [root]),
                        queuedDirectories.insert(resolvedDirectory).inserted
                    else { continue }
                    directories.append(resolvedDirectory)
                } else if values?.isRegularFile == true,
                          itemURL.pathExtension.lowercased() == "jsonl",
                          Self.isWithinCodexRoots(fileURL: itemURL, roots: [root]),
                          !excludedPendingPathKeys.contains(Self.codexPathKey(itemURL))
                {
                    discoveredFiles.append(itemURL)
                }
            }

            if let nextOffset = page.nextOffset {
                state.legacyRecursiveDirectoryOffsetByPath?[directoryPath] = nextOffset
                state.directoryPendingNamesByCursor?[cursorKey] = page.pendingNames
                break
            }
            directories.removeFirst()
            state.legacyRecursiveDirectoryOffsetByPath?.removeValue(forKey: directoryPath)
            state.directoryPendingNamesByCursor?.removeValue(forKey: cursorKey)
        }

        Self.appendCodexActiveLookbackPaths(discoveredFiles, state: &state)
        if directories.isEmpty {
            state.legacyRecursivePendingRootPaths.removeAll { $0 == rootPath }
            state.legacyRecursiveDirectoryPathsByRoot?.removeValue(forKey: rootPath)
        } else {
            state.legacyRecursiveDirectoryPathsByRoot?[rootPath] = directories
        }
    }

    private static func appendCodexActiveLookbackPaths(
        _ files: some Sequence<URL>,
        normalizeExisting: Bool = false,
        state: inout CostUsageCodexActiveLookbackState)
    {
        let files = Array(files)
        guard !files.isEmpty else { return }
        var queuedPaths: Set<String>
        if normalizeExisting {
            var normalizedPaths: Set<String> = []
            state.pendingFilePaths = state.pendingFilePaths.compactMap { path in
                let resolvedPath = Self.codexResolvedPath(URL(fileURLWithPath: path, isDirectory: false))
                return normalizedPaths.insert(resolvedPath).inserted ? resolvedPath : nil
            }
            queuedPaths = normalizedPaths
        } else {
            queuedPaths = Set(state.pendingFilePaths)
        }
        for fileURL in files {
            let resolvedPath = Self.codexResolvedPath(fileURL)
            guard queuedPaths.insert(resolvedPath).inserted else { continue }
            state.pendingFilePaths.append(resolvedPath)
        }
    }

    private static func reconcileCachedCodexPendingPaths(
        cache: CostUsageCache,
        roots: [URL],
        state: inout CostUsageCodexActiveLookbackState) -> Int
    {
        var queuedPaths: Set<String> = []
        state.pendingFilePaths = state.pendingFilePaths.compactMap { path in
            let resolvedPath = Self.codexResolvedPath(URL(fileURLWithPath: path, isDirectory: false))
            return queuedPaths.insert(resolvedPath).inserted ? resolvedPath : nil
        }

        let cachedPendingPaths = cache.files.compactMap { path, usage -> String? in
            guard usage.hasPendingCodexScanWork
                || !usage.hasCurrentCodexParser else { return nil }
            let fileURL = URL(fileURLWithPath: path, isDirectory: false)
            guard Self.isWithinCodexRoots(fileURL: fileURL, roots: roots) else { return nil }
            return Self.codexResolvedPath(fileURL)
        }.sorted()

        var recoveredCount = 0
        for resolvedPath in cachedPendingPaths {
            guard queuedPaths.insert(resolvedPath).inserted else { continue }
            state.pendingFilePaths.append(resolvedPath)
            recoveredCount += 1
        }
        return recoveredCount
    }

    /// Finds changed files already known to contain current-day usage before the bounded queue
    /// is selected. This is intentionally narrower than a full manifest stat pass: active files
    /// are checked immediately, while older partitions continue through durable lookback.
    private static func codexChangedCurrentDayCachedFiles(
        cache: CostUsageCache,
        roots: [URL],
        dayKey: String,
        calendar: Calendar,
        metadata: CodexListingMetadataReader? = nil) -> [URL]
    {
        guard let dayStart = self.parseDayKey(dayKey, calendar: calendar) else { return [] }
        let dayStartMs = Int64(dayStart.timeIntervalSince1970 * 1000)
        return cache.files.compactMap { path, usage -> URL? in
            let fileURL = URL(fileURLWithPath: path)
            guard Self.isWithinCodexRoots(fileURL: fileURL, roots: roots),
                  usage.mtimeUnixMs >= dayStartMs
                  || usage.touchesCodexScanWindow(
                      sinceKey: dayKey,
                      untilKey: dayKey,
                      calendar: calendar)
            else { return nil }
            let fileMetadata = metadata?(fileURL) ?? Self.codexFileMetadata(fileURL: fileURL)
            guard usage.mtimeUnixMs != fileMetadata.mtimeUnixMs
                || usage.size != fileMetadata.size
                || usage.codexScanFileId != fileMetadata.fileId
            else { return nil }
            return fileURL
        }.sorted { $0.path < $1.path }
    }

    private struct CodexActiveLookbackQueueUpdateContext {
        let seedFiles: [URL]
        let migrationSeedPathKeys: [String]?
        let discoveredFiles: [URL]
        let previousDiscovery: CostUsageCodexSessionDiscovery?
        let shouldBoundCatchUp: Bool
        let shouldSeedBoundedQueue: Bool
        let preferNewest: Bool
        let listingMetadata: CodexListingMetadataReader
    }

    private static func seedOrExtendCodexActiveLookbackQueue(
        context: CodexActiveLookbackQueueUpdateContext,
        state: inout CostUsageCodexActiveLookbackState)
    {
        guard context.shouldBoundCatchUp else { return }
        if context.shouldSeedBoundedQueue {
            if let migrationSeedPathKeys = context.migrationSeedPathKeys {
                self.reseedCodexActiveLookbackPathKeys(
                    migrationSeedPathKeys, prioritizeExisting: true, state: &state)
            } else {
                self.appendCodexActiveLookbackPaths(
                    context.preferNewest
                        ? self.sortedCodexSessionFilesNewestFirst(
                            context.seedFiles, metadata: context.listingMetadata)
                        : context.seedFiles,
                    normalizeExisting: true,
                    state: &state)
            }
            return
        }
        guard let previousDiscovery = context.previousDiscovery else { return }
        let previousPaths = Set(previousDiscovery.fileStamps.keys.map {
            Self.codexResolvedPath(URL(fileURLWithPath: $0, isDirectory: false))
        })
        let newFiles = context.discoveredFiles.filter { !previousPaths.contains(Self.codexResolvedPath($0)) }
        Self.appendCodexActiveLookbackPaths(
            context.preferNewest
                ? self.sortedCodexSessionFilesNewestFirst(newFiles, metadata: context.listingMetadata)
                : newFiles,
            state: &state)
    }

    private static func codexCachedFileNeedsScan(
        _ fileURL: URL,
        cache: CostUsageCache,
        metadata: CodexListingMetadataReader? = nil,
        validateSettledForkDependencies: Bool = true) -> Bool
    {
        let retryPath = Self.codexResolvedPath(fileURL)
        if cache.codexHistoryHydrationRetries?[retryPath] != nil {
            return true
        }
        // Settled orphan buffers still need dependency validation on ordinary refreshes
        // so a restored parent can invalidate them without touching the child JSONL.
        guard let usage = cache.files[fileURL.path],
              usage.codexScanComplete == true,
              usage.codexRequestReconciliation?.pendingPaths.isEmpty != false,
              !usage.hasBufferedCodexForkRetryLines
              || (!validateSettledForkDependencies && usage.hasSettledMissingCodexFork)
        else { return true }
        let fileMetadata = metadata?(fileURL) ?? Self.codexFileMetadata(fileURL: fileURL)
        return usage.size != fileMetadata.size
            || usage.mtimeUnixMs != fileMetadata.mtimeUnixMs
            || usage.codexScanFileId != fileMetadata.fileId
            || !usage.hasCurrentCodexParser
    }

    private static func codexHistoryPathsToPreserve(cache: CostUsageCache) -> Set<String> {
        var paths = Set(cache.codexHistoryHydrationRetries?.values.flatMap(\.retainedPaths) ?? [])
        paths.formUnion(cache.codexMalformedDetailsPaths ?? [])
        return paths
    }

    private static func applyCodexHistoryRetryOutcomes(
        _ result: CodexFileScanResult,
        hydrationRetries: [String: CodexHistoryHydrationRetry] = [:],
        cache: inout CostUsageCache)
    {
        var retries = cache.codexHistoryHydrationRetries ?? [:]
        for (path, retry) in hydrationRetries.merging(
            result.historyHydrationRetries,
            uniquingKeysWith: { existing, incoming in
                var merged = existing
                merged.merge(incoming)
                return merged
            })
        {
            if var existing = retries[path] {
                existing.merge(retry)
                retries[path] = existing
            } else {
                retries[path] = retry
            }
        }
        let failedTargets = Set(result.historyHydrationRetries.keys)
        for target in result.completedHistoryRetryTargets where !failedTargets.contains(target) {
            retries.removeValue(forKey: target)
        }
        cache.codexHistoryHydrationRetries = retries.isEmpty ? nil : retries
        if !retries.isEmpty {
            cache.codexScanCatchUpPending = true
        }
    }

    private static func reseedCodexActiveLookbackPathKeys(
        _ pathKeys: some Sequence<String>,
        prioritizeExisting: Bool = false,
        state: inout CostUsageCodexActiveLookbackState)
    {
        var queuedPaths: Set<String> = []
        var reseededPaths: [String] = []
        func append(_ path: String) {
            let pathKey = Self.codexPathKey(URL(fileURLWithPath: path, isDirectory: false))
            guard queuedPaths.insert(pathKey).inserted else { return }
            reseededPaths.append(pathKey)
        }
        // A migration must drain its existing waiters; newly discovered metadata can still
        // take priority over the backlog when admission debt permits it.
        if prioritizeExisting {
            for path in state.pendingFilePaths {
                append(path)
            }
            for path in pathKeys {
                append(path)
            }
        } else {
            for path in pathKeys {
                append(path)
            }
            for path in state.pendingFilePaths {
                append(path)
            }
        }
        state.pendingFilePaths = reseededPaths
    }

    private static func cacheWideMigrationNeedsQueueReseed(
        plan: CodexRefreshPlan,
        inventoryPathKeys: Set<String>,
        state: CostUsageCodexActiveLookbackState) -> Bool
    {
        guard plan.requiresCacheWideFileReprocessing else { return false }
        let queuedPathKeys = Set(state.pendingFilePaths.map {
            Self.codexPathKey(URL(fileURLWithPath: $0, isDirectory: false))
        })
        let requiredPathKeys = plan.requiresAllFilesForCacheWideMigration
            ? inventoryPathKeys
            : plan.cacheWideMigrationPendingPathKeys.intersection(inventoryPathKeys)
        return !requiredPathKeys.isSubset(of: queuedPathKeys)
    }

    private static func codexPendingPathCanAffectRequestedWindow(
        _ path: String,
        cache: CostUsageCache,
        sinceKey: String,
        untilKey: String,
        calendar: Calendar) -> Bool
    {
        let fileURL = URL(fileURLWithPath: path, isDirectory: false)
        let cached = cache.files[Self.codexResolvedPath(fileURL)]
            ?? cache.files[Self.codexPathKey(fileURL)]
            ?? cache.files[fileURL.standardizedFileURL.path]
        let metadata = Self.codexFileMetadata(fileURL: fileURL)
        guard metadata.fileId != nil else { return true }
        let pathDayKey = Self.codexDayKeyFromPath(fileURL)
        let filenameTouchesWindow = pathDayKey.map {
            CostUsageDayRange.isInRange(dayKey: $0, since: sinceKey, until: untilKey)
        } ?? false
        guard let since = Self.parseDayKey(sinceKey, calendar: calendar),
              let until = Self.parseDayKey(untilKey, calendar: calendar),
              since <= until,
              let windowEnd = calendar.date(byAdding: .day, value: 1, to: until)
        else { return true }
        let mtime = Date(timeIntervalSince1970: TimeInterval(metadata.mtimeUnixMs) / 1000)
        let metadataTouchesWindow = mtime >= since && mtime < windowEnd
        let olderFilenameModifiedInWindow = Self.codexDayKeyFromPath(fileURL)
            .map {
                $0 < sinceKey
                    && metadata.mtimeUnixMs >= Int64(since.timeIntervalSince1970 * 1000)
                    && metadata.mtimeUnixMs < Int64(windowEnd.timeIntervalSince1970 * 1000)
            }
            == true
        let hasUsageDay = cached?.days.keys.contains {
            CostUsageDayRange.isInRange(dayKey: $0, since: sinceKey, until: untilKey)
        } == true
        let cachedTouchesWindow = cached.map { usage in
            hasUsageDay
                || (pathDayKey.map { $0 <= untilKey } ?? true && usage.touchesCodexScanWindow(
                    sinceKey: sinceKey,
                    untilKey: untilKey,
                    calendar: calendar))
        } ?? false
        return cachedTouchesWindow
            || filenameTouchesWindow
            || metadataTouchesWindow
            || olderFilenameModifiedInWindow
    }

    private static func codexPendingPathIsRecent(
        _ path: String,
        cache: CostUsageCache,
        priorityDayKey: String?,
        currentDayKey: String,
        calendar: Calendar) -> Bool
    {
        self.codexPendingPathCanAffectRequestedWindow(
            path,
            cache: cache,
            sinceKey: currentDayKey,
            untilKey: currentDayKey,
            calendar: calendar)
            || priorityDayKey.map { dayKey in
                self.codexPendingPathCanAffectRequestedWindow(
                    path,
                    cache: cache,
                    sinceKey: dayKey,
                    untilKey: dayKey,
                    calendar: calendar)
            } == true
    }

    private static func prioritizeCodexRequestedWindowPendingPaths(
        cache: CostUsageCache,
        range: CostUsageDayRange,
        dayKeys: (priority: String?, current: String),
        listingMetadata: @escaping CodexListingMetadataReader,
        state: inout CostUsageCodexActiveLookbackState) -> String?
    {
        guard !state.pendingFilePaths.isEmpty else { return nil }
        if (state.priorityAdmissionDebt ?? 0) > 0 {
            // A boosted first admission owes bounded FIFO service to existing waiters before
            // another newly discovered recent file can jump the queue.
            return nil
        }
        let pendingPaths = state.pendingFilePaths
        var resumableMissingParentForkPaths: [String] = []
        var recentPaths: [String] = []
        var requestedWindowPaths: [String] = []
        var unrelatedPaths: [String] = []
        resumableMissingParentForkPaths.reserveCapacity(pendingPaths.count)
        recentPaths.reserveCapacity(pendingPaths.count)
        requestedWindowPaths.reserveCapacity(pendingPaths.count)
        unrelatedPaths.reserveCapacity(pendingPaths.count)
        for path in pendingPaths {
            let fileURL = URL(fileURLWithPath: path, isDirectory: false)
            let cached = cache.files[Self.codexResolvedPath(fileURL)]
                ?? cache.files[Self.codexPathKey(fileURL)]
            if let cached,
               Self.isUnresolvedMissingParentFork(cached),
               cached.codexScanComplete != true || !cached.hasCurrentCodexParser
            {
                // An incomplete missing-parent fork blocks every verified-day proof until its
                // buffered history is settled. Resume it even when its path and activity are old;
                // settled old-only forks remain on the ordinary FIFO lane.
                resumableMissingParentForkPaths.append(path)
            } else if Self.codexPendingPathIsRecent(
                path,
                cache: cache,
                priorityDayKey: dayKeys.priority,
                currentDayKey: dayKeys.current,
                calendar: range.calendar)
            {
                recentPaths.append(path)
            } else if Self.codexPendingPathCanAffectRequestedWindow(
                path,
                cache: cache,
                sinceKey: range.scanSinceKey,
                untilKey: range.scanUntilKey,
                calendar: range.calendar)
            {
                requestedWindowPaths.append(path)
            } else {
                unrelatedPaths.append(path)
            }
        }
        var historicalPaths = requestedWindowPaths + unrelatedPaths
        if let promotedFork = resumableMissingParentForkPaths.first {
            // The cached-pending reconciliation may have restored this path at the queue tail.
            // Preserve every other waiter's order behind it so ordinary bounded service remains
            // fair while the proof-blocking partial fork resumes.
            state.pendingFilePaths = [promotedFork] + pendingPaths.filter { $0 != promotedFork }
            return promotedFork
        }
        guard !recentPaths.isEmpty else {
            state.pendingFilePaths = historicalPaths
            return nil
        }

        func isFirstAdmission(_ path: String) -> Bool {
            let fileURL = URL(fileURLWithPath: path, isDirectory: false)
            guard let usage = cache.files[Self.codexResolvedPath(fileURL)] else { return true }
            return usage.codexScanComplete == true
                && !Self.codexCachedFileNeedsScan(fileURL, cache: cache, metadata: listingMetadata)
        }

        let promotedIndex = recentPaths.firstIndex { path in
            Self.codexDayKeyFromPath(URL(fileURLWithPath: path, isDirectory: false)) == dayKeys.priority
                && isFirstAdmission(path)
        } ?? recentPaths.firstIndex { path in
            Self.codexDayKeyFromPath(URL(fileURLWithPath: path, isDirectory: false)) == dayKeys.current
                && cache.files[Self.codexResolvedPath(URL(fileURLWithPath: path, isDirectory: false))] == nil
        }
        if let promotedIndex {
            // Admit a newly seen current/closed day before the bounded candidate and hydration
            // caps. Once serviced, partial files rotate normally; unchanged complete files leave
            // the queue. Keep the oldest historical waiter immediately behind this one-time boost.
            let promoted = recentPaths.remove(at: promotedIndex)
            let historical = historicalPaths.isEmpty ? [] : [historicalPaths.removeFirst()]
            state.pendingFilePaths = [promoted] + historical + recentPaths + historicalPaths
            return promoted
        } else if !historicalPaths.isEmpty {
            // Put both lanes within the bounded hydration prefix. The original queue head picks
            // the first lane; actual serviced partial paths rotate to the tail after scanning.
            let recent = recentPaths.removeFirst()
            let historical = historicalPaths.removeFirst()
            let recentWasFirst = pendingPaths.first == recent
            state.pendingFilePaths = (recentWasFirst ? [recent, historical] : [historical, recent])
                + recentPaths + historicalPaths
        } else {
            state.pendingFilePaths = recentPaths
        }
        return nil
    }

    private struct CodexPendingLookbackAppendContext {
        let roots: [URL]
        let maxCount: Int?
        let validateRoots: Bool
    }

    private static func appendPendingCodexActiveLookbackFiles(
        state: inout CostUsageCodexActiveLookbackState,
        context: CodexPendingLookbackAppendContext,
        seenPaths: inout Set<String>,
        fileURLsByPathKey: inout [String: URL],
        files: inout [URL]) -> Int
    {
        if context.validateRoots {
            state.pendingFilePaths = state.pendingFilePaths.filter { path in
                Self.isWithinCodexRoots(
                    fileURL: URL(fileURLWithPath: path, isDirectory: false), roots: context.roots)
            }
        }
        let pendingCount = min(context.maxCount ?? state.pendingFilePaths.count, state.pendingFilePaths.count)
        var normalizedPathSet: Set<String> = []
        let normalizedPrefix = state.pendingFilePaths.prefix(pendingCount).compactMap { path in
            let resolvedPath = Self.codexResolvedPath(URL(fileURLWithPath: path, isDirectory: false))
            return normalizedPathSet.insert(resolvedPath).inserted ? resolvedPath : nil
        }
        state.pendingFilePaths.replaceSubrange(0..<pendingCount, with: normalizedPrefix)
        for path in normalizedPrefix {
            let fileURL = URL(fileURLWithPath: path, isDirectory: false)
            let pathKey = Self.codexPathKey(fileURL)
            guard seenPaths.insert(pathKey).inserted else { continue }
            fileURLsByPathKey[pathKey] = fileURL
            files.append(fileURL)
        }
        return normalizedPrefix.count
    }

    private struct CodexRefreshCandidateSelectionContext {
        let fileURLsByPathKey: [String: URL]
        let shouldBoundCatchUp: Bool
        let boundedQueuePathCount: Int
        let preferNewest: Bool
        let listingMetadata: CodexListingMetadataReader
        let workRecorder: CodexScanWorkRecorder?
    }

    private struct CodexRefreshCandidateSelection {
        let files: [URL]
        let exhaustedVisitBudget: Bool
    }

    private static func codexFilesScheduledForRefresh(
        _ files: [URL],
        activeLookbackState: inout CostUsageCodexActiveLookbackState,
        context: CodexRefreshCandidateSelectionContext) -> CodexRefreshCandidateSelection
    {
        guard context.shouldBoundCatchUp else {
            return CodexRefreshCandidateSelection(
                files: context.preferNewest
                    ? self.sortedCodexSessionFilesNewestFirst(files, metadata: context.listingMetadata)
                    : files,
                exhaustedVisitBudget: false)
        }

        let candidateLimit = Self.codexCatchUpScanCandidateLimit
        var candidates: [URL] = []
        candidates.reserveCapacity(candidateLimit)
        var selectionVisits = 0

        func appendPendingCandidate(path: String) {
            guard selectionVisits < candidateLimit else { return }
            selectionVisits += 1
            context.workRecorder?.recordCodexCandidateSelectionVisit()
            let pendingURL = URL(fileURLWithPath: path, isDirectory: false)
            let pathKey = Self.codexPathKey(pendingURL)
            candidates.append(context.fileURLsByPathKey[pathKey] ?? pendingURL)
        }

        let pendingPaths = activeLookbackState.pendingFilePaths.prefix(context.boundedQueuePathCount)
        for path in pendingPaths {
            appendPendingCandidate(path: path)
            if selectionVisits == candidateLimit {
                break
            }
        }
        return CodexRefreshCandidateSelection(
            files: candidates,
            exhaustedVisitBudget: activeLookbackState.pendingFilePaths.count > candidates.count)
    }

    // swiftlint:disable:next function_parameter_count
    private static func finalizedCodexActiveLookbackState(
        _ state: CostUsageCodexActiveLookbackState,
        completedFilePaths: Set<String>,
        servicedFilePaths: Set<String>,
        completionCandidateCount: Int,
        requiresBoundedDiscoveryCompletion: Bool,
        retainCompletedStateForExactValidation: Bool,
        workRecorder: CodexScanWorkRecorder?) -> CostUsageCodexActiveLookbackState?
    {
        var state = state
        workRecorder?.recordActiveLookbackFinalization(completionCandidates: completedFilePaths.count)
        let prefixCount = min(completionCandidateCount, state.pendingFilePaths.count)
        let retainedPrefix = state.pendingFilePaths.prefix(prefixCount).filter { path in
            completedFilePaths.contains(path)
                == false
        }
        state.pendingFilePaths.replaceSubrange(0..<prefixCount, with: retainedPrefix)
        // Rotate serviced partial files behind every waiter, including paths beyond this pass's
        // candidate limit. Unattempted files retain their place in the queue.
        let servicedSurvivors = retainedPrefix.filter { servicedFilePaths.contains($0) }
        let servicedPrefixPaths = Set(servicedSurvivors)
        state.pendingFilePaths.removeAll { servicedPrefixPaths.contains($0) }
        state.pendingFilePaths.append(contentsOf: servicedSurvivors)
        let boundedDiscoveryIsComplete = !requiresBoundedDiscoveryCompletion
            || (Set(state.completedCurrentWindowRootPaths ?? []) == Set(state.rootPaths)
                && Set(state.completedCurrentWindowFlatRootPaths ?? []) == Set(state.rootPaths))
        let isComplete = boundedDiscoveryIsComplete
            && Set(state.completedRootPaths) == Set(state.rootPaths)
            && state.pendingFilePaths.isEmpty
            && state.legacyRecursivePendingRootPaths.isEmpty
        return isComplete && !retainCompletedStateForExactValidation ? nil : state
    }

    private static func completedCodexActiveLookbackPaths(
        scheduledFiles: [URL],
        pendingPaths: Set<String>,
        attemptedPaths: Set<String>,
        processedPaths: Set<String>,
        cache: CostUsageCache) -> Set<String>
    {
        Set(scheduledFiles.compactMap { fileURL -> String? in
            guard attemptedPaths.contains(fileURL.path), processedPaths.contains(fileURL.path) else { return nil }
            let resolvedPath = Self.codexResolvedPath(fileURL)
            guard pendingPaths.contains(resolvedPath) else { return nil }
            let metadata = Self.codexFileMetadata(fileURL: fileURL)
            if metadata.fileId == nil, !FileManager.default.fileExists(atPath: fileURL.path) {
                return resolvedPath
            }
            if processedPaths.contains(fileURL.path), cache.files[fileURL.path] == nil {
                return resolvedPath
            }
            guard let usage = cache.files[fileURL.path],
                  usage.hasCurrentCodexParser,
                  usage.codexScanComplete == true,
                  !usage.hasPendingCodexForkRetry,
                  usage.codexScanFileId == metadata.fileId,
                  usage.mtimeUnixMs == metadata.mtimeUnixMs,
                  usage.size == metadata.size
            else { return nil }
            return resolvedPath
        })
    }

    private static func listCodexSessionFilesFlat(root: URL, scanSinceKey: String, scanUntilKey: String) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }

        var out: [URL] = []
        for item in items where item.pathExtension.lowercased() == "jsonl" {
            if let dayKey = Self.dayKeyFromFilename(item.lastPathComponent) {
                if !CostUsageDayRange.isInRange(dayKey: dayKey, since: scanSinceKey, until: scanUntilKey) {
                    continue
                }
            }
            out.append(item)
        }
        return out
    }

    private static func listCodexLegacySessionFilesRecursive(root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let rootPath = root.path
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }

        var out: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            if Self.isCodexDatePartitionAncestor(item, rootPath: rootPath) {
                enumerator.skipDescendants()
                continue
            }
            guard item.pathExtension.lowercased() == "jsonl" else { continue }
            out.append(item)
        }
        return out
    }

    private static func isCodexDatePartitionAncestor(_ url: URL, rootPath: String) -> Bool {
        let path = url.path
        guard path.hasPrefix(rootPath + "/") else { return false }
        let relative = path.dropFirst(rootPath.count + 1)
        return !relative.contains("/") && Self.isDatePartitionComponent(String(relative), length: 4)
    }

    private static let codexFilenameDateRegex = try? NSRegularExpression(pattern: "(\\d{4}-\\d{2}-\\d{2})")

    private static func dayKeyFromFilename(_ filename: String) -> String? {
        guard let regex = self.codexFilenameDateRegex else { return nil }
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = regex.firstMatch(in: filename, range: range) else { return nil }
        guard let matchRange = Range(match.range(at: 1), in: filename) else { return nil }
        return String(filename[matchRange])
    }

    private static func codexDayKeyFromPath(_ fileURL: URL) -> String? {
        if let filenameDayKey = dayKeyFromFilename(fileURL.lastPathComponent) {
            return filenameDayKey
        }
        let components = fileURL.standardizedFileURL.pathComponents
        guard components.count >= 4 else { return nil }
        for index in 0...(components.count - 4) {
            let year = components[index]
            let month = components[index + 1]
            let day = components[index + 2]
            guard Self.isDatePartitionComponent(year, length: 4),
                  Self.isDatePartitionComponent(month, length: 2),
                  Self.isDatePartitionComponent(day, length: 2)
            else { continue }
            return "\(year)-\(month)-\(day)"
        }
        return nil
    }

    struct CodexSessionMetadata: Codable, Equatable {
        let sessionId: String?
        var concreteSessionId: String?
        let forkedFromId: String?
        let forkTimestamp: String?
        let projectPath: String?
        let isSubagentThread: Bool
        let subagentHistoryStartOrdinal: Int?
        let historyBaseThreadId: String?
        let requestSessionID: String?

        init(
            sessionId: String?,
            concreteSessionId: String? = nil,
            forkedFromId: String?,
            forkTimestamp: String?,
            projectPath: String?,
            isSubagentThread: Bool,
            subagentHistoryStartOrdinal: Int?,
            historyBaseThreadId: String? = nil,
            requestSessionID: String? = nil)
        {
            self.sessionId = sessionId
            self.concreteSessionId = concreteSessionId
            self.forkedFromId = forkedFromId
            self.forkTimestamp = forkTimestamp
            self.projectPath = projectPath
            self.isSubagentThread = isSubagentThread
            self.subagentHistoryStartOrdinal = subagentHistoryStartOrdinal
            self.historyBaseThreadId = historyBaseThreadId
            self.requestSessionID = requestSessionID
        }
    }

    struct CodexTurnContextMetadata: Codable, Equatable {
        let timestamp: String?
        let model: String?
        let cwd: String?
        let title: String?
        var turnID: String?
    }

    struct CodexTokenCountRecord: Codable, Equatable {
        let timestamp: String
        let model: String?
        let turnID: String?
        let last: CostUsageCodexTotals?
        let total: CostUsageCodexTotals?
    }

    struct CodexBareUsageRecord: Codable, Equatable {
        let timestamp: String?
        let model: String?
        let totals: CostUsageCodexTotals
    }

    struct CodexRequestUsageRecord: Codable, Equatable {
        let timestamp: String
        let threadID: String
        let sessionID: String?
        let responseID: String
        let turnID: String?
        let model: String?
        let usage: CostUsageCodexTotals
        let threadTotal: CostUsageCodexTotals
        let turnTotal: CostUsageCodexTotals?
    }

    enum CodexFastLine: Codable, Equatable {
        case sessionMeta(CodexSessionMetadata)
        case turnContext(CodexTurnContextMetadata)
        case interAgentCommunication(triggerTurn: Bool)
        case taskStarted(turnID: String?)
        case tokenCount(CodexTokenCountRecord)
        case bareUsage(CodexBareUsageRecord)
        case tokenUsageRecord(CodexRequestUsageRecord)

        var boundaryTokenCount: CodexTokenCountRecord? {
            switch self {
            case let .tokenCount(record): record
            case let .tokenUsageRecord(record):
                CodexTokenCountRecord(
                    timestamp: record.timestamp,
                    model: record.model,
                    turnID: record.turnID,
                    last: record.usage,
                    total: record.threadTotal)
            default: nil
            }
        }

        var requiresValidTimestamp: Bool {
            switch self {
            case .sessionMeta, .bareUsage:
                false
            case .turnContext, .interAgentCommunication, .taskStarted, .tokenCount, .tokenUsageRecord:
                true
            }
        }
    }

    struct CodexBufferedFastLine: Codable, Equatable {
        let lineIndex: Int
        let ordinal: Int?
        let endOffset: Int64?
        let line: CodexFastLine

        init(lineIndex: Int, ordinal: Int?, endOffset: Int64? = nil, line: CodexFastLine) {
            self.lineIndex = lineIndex
            self.ordinal = ordinal
            self.endOffset = endOffset
            self.line = line
        }
    }

    private static let codexJSONFieldCachedInputTokens = Array("cached_input_tokens".utf8)
    private static let codexJSONFieldCacheReadInputTokens = Array("cache_read_input_tokens".utf8)
    private static let codexJSONFieldId = Array("id".utf8)
    private static let codexJSONFieldInfo = Array("info".utf8)
    private static let codexJSONFieldInputTokens = Array("input_tokens".utf8)
    private static let codexJSONFieldLastTokenUsage = Array("last_token_usage".utf8)
    private static let codexJSONFieldModel = Array("model".utf8)
    private static let codexJSONFieldModelName = Array("model_name".utf8)
    private static let codexJSONFieldOutputTokens = Array("output_tokens".utf8)
    private static let codexJSONFieldOrdinal = Array("ordinal".utf8)
    private static let codexJSONFieldReasoningOutputTokens = Array("reasoning_output_tokens".utf8)
    private static let codexJSONFieldPayload = Array("payload".utf8)
    private static let codexJSONFieldTimestamp = Array("timestamp".utf8)
    private static let codexJSONFieldTitle = Array("title".utf8)
    private static let codexJSONFieldName = Array("name".utf8)
    private static let codexJSONFieldTotalTokenUsage = Array("total_token_usage".utf8)
    private static let codexJSONFieldTriggerTurn = Array("trigger_turn".utf8)
    private static let codexJSONFieldTurnId = Array("turn_id".utf8)
    private static let codexJSONFieldTurnIdCamel = Array("turnId".utf8)
    private static let codexJSONFieldType = Array("type".utf8)
    private static let codexJSONFieldCwd = Array("cwd".utf8)
    private static let codexJSONFieldCurrentWorkingDirectory = Array("current_working_directory".utf8)
    private static let codexJSONFieldCurrentWorkingDirectoryCamel = Array("currentWorkingDirectory".utf8)

    static func codexModelEvidence(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func codexTurnContextModel(
        payloadModel: String?,
        payloadModelName: String?,
        infoModel: String?,
        infoModelName: String?) -> String?
    {
        var sawCandidate = false
        for candidate in [payloadModel, payloadModelName, infoModel, infoModelName] {
            guard let candidate else { continue }
            sawCandidate = true
            if let model = self.codexModelEvidence(candidate) {
                return model
            }
        }
        // nil means the context omitted every model field; an empty value explicitly clears stale context.
        return sawCandidate ? "" : nil
    }

    private static func codexForkParentId(from payload: [String: Any]?) -> String? {
        ["forked_from_id", "forkedFromId", "parent_session_id", "parentSessionId"].lazy
            .compactMap { Self.codexModelEvidence(payload?[$0] as? String) }.first
    }

    private static func codexHistoryBaseThreadId(from payload: [String: Any]?) -> String? {
        let historyBase = payload?["history_base"] as? [String: Any]
            ?? payload?["historyBase"] as? [String: Any]
        return ["thread_id", "threadId"].lazy.compactMap { Self.codexModelEvidence(historyBase?[$0] as? String) }.first
    }

    private static func codexIsSubagentThread(from payload: [String: Any]?) -> Bool {
        guard let payload else { return false }
        if let source = payload["source"] as? String {
            return source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "subagent"
        }
        if let source = payload["source"] as? [String: Any] {
            return source["subagent"] is String || source["subagent"] is [String: Any]
        }
        return false
    }

    private static func codexTurnID(from bytes: UnsafeBufferPointer<UInt8>, in payloadRange: Range<Int>) -> String? {
        func value(in range: Range<Int>) -> String? {
            for key in [self.codexJSONFieldTurnId, self.codexJSONFieldTurnIdCamel, self.codexJSONFieldId] {
                if let value = extractJSONByteStringField(key, from: bytes, in: range, atDepth: 1), !value.isEmpty {
                    return value
                }
            }
            return nil
        }
        return value(in: payloadRange)
            ?? extractJSONByteObjectField(self.codexJSONFieldInfo, from: bytes, in: payloadRange, atDepth: 1)
            .flatMap(value)
    }

    static func normalizedCodexProjectPath(_ rawPath: String?) -> String? {
        guard let rawPath = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty
        else { return nil }
        let expanded = (rawPath as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
    }

    private static func codexTotals(
        from bytes: UnsafeBufferPointer<UInt8>,
        in objectRange: Range<Int>?) -> CostUsageCodexTotals?
    {
        guard let objectRange else { return nil }
        func integer(_ field: [UInt8]) -> Int? {
            Self.extractJSONByteIntField(field, from: bytes, in: objectRange, atDepth: 1)
        }
        let output = max(0, integer(Self.codexJSONFieldOutputTokens) ?? 0)
        return CostUsageCodexTotals(
            input: max(0, integer(Self.codexJSONFieldInputTokens) ?? 0),
            cached: max(0, max(
                integer(Self.codexJSONFieldCachedInputTokens) ?? 0,
                integer(Self.codexJSONFieldCacheReadInputTokens) ?? 0)),
            output: output,
            reasoning: integer(Self.codexJSONFieldReasoningOutputTokens).map { min(max(0, $0), output) })
    }

    private static func parseCodexFastLine(_ bytes: Data) -> CodexFastLine? {
        bytes.withUnsafeBytes { rawBytes in
            let buffer = rawBytes.bindMemory(to: UInt8.self)
            let root = 0..<buffer.count
            func object(_ field: [UInt8], in range: Range<Int>?) -> Range<Int>? {
                range.flatMap { Self.extractJSONByteObjectField(field, from: buffer, in: $0, atDepth: 1) }
            }
            func string(_ field: [UInt8], in range: Range<Int>?, allowingEmpty: Bool = false) -> String? {
                guard let range else { return nil }
                if allowingEmpty {
                    return Self.extractJSONByteStringFieldAllowingEmpty(field, from: buffer, in: range, atDepth: 1)
                }
                return Self.extractJSONByteStringField(field, from: buffer, in: range, atDepth: 1)
            }
            guard let type = string(Self.codexJSONFieldType, in: root) else { return nil }
            let payload = object(Self.codexJSONFieldPayload, in: root)
            let timestamp = string(Self.codexJSONFieldTimestamp, in: root)
            let info = object(Self.codexJSONFieldInfo, in: payload)
            switch type {
            case "session_meta", "token_usage_record":
                // Ownership has one decoder for compact and fallback JSON, including escaped field names.
                guard let decoded = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
                else { return nil }
                return Self.codexLine(from: decoded)
            case "turn_context":
                return .turnContext(CodexTurnContextMetadata(
                    timestamp: timestamp,
                    model: Self.codexTurnContextModel(
                        payloadModel: string(Self.codexJSONFieldModel, in: payload, allowingEmpty: true),
                        payloadModelName: string(Self.codexJSONFieldModelName, in: payload, allowingEmpty: true),
                        infoModel: string(Self.codexJSONFieldModel, in: info, allowingEmpty: true),
                        infoModelName: string(Self.codexJSONFieldModelName, in: info, allowingEmpty: true)),
                    cwd: string(Self.codexJSONFieldCwd, in: payload)
                        ?? string(Self.codexJSONFieldCurrentWorkingDirectory, in: payload)
                        ?? string(Self.codexJSONFieldCurrentWorkingDirectoryCamel, in: payload),
                    title: string(Self.codexJSONFieldTitle, in: payload)
                        ?? string(Self.codexJSONFieldName, in: payload),
                    turnID: payload.flatMap { Self.codexTurnID(from: buffer, in: $0) }))
            case "inter_agent_communication_metadata":
                guard let payload,
                      let triggerTurn = Self.extractJSONByteBoolField(
                          Self.codexJSONFieldTriggerTurn, from: buffer, in: payload, atDepth: 1)
                else { return nil }
                return .interAgentCommunication(triggerTurn: triggerTurn)
            case "event_msg":
                guard let payload, let payloadType = string(Self.codexJSONFieldType, in: payload)
                else { return nil }
                let turnID = Self.codexTurnID(from: buffer, in: payload)
                if payloadType == "task_started" { return .taskStarted(turnID: turnID) }
                guard payloadType == "token_count", let timestamp, let info else { return nil }
                return .tokenCount(CodexTokenCountRecord(
                    timestamp: timestamp,
                    model: Self.codexModelEvidence(string(Self.codexJSONFieldModel, in: info))
                        ?? Self.codexModelEvidence(string(Self.codexJSONFieldModelName, in: info))
                        ?? Self.codexModelEvidence(string(Self.codexJSONFieldModel, in: payload))
                        ?? Self.codexModelEvidence(string(Self.codexJSONFieldModel, in: root)),
                    turnID: turnID,
                    last: Self.codexTotals(from: buffer, in: object(Self.codexJSONFieldLastTokenUsage, in: info)),
                    total: Self.codexTotals(from: buffer, in: object(Self.codexJSONFieldTotalTokenUsage, in: info))))
            default:
                return nil
            }
        }
    }

    private static func codexLine(from object: [String: Any]) -> CodexFastLine? {
        if let metadata = codexSessionMetadata(from: object) { return .sessionMeta(metadata) }
        guard let timestamp = object["timestamp"] as? String,
              Self.dayKeyFromTimestamp(timestamp) ?? Self.dayKeyFromParsedISO(timestamp) != nil
        else { return nil }
        let payload = object["payload"] as? [String: Any] ?? [:]
        let info = payload["info"] as? [String: Any]
        switch object["type"] as? String {
        case "token_usage_record":
            return Self.codexRequestUsageRecord(from: object).map(CodexFastLine.tokenUsageRecord)
        case "inter_agent_communication_metadata":
            return .interAgentCommunication(triggerTurn: payload["trigger_turn"] as? Bool == true)
        case "turn_context":
            return .turnContext(CodexTurnContextMetadata(
                timestamp: timestamp,
                model: Self.codexTurnContextModel(
                    payloadModel: payload["model"] as? String,
                    payloadModelName: payload["model_name"] as? String,
                    infoModel: info?["model"] as? String,
                    infoModelName: info?["model_name"] as? String),
                cwd: payload["cwd"] as? String
                    ?? payload["current_working_directory"] as? String
                    ?? payload["currentWorkingDirectory"] as? String,
                title: payload["title"] as? String ?? payload["name"] as? String,
                turnID: Self.codexTurnID(from: payload)))
        case "event_msg":
            if payload["type"] as? String == "task_started" {
                return .taskStarted(turnID: Self.codexTurnID(from: payload))
            }
            guard payload["type"] as? String == "token_count" else { return nil }
            func totals(_ usage: [String: Any]) -> CostUsageCodexTotals {
                func integer(_ key: String) -> Int { max(0, (usage[key] as? NSNumber)?.intValue ?? 0) }
                let output = integer("output_tokens")
                return CostUsageCodexTotals(
                    input: integer("input_tokens"),
                    cached: max(integer("cached_input_tokens"), integer("cache_read_input_tokens")),
                    output: output,
                    reasoning: (usage["reasoning_output_tokens"] as? NSNumber)
                        .map { min(max(0, $0.intValue), output) })
            }
            return .tokenCount(CodexTokenCountRecord(
                timestamp: timestamp,
                model: Self.codexModelEvidence(info?["model"] as? String)
                    ?? Self.codexModelEvidence(info?["model_name"] as? String)
                    ?? Self.codexModelEvidence(payload["model"] as? String)
                    ?? Self.codexModelEvidence(object["model"] as? String),
                turnID: Self.codexTurnID(from: payload),
                last: (info?["last_token_usage"] as? [String: Any]).map(totals),
                total: (info?["total_token_usage"] as? [String: Any]).map(totals)))
        default:
            return nil
        }
    }

    /// Extracts usage from non-event rollout lines (one-shot codex exec / headless output).
    /// Only the four canonical response envelopes are inspected so arbitrary prompt text cannot
    /// be misread as token data.
    private static func codexBareUsage(
        from obj: [String: Any]) -> (totals: CostUsageCodexTotals, model: String?)?
    {
        let containers = [
            obj["usage"] as? [String: Any],
            (obj["data"] as? [String: Any]).flatMap { $0["usage"] as? [String: Any] },
            (obj["result"] as? [String: Any]).flatMap { $0["usage"] as? [String: Any] },
            (obj["response"] as? [String: Any]).flatMap { $0["usage"] as? [String: Any] },
        ]

        guard let usage = containers.compactMap(\.self).first,
              let inputTokens = Self.codexBareUsageInt(
                  usage, keys: ["input_tokens", "prompt_tokens", "input"]),
              let outputTokens = Self.codexBareUsageInt(
                  usage, keys: ["output_tokens", "completion_tokens", "output"])
        else { return nil }

        let cachedTokens = ["cached_input_tokens", "cache_read_input_tokens", "cached_tokens"]
            .compactMap { Self.codexBareUsageInt(usage, keys: [$0]) }
            .max() ?? 0
        let billedInput = max(0, inputTokens - cachedTokens)
        guard billedInput > 0 || outputTokens > 0 || cachedTokens > 0 else { return nil }

        func modelEvidence(_ container: [String: Any]?) -> String? {
            Self.codexModelEvidence(container?["model"] as? String)
                ?? Self.codexModelEvidence(container?["model_name"] as? String)
        }

        return (
            CostUsageCodexTotals(
                input: billedInput,
                cached: cachedTokens,
                output: outputTokens,
                reasoning: nil),
            modelEvidence(obj) ?? (obj["data"] as? [String: Any]).flatMap(modelEvidence))
    }

    private static func codexRequestUsageRecord(from object: [String: Any]) -> CodexRequestUsageRecord? {
        guard let payload = object["payload"] as? [String: Any],
              let threadID = codexModelEvidence(payload["thread_id"] as? String),
              let responseID = codexModelEvidence(payload["response_id"] as? String),
              let timestamp = object["timestamp"] as? String,
              let usage = (payload["usage"] as? [String: Any]).flatMap(codexRequestUsage),
              let total = (payload["thread_token_usage"] as? [String: Any]).flatMap(codexRequestUsage),
              codexTotalsAtLeast(total, usage)
        else { return nil }
        let sessionID = Self.codexModelEvidence(payload["session_id"] as? String)
        guard payload["session_id"] == nil || sessionID != nil else { return nil }
        let turnTotal = (payload["turn_token_usage"] as? [String: Any]).flatMap(Self.codexRequestUsage)
        return CodexRequestUsageRecord(
            timestamp: timestamp,
            threadID: threadID,
            sessionID: sessionID,
            responseID: responseID,
            turnID: Self.codexTurnID(from: payload),
            model: Self.codexModelEvidence(payload["model"] as? String),
            usage: usage,
            threadTotal: total,
            turnTotal: turnTotal.flatMap { Self.codexTotalsAtLeast($0, usage) ? $0 : nil })
    }

    private static func codexRequestUsage(_ usage: [String: Any]) -> CostUsageCodexTotals? {
        func integer(_ key: String, defaultValue: Int? = nil) -> Int? {
            guard let value = usage[key] else { return defaultValue }
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue >= 0,
                  number.doubleValue < Double(Int.max),
                  number.doubleValue.rounded(.towardZero) == number.doubleValue
            else { return nil }
            return number.intValue
        }
        guard let input = integer("input_tokens"), let output = integer("output_tokens"),
              let cached = integer("cached_input_tokens", defaultValue: 0), cached <= input,
              let reasoning = integer("reasoning_output_tokens", defaultValue: 0), reasoning <= output,
              !input.addingReportingOverflow(output).overflow
        else { return nil }
        return CostUsageCodexTotals(input: input, cached: cached, output: output, reasoning: reasoning)
    }

    private static func codexBareUsageInt(_ dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let number = dict[key] as? NSNumber {
                return max(0, number.intValue)
            }
        }
        return nil
    }

    private static func codexFastLineTimestampValidity(_ bytes: Data) -> Bool? {
        let timestamp = bytes.withUnsafeBytes { rawBytes in
            let rawBuffer = rawBytes.bindMemory(to: UInt8.self)
            guard !rawBuffer.isEmpty else { return nil as String? }
            return Self.extractJSONByteStringField(
                Self.codexJSONFieldTimestamp,
                from: rawBuffer,
                in: 0..<rawBuffer.count,
                atDepth: 1)
        }
        guard let timestamp else { return nil }
        return (Self.dayKeyFromTimestamp(timestamp) ?? Self.dayKeyFromParsedISO(timestamp)) != nil
    }

    private static func codexLineOrdinal(_ bytes: Data) -> Int? {
        bytes.withUnsafeBytes { rawBytes in
            let rawBuffer = rawBytes.bindMemory(to: UInt8.self)
            guard !rawBuffer.isEmpty else { return nil }
            return Self.extractJSONByteIntField(
                Self.codexJSONFieldOrdinal,
                from: rawBuffer,
                in: 0..<rawBuffer.count,
                atDepth: 1)
        }
    }

    static func parseCodexSessionIdentifier(
        fileURL: URL,
        checkCancellation: CancellationCheck? = nil) throws -> String?
    {
        try self.parseCodexSessionMetadata(fileURL: fileURL, checkCancellation: checkCancellation)?.sessionId
    }

    static let codexSessionMetadataMaxLineBytes = 256 * 1024

    private static func codexSessionMetadata(from obj: [String: Any]) -> CodexSessionMetadata? {
        guard obj["type"] as? String == "session_meta" else { return nil }
        let payload = obj["payload"] as? [String: Any]
        let concreteSessionId = [payload?["id"], obj["id"]]
            .compactMap { $0 as? String }.first { !$0.isEmpty }
        let sessionId = [
            concreteSessionId, payload?["session_id"] as? String, payload?["sessionId"] as? String,
            obj["session_id"] as? String, obj["sessionId"] as? String,
        ].compactMap(\.self).first { !$0.isEmpty }
        return CodexSessionMetadata(
            sessionId: sessionId,
            concreteSessionId: concreteSessionId,
            forkedFromId: Self.codexForkParentId(from: payload),
            forkTimestamp: payload?["timestamp"] as? String ?? obj["timestamp"] as? String,
            projectPath: Self.normalizedCodexProjectPath(payload?["cwd"] as? String),
            isSubagentThread: Self.codexIsSubagentThread(from: payload),
            subagentHistoryStartOrdinal: (payload?["subagent_history_start_ordinal"] as? NSNumber)?.intValue,
            historyBaseThreadId: Self.codexHistoryBaseThreadId(from: payload),
            requestSessionID: payload?["session_id"] as? String)
    }

    private static func parseCodexSessionMetadata(
        fileURL: URL,
        checkCancellation: CancellationCheck? = nil) throws -> CodexSessionMetadata?
    {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            self.log.warning(
                "Codex cost usage failed to open session file for session id parsing",
                metadata: ["path": fileURL.path, "error": error.localizedDescription])
            return nil
        }
        defer { try? handle.close() }

        var buffer = Data()
        var discardingOversizedLine = false

        func parseSessionMetadata(from lineData: Data) -> CodexSessionMetadata? {
            guard !lineData.isEmpty else { return nil }
            return autoreleasepool {
                guard let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
                else { return nil }
                return Self.codexSessionMetadata(from: obj)
            }
        }

        do {
            var matchedMetadata: CodexSessionMetadata?
            while true {
                let reachedEOF = try autoreleasepool { () throws -> Bool in
                    guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                        return true
                    }
                    try checkCancellation?()

                    var segmentStart = chunk.startIndex
                    while segmentStart < chunk.endIndex {
                        let newlineIndex = chunk[segmentStart...].firstIndex(of: 0x0A)
                        let segmentEnd = newlineIndex ?? chunk.endIndex

                        if !discardingOversizedLine {
                            let segmentCount = chunk.distance(from: segmentStart, to: segmentEnd)
                            let remainingBytes = Self.codexSessionMetadataMaxLineBytes - buffer.count
                            if segmentCount <= remainingBytes {
                                buffer.append(contentsOf: chunk[segmentStart..<segmentEnd])
                            } else {
                                // Release the retained prefix immediately. The buffer never exceeds the line limit.
                                buffer.removeAll(keepingCapacity: false)
                                discardingOversizedLine = true
                            }
                        }

                        guard let newlineIndex else { break }
                        if !discardingOversizedLine,
                           let metadata = parseSessionMetadata(from: buffer)
                        {
                            matchedMetadata = metadata
                            break
                        }
                        buffer.removeAll(keepingCapacity: true)
                        discardingOversizedLine = false
                        segmentStart = chunk.index(after: newlineIndex)
                    }

                    return false
                }
                if let matchedMetadata {
                    return matchedMetadata
                }
                if reachedEOF {
                    break
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            self.log.warning(
                "Codex cost usage failed while reading session file for session id parsing",
                metadata: ["path": fileURL.path, "error": error.localizedDescription])
            return nil
        }

        if !discardingOversizedLine,
           let metadata = parseSessionMetadata(from: buffer)
        {
            return metadata
        }
        return nil
    }

    static func codexFileIsSubagentThread(
        fileURL: URL,
        checkCancellation: CancellationCheck? = nil) throws -> Bool
    {
        try self.parseCodexSessionMetadata(
            fileURL: fileURL,
            checkCancellation: checkCancellation)?.isSubagentThread == true
    }

    static func parseCodexFile(
        fileURL: URL,
        range: CostUsageDayRange,
        startOffset: Int64 = 0,
        initialModel: String? = nil,
        initialTotals: CostUsageCodexTotals? = nil,
        initialRawTotalsBaseline: CostUsageCodexTotals? = nil,
        initialHasDivergentTotals: Bool = false,
        initialCodexTurnID: String? = nil,
        initialCodexUsageRowIndex: Int = 0,
        initialLastAcceptedTokenTimestampUnixMs: Int64? = nil,
        inheritedTotalsResolver: ((String, String) -> CodexForkBaseline)? = nil) -> CodexParseResult
    {
        let throwingResolver: ((String, String) throws -> CodexForkBaseline)? = inheritedTotalsResolver
            .map { resolver in
                { sessionId, timestamp in resolver(sessionId, timestamp) }
            }
        return (
            try? Self.parseCodexFileCancellable(
                fileURL: fileURL,
                range: range,
                startOffset: startOffset,
                initialModel: initialModel,
                initialTotals: initialTotals,
                initialRawTotalsBaseline: initialRawTotalsBaseline,
                initialHasDivergentTotals: initialHasDivergentTotals,
                initialCodexTurnID: initialCodexTurnID,
                initialCodexUsageRowIndex: initialCodexUsageRowIndex,
                initialLastAcceptedTokenTimestampUnixMs: initialLastAcceptedTokenTimestampUnixMs,
                inheritedTotalsResolver: throwingResolver,
                checkCancellation: nil)) ?? CodexParseResult(
            days: [:],
            parsedBytes: startOffset,
            lastModel: initialModel,
            lastTotals: initialTotals,
            lastCountedTotals: initialTotals,
            lastRawTotalsBaseline: initialRawTotalsBaseline,
            lastRawTotalsWatermark: initialRawTotalsBaseline,
            seenRawTotals: [],
            hasDivergentTotals: initialHasDivergentTotals,
            hasInterleavedTotals: false,
            lastCodexTurnID: initialCodexTurnID,
            sessionId: nil,
            forkedFromId: nil,
            dependsOnParentTotals: false,
            forkBaselineResolved: false,
            projectPath: nil,
            codexSession: CostUsageCodexSessionMetadata(
                sessionId: nil,
                forkedFromId: nil,
                cwd: nil,
                title: nil,
                startedAtUnixMs: nil,
                latestActivityUnixMs: nil,
                latestAcceptedUsageUnixMs: initialLastAcceptedTokenTimestampUnixMs),
            rows: [],
            tokenSnapshots: [],
            jsonlResumeState: nil,
            bufferedSubagentLines: nil,
            bufferedUnresolvedForkLines: nil)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func parseCodexFileCancellable(
        fileURL: URL,
        range: CostUsageDayRange,
        startOffset: Int64 = 0,
        initialModel: String? = nil,
        initialSessionID: String? = nil,
        initialTotals: CostUsageCodexTotals? = nil,
        initialRawTotalsBaseline: CostUsageCodexTotals? = nil,
        initialRawTotalsWatermark: CostUsageCodexTotals? = nil,
        initialSeenRawTotals: [CostUsageCodexTotals] = [],
        initialHasDivergentTotals: Bool = false,
        initialHasInterleavedTotals: Bool = false,
        initialCodexTurnID: String? = nil,
        initialCodexUsageRowIndex: Int = 0,
        initialLastAcceptedTokenTimestampUnixMs: Int64? = nil,
        initialBufferedSubagentLines: [CodexBufferedFastLine]? = nil,
        initialBufferedUnresolvedForkLines: [CodexBufferedFastLine]? = nil,
        includeInitialBufferedTokenSnapshots: Bool = false,
        initialJSONLResumeState: CostUsageJsonl.ResumeState? = nil,
        initialForkAccountingState: CodexForkAccountingState? = nil,
        initialRequestLedgerState: CodexRequestLedgerState? = nil,
        initialRequestLedgerRows: [CodexUsageRow] = [],
        scanTargetSize: Int64? = nil,
        maxBytesToRead: Int64? = nil,
        shouldStopReading: ((Int64) -> Bool)? = nil,
        inheritedTotalsResolver: ((String, String) throws -> CodexForkBaseline)? = nil,
        checkCancellation: CancellationCheck? = nil) throws -> CodexParseResult
    {
        var currentModel = initialModel
        var previousTotals = initialTotals
        var sessionId = initialForkAccountingState?.metadata.sessionId ?? initialSessionID
        var forkedFromId = initialForkAccountingState?.metadata.forkedFromId
        var historyBaseThreadId = initialForkAccountingState?.metadata.historyBaseThreadId
        var projectPath = initialForkAccountingState?.metadata.projectPath
        var isSubagentThread = false
        var didCaptureLeafMetadata = sessionId != nil
        var forkTimestamp = initialForkAccountingState?.metadata.forkTimestamp
        var subagentHistoryStartOrdinal: Int?
        var subagentCounterSemantics: CodexSubagentCounterSemantics?
        var usesLocalSubagentBoundary = false
        var candidateBoundaryDependsOnParentTotals = false
        var parentConfirmedLocalBoundary = false
        var suppressUnownedCopiedPrefix = false
        var codexSession = CostUsageCodexSessionMetadata(
            sessionId: sessionId,
            forkedFromId: forkedFromId,
            cwd: projectPath,
            title: nil,
            startedAtUnixMs: nil,
            latestActivityUnixMs: nil)
        var inheritedTotals = initialForkAccountingState?.inheritedTotals
        var remainingInheritedTotals = initialForkAccountingState?.remainingInheritedTotals
        var forkBaselineResolved = initialForkAccountingState != nil
        var hasUnresolvedForkBaseline = false
        var currentTurnID = initialCodexTurnID
        var codexUsageRowIndex = initialCodexUsageRowIndex
        var rawTotalsBaseline = initialRawTotalsBaseline ?? initialTotals
        var sawDivergentTotals = initialHasDivergentTotals
        var tracker = CodexTotalsTracker(
            watermark: initialRawTotalsWatermark ?? initialRawTotalsBaseline ?? initialTotals,
            seenRawTotals: initialSeenRawTotals,
            sawInterleavedTotals: initialHasInterleavedTotals)
        var deferredError: Error?

        var days: [String: [String: [Int]]] = [:]
        var rows: [CodexUsageRow] = []
        var rowSourceEndOffsets: [Int: Int64] = [:]
        var tokenSnapshots: [CostUsageCodexTokenSnapshot] = []
        var lastAcceptedTokenTimestampUnixMs = initialLastAcceptedTokenTimestampUnixMs
        var requestLedger = initialRequestLedgerState ?? CodexRequestLedgerState()
        var replacedLegacyRowIndices: Set<Int> = []
        let retainedRows = Dictionary(initialRequestLedgerRows.compactMap { row in
            row.eventIndex.map { ($0, row) }
        }, uniquingKeysWith: { first, _ in first })

        func mirrorKey(
            turnID: String?,
            usage: CostUsageCodexTotals,
            total: CostUsageCodexTotals?,
            timestamp: String?) -> String
        {
            var components: [String] = [
                turnID ?? "",
                String(usage.input),
                String(usage.cached),
                String(usage.output),
                String(usage.reasoning ?? 0),
            ]
            components.append(total.map { String($0.input) } ?? "")
            components.append(total.map { String($0.cached) } ?? "")
            components.append(total.map { String($0.output) } ?? "")
            components.append(timestamp ?? "")
            return components.joined(separator: "\u{1F}")
        }

        func adjacentMirrorKeys(
            turnID: String?,
            usage: CostUsageCodexTotals,
            total: CostUsageCodexTotals?,
            timestamp: String) -> Set<String>
        {
            var keys: Set<String> = [mirrorKey(turnID: turnID, usage: usage, total: nil, timestamp: timestamp)]
            // The counter alias deliberately omits time; request size alone never establishes a mirror.
            if let total { keys.insert(mirrorKey(turnID: turnID, usage: usage, total: total, timestamp: nil)) }
            return keys
        }

        func observeLegacyMirror(
            usage: CostUsageCodexTotals?,
            turnID: String?,
            total: CostUsageCodexTotals?,
            timestamp: String) -> (snapshot: String, adjacent: Set<String>)?
        {
            guard let usage else { return nil }
            let snapshot = mirrorKey(turnID: turnID, usage: usage, total: total, timestamp: timestamp)
            let adjacent = adjacentMirrorKeys(turnID: turnID, usage: usage, total: total, timestamp: timestamp)
            requestLedger.beginLegacyObservation(keys: adjacent, snapshot: snapshot)
            return (snapshot, adjacent)
        }

        func handleRequestLedger(_ record: CodexRequestUsageRecord, endOffset: Int64?) {
            guard !suppressUnownedCopiedPrefix, record.threadID == sessionId,
                  record.sessionID == nil || record.sessionID == (requestLedger.sessionID ?? sessionId),
                  let day = Self.dayKeyFromTimestamp(record.timestamp, calendar: range.calendar)
                  ?? Self.dayKeyFromParsedISO(record.timestamp, calendar: range.calendar)
            else { return }
            let usage = record.usage
            let responseID = record.responseID
            let timestamp = record.timestamp
            let turnID = record.turnID ?? currentTurnID ?? requestLedger.activeTurnID
            var keys = [
                mirrorKey(turnID: turnID, usage: usage, total: record.threadTotal, timestamp: timestamp),
                mirrorKey(turnID: turnID, usage: usage, total: nil, timestamp: timestamp),
            ]
            if let turnTotal = record.turnTotal {
                keys.append(mirrorKey(turnID: turnID, usage: usage, total: turnTotal, timestamp: timestamp))
            }
            // Identity, rather than cumulative counters, proves that a reset is a new request.
            // Copied parent records fail the ownership check above even if the parent is unavailable.
            let isReplay = requestLedger.responseIDs.contains(responseID)
            let mirror = keys.first(where: { requestLedger.legacyRowIndices[$0] != nil })
            let adjacentKeys = adjacentMirrorKeys(
                turnID: turnID, usage: usage, total: record.threadTotal, timestamp: timestamp)
            let adjacentIndex = requestLedger.pendingLegacyMirrors?.isDisjoint(with: adjacentKeys) == false
                ? requestLedger.pendingLegacyRowIndex : nil
            let mirrorIndex = mirror.flatMap { requestLedger.legacyRowIndices[$0] } ?? adjacentIndex
            requestLedger.pendingLegacyMirrors = nil
            requestLedger.pendingLegacyRowIndex = nil
            requestLedger.pendingLedgerMirrors = mirrorIndex == nil ? adjacentKeys : nil
            requestLedger.pendingLedgerResponseID = mirrorIndex == nil ? responseID : nil
            let legacyRow = mirrorIndex.flatMap { index in
                rows.first(where: { $0.eventIndex == index }) ?? retainedRows[index]
            }
            if let legacyRow {
                keys.append(contentsOf: legacyRow.requestMirrorKeys ?? [])
            }
            let base = requestLedger.countedUsage ?? .init(input: 0, cached: 0, output: 0)
            if !isReplay {
                guard !base.input.addingReportingOverflow(usage.input).overflow,
                      !base.cached.addingReportingOverflow(usage.cached).overflow,
                      !base.output.addingReportingOverflow(usage.output).overflow,
                      !Self.codexAddTotals(base, usage).input.addingReportingOverflow(
                          Self.codexAddTotals(base, usage).output).overflow
                else { return }
            }
            requestLedger.rememberMirrors(keys, responseID: responseID)
            requestLedger.responseIDs.insert(responseID)

            if let index = mirrorIndex, let legacy = legacyRow {
                requestLedger.legacyRowIndices = requestLedger.legacyRowIndices.filter { $0.value != index }
                replacedLegacyRowIndices.insert(index)
                if rows.contains(where: { $0.eventIndex == index }) {
                    add(
                        dayKey: legacy.day,
                        model: legacy.model,
                        input: -legacy.input,
                        cached: -legacy.cached,
                        output: -legacy.output)
                    rows.removeAll { $0.eventIndex == index }
                    rowSourceEndOffsets.removeValue(forKey: index)
                }
            }
            guard !isReplay else { return }
            let model = record.model
                ?? turnID.flatMap { requestLedger.turnModels[$0] }
                ?? (turnID == currentTurnID || turnID == requestLedger.activeTurnID
                    ? Self.codexModelEvidence(currentModel) : nil)
                ?? CostUsagePricing.codexUnattributedModel
            requestLedger.countedUsage = Self.codexAddTotals(base, usage)
            appendUsage(
                usage,
                day: day,
                model: model,
                timestamp: timestamp,
                turnID: turnID,
                responseID: responseID,
                mirrorKeys: keys,
                retainedPricing: legacyRow,
                endOffset: endOffset)
            observeTimestamp(timestamp)
            lastAcceptedTokenTimestampUnixMs = unixMilliseconds(from: timestamp)
        }

        func add(dayKey: String, model: String, input: Int, cached: Int, output: Int) {
            guard CostUsageDayRange.isInRange(dayKey: dayKey, since: range.scanSinceKey, until: range.scanUntilKey)
            else { return }
            let normModel = CostUsagePricing.normalizeCodexModel(model)

            var dayModels = days[dayKey] ?? [:]
            var packed = dayModels[normModel] ?? [0, 0, 0]
            packed[0] = (packed[safe: 0] ?? 0) + input
            packed[1] = (packed[safe: 1] ?? 0) + cached
            packed[2] = (packed[safe: 2] ?? 0) + output
            dayModels[normModel] = packed
            days[dayKey] = dayModels
        }

        @discardableResult
        func appendUsage(
            _ usage: CostUsageCodexTotals,
            day: String,
            model: String,
            timestamp: String?,
            turnID: String?,
            responseID: String? = nil,
            mirrorKeys: [String]? = nil,
            retainedPricing: CodexUsageRow? = nil,
            endOffset: Int64? = nil) -> Int
        {
            let index = codexUsageRowIndex
            codexUsageRowIndex += 1
            let normalizedModel = CostUsagePricing.normalizeCodexModel(model)
            add(dayKey: day, model: normalizedModel, input: usage.input, cached: usage.cached, output: usage.output)
            guard CostUsageDayRange.isInRange(dayKey: day, since: range.scanSinceKey, until: range.scanUntilKey)
            else { return index }
            // A typed mirror changes request identity, not the matching row's saved billing evidence.
            let pricing = retainedPricing.flatMap { $0.model == normalizedModel ? $0 : nil }
            rows.append(CodexUsageRow(
                day: day,
                model: normalizedModel,
                rawModel: model,
                turnID: turnID,
                eventIndex: index,
                timestampUnixMs: unixMilliseconds(from: timestamp),
                input: usage.input,
                cached: usage.cached,
                output: usage.output,
                reasoning: usage.reasoning,
                knownCostNanos: pricing?.knownCostNanos,
                unpricedTokens: pricing?.unpricedTokens,
                pricingModel: pricing?.pricingModel,
                pricingMode: pricing?.pricingMode,
                responseID: responseID,
                requestMirrorKeys: mirrorKeys))
            rowSourceEndOffsets[index] = endOffset
            return index
        }

        func unixMilliseconds(from timestamp: String?) -> Int64? {
            guard let timestamp,
                  let date = Self.dateFromTimestamp(timestamp)
            else { return nil }
            return Int64((date.timeIntervalSince1970 * 1000).rounded())
        }

        /// Counts one-shot codex exec / headless rollout rows whose usage object is not wrapped in the
        /// interactive event_msg/token_count envelope. Tokscale parity: accept OpenAI and completion-style
        /// aliases, subtract cached input from billed input, and fall back to the last accepted timestamp
        /// so timestamp-less responses remain attributable to the active day.
        func handleBareUsage(_ record: CodexBareUsageRecord, sourceEndOffset: Int64?) {
            guard !suppressUnownedCopiedPrefix, !hasUnresolvedForkBaseline else { return }
            let dayKey: String
            let resolvedTimestampUnixMs: Int64?
            if let timestamp = record.timestamp {
                guard let parsedDayKey = Self.dayKeyFromTimestamp(timestamp, calendar: range.calendar)
                    ?? Self.dayKeyFromParsedISO(timestamp, calendar: range.calendar)
                else { return }
                dayKey = parsedDayKey
                resolvedTimestampUnixMs = unixMilliseconds(from: timestamp)
                observeTimestamp(timestamp)
            } else {
                guard let timestampUnixMs = lastAcceptedTokenTimestampUnixMs else { return }
                dayKey = CostUsageDayRange.dayKey(
                    from: Date(timeIntervalSince1970: Double(timestampUnixMs) / 1000),
                    calendar: range.calendar)
                resolvedTimestampUnixMs = timestampUnixMs
            }
            let model = Self.codexModelEvidence(record.model)
                ?? Self.codexModelEvidence(currentModel)
                ?? CostUsagePricing.codexUnattributedModel
            let normModel = CostUsagePricing.normalizeCodexModel(model)

            let eventIndex = codexUsageRowIndex
            codexUsageRowIndex += 1
            add(
                dayKey: dayKey,
                model: normModel,
                input: record.totals.input,
                cached: record.totals.cached,
                output: record.totals.output)
            if CostUsageDayRange.isInRange(dayKey: dayKey, since: range.scanSinceKey, until: range.scanUntilKey) {
                rows.append(CodexUsageRow(
                    day: dayKey,
                    model: normModel,
                    rawModel: model,
                    turnID: currentTurnID,
                    eventIndex: eventIndex,
                    timestampUnixMs: resolvedTimestampUnixMs,
                    input: record.totals.input,
                    cached: record.totals.cached,
                    output: record.totals.output,
                    reasoning: record.totals.reasoning))
                if let sourceEndOffset {
                    rowSourceEndOffsets[eventIndex] = sourceEndOffset
                }
            }
            if let resolvedTimestampUnixMs {
                lastAcceptedTokenTimestampUnixMs = resolvedTimestampUnixMs
            }
        }

        func observeTimestamp(_ timestamp: String?) {
            guard let unixMs = unixMilliseconds(from: timestamp) else { return }
            codexSession.startedAtUnixMs = switch codexSession.startedAtUnixMs {
            case let current?: min(current, unixMs)
            case nil: unixMs
            }
            codexSession.latestActivityUnixMs = switch codexSession.latestActivityUnixMs {
            case let current?: max(current, unixMs)
            case nil: unixMs
            }
        }

        func observeCwd(_ value: String?) {
            guard let value = Self.codexModelEvidence(value) else { return }
            codexSession.cwd = value
        }

        func resolveForkBaseline(parentSessionId: String, forkedAt: String) throws {
            guard !forkBaselineResolved else { return }
            guard let inheritedTotalsResolver else { return }
            forkBaselineResolved = true
            switch try inheritedTotalsResolver(parentSessionId, forkedAt) {
            case let .resolved(totals):
                inheritedTotals = totals
                remainingInheritedTotals = totals
                hasUnresolvedForkBaseline = false
            case .unresolved:
                hasUnresolvedForkBaseline = true
            }
        }

        func configureForkAccountingIfReady() throws {
            guard let forkedFromId else { return }
            if isSubagentThread, subagentCounterSemantics == nil {
                return
            }
            if subagentCounterSemantics == .independent || usesLocalSubagentBoundary {
                forkBaselineResolved = true
                inheritedTotals = nil
                remainingInheritedTotals = nil
                hasUnresolvedForkBaseline = false
                return
            }
            try resolveForkBaseline(
                parentSessionId: forkedFromId,
                forkedAt: forkTimestamp ?? "")
        }

        /// Codex Desktop paginated rollouts keep the original `forked_from_id` while continuing the
        /// same cumulative counter in a new file. The ancestor snapshot is then far below the first
        /// `total - last` gap (the previous page's last total), and totals-only fork accounting bills
        /// the whole thread to the new page. Raise the inherited baseline to that local proof only
        /// when `history_base.thread_id` is not the fork parent already subtracted by #1164.
        func raiseInheritedBaselineIfContinuedCounter(
            total: CostUsageCodexTotals,
            last: CostUsageCodexTotals)
        {
            guard previousTotals == nil, let currentInherited = inheritedTotals else { return }
            guard let historyBaseThreadId,
                  !CodexSubagentRolloutShape.sameConcreteSessionID(historyBaseThreadId, forkedFromId)
            else { return }
            guard Self.codexTotalsAtLeast(total, last) else { return }
            let localInherited = Self.codexTotalDelta(from: last, to: total)
            guard localInherited.input > 0 || localInherited.cached > 0 || localInherited.output > 0 else {
                return
            }
            guard Self.codexTotalsAtLeast(localInherited, currentInherited),
                  !Self.codexTotalsEqual(localInherited, currentInherited)
            else { return }
            self.log.debug(
                "Codex cost usage raised inherited fork baseline from first total-last",
                metadata: [
                    "sessionId": sessionId ?? "unknown",
                    "forkedFromId": forkedFromId ?? "unknown",
                    "historyBaseThreadId": historyBaseThreadId,
                    "ancestorInput": String(currentInherited.input),
                    "localInput": String(localInherited.input),
                ])
            inheritedTotals = localInherited
            remainingInheritedTotals = localInherited
        }

        func handleSessionMetadata(_ metadata: CodexSessionMetadata) throws {
            // The first parsed session_meta is the authoritative leaf. Copied prefixes can
            // contain many embedded ancestor metas; they are shape evidence, never new identity.
            if didCaptureLeafMetadata {
                // A same-leaf restart may add metadata that was absent from the initial record.
                // Enrich missing fork/project fields without allowing an ancestor to replace identity.
                guard CodexSubagentRolloutShape.sameConcreteSessionID(metadata.sessionId, sessionId) else { return }
                isSubagentThread = isSubagentThread || metadata.isSubagentThread
                if requestLedger.sessionID == nil {
                    requestLedger.sessionID = metadata.requestSessionID ?? metadata.sessionId
                }
                if forkedFromId == nil, let enrichedParentID = metadata.forkedFromId {
                    forkedFromId = enrichedParentID
                    codexSession.forkedFromId = enrichedParentID
                    forkTimestamp = metadata.forkTimestamp ?? forkTimestamp
                    try configureForkAccountingIfReady()
                }
                if codexSession.concreteSessionId == nil {
                    codexSession.concreteSessionId = metadata.concreteSessionId
                }
                if projectPath == nil {
                    projectPath = metadata.projectPath
                }
                if subagentHistoryStartOrdinal == nil {
                    subagentHistoryStartOrdinal = metadata.subagentHistoryStartOrdinal
                }
                if historyBaseThreadId == nil {
                    historyBaseThreadId = metadata.historyBaseThreadId
                }
                observeTimestamp(metadata.forkTimestamp)
                if codexSession.cwd == nil {
                    observeCwd(metadata.projectPath)
                }
                return
            }
            didCaptureLeafMetadata = true
            sessionId = metadata.sessionId
            requestLedger.sessionID = metadata.requestSessionID ?? metadata.sessionId
            forkedFromId = metadata.forkedFromId
            historyBaseThreadId = metadata.historyBaseThreadId
            forkTimestamp = metadata.forkTimestamp
            projectPath = metadata.projectPath
            subagentHistoryStartOrdinal = metadata.subagentHistoryStartOrdinal
            codexSession.sessionId = metadata.sessionId
            codexSession.concreteSessionId = metadata.concreteSessionId
            codexSession.forkedFromId = metadata.forkedFromId
            observeTimestamp(metadata.forkTimestamp)
            observeCwd(metadata.projectPath)
            isSubagentThread = metadata.isSubagentThread
            try configureForkAccountingIfReady()
        }

        // swiftlint:disable:next function_body_length cyclomatic_complexity
        func handleTokenCount(_ record: CodexTokenCountRecord, sourceEndOffset: Int64?) throws {
            observeTimestamp(record.timestamp)
            guard let dayKey = Self.dayKeyFromTimestamp(record.timestamp, calendar: range.calendar)
                ?? Self.dayKeyFromParsedISO(record.timestamp, calendar: range.calendar)
            else { return }
            guard !suppressUnownedCopiedPrefix else { return }

            let model = Self.codexModelEvidence(currentModel)
                ?? Self.codexModelEvidence(record.model)
                ?? CostUsagePricing.codexUnattributedModel
            let total = record.total
            let last = record.last
            let mirrorTurnID = record.turnID ?? currentTurnID ?? requestLedger.activeTurnID
            var mirror = observeLegacyMirror(
                usage: last, turnID: mirrorTurnID, total: total, timestamp: record.timestamp)
            defer { requestLedger.clearPendingMirrors(when: mirror == nil) }
            // A cumulative fork counter is not attributable until either the parent snapshot or
            // a trustworthy child-owned suffix establishes the inherited baseline. Publishing
            // best-effort `last` rows here can replay billions of copied-prefix tokens.
            guard !hasUnresolvedForkBaseline else { return }
            if forkedFromId != nil,
               previousTotals == nil,
               let total, let last,
               Self.codexTotalsEqual(total, last),
               let baseline = inheritedTotals ?? rawTotalsBaseline,
               baseline.input > 0 || baseline.cached > 0 || baseline.output > 0,
               Self.codexTotalsAtLeast(total, baseline)
            {
                // The first post-boundary total==last can be either a copied inherited
                // snapshot or a genuinely new counter. Neither interpretation is proven
                // by these fields, so retain the event and leave this fork incomplete.
                hasUnresolvedForkBaseline = true
                return
            }
            if let total, let last {
                raiseInheritedBaselineIfContinuedCounter(total: total, last: last)
            }

            var deltaInput = 0
            var deltaCached = 0
            var deltaOutput = 0
            var deltaReasoning: Int?

            func adjustedLastDelta(_ rawDelta: CostUsageCodexTotals) -> CostUsageCodexTotals {
                guard var remaining = remainingInheritedTotals else { return rawDelta }

                let adjusted = CostUsageCodexTotals(
                    input: max(0, rawDelta.input - remaining.input),
                    cached: max(0, rawDelta.cached - remaining.cached),
                    output: max(0, rawDelta.output - remaining.output),
                    reasoning: Self.codexSubtractOptional(rawDelta.reasoning, remaining.reasoning))

                remaining.input = max(0, remaining.input - rawDelta.input)
                remaining.cached = max(0, remaining.cached - rawDelta.cached)
                remaining.output = max(0, remaining.output - rawDelta.output)
                remaining.reasoning = Self.codexSubtractOptional(remaining.reasoning, rawDelta.reasoning)
                remainingInheritedTotals = if remaining.input == 0, remaining.cached == 0,
                                              remaining.output == 0
                {
                    nil
                } else {
                    remaining
                }

                return adjusted
            }

            // Fork totals are normalized against the selected baseline. Classified independent
            // counters and locally delimited suffixes intentionally bypass the parent baseline.
            let adjustedTotal: CostUsageCodexTotals? = total.map { rawTotals in
                guard let inheritedTotals, !hasUnresolvedForkBaseline else { return rawTotals }
                return CostUsageCodexTotals(
                    input: max(0, rawTotals.input - inheritedTotals.input),
                    cached: max(0, rawTotals.cached - inheritedTotals.cached),
                    output: max(0, rawTotals.output - inheritedTotals.output),
                    reasoning: Self.codexSubtractOptional(rawTotals.reasoning, inheritedTotals.reasoning))
            }

            if let adjustedTotal {
                // Only committed observations enter the seen set. Replacing this with a bare
                // watermark-equality check would skip first-time fork baseline bookkeeping.
                // Post-latch containment remains the load-bearing overcount guard.
                if tracker.isSeen(adjustedTotal) {
                    return
                }
                let staleBaseline = tracker.watermark ?? rawTotalsBaseline
                if let previousTotal = staleBaseline,
                   !hasUnresolvedForkBaseline,
                   Self.codexLooksLikeStaleRegression(
                       current: adjustedTotal,
                       previous: previousTotal,
                       last: last ?? .init(input: 0, cached: 0, output: 0))
                {
                    // Keep the cancellable parser aligned with the snapshot accumulator:
                    // stale regressions are skipped before they can reset the baseline or
                    // latch interleaved mode.
                    return
                }
                tracker.latchIfBelowWatermark(adjustedTotal)
            }
            let watermarkBaseline = tracker.watermark ?? rawTotalsBaseline
            defer {
                if let adjustedTotal {
                    tracker.commitObserved(adjustedTotal)
                }
            }

            func totalsDerivedDelta(to currentTotals: CostUsageCodexTotals) -> CostUsageCodexTotals {
                if tracker.sawInterleavedTotals {
                    return Self.codexContainedTotalDelta(
                        watermark: watermarkBaseline,
                        counted: previousTotals,
                        current: currentTotals)
                }
                if sawDivergentTotals {
                    return Self.codexDivergentTotalDelta(
                        rawBaseline: watermarkBaseline,
                        countedBaseline: previousTotals,
                        current: currentTotals)
                }
                return Self.codexTotalDelta(from: watermarkBaseline, to: currentTotals)
            }

            func commitDelta(_ delta: CostUsageCodexTotals, rawBaseline: CostUsageCodexTotals) {
                deltaInput = delta.input
                deltaCached = delta.cached
                deltaOutput = delta.output
                deltaReasoning = delta.reasoning
                let prev = previousTotals ?? .init(
                    input: 0,
                    cached: 0,
                    output: 0,
                    reasoning: delta.reasoning == nil ? nil : 0)
                previousTotals = Self.codexAddTotals(prev, delta)
                rawTotalsBaseline = rawBaseline
                if !Self.codexTotalsEqual(rawTotalsBaseline, previousTotals) {
                    sawDivergentTotals = true
                }
            }

            if let currentTotals = adjustedTotal,
               forkedFromId != nil,
               !hasUnresolvedForkBaseline
            {
                // Non-interleaved forks keep totals-only accounting (#1164 / 45b68c34).
                // After latch, use post-latch containment capped by last when present.
                let delta: CostUsageCodexTotals = if tracker.sawInterleavedTotals {
                    Self.codexPostLatchEventDelta(
                        watermark: watermarkBaseline,
                        counted: previousTotals,
                        current: currentTotals,
                        adjustedLast: last.map { adjustedLastDelta($0) })
                } else {
                    totalsDerivedDelta(to: currentTotals)
                }
                commitDelta(delta, rawBaseline: currentTotals)
                remainingInheritedTotals = nil
            } else if let last {
                let rawDelta = last
                let hadRemainingInheritedTotals = remainingInheritedTotals != nil
                var adjustedDelta = adjustedLastDelta(rawDelta)
                let prev = previousTotals ?? .init(
                    input: 0,
                    cached: 0,
                    output: 0,
                    reasoning: adjustedDelta.reasoning == nil ? nil : 0)

                if let currentTotals = adjustedTotal, !hasUnresolvedForkBaseline {
                    if tracker.sawInterleavedTotals {
                        adjustedDelta = Self.codexPostLatchEventDelta(
                            watermark: watermarkBaseline,
                            counted: previousTotals,
                            current: currentTotals,
                            adjustedLast: adjustedDelta)
                        remainingInheritedTotals = nil
                    } else {
                        let totalDelta = Self.codexTotalDelta(from: watermarkBaseline, to: currentTotals)
                        if !hadRemainingInheritedTotals,
                           Self.codexShouldPreferTotalDelta(
                               rawBaseline: watermarkBaseline,
                               currentTotal: currentTotals,
                               totalDelta: totalDelta,
                               lastDelta: rawDelta,
                               sawDivergentTotals: sawDivergentTotals)
                        {
                            adjustedDelta = totalDelta
                            remainingInheritedTotals = nil
                        }
                    }
                    commitDelta(adjustedDelta, rawBaseline: currentTotals)
                } else {
                    let countedTotals = Self.codexAddTotals(prev, adjustedDelta)
                    deltaInput = adjustedDelta.input
                    deltaCached = adjustedDelta.cached
                    deltaOutput = adjustedDelta.output
                    deltaReasoning = adjustedDelta.reasoning
                    previousTotals = countedTotals
                    rawTotalsBaseline = countedTotals
                    tracker.raiseWatermark(to: countedTotals)
                }
            } else if let currentTotals = adjustedTotal {
                commitDelta(totalsDerivedDelta(to: currentTotals), rawBaseline: currentTotals)
                remainingInheritedTotals = nil
            } else {
                return
            }

            let deltaUsage = CostUsageCodexTotals(
                input: deltaInput, cached: deltaCached, output: deltaOutput, reasoning: deltaReasoning)
            if mirror == nil {
                mirror = observeLegacyMirror(
                    usage: deltaUsage, turnID: mirrorTurnID, total: total, timestamp: record.timestamp)
            }

            // Observe legacy counters even when the ledger owns the row. Later legacy-only events
            // still need their original baseline and replay/containment protection.
            if let key = mirror?.snapshot, requestLedger.mirroredResponses?[key] != nil {
                return
            }
            if deltaInput == 0, deltaCached == 0, deltaOutput == 0 {
                return
            }
            if let timestampUnixMs = unixMilliseconds(from: record.timestamp) {
                lastAcceptedTokenTimestampUnixMs = timestampUnixMs
            }
            let eventIndex = appendUsage(
                deltaUsage,
                day: dayKey,
                model: model,
                timestamp: record.timestamp,
                turnID: record.turnID ?? currentTurnID,
                mirrorKeys: mirror.map { [$0.snapshot] },
                endOffset: sourceEndOffset)
            if let key = mirror?.snapshot { requestLedger.legacyRowIndices[key] = eventIndex }
            requestLedger.pendingLegacyMirrors = mirror?.adjacent
            requestLedger.pendingLegacyRowIndex = eventIndex
        }

        func processFastLine(_ fastLine: CodexFastLine, sourceEndOffset: Int64?) throws {
            switch fastLine {
            case let .sessionMeta(metadata):
                try handleSessionMetadata(metadata)
            case let .turnContext(metadata):
                requestLedger.clearPendingMirrors()
                observeTimestamp(metadata.timestamp)
                observeCwd(metadata.cwd)
                if let title = Self.codexModelEvidence(metadata.title) { codexSession.title = title }
                if let turnID = metadata.turnID {
                    requestLedger.activeTurnID = turnID
                }
                if let model = metadata.model {
                    // An explicitly blank context clears stale model evidence; an omitted field preserves it.
                    currentModel = Self.codexModelEvidence(model)
                }
                if let turnID = metadata.turnID, let model = Self.codexModelEvidence(currentModel) {
                    requestLedger.turnModels[turnID] = model
                }
            case .interAgentCommunication:
                break
            case let .taskStarted(turnID):
                requestLedger.clearPendingMirrors()
                currentTurnID = turnID
            case let .tokenCount(record):
                try handleTokenCount(record, sourceEndOffset: sourceEndOffset)
            case let .bareUsage(record):
                handleBareUsage(record, sourceEndOffset: sourceEndOffset)
            case let .tokenUsageRecord(record):
                handleRequestLedger(record, endOffset: sourceEndOffset)
            }
        }

        let maxLineBytes = 256 * 1024
        // Bumped from 32KB to maxLineBytes in 0.23.3: Codex CLI 0.125+ emits
        // turn_context lines ~38–41KB (bundled user_instructions / project
        // AGENTS.md). The previous 32KB cap silently truncated every
        // turn_context, so currentModel never updated and ~93%+ of tokens
        // fell through to the `?? "gpt-5"` default below — masking real
        // gpt-5.4 / gpt-5.5 attribution. Matching Claude/Pi scanners which
        // already use maxLineBytes here.
        let prefixBytes = maxLineBytes

        var pendingSubagentLines = initialBufferedSubagentLines
        var bufferedUnresolvedForkLines = initialBufferedUnresolvedForkLines
        var authoritativeSessionMetadataLine: CodexBufferedFastLine?

        // A staged full replacement does not persist event snapshots until it commits. Restore
        // snapshots from the buffered prefix so the completion pass can atomically replace the
        // previous snapshot generation rather than appending only the newly read suffix.
        if includeInitialBufferedTokenSnapshots {
            let initialSnapshotBuffers = (initialBufferedSubagentLines ?? [])
                + (initialBufferedUnresolvedForkLines ?? [])
            tokenSnapshots.reserveCapacity(initialSnapshotBuffers.count)
            for buffered in initialSnapshotBuffers {
                guard case let .tokenCount(record) = buffered.line,
                      record.last != nil || record.total != nil
                else { continue }
                tokenSnapshots.append(CostUsageCodexTokenSnapshot(
                    timestamp: record.timestamp,
                    last: record.last,
                    total: record.total,
                    endOffset: buffered.endOffset))
            }
        }

        if let initialBufferedSubagentLines, startOffset > 0 {
            for buffered in initialBufferedSubagentLines {
                guard case let .sessionMeta(metadata) = buffered.line else { continue }
                try handleSessionMetadata(metadata)
            }
        } else if startOffset == 0,
                  let metadata = try Self.parseCodexSessionMetadata(
                      fileURL: fileURL,
                      checkCancellation: checkCancellation)
        {
            try handleSessionMetadata(metadata)
            if metadata.isSubagentThread {
                // Subagent provenance can omit a fork id. Buffer parsed events, not JSON, so
                // classification remains one disk pass and reuses the existing totals reducer.
                pendingSubagentLines = []
            }
        }
        if let initialBufferedUnresolvedForkLines, startOffset > 0 {
            for buffered in initialBufferedUnresolvedForkLines {
                guard case let .sessionMeta(metadata) = buffered.line else { continue }
                try handleSessionMetadata(metadata)
            }
            if !hasUnresolvedForkBaseline {
                for buffered in initialBufferedUnresolvedForkLines {
                    try processFastLine(buffered.line, sourceEndOffset: buffered.endOffset)
                    if hasUnresolvedForkBaseline { break }
                }
                if !hasUnresolvedForkBaseline {
                    bufferedUnresolvedForkLines = nil
                }
            }
        }

        func routeFastLine(
            _ fastLine: CodexFastLine,
            lineIndex: Int,
            ordinal: Int?,
            endOffset: Int64) throws
        {
            let bufferedLine = Self.CodexBufferedFastLine(
                lineIndex: lineIndex,
                ordinal: ordinal,
                endOffset: endOffset,
                line: fastLine)
            if case let .sessionMeta(metadata) = fastLine,
               authoritativeSessionMetadataLine == nil,
               CodexSubagentRolloutShape.sameConcreteSessionID(metadata.sessionId, sessionId)
            {
                authoritativeSessionMetadataLine = bufferedLine
            }
            if case let .tokenCount(record) = fastLine, record.last != nil || record.total != nil {
                tokenSnapshots.append(CostUsageCodexTokenSnapshot(
                    timestamp: record.timestamp,
                    last: record.last,
                    total: record.total,
                    endOffset: endOffset))
            }
            if pendingSubagentLines != nil {
                pendingSubagentLines?.append(bufferedLine)
            } else {
                try processFastLine(fastLine, sourceEndOffset: endOffset)
                if hasUnresolvedForkBaseline {
                    if bufferedUnresolvedForkLines == nil {
                        if let metadataLine = authoritativeSessionMetadataLine,
                           metadataLine.lineIndex != lineIndex
                        {
                            bufferedUnresolvedForkLines = [metadataLine]
                        } else {
                            bufferedUnresolvedForkLines = []
                        }
                    }
                    bufferedUnresolvedForkLines?.append(bufferedLine)
                }
            }
        }

        var parsedBytes: Int64
        let targetSize = min(
            scanTargetSize ?? Self.codexFileMetadata(fileURL: fileURL).size,
            Self.codexFileMetadata(fileURL: fileURL).size)
        var physicalLineIndex = (initialBufferedSubagentLines?.last?.lineIndex ?? -1) + 1
        var jsonlResumeState = initialJSONLResumeState
        do {
            let scanProgress = try CostUsageJsonl.scanBounded(
                fileURL: fileURL,
                offset: startOffset,
                maxLineBytes: maxLineBytes,
                prefixBytes: prefixBytes,
                maxBytesToRead: maxBytesToRead,
                resumeState: initialJSONLResumeState,
                shouldStop: shouldStopReading,
                checkCancellation: checkCancellation,
                onLine: { line in
                    let lineIndex = physicalLineIndex
                    physicalLineIndex += 1
                    if deferredError != nil {
                        return
                    }
                    guard !line.bytes.isEmpty else { return }
                    if line.wasTruncated {
                        // `turn_context` can carry very large prompts, but its model usually appears near the start.
                        // A truncated line cannot be structurally validated with Foundation, so
                        // only accept the canonical root discriminator to avoid prompt-text hits.
                        let truncatedTurnContext = Self.extractCodexTruncatedTurnContext(from: line.bytes)
                        if truncatedTurnContext.isValid {
                            do {
                                try routeFastLine(
                                    .turnContext(CodexTurnContextMetadata(
                                        timestamp: nil,
                                        model: truncatedTurnContext.model,
                                        cwd: nil,
                                        title: nil)),
                                    lineIndex: lineIndex,
                                    ordinal: nil,
                                    endOffset: line.endOffset)
                            } catch {
                                deferredError = error
                            }
                        }
                        if pendingSubagentLines != nil {
                            let truncatedMetadata = Self.extractCodexTruncatedSessionMetadata(from: line.bytes)
                            if truncatedMetadata.isSessionMetadata {
                                do {
                                    try routeFastLine(
                                        .sessionMeta(CodexSessionMetadata(
                                            sessionId: truncatedMetadata.sessionID,
                                            concreteSessionId: nil,
                                            forkedFromId: nil,
                                            forkTimestamp: nil,
                                            projectPath: nil,
                                            isSubagentThread: false,
                                            subagentHistoryStartOrdinal: nil)),
                                        lineIndex: lineIndex,
                                        ordinal: nil,
                                        endOffset: line.endOffset)
                                } catch {
                                    deferredError = error
                                }
                            }
                        }
                        return
                    }

                    if !line.bytes.containsAscii(#""token_usage_record""#), line.bytes.containsAscii(#""usage""#) {
                        autoreleasepool {
                            guard let obj = (try? JSONSerialization.jsonObject(with: line.bytes)) as? [String: Any],
                                  obj["type"] == nil,
                                  let bare = Self.codexBareUsage(from: obj)
                            else { return }
                            do {
                                try routeFastLine(
                                    .bareUsage(CodexBareUsageRecord(
                                        timestamp: obj["timestamp"] as? String,
                                        model: bare.model,
                                        totals: bare.totals)),
                                    lineIndex: lineIndex,
                                    ordinal: Self.codexLineOrdinal(line.bytes),
                                    endOffset: line.endOffset)
                            } catch {
                                deferredError = error
                            }
                        }
                        return
                    }

                    guard
                        line.bytes.containsAscii(#""type":"event_msg""#)
                        || line.bytes.containsAscii(#""event_msg""#)
                        || line.bytes.containsAscii(#""type":"turn_context""#)
                        || line.bytes.containsAscii(#""turn_context""#)
                        || line.bytes.containsAscii(#""type":"session_meta""#)
                        || line.bytes.containsAscii(#""session_meta""#)
                        || line.bytes.containsAscii(#""type":"inter_agent_communication_metadata""#)
                        || line.bytes.containsAscii(#""inter_agent_communication_metadata""#)
                        || line.bytes.containsAscii(#""token_usage_record""#)
                    else { return }

                    if line.bytes.containsAscii(#""type":"event_msg""#),
                       !line.bytes.containsAscii(#""token_count""#),
                       !line.bytes.containsAscii(#""task_started""#)
                    {
                        return
                    }

                    if let fastLine = Self.parseCodexFastLine(line.bytes) {
                        let ordinal = Self.codexLineOrdinal(line.bytes)
                        let timestampValidity = fastLine.requiresValidTimestamp
                            ? Self.codexFastLineTimestampValidity(line.bytes)
                            : true
                        if timestampValidity == true {
                            do {
                                try routeFastLine(
                                    fastLine,
                                    lineIndex: lineIndex,
                                    ordinal: ordinal,
                                    endOffset: line.endOffset)
                            } catch {
                                deferredError = error
                            }
                            return
                        }
                        if timestampValidity == false {
                            return
                        }
                    }

                    autoreleasepool {
                        guard let object = (try? JSONSerialization.jsonObject(with: line.bytes)) as? [String: Any],
                              let parsedLine = Self.codexLine(from: object)
                        else { return }
                        do {
                            try routeFastLine(
                                parsedLine,
                                lineIndex: lineIndex,
                                ordinal: (object["ordinal"] as? NSNumber)?.intValue,
                                endOffset: line.endOffset)
                        } catch {
                            deferredError = error
                        }
                    }
                })
            parsedBytes = scanProgress.readOffset
            jsonlResumeState = scanProgress.resumeState
            if let deferredError {
                throw deferredError
            }

            if let pendingSubagentLines, parsedBytes >= targetSize, jsonlResumeState == nil {
                // Same-leaf metadata can fill lineage fields after the opening record. Collect it
                // before replay so copied-prefix totals never run once on the wrong baseline, and
                // so an owned-suffix filter cannot discard the only fork identifier.
                for buffered in pendingSubagentLines {
                    guard case let .sessionMeta(metadata) = buffered.line,
                          CodexSubagentRolloutShape.sameConcreteSessionID(metadata.sessionId, sessionId)
                    else { continue }
                    if forkedFromId == nil, let enrichedParentID = metadata.forkedFromId {
                        forkedFromId = enrichedParentID
                        codexSession.forkedFromId = enrichedParentID
                        forkTimestamp = metadata.forkTimestamp ?? forkTimestamp
                    }
                    if projectPath == nil {
                        projectPath = metadata.projectPath
                    }
                    if subagentHistoryStartOrdinal == nil {
                        subagentHistoryStartOrdinal = metadata.subagentHistoryStartOrdinal
                    }
                    observeTimestamp(metadata.forkTimestamp)
                    if codexSession.cwd == nil {
                        observeCwd(metadata.projectPath)
                    }
                }
                let observations = pendingSubagentLines.compactMap { buffered -> CodexSubagentRolloutShape
                    .Observation? in
                    let kind: CodexSubagentRolloutShape.Observation.Kind
                    switch buffered.line {
                    case let .sessionMeta(metadata):
                        kind = .sessionMetadata(id: metadata.sessionId)
                    case .turnContext:
                        kind = .turnContext
                    case let .interAgentCommunication(triggerTurn):
                        kind = .interAgentCommunication(triggerTurn: triggerTurn)
                    case .tokenCount, .tokenUsageRecord:
                        guard let record = buffered.line.boundaryTokenCount else { return nil }
                        kind = .tokenCount(total: record.total, last: record.last)
                    case .taskStarted, .bareUsage:
                        return nil
                    }
                    return Self.CodexSubagentRolloutShape.Observation(
                        lineIndex: buffered.lineIndex,
                        kind: kind)
                }
                let shape = CodexSubagentRolloutShape.classify(
                    leafSessionID: sessionId,
                    observations: observations,
                    hasExplicitParent: forkedFromId != nil)
                subagentCounterSemantics = shape.counterSemantics
                if forkedFromId == nil {
                    forkedFromId = shape.inferredParentSessionID
                }
                let explicitStartOrdinal = subagentHistoryStartOrdinal.flatMap { $0 >= 0 ? $0 : nil }
                let explicitOwnedSuffix: CodexSubagentRolloutShape.CodexSubagentOwnedSuffix? = {
                    guard let startOrdinal = explicitStartOrdinal,
                          let firstOwnedLine = pendingSubagentLines.first(where: {
                              ($0.ordinal ?? Int.min) >= startOrdinal
                          })
                    else { return nil }

                    let inheritedTotal = pendingSubagentLines
                        .prefix(while: { ($0.ordinal ?? Int.min) < startOrdinal })
                        .compactMap { buffered -> CostUsageCodexTotals? in
                            buffered.line.boundaryTokenCount?.total
                        }
                        .last
                    let firstOwnedToken = pendingSubagentLines.first { buffered in
                        guard (buffered.ordinal ?? Int.min) >= startOrdinal,
                              buffered.line.boundaryTokenCount != nil
                        else { return false }
                        return true
                    }
                    let inferredTotal = firstOwnedToken.flatMap { buffered -> CostUsageCodexTotals? in
                        guard let record = buffered.line.boundaryTokenCount else { return nil }
                        if let total = record.total, let last = record.last,
                           Self.codexTotalsAtLeast(total, last)
                        {
                            return Self.codexTotalDelta(from: last, to: total)
                        }
                        if record.total == nil, record.last != nil {
                            return .init(input: 0, cached: 0, output: 0)
                        }
                        return nil
                    }
                    guard let rawTotalsBaseline = inheritedTotal ?? inferredTotal else { return nil }
                    return .init(
                        startLineIndex: firstOwnedLine.lineIndex,
                        rawTotalsBaseline: rawTotalsBaseline)
                }()

                // The explicit ordinal excludes earlier inferred markers even before owned records arrive.
                let hasExplicitBoundary = explicitStartOrdinal != nil
                var ownedSuffix = hasExplicitBoundary ? explicitOwnedSuffix : shape.ownedSuffix
                var locallyConfirmedBoundary = explicitOwnedSuffix != nil
                if hasExplicitBoundary {
                    subagentCounterSemantics = .copiedPrefix
                } else if let candidate = shape.ownedSuffixCandidate {
                    if candidate.isLocallyConfirmed {
                        subagentCounterSemantics = .copiedPrefix
                        ownedSuffix = candidate.ownedSuffix
                        locallyConfirmedBoundary = true
                    } else if let parentSessionID = forkedFromId {
                        candidateBoundaryDependsOnParentTotals = true
                        if let inheritedTotalsResolver {
                            switch try inheritedTotalsResolver(parentSessionID, forkTimestamp ?? "") {
                            case let .resolved(parentTotals):
                                if Self.codexTotalsEqual(parentTotals, candidate.parentTotalsAtBoundary) {
                                    subagentCounterSemantics = .copiedPrefix
                                    ownedSuffix = candidate.ownedSuffix
                                    parentConfirmedLocalBoundary = true
                                }
                            case .unresolved:
                                break
                            }
                        }
                    }
                }
                usesLocalSubagentBoundary = hasExplicitBoundary || ownedSuffix != nil
                suppressUnownedCopiedPrefix = subagentCounterSemantics == .copiedPrefix
                    && ownedSuffix == nil
                    && (hasExplicitBoundary || forkedFromId == nil)
                if let ownedSuffix {
                    previousTotals = nil
                    // Keep totals-derived accounting after the boundary. Real flat-total rows
                    // repeat the previous token payload with a fresh outer timestamp; their
                    // non-zero `last` is replay evidence, not new usage (#2037).
                    rawTotalsBaseline = ownedSuffix.rawTotalsBaseline
                    sawDivergentTotals = false
                    tracker = CodexTotalsTracker(
                        watermark: ownedSuffix.rawTotalsBaseline,
                        seenRawTotals: [],
                        sawInterleavedTotals: false)
                    currentModel = nil
                    currentTurnID = nil
                }
                self.log.debug(
                    "Codex cost usage classified subagent rollout counter semantics",
                    metadata: [
                        "sessionId": sessionId ?? "unknown",
                        "semantics": subagentCounterSemantics == .copiedPrefix ? "copiedPrefix" : "independent",
                        "localBoundary": ownedSuffix == nil ? "false" : "true",
                        "locallyConfirmedBoundary": locallyConfirmedBoundary ? "true" : "false",
                        "parentConfirmedBoundary": parentConfirmedLocalBoundary ? "true" : "false",
                        "suppressedUnownedPrefix": suppressUnownedCopiedPrefix ? "true" : "false",
                        "sessionMetadataCount": String(observations.count(where: {
                            if case .sessionMetadata = $0.kind {
                                true
                            } else {
                                false
                            }
                        })),
                    ])
                try configureForkAccountingIfReady()
                for buffered in pendingSubagentLines
                    where ownedSuffix.map({ buffered.lineIndex >= $0.startLineIndex }) ?? true
                {
                    try processFastLine(buffered.line, sourceEndOffset: buffered.endOffset)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            self.log.warning(
                "Codex cost usage failed while scanning session file",
                metadata: ["path": fileURL.path, "error": error.localizedDescription])
            parsedBytes = startOffset
            jsonlResumeState = initialJSONLResumeState
        }

        codexSession.latestAcceptedUsageUnixMs = lastAcceptedTokenTimestampUnixMs
        let forkAccountingState: CodexForkAccountingState? = if let sessionId, let forkedFromId,
                                                                !isSubagentThread, forkBaselineResolved,
                                                                !hasUnresolvedForkBaseline
        {
            CodexForkAccountingState(
                metadata: CodexSessionMetadata(
                    sessionId: sessionId,
                    forkedFromId: forkedFromId,
                    forkTimestamp: forkTimestamp,
                    projectPath: projectPath,
                    isSubagentThread: false,
                    subagentHistoryStartOrdinal: nil,
                    historyBaseThreadId: historyBaseThreadId),
                inheritedTotals: inheritedTotals,
                remainingInheritedTotals: remainingInheritedTotals)
        } else {
            nil
        }
        return CodexParseResult(
            days: days,
            parsedBytes: parsedBytes,
            lastModel: currentModel,
            lastTotals: sawDivergentTotals && !Self.codexTotalsEqual(rawTotalsBaseline, previousTotals)
                ? nil
                : previousTotals,
            lastCountedTotals: previousTotals,
            lastRawTotalsBaseline: rawTotalsBaseline,
            lastRawTotalsWatermark: tracker.watermark,
            seenRawTotals: tracker.seenRawTotals,
            hasDivergentTotals: sawDivergentTotals && !Self.codexTotalsEqual(rawTotalsBaseline, previousTotals),
            hasInterleavedTotals: tracker.sawInterleavedTotals,
            lastCodexTurnID: currentTurnID,
            sessionId: sessionId,
            forkedFromId: forkedFromId,
            dependsOnParentTotals: forkedFromId != nil
                && (candidateBoundaryDependsOnParentTotals
                    || (subagentCounterSemantics != .independent && !usesLocalSubagentBoundary)),
            forkBaselineResolved: forkBaselineResolved && !hasUnresolvedForkBaseline,
            projectPath: projectPath,
            codexSession: codexSession,
            rows: rows,
            tokenSnapshots: tokenSnapshots,
            jsonlResumeState: jsonlResumeState,
            bufferedSubagentLines: parsedBytes < targetSize
                || jsonlResumeState != nil
                || hasUnresolvedForkBaseline
                ? pendingSubagentLines
                : nil,
            bufferedUnresolvedForkLines: hasUnresolvedForkBaseline
                ? bufferedUnresolvedForkLines
                : nil,
            rowSourceEndOffsets: rowSourceEndOffsets,
            nextUsageRowIndex: codexUsageRowIndex,
            forkAccountingState: forkAccountingState,
            requestLedgerState: requestLedger.responseIDs.isEmpty && requestLedger.legacyRowIndices.isEmpty
                && requestLedger.turnModels.isEmpty && requestLedger.activeTurnID == nil
                && requestLedger.sessionID == sessionId
                ? nil : requestLedger,
            replacedLegacyRowIndices: replacedLegacyRowIndices)
    }

    private static func codexTurnID(from payload: [String: Any]) -> String? {
        let containers: [[String: Any]?] = [payload, payload["info"] as? [String: Any]]
        for container in containers.compactMap(\.self) {
            for key in ["turn_id", "turnId", "id"] {
                if let value = container[key] as? String, !value.isEmpty { return value }
            }
        }
        return nil
    }

    private enum CodexFileScanOutcome {
        case processed
        case deferred
    }

    private static func hydrateCodexAliasHistoryIfNeeded(
        metadata: CodexFileMetadata,
        context: CodexFileScanContext,
        cache: inout CostUsageCache,
        state: inout CodexScanState,
        existingAliases: [String]) throws -> Bool
    {
        guard metadata.fileId != nil,
              let historyHydrator = context.resources.historyHydrator
        else { return true }
        let allAliases = existingAliases
        let aliases = allAliases
            .filter { cache.files[$0]?.codexTokenSnapshots == nil }
        guard !aliases.isEmpty else { return true }
        guard case .ready = try historyHydrator.hydrate(
            paths: Set(aliases),
            retryTargetPath: metadata.path,
            retainedPaths: Set(allAliases).union([metadata.path]))
        else {
            Self.deferCodexHistoryHydration(
                targetPath: metadata.path,
                retainedPaths: Set(allAliases).union([metadata.path]),
                cache: cache,
                state: &state)
            return false
        }
        for alias in aliases {
            guard let cached = cache.files[alias] else { continue }
            let hydrated = historyHydrator.usageWithHydratedSnapshots(cached, path: alias)
            guard hydrated.codexTokenSnapshots != nil else { continue }
            cache.files[alias] = hydrated
            context.resources.inheritedResolver.updateCachedUsage(
                fileURL: URL(fileURLWithPath: alias),
                usage: hydrated)
        }
        return true
    }

    private static func deferCodexHistoryHydration(
        targetPath: String,
        retainedPaths: Set<String>,
        cache: CostUsageCache,
        state: inout CodexScanState)
    {
        let target = Self.codexResolvedPath(URL(fileURLWithPath: targetPath))
        let retained = retainedPaths.filter { cache.files[$0] != nil }
        var retry = CodexHistoryHydrationRetry(retainedPaths: retained, forceFullRescan: true)
        if let existing = cache.codexHistoryHydrationRetries?[target] {
            retry.merge(existing)
        }
        if var failed = state.historyHydrationRetries[target] {
            failed.merge(retry)
            state.historyHydrationRetries[target] = failed
        } else {
            state.historyHydrationRetries[target] = retry
        }
        state.deferredCachePaths.formUnion(retry.retainedPaths)
    }

    private static func hydrateCodexFileHistoryIfNeeded(
        metadata: CodexFileMetadata,
        fileURL: URL,
        context: CodexFileScanContext,
        cache: inout CostUsageCache,
        state: inout CodexScanState,
        retainedAliasPaths: Set<String> = []) throws -> Bool
    {
        guard let cached = cache.files[metadata.path],
              cached.codexTokenSnapshots == nil,
              let historyHydrator = context.resources.historyHydrator
        else { return true }
        switch try historyHydrator.hydrate(
            paths: [metadata.path],
            retryTargetPath: metadata.path,
            retainedPaths: retainedAliasPaths.union([metadata.path]))
        {
        case .ready:
            let hydrated = historyHydrator.usageWithHydratedSnapshots(cached, path: metadata.path)
            guard hydrated.codexTokenSnapshots != nil else { return true }
            cache.files[metadata.path] = hydrated
            context.resources.inheritedResolver.updateCachedUsage(fileURL: fileURL, usage: hydrated)
            return true
        case .stale, .unavailable:
            Self.deferCodexHistoryHydration(
                targetPath: metadata.path,
                retainedPaths: retainedAliasPaths.union([metadata.path]),
                cache: cache,
                state: &state)
            return false
        }
    }

    private static func scanCodexFile(
        fileURL: URL,
        context: CodexFileScanContext,
        cache: inout CostUsageCache,
        state: inout CodexScanState) throws -> CodexFileScanOutcome
    {
        try context.checkCancellation?()
        let metadata = Self.codexFileMetadata(fileURL: fileURL)
        let retainsRecoveryHistory = context.sourceRowRecoveryPathKeys.contains(Self.codexPathKey(fileURL))
            || (context.preserveUnavailableHistoryDuringRecovery
                && cache.files[metadata.path].map {
                    Self.codexUnavailableHistoryNeedsRecovery($0, range: context.range)
                } == true)
        if metadata.fileId == nil, !FileManager.default.fileExists(atPath: metadata.path) {
            if retainsRecoveryHistory { return .deferred }
            let retryTarget = Self.codexResolvedPath(fileURL)
            let retry = cache.codexHistoryHydrationRetries?[retryTarget]
            if let retry {
                guard Self.canReleaseMissingCodexHistoryRetry(retry, context: context, cache: cache) else {
                    Self.deferCodexHistoryHydration(
                        targetPath: retryTarget,
                        retainedPaths: Set(retry.retainedPaths).union([metadata.path]),
                        cache: cache,
                        state: &state)
                    return .processed
                }
                for retainedPath in retry.retainedPaths {
                    Self.dropCachedCodexFile(
                        path: retainedPath,
                        cached: cache.files[retainedPath],
                        cache: &cache)
                    cache.codexMalformedDetailsPaths?.remove(retainedPath)
                }
                state.confirmedAbsentHistoryRetryPaths.formUnion(retry.retainedPaths)
                state.confirmedAbsentHistoryRetryPaths.insert(retryTarget)
                state.confirmedAbsentHistoryRetryPaths.insert(metadata.path)
                Self.dropCachedCodexFile(
                    path: metadata.path,
                    cached: cache.files[metadata.path],
                    cache: &cache)
                cache.codexMalformedDetailsPaths?.remove(metadata.path)
                state.completedHistoryRetryTargets.insert(retryTarget)
            } else {
                Self.dropCachedCodexFile(path: metadata.path, cached: cache.files[metadata.path], cache: &cache)
                cache.codexMalformedDetailsPaths?.remove(metadata.path)
            }
            return .processed
        }
        guard metadata.fileId != nil, FileManager.default.isReadableFile(atPath: metadata.path) else {
            return .deferred
        }
        defer {
            context.resources.cachePathAliasIndex.update(
                path: metadata.path,
                fileID: cache.files[metadata.path]?.codexScanFileId)
        }
        let existingAliases = metadata.fileId.map {
            context.resources.cachePathAliasIndex.aliases(fileID: $0, excludingPath: metadata.path)
        } ?? []
        if let fileId = metadata.fileId, state.seenFileIds.contains(fileId) {
            let retryTarget = Self.codexResolvedPath(fileURL)
            if cache.codexHistoryHydrationRetries?[retryTarget] != nil {
                Self.deferCodexHistoryHydration(
                    targetPath: metadata.path,
                    retainedPaths: Set(existingAliases).union([metadata.path]),
                    cache: cache,
                    state: &state)
                return .deferred
            }
            Self.dropCachedCodexFile(path: metadata.path, cached: cache.files[metadata.path], cache: &cache)
            return .processed
        }
        guard try Self.hydrateCodexAliasHistoryIfNeeded(
            metadata: metadata,
            context: context,
            cache: &cache,
            state: &state,
            existingAliases: existingAliases)
        else { return .deferred }
        if !existingAliases.isEmpty {
            guard try Self.hydrateCodexFileHistoryIfNeeded(
                metadata: metadata,
                fileURL: fileURL,
                context: context,
                cache: &cache,
                state: &state,
                retainedAliasPaths: Set(existingAliases))
            else { return .deferred }
        }
        Self.reconcileCodexCachePathAliases(
            metadata: metadata,
            cache: &cache,
            aliasIndex: context.resources.cachePathAliasIndex,
            existingAliases: existingAliases)

        let cached = cache.files[metadata.path]

        // Queue a present but unresolved parent before retrying its child. Confirmed missing
        // ancestry must still let the child finish parsing and settle its scheduling state.
        if let cached,
           let parentID = cached.forkedFromId,
           let buffered = cached.codexBufferedUnresolvedForkLines,
           let forkTimestamp = buffered.compactMap({ line -> String? in
               guard case let .sessionMeta(metadata) = line.line else { return nil }
               return metadata.forkTimestamp
           }).first,
           case .unresolved = try context.resources.inheritedResolver.inheritedTotals(
               for: parentID, atOrBefore: forkTimestamp),
           context.resources.inheritedResolver.dependencyKeyUsed(for: parentID)
               .map(Self.codexDependencyIsMissing) != true
        {
            return .deferred
        }

        let freshnessInput = CodexFileScanInput(fileURL: fileURL, metadata: metadata, cached: cached)
        if try Self.keepCachedCodexFileIfFresh(
            input: freshnessInput,
            context: context,
            cache: &cache,
            state: &state)
        {
            return .processed
        }
        guard try Self.hydrateCodexFileHistoryIfNeeded(
            metadata: metadata,
            fileURL: fileURL,
            context: context,
            cache: &cache,
            state: &state)
        else { return .deferred }
        return try Self.scanCodexFileContent(
            fileURL: fileURL,
            metadata: metadata,
            context: context,
            cache: &cache,
            state: &state)
    }

    private static func canReleaseMissingCodexHistoryRetry(
        _ retry: CodexHistoryHydrationRetry,
        context: CodexFileScanContext,
        cache: CostUsageCache) -> Bool
    {
        retry.retainedPaths.allSatisfy { path in
            let fileURL = URL(fileURLWithPath: path)
            let pathKey = Self.codexPathKey(fileURL)
            guard !context.sourceRowRecoveryPathKeys.contains(pathKey) else { return false }
            if context.preserveUnavailableHistoryDuringRecovery,
               let cached = cache.files[path],
               Self.codexUnavailableHistoryNeedsRecovery(cached, range: context.range)
            {
                return false
            }
            let metadata = Self.codexFileMetadata(fileURL: fileURL)
            return metadata.fileId == nil && !FileManager.default.fileExists(atPath: metadata.path)
        }
    }

    private static func scanCodexFileContent(
        fileURL: URL,
        metadata: CodexFileMetadata,
        context: CodexFileScanContext,
        cache: inout CostUsageCache,
        state: inout CodexScanState) throws -> CodexFileScanOutcome
    {
        let input = CodexFileScanInput(
            fileURL: fileURL,
            metadata: metadata,
            cached: cache.files[metadata.path])

        let pendingWorkBytes = Self.pendingCodexScanWorkBytes(
            metadata: metadata,
            cached: input.cached)
        let allowedWorkBytes: Int64
        if let budget = context.scanBudget {
            switch budget.admit(workBytes: pendingWorkBytes) {
            case let .allow(allowance):
                allowedWorkBytes = allowance
            case .deferBudget:
                Self.log.debug(
                    "Deferring Codex session cost scan until a later refresh",
                    metadata: [
                        "path": metadata.path,
                        "pendingBytes": "\(pendingWorkBytes)",
                        "consumed": "\(budget.bytesConsumed)",
                        "limit": "\(budget.maxBytesPerRefresh)",
                    ])
                // Preserve stale cache so later refreshes can resume catch-up.
                return .deferred
            }
        } else {
            allowedWorkBytes = pendingWorkBytes
        }

        if try Self.appendCodexFileIncrementIfPossible(
            input: input,
            context: context,
            cache: &cache,
            state: &state,
            maxBytesToRead: allowedWorkBytes)
        {
            context.scanBudget?.consume(workBytes: allowedWorkBytes)
            state.completedHistoryRetryTargets.insert(Self.codexResolvedPath(fileURL))
            cache.codexMalformedDetailsPaths?.remove(metadata.path)
            return .processed
        }
        // A staged ordinary fork can replay its validated buffer at EOF through the
        // replacement parser. Reserving the full file here would starve the parent lookup
        // inside that replay and discard freshly confirmed missing-ancestry evidence.
        let replaysReplacementAtEOF = input.cached.map { cached in
            pendingWorkBytes == 0
                && cached.codexReplacementScanPending == true
                && cached.codexScanComplete == true
                && cached.parsedBytes == metadata.size
                && cached.codexBufferedSubagentLines?.isEmpty != false
                && cached.codexHasBufferedSubagentLines != true
                && Self.codexBufferedForkHasMetadata(cached)
        } ?? false
        let fullRescanWorkBytes = replaysReplacementAtEOF ? 0 : max(0, metadata.size)
        let fullRescanAllowedBytes: Int64
        if fullRescanWorkBytes == pendingWorkBytes {
            fullRescanAllowedBytes = allowedWorkBytes
        } else if let budget = context.scanBudget {
            budget.release(workBytes: allowedWorkBytes)
            switch budget.admit(workBytes: fullRescanWorkBytes) {
            case let .allow(allowance):
                fullRescanAllowedBytes = allowance
            case .deferBudget:
                // No work was consumed by the rejected incremental path, so this is only
                // reachable when the refresh budget has no allowance for the full rescan.
                return .deferred
            }
        } else {
            fullRescanAllowedBytes = fullRescanWorkBytes
        }

        try Self.rescanCodexFile(
            input: input,
            context: context,
            cache: &cache,
            state: &state,
            maxBytesToRead: fullRescanAllowedBytes)
        context.scanBudget?.consume(workBytes: fullRescanAllowedBytes)
        state.completedHistoryRetryTargets.insert(Self.codexResolvedPath(fileURL))
        cache.codexMalformedDetailsPaths?.remove(metadata.path)
        return .processed
    }

    static func pendingCodexScanWorkBytes(metadata: CodexFileMetadata, cached: CostUsageFileUsage?) -> Int64 {
        // Called only after keepCachedCodexFileIfFresh failed. Forced rescans, priority invalidation,
        // and other paths that reread JSONL must still charge the file; the sole zero-work exception
        // is a validated same-size buffered replay.
        guard let cached, cached.hasCurrentCodexParser else { return max(0, metadata.size) }
        if Self.isValidatedSameSizeBufferedCodexForkRetry(metadata: metadata, cached: cached) {
            return 0
        }
        if Self.isAppendSafeBufferedCodexForkResume(metadata: metadata, cached: cached) {
            let startOffset = cached.parsedBytes ?? cached.size
            return max(0, metadata.size - startOffset)
        }
        if cached.codexScanComplete == false {
            if cached.codexScanFileId != nil,
               cached.codexScanFileId == metadata.fileId,
               let parsedBytes = cached.parsedBytes,
               parsedBytes > 0,
               parsedBytes <= metadata.size,
               cached.codexTokenIndexAnchor?.indexedBytes == parsedBytes,
               cached.codexTokenIndexAnchor.map({
                   Self.codexTokenIndexAnchorMatches(
                       $0,
                       fileURL: URL(fileURLWithPath: metadata.path),
                       metadata: metadata)
               }) == true
            {
                return max(0, metadata.size - parsedBytes)
            }
            return max(0, metadata.size)
        }
        let startOffset = cached.parsedBytes ?? cached.size
        if metadata.size > cached.size,
           startOffset > 0,
           startOffset <= metadata.size,
           cached.forkedFromId == nil
        {
            return max(0, metadata.size - startOffset)
        }
        return max(0, metadata.size)
    }

    private static func codexUnavailableHistoryNeedsRecovery(
        _ usage: CostUsageFileUsage,
        range: CostUsageDayRange) -> Bool
    {
        usage.codexPendingSourcePricing != nil
            || codexSourceRowRecoveryPricing(usage, range: range) != nil
            || codexParserRevisionMigrationPricing(usage, range: range) != nil
    }

    private static func makeCodexRefreshPlan(
        cache: CostUsageCache,
        range: CostUsageDayRange,
        now: Date,
        nowMs: Int64,
        options: Options) -> CodexRefreshPlan
    {
        let refreshMs = Int64(max(0, options.refreshMinIntervalSeconds) * 1000)
        let roots = self.codexSessionsRoots(options: options)
        let rootsFingerprint = Self.codexRootsFingerprint(roots)
        let rootsChanged = cache.roots != rootsFingerprint
        let windowExpanded = Self.requestedWindowExpandsCache(range: range, cache: cache)
        let sourceRowRecoveryPathKeys: Set<String> = if !options.forceRescan, !rootsChanged {
            Self.codexSourceRowRecoveryPathKeys(cache: cache, range: range, roots: roots)
        } else {
            []
        }
        let preserveUnavailableHistoryDuringRecovery = !options.forceRescan && !rootsChanged
            && (!sourceRowRecoveryPathKeys.isEmpty || cache.files.contains { path, usage in
                usage.codexPendingSourcePricing != nil && FileManager.default.isReadableFile(atPath: path)
            })
        let pricingMetadataMigrationPathKeys = options.useCodexCatchUpWorkingSet
            ? []
            : Set(cache.files.compactMap { path, usage in
                Self.needsCodexPricingMetadata(usage, range: range)
                    ? Self.codexPathKey(URL(fileURLWithPath: path))
                    : nil
            })
        let needsPricingMetadataMigration = !pricingMetadataMigrationPathKeys.isEmpty
        let parserMigrationPathKeys = Set(cache.files.compactMap { path, usage in
            usage.hasCurrentCodexParser ? nil : Self.codexPathKey(URL(fileURLWithPath: path))
        })
        let needsProjectMetadataMigration = cache.codexProjectMetadataVersion != Self.codexProjectMetadataVersion
        let modelsDevLoad = ModelsDevCache.load(now: now, cacheRoot: options.cacheRoot)
        let modelsDevCatalog = modelsDevLoad.artifact?.catalog
        let codexPricingKey = Self.codexPricingKey(modelsDevArtifact: modelsDevLoad.artifact)
        let pricingKeyChanged = cache.codexPricingKey != codexPricingKey
        let codexPriorityMetadataKey = Self.codexPriorityMetadataKey(databaseURL: options.codexTraceDatabaseURL)
        let hasPriorityMetadata = codexPriorityMetadataKey.hasPrefix("sqlite:")
        let priorityMetadataChanged = Self.codexPriorityMetadataChanged(
            old: cache.codexPriorityMetadataKey,
            new: codexPriorityMetadataKey)
        let turnIDCacheMigrationPathKeys = hasPriorityMetadata && !options.useCodexCatchUpWorkingSet
            ? Set(cache.files.compactMap { path, usage in
                usage.codexTurnIDs == nil && usage.touchesCodexScanWindow(
                    sinceKey: range.scanSinceKey,
                    untilKey: range.scanUntilKey,
                    calendar: range.calendar)
                    ? Self.codexPathKey(URL(fileURLWithPath: path))
                    : nil
            })
            : []
        let needsTurnIDCacheMigration = !turnIDCacheMigrationPathKeys.isEmpty
        let shouldInspectPriorityTurns = options.forceRescan
            || windowExpanded
            || rootsChanged
            || needsPricingMetadataMigration
            || needsProjectMetadataMigration
            || needsTurnIDCacheMigration
            || priorityMetadataChanged
            || refreshMs == 0
            || cache.lastScanUnixMs == 0
            || nowMs - cache.lastScanUnixMs > refreshMs
        let resolvedPriorityDatabaseURL = Self.resolvedCodexPriorityDatabaseURL(options.codexTraceDatabaseURL)
        if shouldInspectPriorityTurns {
            if options.forceRescan {
                Self.dropCodexPriorityTurnsMemo(databaseURL: resolvedPriorityDatabaseURL)
            } else {
                Self.seedCodexPriorityTurnsMemoIfEmpty(
                    cache.codexPriorityTurnsCursor,
                    databaseURL: resolvedPriorityDatabaseURL)
            }
        }
        let priorityTurns = shouldInspectPriorityTurns ? Self.codexPriorityTurns(
            databaseURL: resolvedPriorityDatabaseURL,
            sinceDayKey: range.scanSinceKey,
            untilDayKey: range.scanUntilKey) : [:]
        let priorityTurnsCursor = shouldInspectPriorityTurns
            ? Self.codexPriorityTurnsPersistedCursor(databaseURL: resolvedPriorityDatabaseURL)
            : nil
        let priorityTurnKeys = Self.codexPriorityTurnKeys(priorityTurns, calendar: range.calendar)
        let priorityTurnIDsByDay = Self.codexPriorityTurnIDsByDay(priorityTurns, calendar: range.calendar)
        let priorityTurnsChanged = shouldInspectPriorityTurns
            && hasPriorityMetadata
            && Self.codexPriorityTurnKeysChanged(
                old: cache.codexPriorityTurnKeys,
                new: priorityTurnKeys,
                range: range,
                workRecorder: options.codexScanWorkRecorderForTesting)
        let changedPriorityTurnIDs = shouldInspectPriorityTurns && hasPriorityMetadata
            ? Self.changedPriorityTurnIDs(
                old: cache.codexPriorityTurnIDsByDay,
                new: priorityTurnIDsByDay,
                oldKeys: cache.codexPriorityTurnKeys,
                newKeys: priorityTurnKeys,
                range: range,
                workRecorder: options.codexScanWorkRecorderForTesting)
            : []
        let requiresAllFilesForCacheWideMigration = !options.useCodexCatchUpWorkingSet
            && !cache.files.isEmpty
            && (options.forceRescan
                || pricingKeyChanged
                || needsProjectMetadataMigration
                || priorityMetadataChanged
                || priorityTurnsChanged)
        let cacheWideMigrationPendingPathKeys = pricingMetadataMigrationPathKeys
            .union(turnIDCacheMigrationPathKeys)
            .union(parserMigrationPathKeys)
            .union(sourceRowRecoveryPathKeys)
        let historyRetries = cache.codexHistoryHydrationRetries ?? [:]
        let historyRetryPathKeys = Self.codexHistoryRetryPathKeys(cache: cache)
        let requiresCacheWideFileReprocessing = requiresAllFilesForCacheWideMigration
            || !cacheWideMigrationPendingPathKeys.isEmpty
        let shouldRefresh = options.forceRescan
            || !parserMigrationPathKeys.isEmpty
            || !sourceRowRecoveryPathKeys.isEmpty
            || windowExpanded
            || rootsChanged
            || needsPricingMetadataMigration
            || pricingKeyChanged
            || needsProjectMetadataMigration
            || needsTurnIDCacheMigration
            || priorityMetadataChanged
            || priorityTurnsChanged
            || refreshMs == 0
            || cache.lastScanUnixMs == 0
            || nowMs - cache.lastScanUnixMs > refreshMs
            || !historyRetries.isEmpty

        return CodexRefreshPlan(
            refreshMs: refreshMs,
            roots: roots,
            rootsFingerprint: rootsFingerprint,
            rootsChanged: rootsChanged,
            windowExpanded: windowExpanded,
            needsPricingMetadataMigration: needsPricingMetadataMigration,
            needsProjectMetadataMigration: needsProjectMetadataMigration,
            modelsDevCatalog: modelsDevCatalog,
            codexPricingKey: codexPricingKey,
            codexPriorityMetadataKey: codexPriorityMetadataKey,
            hasPriorityMetadata: hasPriorityMetadata,
            priorityTurns: priorityTurns,
            priorityTurnKeys: priorityTurnKeys,
            priorityTurnIDsByDay: priorityTurnIDsByDay,
            inspectedPriorityTurns: shouldInspectPriorityTurns,
            priorityTurnsCursor: priorityTurnsCursor,
            priorityMetadataChanged: priorityMetadataChanged,
            priorityTurnsChanged: priorityTurnsChanged,
            needsTurnIDCacheMigration: needsTurnIDCacheMigration,
            changedPriorityTurnIDs: changedPriorityTurnIDs,
            requiresAllFilesForCacheWideMigration: requiresAllFilesForCacheWideMigration,
            cacheWideMigrationPendingPathKeys: cacheWideMigrationPendingPathKeys,
            sourceRowRecoveryPathKeys: sourceRowRecoveryPathKeys,
            historyRetryPathKeys: historyRetryPathKeys.all,
            forceFullScanHistoryRetryPathKeys: historyRetryPathKeys.forceFullScan,
            preserveUnavailableHistoryDuringRecovery: preserveUnavailableHistoryDuringRecovery,
            requiresCacheWideFileReprocessing: requiresCacheWideFileReprocessing,
            shouldRefresh: shouldRefresh)
    }

    private static func loadCodexCache(
        options: Options,
        range: CostUsageDayRange) -> CostUsageStoreLoad
    {
        if options.useCodexCatchUpWorkingSet {
            return CostUsageStoreAccess.loadCodexWorkingSet(
                cacheRoot: options.cacheRoot,
                calendar: range.calendar)
        }
        return CostUsageStoreAccess.load(cacheRoot: options.cacheRoot, calendar: range.calendar)
    }

    private struct CodexCatchUpHydrationPlan {
        let scheduledFiles: [URL]
        let paths: Set<String>
        let deferredCandidates: Bool
        let requestReconciliations: [String: CostUsageCodexRequestReconciliation]
    }

    /// Selects the detail working set before SQLite decodes any event rows. Persisted token
    /// snapshots make a fork's immediate parent the only detail dependency needed to establish
    /// its baseline; the parent's own lineage is already reflected in those snapshots. Recursing
    /// through every older ancestor only increases memory and cannot improve the child's answer.
    ///
    /// The plan admits whole candidate/dependency groups against both a path cap and the remaining
    /// scan-byte allowance. Same-thread request pages join the candidate and direct parent within
    /// the path cap; larger sibling cohorts carry manifest-visible progress across refreshes.
    /// The first oversized group may use partial-file admission. Deferred candidates remain in
    /// the durable active-lookback queue for the next pass.
    private static func codexCatchUpHydrationPlan(
        scheduledFiles: [URL],
        cache: CostUsageCache,
        scanBudget: CodexScanBudget,
        prehydratedPaths: Set<String> = []) -> CodexCatchUpHydrationPlan
    {
        var pathBySessionID: [String: String] = [:]
        for (path, usage) in cache.files {
            guard let sessionID = usage.sessionId, !sessionID.isEmpty else { continue }
            pathBySessionID[sessionID] = Self.codexResolvedPath(URL(fileURLWithPath: path))
        }

        func hydrationWorkBytes(path: String) -> Int64 {
            let persistedSize = cache.files[path]?.size ?? 0
            let currentSize = Self.codexFileMetadata(fileURL: URL(fileURLWithPath: path)).size
            let sourceBytes = max(1, max(persistedSize, currentSize))
            return scanBudget.maxFileBytes > 0
                ? min(sourceBytes, scanBudget.maxFileBytes)
                : sourceBytes
        }

        var requestReconciliations: [String: CostUsageCodexRequestReconciliation] = [:]
        var admittedFiles: [URL] = []
        var admittedPaths = prehydratedPaths
        var plannedBytes: Int64 = 0
        let remainingBytes = scanBudget.planningRemainingBytes

        for fileURL in scheduledFiles {
            let candidatePath = Self.codexResolvedPath(fileURL)
            let candidate = cache.files[candidatePath]
            let dependencyPath = candidate?.forkedFromId.flatMap { pathBySessionID[$0] }
            let metadata = Self.codexFileMetadata(fileURL: fileURL)
            let sessionID = candidate?.sessionId ?? Self.codexBoundedRequestSessionID(fileURL)
            var reconciliation = candidate?.codexRequestReconciliation
            if reconciliation?.size != metadata.size || reconciliation?.mtimeUnixMs != metadata.mtimeUnixMs
                || reconciliation?.parserRevision != CostUsageFileUsage.currentCodexParserRevision
                || reconciliation?.sessionID != sessionID
            {
                reconciliation = CostUsageCodexRequestReconciliation(
                    size: metadata.size,
                    mtimeUnixMs: metadata.mtimeUnixMs,
                    parserRevision: CostUsageFileUsage.currentCodexParserRevision,
                    sessionID: sessionID,
                    pendingPaths: cache.files.keys.filter {
                        $0 != candidatePath && sessionID != nil && cache.files[$0]?.sessionId == sessionID
                    }.sorted())
            }
            let requiredPaths = [dependencyPath, candidatePath].compactMap(\.self)
            let basePaths = Set(requiredPaths).subtracting(admittedPaths)
            let siblingAllowance = max(0, Self.codexCatchUpHydrationPathLimit - admittedPaths.count - basePaths.count)
            let siblingPaths = Array((reconciliation?.pendingPaths ?? []).filter {
                !basePaths.contains($0) && !admittedPaths.contains($0)
            }.prefix(siblingAllowance))
            let newPaths = Array(basePaths) + siblingPaths
            let groupBytes = newPaths.reduce(Int64(0)) { partial, path in
                let work = hydrationWorkBytes(path: path)
                return partial > Int64.max - work ? Int64.max : partial + work
            }
            let fitsPathLimit = admittedPaths.count + newPaths.count <= Self.codexCatchUpHydrationPathLimit
            let fitsByteLimit = remainingBytes == Int64.max
                || (plannedBytes <= remainingBytes && groupBytes <= remainingBytes - plannedBytes)
            let canUseFirstPartialAdmission = admittedFiles.isEmpty && remainingBytes > 0
            guard fitsPathLimit, fitsByteLimit || canUseFirstPartialAdmission else {
                break
            }

            admittedFiles.append(URL(fileURLWithPath: candidatePath))
            requestReconciliations[candidatePath] = reconciliation
            admittedPaths.formUnion(newPaths)
            plannedBytes = plannedBytes > Int64.max - groupBytes ? Int64.max : plannedBytes + groupBytes

            // Once an oversized first group consumes the available allowance, later candidates
            // would only decode details that the scanner is guaranteed to defer.
            if !fitsByteLimit {
                break
            }
        }
        return CodexCatchUpHydrationPlan(
            scheduledFiles: admittedFiles,
            paths: admittedPaths,
            deferredCandidates: admittedFiles.count < scheduledFiles.count,
            requestReconciliations: requestReconciliations)
    }

    /// Only the metadata prefix is needed to group a newly discovered page with persisted siblings.
    /// Files with late metadata are grouped after their ordinary bounded parser pass instead.
    private static func codexBoundedRequestSessionID(_ fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.codexSessionMetadataMaxLineBytes) else { return nil }
        for line in data.split(separator: 0x0A) {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let metadata = Self.codexSessionMetadata(from: object)
            else { continue }
            return metadata.sessionId
        }
        return nil
    }

    private static func codexPreviousReportCandidate(
        cache: CostUsageCache,
        store: CostUsageStore,
        range: CostUsageDayRange,
        plan: CodexRefreshPlan,
        options: Options) -> CostUsageCodexPreviousReport?
    {
        guard !codexHistoryRangeHasUnsettledMissingParentFork(cache: cache, range: range)
        else { return nil }
        let currentScanIsPending = cache.codexScanCatchUpPending == true
            || cache.files.values.contains(where: \.hasPendingCodexScanWork)
        if currentScanIsPending,
           let previous = self.codexPreviousReport(
               cache: cache,
               range: range,
               rootsFingerprint: plan.rootsFingerprint)
        {
            return previous
        }

        // The report payload is a compatibility fallback for older stores and is scoped to
        // one requested window. Once the durable verified ledger exists, project the pending
        // request from that range-independent baseline instead of allowing a 30/365-day
        // alternation to replace the other consumer's established history.
        if currentScanIsPending {
            let projection = CostUsageStoreAccess.readCodexReportProjection(
                store: store,
                calendar: range.calendar,
                temporalRange: (range.sinceKey, range.untilKey))
            if let verifiedSince = projection.verifiedScanSinceKey,
               let verifiedUntil = projection.verifiedScanUntilKey,
               verifiedSince <= range.sinceKey,
               verifiedUntil >= range.untilKey
            {
                let report = CostUsageCodexReportProjectionBuilder.buildVerifiedReport(
                    projection: projection,
                    range: range,
                    cacheRoot: options.cacheRoot)
                guard !report.data.isEmpty else { return nil }
                var verifiedCache = cache
                if let updatedAt = projection.verifiedUpdatedAtUnixMs, updatedAt > 0 {
                    verifiedCache.lastScanUnixMs = updatedAt
                }
                return CostUsageCodexPreviousReport(
                    report: report,
                    cache: verifiedCache,
                    reportSinceKey: range.sinceKey,
                    reportUntilKey: range.untilKey)
            }
        }

        // A routine bounded refresh can turn an established cache back into pending while it
        // validates a growing active tail. Snapshot the established report before any refresh,
        // not only explicit rescans, so presentation can remain stable until catch-up converges.
        let sourceCache: CostUsageCache? = if plan.shouldRefresh,
                                              !currentScanIsPending,
                                              !Self.codexHistoryRangeHasUnsettledMissingParentFork(
                                                  cache: cache, range: range),
                                              !cache.days.isEmpty
        {
            cache
        } else {
            nil
        }
        guard let sourceCache,
              sourceCache.timeZoneIdentifier == range.calendar.timeZone.identifier,
              sourceCache.roots == plan.rootsFingerprint,
              !self.requestedWindowExpandsCache(range: range, cache: sourceCache),
              !sourceCache.days.isEmpty
        else { return nil }

        let report: CostUsageDailyReport
        if options.useCodexCatchUpWorkingSet {
            let projection = CostUsageStoreAccess.readCodexReportProjection(
                store: store,
                calendar: range.calendar,
                temporalRange: (range.sinceKey, range.untilKey))
            report = CostUsageCodexReportProjectionBuilder.build(
                projection: projection,
                roots: plan.roots,
                range: range,
                cacheRoot: options.cacheRoot,
                includeBreakdowns: false).report
        } else {
            report = self.buildCodexReportFromCache(
                cache: sourceCache,
                range: range,
                modelsDevCatalog: plan.modelsDevCatalog,
                modelsDevCacheRoot: options.cacheRoot,
                priorityTurns: plan.priorityTurns)
        }
        return CostUsageCodexPreviousReport(
            report: report,
            cache: sourceCache,
            reportSinceKey: range.sinceKey,
            reportUntilKey: range.untilKey)
    }

    static func codexPreviousReport(
        cache: CostUsageCache,
        range: CostUsageDayRange,
        rootsFingerprint: [String: Int64]) -> CostUsageCodexPreviousReport?
    {
        guard cache.codexScanCatchUpPending == true,
              !codexHistoryRangeHasUnsettledMissingParentFork(cache: cache, range: range),
              let previous = cache.codexPreviousReport,
              previous.matches(
                  scanSinceKey: range.sinceKey,
                  scanUntilKey: range.untilKey,
                  timeZoneIdentifier: range.calendar.timeZone.identifier,
                  roots: rootsFingerprint)
        else { return nil }
        return previous
    }

    static func scopedPreviousReport(
        _ previous: CostUsageCodexPreviousReport,
        range: CostUsageDayRange) -> CostUsageDailyReport
    {
        let report = previous.report
        return CostUsageDailyReport.merged([CostUsageDailyReport(
            data: report.data.filter {
                CostUsageDayRange.isInRange(dayKey: $0.date, since: range.sinceKey, until: range.untilKey)
            },
            summary: nil,
            hourly: report.hourly.filter {
                CostUsageDayRange.isInRange(
                    dayKey: CostUsageDayRange.dayKey(from: $0.hour, calendar: range.calendar),
                    since: range.sinceKey,
                    until: range.untilKey)
            },
            quotaSlices: report.quotaSlices.filter {
                CostUsageDayRange.isInRange(
                    dayKey: CostUsageDayRange.dayKey(from: $0.timestamp, calendar: range.calendar),
                    since: range.sinceKey,
                    until: range.untilKey)
            })], calendar: range.calendar)
    }

    private static func saveCodexCache(
        _ cache: inout CostUsageCache,
        loadedCache: CostUsageStoreLoad,
        range: CostUsageDayRange,
        previousReport: CostUsageCodexPreviousReport?,
        hydratedPaths: Set<String>? = nil,
        confirmedAbsentHistoryRetryPaths: Set<String> = [],
        retryRegistryToken: CodexScanHistoryHydrationRetryRegistry.CommitToken = .init(),
        independentlyVerifiedCodexWindow: (sinceKey: String, untilKey: String)? = nil,
        independentlyVerifiedDayKeys: [String] = [])
    {
        // The serial scan queue remains the per-process writer boundary. The store actor owns
        // the sole writable connection; app and CLI readers take independent WAL snapshots.
        let saveResult: CostUsageStoreBudgetResult = if let hydratedPaths {
            CostUsageStoreAccess.saveCodexCatchUp(
                store: loadedCache.store,
                cache: cache,
                calendar: range.calendar,
                requestedScanWindow: (sinceKey: range.scanSinceKey, untilKey: range.scanUntilKey),
                reportWindow: (sinceKey: range.sinceKey, untilKey: range.untilKey),
                hydratedPaths: hydratedPaths,
                confirmedAbsentHistoryRetryPaths: confirmedAbsentHistoryRetryPaths)
        } else {
            CostUsageStoreAccess.save(
                store: loadedCache.store,
                cache: cache,
                calendar: range.calendar,
                requestedScanWindow: (sinceKey: range.scanSinceKey, untilKey: range.scanUntilKey),
                reportWindow: (sinceKey: range.sinceKey, untilKey: range.untilKey),
                skipIdenticalContent: true,
                expectedScanStamp: loadedCache.scanStamp,
                receipt: loadedCache.receipt,
                requireScanStamp: true)
        }
        if saveResult.catchUpRequired {
            cache.codexScanCatchUpPending = true
            cache.codexPreviousReport = previousReport
        } else {
            CodexScanHistoryHydrationRetryRegistry.clear(
                databaseURL: loadedCache.store.databaseURL,
                committed: retryRegistryToken)
        }
        guard saveResult.cacheWasPersisted else { return }
        let expectedCommit = CostUsageStoreCodexScanCommit(
            lastScanUnixMs: max(cache.lastScanUnixMs, loadedCache.cache.lastScanUnixMs),
            rootPaths: cache.roots?.keys.map(\.self) ?? [],
            timeZoneIdentifier: range.calendar.timeZone.identifier)
        if let independentlyVerifiedCodexWindow {
            // Persist sparse window evidence only after the cache save commits. The proof is
            // computed from the final in-memory working set and never hydrates unrelated rows.
            _ = CostUsageStoreAccess.recordVerifiedCodexWindow(
                store: loadedCache.store,
                sinceDay: independentlyVerifiedCodexWindow.sinceKey,
                untilDay: independentlyVerifiedCodexWindow.untilKey,
                calendar: range.calendar,
                expectedCommit: expectedCommit)
        }
        // A bounded save can commit a safe per-day working set while full catch-up remains
        // pending. Record only days that independently passed the full inventory/file gate.
        for day in independentlyVerifiedDayKeys {
            _ = CostUsageStoreAccess.recordVerifiedCodexDay(
                store: loadedCache.store,
                day: day,
                calendar: range.calendar,
                expectedCommit: expectedCommit)
        }
    }

    private static func independentlyVerifiedCodexWindow(
        cache: CostUsageCache,
        roots: [URL],
        range: CostUsageDayRange) -> (sinceKey: String, untilKey: String)?
    {
        guard cache.codexScanCatchUpPending == true,
              self.codexRequestedWindowProjectionCanPublish(
                  cache: cache,
                  roots: roots,
                  sinceKey: range.sinceKey,
                  untilKey: range.untilKey,
                  calendar: range.calendar)
        else { return nil }
        return (sinceKey: range.sinceKey, untilKey: range.untilKey)
    }

    private static func independentlyVerifiedCodexDayKeys(
        cache: CostUsageCache,
        roots: [URL],
        now: Date,
        range: CostUsageDayRange) -> [String]
    {
        guard cache.codexScanCatchUpPending == true else { return [] }
        let currentDayKey = CostUsageDayRange.dayKey(from: now, calendar: range.calendar)
        let closedDay = range.calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let closedDayKey = CostUsageDayRange.dayKey(from: closedDay, calendar: range.calendar)
        return Array(Set([closedDayKey, currentDayKey])).sorted().filter { dayKey in
            CostUsageDayRange.isInRange(
                dayKey: dayKey,
                since: range.sinceKey,
                until: range.untilKey)
                && Self.codexCurrentDayProjectionCanPublish(
                    cache: cache,
                    roots: roots,
                    dayKey: dayKey,
                    calendar: range.calendar)
        }
    }

    private struct CodexExactValidationResult {
        let summary: CodexScanProgressSummary
        let isComplete: Bool
    }

    private static func resetCodexExactValidation(_ state: inout CostUsageCodexActiveLookbackState) {
        state.exactInventoryPendingRootPaths = nil
        state.exactInventoryDirectoryPathsByRoot = nil
        state.exactInventoryDirectoryOffsetByPath = nil
        state.exactInventoryVisitedDirectoryPaths = nil
        state.exactValidationPaths = nil
        state.exactValidationNextIndex = nil
        state.exactValidationProcessedBytes = nil
        state.exactValidationTotalBytes = nil
        state.exactValidationCompletedFiles = nil
        state.exactValidationTotalFiles = nil
        state.exactValidationSeenIdentities = nil
        state.exactValidationInventoryPaths = nil
        state.exactInventoryGeneration = nil
        state.exactInventoryScanSinceKey = nil
        state.exactInventoryScanUntilKey = nil
        state.exactInventoryNextDayKeyByRoot = nil
        state.exactInventoryDirectoryOffsetByRoot = nil
        state.exactInventoryCompletedRootPaths = nil
        state.exactInventoryFlatDirectoryOffsetByRoot = nil
        state.exactInventoryCompletedFlatRootPaths = nil
        state.exactCachedValidationLastPath = nil
        state.directoryPendingNamesByCursor = state.directoryPendingNamesByCursor?.filter {
            !$0.key.hasPrefix("exact-")
        }
    }

    private static func codexUsageTouchesWindow(
        _ usage: CostUsageFileUsage,
        sinceKey: String,
        untilKey: String) -> Bool
    {
        usage.days.keys.contains {
            CostUsageDayRange.isInRange(dayKey: $0, since: sinceKey, until: untilKey)
        }
    }

    private static func codexExactValidationNeedsCheck(
        path: String,
        roots: [URL]) -> Bool
    {
        // An old partition file can gain current usage after the prior scan. Check its
        // persisted snapshot before pruning it, even if its cached days are all old.
        self.isWithinCodexRoots(fileURL: URL(fileURLWithPath: path), roots: roots)
    }

    private static func codexExactValidationSummary(
        cache: CostUsageCache,
        generation: String,
        sinceKey: String,
        untilKey: String,
        roots: [URL]) -> CodexScanProgressSummary
    {
        var identities: Set<String> = []
        var totalBytes: Int64 = 0
        for (path, usage) in cache.files
            where usage.codexInventoryValidationGeneration == generation
            && Self.codexUsageTouchesWindow(usage, sinceKey: sinceKey, untilKey: untilKey)
            && Self.isWithinCodexRoots(fileURL: URL(fileURLWithPath: path), roots: roots)
        {
            guard let identity = usage.codexScanFileId, identities.insert(identity).inserted else { continue }
            totalBytes += max(0, usage.size)
        }
        return CodexScanProgressSummary(
            processedBytes: totalBytes,
            totalBytes: totalBytes,
            completedFiles: identities.count,
            totalFiles: identities.count)
    }

    private static func validateCodexExactFile(
        _ fileURL: URL,
        generation: String,
        cache: inout CostUsageCache,
        state: inout CostUsageCodexActiveLookbackState) -> Bool
    {
        let path = Self.codexResolvedPath(fileURL)
        let metadata = Self.codexFileMetadata(fileURL: URL(fileURLWithPath: path))
        guard let identity = metadata.fileId else {
            if !FileManager.default.fileExists(atPath: path), let removed = cache.files.removeValue(forKey: path) {
                Self.applyFileDays(cache: &cache, fileDays: removed.days, sign: -1)
            }
            return true
        }
        guard var usage = cache.files[path],
              usage.hasCurrentCodexParser,
              usage.codexScanComplete != false,
              !usage.hasPendingCodexForkRetry,
              usage.codexScanFileId == identity,
              usage.mtimeUnixMs == metadata.mtimeUnixMs,
              usage.size == metadata.size
        else {
            var pendingPaths = Set(state.pendingFilePaths)
            pendingPaths.insert(path)
            state.pendingFilePaths = pendingPaths.sorted()
            Self.resetCodexExactValidation(&state)
            return false
        }
        usage.codexInventoryValidationGeneration = generation
        cache.files[path] = usage
        return true
    }

    // swiftlint:disable:next function_body_length function_parameter_count
    private static func advanceCodexExactValidation(
        cache: inout CostUsageCache,
        roots: [URL],
        scanSinceKey: String,
        scanUntilKey: String,
        calendar: Calendar,
        scanBudget: CodexScanBudget,
        checkCancellation: CancellationCheck?,
        workRecorder: CodexScanWorkRecorder?,
        state: inout CostUsageCodexActiveLookbackState) throws -> CodexExactValidationResult
    {
        if state.exactInventoryGeneration == nil
            || state.exactInventoryScanSinceKey != scanSinceKey
            || state.exactInventoryScanUntilKey != scanUntilKey
        {
            self.resetCodexExactValidation(&state)
            state.exactInventoryGeneration = UUID().uuidString
            state.exactInventoryScanSinceKey = scanSinceKey
            state.exactInventoryScanUntilKey = scanUntilKey
            state.exactInventoryNextDayKeyByRoot = [:]
            state.exactInventoryDirectoryOffsetByRoot = [:]
            state.exactInventoryCompletedRootPaths = []
            state.exactInventoryFlatDirectoryOffsetByRoot = [:]
            state.exactInventoryCompletedFlatRootPaths = []
        }
        let generation = state.exactInventoryGeneration ?? UUID().uuidString
        var remainingWorkVisits = Self.codexCatchUpScanCandidateLimit
        var completedRoots = Set(state.exactInventoryCompletedRootPaths ?? [])
        var completedFlatRoots = Set(state.exactInventoryCompletedFlatRootPaths ?? [])
        let retainedSince = Self.localStartOfDay(scanSinceKey, calendar: calendar) ?? .distantPast
        for root in roots where remainingWorkVisits > 0 && !scanBudget.shouldStopBeforeNextFile() {
            try checkCancellation?()
            let rootPath = Self.codexResolvedPath(root)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let partitionCursorKey = "exact-partition:\(rootPath)"
            let flatCursorKey = "exact-flat:\(rootPath)"
            state.directoryPendingNamesByCursor = state.directoryPendingNamesByCursor ?? [:]
            if !completedRoots.contains(rootPath) {
                let page = Self.listCodexSessionFilesByDatePartitionPage(
                    root: root,
                    scanSinceKey: scanSinceKey,
                    scanUntilKey: scanUntilKey,
                    resumeDayKey: state.exactInventoryNextDayKeyByRoot?[rootPath],
                    resumeDirectoryOffset: state.exactInventoryDirectoryOffsetByRoot?[rootPath] ?? 0,
                    resumePendingNames: state.directoryPendingNamesByCursor?[partitionCursorKey] ?? [],
                    visitLimit: remainingWorkVisits,
                    preferNewest: false,
                    calendar: calendar,
                    shouldStop: { scanBudget.shouldStopBeforeNextFile() },
                    workRecorder: workRecorder)
                remainingWorkVisits -= page.visits
                for fileURL in page.files {
                    guard Self.validateCodexExactFile(
                        fileURL,
                        generation: generation,
                        cache: &cache,
                        state: &state)
                    else {
                        return CodexExactValidationResult(
                            summary: Self.codexExactValidationSummary(
                                cache: cache,
                                generation: generation,
                                sinceKey: scanSinceKey,
                                untilKey: scanUntilKey,
                                roots: roots),
                            isComplete: false)
                    }
                }
                if page.isComplete {
                    completedRoots.insert(rootPath)
                    state.exactInventoryNextDayKeyByRoot?.removeValue(forKey: rootPath)
                    state.exactInventoryDirectoryOffsetByRoot?.removeValue(forKey: rootPath)
                    state.directoryPendingNamesByCursor?.removeValue(forKey: partitionCursorKey)
                } else {
                    state.exactInventoryNextDayKeyByRoot?[rootPath] = page.nextDayKey
                    state.exactInventoryDirectoryOffsetByRoot?[rootPath] = page.nextDirectoryOffset
                    state.directoryPendingNamesByCursor?[partitionCursorKey] = page.pendingNames
                }
            }
            if completedRoots.contains(rootPath),
               !completedFlatRoots.contains(rootPath),
               remainingWorkVisits > 0,
               !scanBudget.shouldStopBeforeNextFile()
            {
                let page = Self.listCodexDirectoryPage(
                    directoryURL: root,
                    resumeOffset: state.exactInventoryFlatDirectoryOffsetByRoot?[rootPath] ?? 0,
                    visitLimit: remainingWorkVisits,
                    resumePendingNames: state.directoryPendingNamesByCursor?[flatCursorKey] ?? [],
                    filter: { name in
                        guard name.lowercased().hasSuffix(".jsonl") else { return false }
                        guard let dayKey = Self.dayKeyFromFilename(name) else { return true }
                        return CostUsageDayRange.isInRange(
                            dayKey: dayKey,
                            since: scanSinceKey,
                            until: scanUntilKey)
                    },
                    shouldStop: { scanBudget.shouldStopBeforeNextFile() },
                    workRecorder: workRecorder)
                remainingWorkVisits -= page.visits
                for fileURL in page.files {
                    let path = Self.codexResolvedPath(fileURL)
                    let hasActiveCachedUsage = cache.files[path].map {
                        Self.codexUsageTouchesWindow($0, sinceKey: scanSinceKey, untilKey: scanUntilKey)
                    } ?? false
                    let modifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate
                    guard Self.dayKeyFromFilename(fileURL.lastPathComponent) != nil
                        || hasActiveCachedUsage
                        || (modifiedAt ?? .distantPast) >= retainedSince
                    else { continue }
                    guard Self.validateCodexExactFile(
                        fileURL,
                        generation: generation,
                        cache: &cache,
                        state: &state)
                    else {
                        return CodexExactValidationResult(
                            summary: Self.codexExactValidationSummary(
                                cache: cache,
                                generation: generation,
                                sinceKey: scanSinceKey,
                                untilKey: scanUntilKey,
                                roots: roots),
                            isComplete: false)
                    }
                }
                if page.isUnavailable {
                    state.exactInventoryFlatDirectoryOffsetByRoot?[rootPath] = page.nextOffset
                    state.directoryPendingNamesByCursor?[flatCursorKey] = page.pendingNames
                } else if let nextOffset = page.nextOffset {
                    state.exactInventoryFlatDirectoryOffsetByRoot?[rootPath] = nextOffset
                    state.directoryPendingNamesByCursor?[flatCursorKey] = page.pendingNames
                } else {
                    completedFlatRoots.insert(rootPath)
                    state.exactInventoryFlatDirectoryOffsetByRoot?.removeValue(forKey: rootPath)
                    state.directoryPendingNamesByCursor?.removeValue(forKey: flatCursorKey)
                }
            }
        }
        state.exactInventoryCompletedRootPaths = completedRoots.sorted()
        state.exactInventoryCompletedFlatRootPaths = completedFlatRoots.sorted()
        let rootPaths = Set(roots.map(Self.codexResolvedPath))
        guard completedRoots == rootPaths, completedFlatRoots == rootPaths else {
            return CodexExactValidationResult(
                summary: Self.codexExactValidationSummary(
                    cache: cache,
                    generation: generation,
                    sinceKey: scanSinceKey,
                    untilKey: scanUntilKey,
                    roots: roots),
                isComplete: false)
        }

        let lastPath = state.exactCachedValidationLastPath
        let candidates = cache.files.keys.filter { path in
            guard lastPath.map({ path > $0 }) ?? true else { return false }
            return Self.codexExactValidationNeedsCheck(
                path: path,
                roots: roots)
        }.sorted().prefix(remainingWorkVisits)
        for path in candidates where !scanBudget.shouldStopBeforeNextFile() {
            try checkCancellation?()
            workRecorder?.recordCodexProgressAccountingVisit()
            remainingWorkVisits -= 1
            state.exactCachedValidationLastPath = path
            guard Self.validateCodexExactFile(
                URL(fileURLWithPath: path),
                generation: generation,
                cache: &cache,
                state: &state)
            else {
                return CodexExactValidationResult(
                    summary: Self.codexExactValidationSummary(
                        cache: cache,
                        generation: generation,
                        sinceKey: scanSinceKey,
                        untilKey: scanUntilKey,
                        roots: roots),
                    isComplete: false)
            }
        }
        let hasRemainingCachedValidation = cache.files.contains { path, _ in
            (state.exactCachedValidationLastPath.map { path > $0 } ?? true)
                && Self.codexExactValidationNeedsCheck(
                    path: path,
                    roots: roots)
        }
        let summary = Self.codexExactValidationSummary(
            cache: cache,
            generation: generation,
            sinceKey: scanSinceKey,
            untilKey: scanUntilKey,
            roots: roots)
        return CodexExactValidationResult(
            summary: summary,
            isComplete: !hasRemainingCachedValidation)
    }

    // swiftlint:disable:next function_parameter_count
    private static func rollingCodexRetentionWindow(
        cachedSinceKey: String?,
        cachedUntilKey: String?,
        cachedRetainedLookbackDays: Int?,
        requestedSinceKey: String,
        requestedUntilKey: String,
        calendar: Calendar) -> (sinceKey: String, untilKey: String, rememberedLookbackDays: Int)
    {
        let maximumRememberedLookbackDays = 365
        let calendar = CostUsageDayRange.localGregorianCalendar(matching: calendar)
        guard let requestedSince = Self.parseDayKey(requestedSinceKey, calendar: calendar),
              let requestedUntil = Self.parseDayKey(requestedUntilKey, calendar: calendar),
              requestedSince <= requestedUntil
        else { return (requestedSinceKey, requestedUntilKey, 1) }
        let requestedDays = max(
            1,
            (calendar.dateComponents([.day], from: requestedSince, to: requestedUntil).day ?? 0) + 1)
        guard let cachedSinceKey,
              let cachedUntilKey,
              let cachedSince = Self.parseDayKey(cachedSinceKey, calendar: calendar),
              let cachedUntil = Self.parseDayKey(cachedUntilKey, calendar: calendar),
              cachedSince <= cachedUntil
        else {
            return (
                requestedSinceKey,
                requestedUntilKey,
                min(requestedDays, maximumRememberedLookbackDays))
        }

        let cachedDays = max(1, (calendar.dateComponents([.day], from: cachedSince, to: cachedUntil).day ?? 0) + 1)
        let rememberedCachedDays = min(
            max(1, cachedRetainedLookbackDays ?? cachedDays),
            maximumRememberedLookbackDays)
        let retainedDays = max(rememberedCachedDays, requestedDays)
        let rememberedLookbackDays = min(
            max(rememberedCachedDays, requestedDays),
            maximumRememberedLookbackDays)
        let retainedUntil = requestedUntil
        let rollingSince = calendar.date(
            byAdding: .day,
            value: -(retainedDays - 1),
            to: retainedUntil) ?? requestedSince
        return (
            CostUsageDayRange.dayKey(from: rollingSince, calendar: calendar),
            CostUsageDayRange.dayKey(from: retainedUntil, calendar: calendar),
            rememberedLookbackDays)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func loadCodexDaily(
        range: CostUsageDayRange,
        now: Date,
        options: Options,
        checkCancellation: CancellationCheck?) throws -> CostUsageDailyReport
    {
        let loadedCache = Self.loadCodexCache(options: options, range: range)
        defer { loadedCache.release() }
        var cache = loadedCache.cache
        var retryRegistryToken = CodexScanHistoryHydrationRetryRegistry.mergePending(
            databaseURL: loadedCache.store.databaseURL,
            into: &cache)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        // Keep an unfinished discovery queue on its original wider scan range when a
        // dashboard requests a narrower report of the same roots and ending day.
        let scanRange: CostUsageDayRange
        if !options.forceRescan,
           cache.timeZoneIdentifier == range.calendar.timeZone.identifier,
           cache.scanUntilKey == range.scanUntilKey,
           let pending = cache.codexActiveLookbackState,
           pending.rootPaths == Self.codexSessionsRoots(options: options)
               .map(Self.codexResolvedPath).sorted()
        {
            // The requested window has one day of scan padding on each side. Preserve
            // unfinished discovery within the maximum 365-day lookback, but do not let
            // an older request pin later narrow refreshes to years of stale history.
            let oldestRetainedScanDay = range.calendar.date(
                byAdding: .day,
                value: -365,
                to: Self.parseDayKey(range.untilKey, calendar: range.calendar) ?? now)
                .map { CostUsageDayRange.dayKey(from: $0, calendar: range.calendar) }
                ?? pending.scanSinceKey
            scanRange = range.retainingScanStart(max(pending.scanSinceKey, oldestRetainedScanDay))
        } else {
            scanRange = range
        }
        let plan = Self.makeCodexRefreshPlan(cache: cache, range: scanRange, now: now, nowMs: nowMs, options: options)
        let previousReport = Self.codexPreviousReportCandidate(
            cache: cache,
            store: loadedCache.store,
            range: range,
            plan: plan,
            options: options)

        if plan.shouldRefresh {
            let range = scanRange
            try checkCancellation?()
            var listingMetadataByPath: [String: CodexFileMetadata] = [:]
            let listingMetadata: CodexListingMetadataReader = { fileURL in
                let path = fileURL.path
                if let cached = listingMetadataByPath[path] { return cached }
                options.codexScanWorkRecorderForTesting?.recordCodexListingMetadataRead()
                let metadata = Self.codexFileMetadata(fileURL: fileURL)
                listingMetadataByPath[path] = metadata
                return metadata
            }
            let cachedSinceKey = cache.scanSinceKey
            let cachedUntilKey = cache.scanUntilKey
            // Once a bounded migration starts, its marker becomes current while the file is
            // incomplete. Retain both cached window edges until that prefix finishes parsing.
            let parserMigrationPending = cache.files.values.contains {
                !$0.hasCurrentCodexParser || $0.codexScanComplete == false
            }
            let shouldRunColdCacheLookback = cache.files.isEmpty || plan.rootsChanged
            let coldCacheLookbackStart = Self.localStartOfDay(range.scanSinceKey, calendar: options.calendar)
            let scanBudget = options.codexScanBudgetForTesting ?? CodexScanBudget(
                maxFileBytes: options.maxCodexSessionFileBytes,
                maxBytesPerRefresh: options.maxCodexScanBytesPerRefresh,
                maxDuration: options.maxCodexScanDurationPerRefresh)
            var activeLookbackState = Self.codexActiveLookbackState(
                cache: cache,
                roots: plan.roots,
                scanSinceKey: range.scanSinceKey,
                includeLegacyRecursiveScan: shouldRunColdCacheLookback)
            let activeLookbackStateWasReset = cache.codexActiveLookbackState.map {
                $0.scanSinceKey != activeLookbackState.scanSinceKey
                    || $0.rootPaths != activeLookbackState.rootPaths
            } ?? true
            let isExactInventoryProofPass = scanBudget.hasTimeLimit
                && !options.forceRescan
                && !options.useCodexCatchUpWorkingSet
                && cache.codexActiveLookbackState != nil
                && Self.codexBoundedDiscoveryIsComplete(activeLookbackState)
                && !plan.requiresCacheWideFileReprocessing
                && plan.historyRetryPathKeys.isEmpty
            if isExactInventoryProofPass {
                let retainedWindow = Self.rollingCodexRetentionWindow(
                    cachedSinceKey: cachedSinceKey,
                    cachedUntilKey: cachedUntilKey,
                    cachedRetainedLookbackDays: cache.codexRetainedLookbackDays,
                    requestedSinceKey: range.scanSinceKey,
                    requestedUntilKey: range.scanUntilKey,
                    calendar: range.calendar)
                let exact = try Self.advanceCodexExactValidation(
                    cache: &cache,
                    roots: plan.roots,
                    scanSinceKey: retainedWindow.sinceKey,
                    scanUntilKey: retainedWindow.untilKey,
                    calendar: range.calendar,
                    scanBudget: scanBudget,
                    checkCancellation: checkCancellation,
                    workRecorder: options.codexScanWorkRecorderForTesting,
                    state: &activeLookbackState)
                if exact.isComplete {
                    let generation = activeLookbackState.exactInventoryGeneration
                    for path in cache.files.keys {
                        guard let old = cache.files[path],
                              Self.codexUsageTouchesWindow(
                                  old,
                                  sinceKey: retainedWindow.sinceKey,
                                  untilKey: retainedWindow.untilKey),
                              Self.isWithinCodexRoots(fileURL: URL(fileURLWithPath: path), roots: plan.roots),
                              old.codexInventoryValidationGeneration != generation
                        else { continue }
                        Self.applyFileDays(cache: &cache, fileDays: old.days, sign: -1)
                        cache.files.removeValue(forKey: path)
                    }
                    let activeInventoryPaths: [String] = cache.files.compactMap { entry in
                        let (path, usage) = entry
                        guard usage.codexInventoryValidationGeneration == generation,
                              Self.codexUsageTouchesWindow(
                                  usage,
                                  sinceKey: retainedWindow.sinceKey,
                                  untilKey: retainedWindow.untilKey)
                        else { return nil }
                        return path
                    }
                    cache.codexScanInventoryPaths = activeInventoryPaths.count
                        <= Self.codexCatchUpScanCandidateLimit ? activeInventoryPaths.sorted() : nil
                    cache.codexActiveLookbackState = nil
                } else {
                    cache.codexScanInventoryPaths = nil
                    cache.codexActiveLookbackState = activeLookbackState
                }
                Self.pruneDays(
                    cache: &cache,
                    sinceKey: retainedWindow.sinceKey,
                    untilKey: retainedWindow.untilKey)
                cache.roots = plan.rootsFingerprint
                cache.scanSinceKey = retainedWindow.sinceKey
                cache.scanUntilKey = retainedWindow.untilKey
                cache.codexRetainedLookbackDays = retainedWindow.rememberedLookbackDays
                cache.codexPricingKey = plan.codexPricingKey
                cache.codexPriorityMetadataKey = plan.codexPriorityMetadataKey
                cache.codexProjectMetadataVersion = Self.codexProjectMetadataVersion
                cache.codexScanProcessedBytes = exact.summary.processedBytes
                cache.codexScanTotalBytes = exact.summary.totalBytes
                cache.codexScanCompletedFiles = exact.summary.completedFiles
                cache.codexScanTotalFiles = exact.summary.totalFiles
                cache.codexScanCatchUpPending = !exact.isComplete
                cache.codexPreviousReport = exact.isComplete ? nil : previousReport
                cache.lastScanUnixMs = nowMs
                let independentlyVerifiedCodexWindow = Self.independentlyVerifiedCodexWindow(
                    cache: cache,
                    roots: plan.roots,
                    range: range)
                let independentlyVerifiedDayKeys = Self.independentlyVerifiedCodexDayKeys(
                    cache: cache,
                    roots: plan.roots,
                    now: now,
                    range: range)
                Self.saveCodexCache(
                    &cache,
                    loadedCache: loadedCache,
                    range: range,
                    previousReport: previousReport,
                    retryRegistryToken: retryRegistryToken,
                    independentlyVerifiedCodexWindow: independentlyVerifiedCodexWindow,
                    independentlyVerifiedDayKeys: independentlyVerifiedDayKeys)
                if let previous = Self.codexPreviousReport(
                    cache: cache,
                    range: range,
                    rootsFingerprint: plan.rootsFingerprint)
                {
                    return Self.scopedPreviousReport(previous, range: range)
                }
                return Self.buildCodexReportFromCache(
                    cache: cache,
                    range: range,
                    modelsDevCatalog: plan.modelsDevCatalog,
                    modelsDevCacheRoot: options.cacheRoot,
                    priorityTurns: plan.priorityTurns)
            }
            let hasScanLimit = scanBudget.hasTimeLimit || scanBudget.maxFileBytes > 0
                || scanBudget.maxBytesPerRefresh > 0
            let shouldBoundCatchUp = hasScanLimit
                && (options.forceRescan
                    || (scanBudget.hasTimeLimit && cache.files.isEmpty)
                    || cache.codexScanCatchUpPending == true
                    || cache.files.values.contains(where: \.hasPendingCodexScanWork)
                    || cache.codexActiveLookbackState != nil
                    || plan.requiresCacheWideFileReprocessing)
            let shouldPageDiscovery = scanBudget.hasTimeLimit && shouldBoundCatchUp && !isExactInventoryProofPass
            if shouldBoundCatchUp, !scanBudget.hasTimeLimit || activeLookbackStateWasReset {
                Self.appendCodexActiveLookbackPaths(
                    cache.files.keys.sorted().filter { cache.files[$0]?.hasPendingCodexScanWork == true }
                        .map { URL(fileURLWithPath: $0, isDirectory: false) },
                    state: &activeLookbackState)
            }
            let migrationQueueOwnsCachedPaths = plan.requiresCacheWideFileReprocessing
                || activeLookbackState.cacheWideMigrationQueueActive == true
            let hasPersistedMetadataSweep = cache.codexSessionDiscovery?.metadataInventoryEstablished == true
            // After a persisted metadata sweep exists, paginated filesystem discovery owns new
            // paths rather than re-enqueuing every completed cached file. The metadata sweep
            // itself detects edits/deletions across the retained history, current-day checks
            // front-load active changes, and migrations retain their explicit complete seed.
            let discoveryExcludedPathKeys = migrationQueueOwnsCachedPaths || hasPersistedMetadataSweep
                ? Set(cache.files.keys.map {
                    Self.codexPathKey(URL(fileURLWithPath: $0, isDirectory: false))
                })
                : []
            var seenPaths: Set<String> = []
            var fileURLsByPathKey: [String: URL] = [:]
            var files: [URL] = []
            var remainingDiscoveryVisits = Self.codexCatchUpScanCandidateLimit
            for root in plan.roots {
                if shouldPageDiscovery {
                    Self.advanceCodexCurrentWindow(
                        root: root,
                        range: range,
                        preferNewest: options.preferNewestCodexSessionsFirst,
                        remainingDiscoveryVisits: &remainingDiscoveryVisits,
                        excludedPendingPathKeys: discoveryExcludedPathKeys,
                        workRecorder: options.codexScanWorkRecorderForTesting,
                        listingMetadata: listingMetadata,
                        state: &activeLookbackState)
                } else {
                    let rootFiles = Self.listCodexSessionFiles(
                        root: root,
                        scanSinceKey: range.scanSinceKey,
                        scanUntilKey: range.scanUntilKey,
                        includeRecursive: options.forceRescan || isExactInventoryProofPass,
                        calendar: options.calendar,
                        workRecorder: options.codexScanWorkRecorderForTesting)
                    for path in rootFiles.map(\.path).sorted() {
                        let pathKey = Self.codexPathKey(standardizedPath: path)
                        guard seenPaths.insert(pathKey).inserted else { continue }
                        let canonicalFileURL = URL(fileURLWithPath: pathKey, isDirectory: false)
                        fileURLsByPathKey[pathKey] = canonicalFileURL
                        files.append(canonicalFileURL)
                    }
                }

                // The lookback runs on every refresh, not just cold ones: a session
                // resumed in an older date partition is appended to in place, so the
                // in-window partition listing never sees it and `cachedCodexSessionFiles`
                // cannot either until it has been scanned once. Without this, such a
                // session's usage stays invisible until a forced rescan.
                //
                // Partition discovery and any discovered candidates persist across bounded
                // passes. That prevents a small budget from restarting at the oldest day or
                // rediscovering a file without ever leaving enough budget to parse it.
                if isExactInventoryProofPass {
                    let rootPath = Self.codexResolvedPath(root)
                    activeLookbackState.completedRootPaths = Array(
                        Set(activeLookbackState.completedRootPaths).union([rootPath])).sorted()
                    activeLookbackState.legacyRecursivePendingRootPaths.removeAll { $0 == rootPath }
                    activeLookbackState.nextDayKeyByRoot.removeValue(forKey: rootPath)
                    activeLookbackState.nextDirectoryOffsetByRoot?.removeValue(forKey: rootPath)
                } else if let coldCacheLookbackStart {
                    if shouldPageDiscovery {
                        Self.advanceCodexActiveLookbackPage(
                            root: root,
                            range: range,
                            modifiedSince: coldCacheLookbackStart,
                            preferNewest: options.preferNewestCodexSessionsFirst,
                            remainingDiscoveryVisits: &remainingDiscoveryVisits,
                            excludedPendingPathKeys: discoveryExcludedPathKeys,
                            workRecorder: options.codexScanWorkRecorderForTesting,
                            state: &activeLookbackState)
                        Self.advanceCodexLegacyRecursivePage(
                            root: root,
                            remainingDiscoveryVisits: &remainingDiscoveryVisits,
                            excludedPendingPathKeys: discoveryExcludedPathKeys,
                            workRecorder: options.codexScanWorkRecorderForTesting,
                            state: &activeLookbackState)
                    } else {
                        Self.advanceCodexActiveLookback(
                            root: root,
                            range: range,
                            modifiedSince: coldCacheLookbackStart,
                            scanBudget: scanBudget,
                            state: &activeLookbackState)
                    }
                }
            }
            let historyRetryTargetURLs = (cache.codexHistoryHydrationRetries ?? [:])
                .keys
                .sorted()
                .compactMap { path -> URL? in
                    let fileURL = URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL
                    guard Self.isWithinCodexRoots(fileURL: fileURL, roots: plan.roots) else { return nil }
                    return fileURL
                }
            for fileURL in historyRetryTargetURLs {
                let pathKey = Self.codexPathKey(fileURL)
                guard seenPaths.insert(pathKey).inserted else { continue }
                let canonicalFileURL = URL(fileURLWithPath: pathKey, isDirectory: false)
                fileURLsByPathKey[pathKey] = canonicalFileURL
                files.append(canonicalFileURL)
            }
            if shouldBoundCatchUp {
                Self.appendCodexActiveLookbackPaths(
                    historyRetryTargetURLs,
                    normalizeExisting: true,
                    state: &activeLookbackState)
            }
            let recoveredPendingPathCount = shouldBoundCatchUp
                ? Self.reconcileCachedCodexPendingPaths(
                    cache: cache,
                    roots: plan.roots,
                    state: &activeLookbackState)
                : 0
            if recoveredPendingPathCount > 0 {
                Self.log.info(
                    "Codex cost scan restored omitted pending files",
                    metadata: ["recoveredFiles": "\(recoveredPendingPathCount)"])
            }

            // Priority metadata can reprice old, otherwise unchanged sessions. Resolve every
            // affected persisted path before bounded selection and append it to the durable
            // lookback queue. Subsequent passes therefore cannot lose the tail of a result set
            // larger than the per-pass candidate limit.
            if options.useCodexCatchUpWorkingSet,
               !plan.changedPriorityTurnIDs.isEmpty,
               activeLookbackState.priorityMigrationGenerationKey != plan.codexPriorityMetadataKey
            {
                let priorityPaths = try CostUsageStoreAccess.pathsContainingCodexTurnIDs(
                    store: loadedCache.store,
                    turnIDs: plan.changedPriorityTurnIDs)
                Self.appendCodexActiveLookbackPaths(
                    priorityPaths.sorted().map { URL(fileURLWithPath: $0) },
                    normalizeExisting: true,
                    state: &activeLookbackState)
                if !priorityPaths.isEmpty {
                    activeLookbackState.cacheWideMigrationQueueActive = true
                }
                activeLookbackState.priorityMigrationGenerationKey = plan.codexPriorityMetadataKey
            }

            if options.useCodexCatchUpWorkingSet,
               scanBudget.maxBytesPerRefresh == 0
               || scanBudget.maxFileBytes > 0
               && scanBudget.maxBytesPerRefresh > scanBudget.maxFileBytes
            {
                let currentDayKey = CostUsageDayRange.dayKey(from: now, calendar: range.calendar)
                Self.appendCodexActiveLookbackPaths(
                    Self.codexChangedCurrentDayCachedFiles(
                        cache: cache,
                        roots: plan.roots,
                        dayKey: currentDayKey,
                        calendar: range.calendar,
                        metadata: listingMetadata),
                    state: &activeLookbackState)
            }

            let cachedCodexFilesForQueue = !shouldPageDiscovery
                ? Self.cachedCodexSessionFiles(
                    cache: cache,
                    range: range,
                    roots: plan.roots,
                    excludingPaths: seenPaths)
                .sorted(by: { $0.path < $1.path })
                : []
            let queueSeedFiles = files + cachedCodexFilesForQueue
            // Completed, unchanged cache entries already contribute to the ledger. Enqueuing
            // them on a fresh bounded pass can spend the only candidate slot on a no-op while
            // an appended partial session waits behind it. Explicit migrations use their own
            // reseed path below and still revisit those entries.
            let pendingQueueSeedFiles = queueSeedFiles.filter {
                Self.codexCachedFileNeedsScan($0, cache: cache, metadata: listingMetadata)
            }
            let preMaterializationInventoryPathKeys = Set(cache.files.keys.map {
                Self.codexPathKey(URL(fileURLWithPath: $0, isDirectory: false))
            }).union(queueSeedFiles.map(Self.codexPathKey))
            let cacheWideMigrationNeedsQueueReseed = Self.cacheWideMigrationNeedsQueueReseed(
                plan: plan,
                inventoryPathKeys: preMaterializationInventoryPathKeys,
                state: activeLookbackState)
            let migrationSeedPathKeys = cacheWideMigrationNeedsQueueReseed
                ? (options.preferNewestCodexSessionsFirst
                    ? Self.sortedCodexSessionFilesNewestFirst(
                        preMaterializationInventoryPathKeys.map {
                            URL(fileURLWithPath: $0, isDirectory: false)
                        },
                        metadata: listingMetadata)
                    : preMaterializationInventoryPathKeys.sorted().map {
                        URL(fileURLWithPath: $0, isDirectory: false)
                    })
                .map(Self.codexPathKey)
                : nil
            if cacheWideMigrationNeedsQueueReseed {
                activeLookbackState.cacheWideMigrationQueueActive = true
            }
            // One-shot metadata keys can advance in this pass because the durable queue now owns
            // every required revisit. Later passes observe the new key and drain the queue without reseeding.
            let shouldSeedBoundedQueue = activeLookbackStateWasReset || cacheWideMigrationNeedsQueueReseed
            Self.seedOrExtendCodexActiveLookbackQueue(
                context: CodexActiveLookbackQueueUpdateContext(
                    seedFiles: pendingQueueSeedFiles,
                    migrationSeedPathKeys: migrationSeedPathKeys,
                    discoveredFiles: pendingQueueSeedFiles,
                    previousDiscovery: cache.codexSessionDiscovery,
                    shouldBoundCatchUp: shouldBoundCatchUp,
                    shouldSeedBoundedQueue: shouldSeedBoundedQueue,
                    preferNewest: options.preferNewestCodexSessionsFirst,
                    listingMetadata: listingMetadata),
                state: &activeLookbackState)

            // Prioritize the most recent closed day before materializing the pending prefix so
            // that the bounded candidate slice actually contains that partition.
            let mostRecentClosedDayKey = range.calendar.date(
                byAdding: .day,
                value: -1,
                to: now)
                .map {
                    CostUsageDayRange.dayKey(from: $0, calendar: range.calendar)
                }
            let priorityDayKey = mostRecentClosedDayKey.flatMap {
                CostUsageDayRange.isInRange(
                    dayKey: $0,
                    since: range.sinceKey,
                    until: range.untilKey) ? $0 : nil
            }
            let promotedPendingPath = (options.preferNewestCodexSessionsFirst
                || scanBudget.maxBytesPerRefresh == 0)
                ? Self.prioritizeCodexRequestedWindowPendingPaths(
                    cache: cache,
                    range: range,
                    dayKeys: (
                        priority: priorityDayKey,
                        current: CostUsageDayRange.dayKey(from: now, calendar: range.calendar)),
                    listingMetadata: listingMetadata,
                    state: &activeLookbackState)
                : nil

            let materializedPendingPathCount = Self.appendPendingCodexActiveLookbackFiles(
                state: &activeLookbackState,
                context: CodexPendingLookbackAppendContext(
                    roots: plan.roots,
                    maxCount: shouldBoundCatchUp ? Self.codexCatchUpScanCandidateLimit : nil,
                    validateRoots: activeLookbackStateWasReset),
                seenPaths: &seenPaths,
                fileURLsByPathKey: &fileURLsByPathKey,
                files: &files)
            let hasUnmaterializedPendingPaths = activeLookbackState.pendingFilePaths
                .count > materializedPendingPathCount

            for fileURL in cachedCodexFilesForQueue {
                let pathKey = Self.codexPathKey(fileURL)
                guard seenPaths.insert(pathKey).inserted else { continue }
                fileURLsByPathKey[pathKey] = fileURL
                files.append(fileURL)
            }

            let inventoryPathKeys = shouldPageDiscovery
                ? Set(cache.files.keys.map {
                    Self.codexPathKey(URL(fileURLWithPath: $0, isDirectory: false))
                })
                .union(fileURLsByPathKey.keys)
                : Set(fileURLsByPathKey.keys)
            if shouldBoundCatchUp, !scanBudget.hasTimeLimit {
                // Full byte-only discovery sees appends to completed files and new files that
                // were discovered but not admitted on an earlier pass. Dependency-only orphan
                // checks belong to the fresh queue seed: re-adding settled files while a bounded
                // working set drains would prevent a queue larger than one allowance from settling.
                let dirtyFiles = files.filter {
                    Self.codexCachedFileNeedsScan(
                        $0,
                        cache: cache,
                        metadata: listingMetadata,
                        validateSettledForkDependencies: false)
                }
                Self.appendCodexActiveLookbackPaths(
                    options.preferNewestCodexSessionsFirst
                        ? Self.sortedCodexSessionFilesNewestFirst(
                            dirtyFiles, metadata: listingMetadata) : dirtyFiles,
                    state: &activeLookbackState)
            }
            var filePathsInScan = seenPaths
            if activeLookbackState.cacheWideMigrationQueueActive == true {
                filePathsInScan.formUnion(inventoryPathKeys)
            }
            let canExtendSelectedPrefix = shouldSeedBoundedQueue
                || (!isExactInventoryProofPass && !hasUnmaterializedPendingPaths)
            let boundedQueuePathCount = canExtendSelectedPrefix
                ? min(Self.codexCatchUpScanCandidateLimit, activeLookbackState.pendingFilePaths.count)
                : materializedPendingPathCount
            let refreshSelection = Self.codexFilesScheduledForRefresh(
                files,
                activeLookbackState: &activeLookbackState,
                context: CodexRefreshCandidateSelectionContext(
                    fileURLsByPathKey: fileURLsByPathKey,
                    shouldBoundCatchUp: shouldBoundCatchUp,
                    boundedQueuePathCount: boundedQueuePathCount,
                    preferNewest: options.preferNewestCodexSessionsFirst,
                    listingMetadata: listingMetadata,
                    workRecorder: options.codexScanWorkRecorderForTesting))
            let filesScheduledForRefresh: [URL]
            var hydratedCodexPaths: Set<String>
            let hydrationDeferredCandidates: Bool
            var requestReconciliations: [String: CostUsageCodexRequestReconciliation]
            if options.useCodexCatchUpWorkingSet {
                let hydrationPlan = Self.codexCatchUpHydrationPlan(
                    scheduledFiles: refreshSelection.files,
                    cache: cache,
                    scanBudget: scanBudget)
                filesScheduledForRefresh = hydrationPlan.scheduledFiles
                hydratedCodexPaths = hydrationPlan.paths
                hydrationDeferredCandidates = hydrationPlan.deferredCandidates
                requestReconciliations = hydrationPlan.requestReconciliations
                if !hydratedCodexPaths.isEmpty {
                    options.codexScanWorkRecorderForTesting?.recordCodexHydration(
                        files: hydratedCodexPaths.count)
                    let hydrated = CostUsageStoreAccess.hydrateCodexWorkingSet(
                        store: loadedCache.store,
                        calendar: range.calendar,
                        paths: hydratedCodexPaths)
                    // The working-set read returns the same compact manifest plus selected
                    // detail rows. Keep all compact file entries, replacing only their hydrated
                    // values so discovery/progress can still reason about the full inventory.
                    cache.files = hydrated.files
                }
            } else {
                filesScheduledForRefresh = refreshSelection.files
                hydratedCodexPaths = []
                hydrationDeferredCandidates = false
                requestReconciliations = [:]
            }
            let completionStatesBeforeScan = Self.codexCompletionStates(
                files: filesScheduledForRefresh.prefix(Self.codexCatchUpScanCandidateLimit),
                cache: cache,
                includePreviouslyCompletedSnapshots: true)
            let fileIndex = CodexSessionFileIndex(
                files: files,
                roots: plan.roots,
                cachedSessionFiles: shouldPageDiscovery
                    ? [:]
                    : Self.cachedCodexSessionIndex(
                        cache: cache,
                        roots: plan.roots,
                        knownExistingPaths: filePathsInScan),
                cachedDiscovery: plan.rootsChanged ? nil : cache.codexSessionDiscovery,
                scanBudget: scanBudget,
                headParseObserver: self.codexSessionHeadParseObserverStore?.observer,
                checkCancellation: checkCancellation)
            let historyHydrator = options.useCodexCatchUpWorkingSet
                ? nil
                : CodexScanHistoryHydrator(
                    storeLoad: loadedCache,
                    checkCancellation: checkCancellation)
            let inheritedResolver = CodexInheritedTotalsResolver(
                fileIndex: fileIndex,
                checkCancellation: checkCancellation,
                scanBudget: scanBudget,
                cachedFiles: cache.files,
                historyHydrator: historyHydrator)
            let cachePathAliasIndex = CodexCachePathAliasIndex(
                files: cache.files,
                workRecorder: options.codexScanWorkRecorderForTesting)
            let resources = CodexScanResources(
                fileIndex: fileIndex,
                inheritedResolver: inheritedResolver,
                cachePathAliasIndex: cachePathAliasIndex,
                historyHydrator: historyHydrator,
                projectPathResolver: CodexCanonicalProjectPathResolver(),
                modelsDevCatalog: plan.modelsDevCatalog,
                modelsDevCacheRoot: options.cacheRoot,
                priorityTurns: plan.priorityTurns)
            let metadataRetainedWindow = Self.rollingCodexRetentionWindow(
                cachedSinceKey: options.forceRescan ? nil : cachedSinceKey,
                cachedUntilKey: options.forceRescan ? nil : cachedUntilKey,
                cachedRetainedLookbackDays: options.forceRescan ? nil : cache.codexRetainedLookbackDays,
                requestedSinceKey: range.scanSinceKey,
                requestedUntilKey: parserMigrationPending
                    ? max(range.scanUntilKey, cachedUntilKey ?? range.scanUntilKey)
                    : range.scanUntilKey,
                calendar: range.calendar)
            let metadataScanRange: CostUsageDayRange = if
                let retainedSince = Self.parseDayKey(
                    metadataRetainedWindow.sinceKey,
                    calendar: range.calendar),
                let retainedUntil = Self.parseDayKey(
                    metadataRetainedWindow.untilKey,
                    calendar: range.calendar)
            {
                CostUsageDayRange(
                    since: retainedSince,
                    until: retainedUntil,
                    calendar: range.calendar)
            } else {
                range
            }
            // A parser migration must cover both ends of retained history. A narrow historical
            // request must not discard newer cached days when its file is reparsed.
            let catchUpScanRange = options.useCodexCatchUpWorkingSet || parserMigrationPending
                ? metadataScanRange : range
            var scanContext = Self.codexFileScanContext(
                range: catchUpScanRange,
                options: options,
                plan: plan,
                resources: resources,
                checkCancellation: checkCancellation,
                scanBudget: scanBudget)
            scanContext.requestReconciliationCandidatePaths = Set(requestReconciliations.keys)
            var scanResult = try Self.scanCodexFiles(
                filesScheduledForRefresh,
                context: scanContext,
                cache: &cache,
                inheritedResolver: inheritedResolver,
                hydratedPaths: options.useCodexCatchUpWorkingSet ? hydratedCodexPaths : nil)
            let currentDayKey = CostUsageDayRange.dayKey(from: now, calendar: range.calendar)
            var metadataRefreshCandidates: [URL]
            if options.useCodexCatchUpWorkingSet {
                var metadataScanContext = Self.codexFileScanContext(
                    range: metadataScanRange,
                    options: options,
                    plan: plan,
                    resources: resources,
                    checkCancellation: checkCancellation,
                    scanBudget: scanBudget)
                try fileIndex.advanceMetadataInventory(scanBudget: shouldBoundCatchUp
                    ? CodexScanBudget(
                        maxFileBytes: Int64(Self.codexCatchUpScanCandidateLimit),
                        maxBytesPerRefresh: Int64(Self.codexCatchUpScanCandidateLimit),
                        maxDuration: 0.25)
                    : nil)
                metadataRefreshCandidates = try fileIndex.takeMetadataRefreshCandidates(
                    cache: cache,
                    dayKey: currentDayKey,
                    scanSinceKey: metadataRetainedWindow.sinceKey,
                    calendar: range.calendar,
                    visitLimit: Self.codexCatchUpScanCandidateLimit,
                    restartCompletedSweep: activeLookbackState.pendingFilePaths.isEmpty
                        && cache.codexHistoryHydrationRetries?.isEmpty != false
                        && !cache.files.values.contains(where: \.hasPendingCodexScanWork))

                let protectedHistoryPaths = Self.codexHistoryPathsToPreserve(cache: cache)
                    .union(scanResult.deferredCachePaths)
                let protectedHistoryPathKeys = Set(protectedHistoryPaths.map {
                    Self.codexPathKey(URL(fileURLWithPath: $0))
                })
                let missingMetadataPaths = Set(metadataRefreshCandidates.compactMap { fileURL -> String? in
                    let metadata = Self.codexFileMetadata(fileURL: fileURL)
                    let pathKey = Self.codexPathKey(fileURL)
                    return metadata.fileId == nil && !protectedHistoryPathKeys.contains(pathKey)
                        ? Self.codexResolvedPath(fileURL) : nil
                })
                if !missingMetadataPaths.isEmpty {
                    for path in missingMetadataPaths {
                        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
                        let cachePath = cache.files[path] != nil ? path : standardizedPath
                        if let removed = cache.files.removeValue(forKey: cachePath) {
                            Self.applyFileDays(cache: &cache, fileDays: removed.days, sign: -1)
                        }
                    }
                    fileIndex.forgetMissingFiles(missingMetadataPaths)
                    metadataRefreshCandidates.removeAll {
                        missingMetadataPaths.contains(Self.codexResolvedPath($0))
                    }
                    scanResult = scanResult.unioning(
                        scannedPaths: missingMetadataPaths,
                        attemptedPaths: missingMetadataPaths,
                        processedPaths: missingMetadataPaths)
                }

                // Metadata validation can discover a changed active file after the first
                // bounded selection has already run. Use any remaining detail/byte budget in
                // this same refresh so an explicit app refresh observes appended usage rather
                // than requiring a second timer tick. The ordinary hydration cap still bounds
                // resident detail state, and overflow candidates stay in the durable queue.
                let immediatePlan = Self.codexCatchUpHydrationPlan(
                    scheduledFiles: metadataRefreshCandidates,
                    cache: cache,
                    scanBudget: scanBudget,
                    prehydratedPaths: hydratedCodexPaths)
                let immediateCandidates = immediatePlan.scheduledFiles
                if !immediateCandidates.isEmpty,
                   scanBudget.shouldStopBeforeNextFile() == false
                {
                    let immediatePaths = immediatePlan.paths.subtracting(hydratedCodexPaths)
                    requestReconciliations.merge(immediatePlan.requestReconciliations) { _, new in new }
                    metadataScanContext.requestReconciliationCandidatePaths = Set(requestReconciliations.keys)
                    let hydrated = CostUsageStoreAccess.hydrateCodexWorkingSet(
                        store: loadedCache.store,
                        calendar: range.calendar,
                        paths: immediatePaths)
                    for path in immediatePaths {
                        if let usage = hydrated.files[path] {
                            cache.files[path] = usage
                        }
                    }
                    options.codexScanWorkRecorderForTesting?.recordCodexHydration(
                        files: immediatePaths.count)
                    hydratedCodexPaths.formUnion(immediatePaths)
                    let immediateResult = try Self.scanCodexFiles(
                        immediateCandidates,
                        context: metadataScanContext,
                        cache: &cache,
                        inheritedResolver: inheritedResolver,
                        hydratedPaths: hydratedCodexPaths.union(immediatePaths).union(scanResult.scannedPaths))
                    scanResult = scanResult.merging(immediateResult)
                    let scannedPathKeys = Set(immediateResult.processedPaths.map {
                        Self.codexPathKey(URL(fileURLWithPath: $0))
                    })
                    metadataRefreshCandidates.removeAll {
                        scannedPathKeys.contains(Self.codexPathKey($0))
                    }
                }
            } else {
                metadataRefreshCandidates = []
            }
            for (path, planned) in requestReconciliations {
                guard var usage = cache.files[path] else { continue }
                var reconciliation = planned
                if reconciliation.sessionID != usage.sessionId {
                    reconciliation.sessionID = usage.sessionId
                    reconciliation.pendingPaths = cache.files.keys.filter {
                        $0 != path && usage.sessionId != nil && cache.files[$0]?.sessionId == usage.sessionId
                    }.sorted()
                }
                if usage.codexScanComplete == true, usage.hasCurrentCodexParser,
                   !usage.hasPendingCodexReplacementScan, !usage.hasPendingCodexForkRetry
                {
                    reconciliation.pendingPaths.removeAll { siblingPath in
                        guard let sibling = cache.files[siblingPath] else { return true }
                        return hydratedCodexPaths.contains(siblingPath)
                            && sibling.hasCurrentCodexParser && sibling.codexScanComplete == true
                            && !sibling.hasPendingCodexReplacementScan && !sibling.hasPendingCodexForkRetry
                    }
                }
                usage.codexRequestReconciliation = reconciliation
                cache.files[path] = usage
            }
            Self.applyCodexHistoryRetryOutcomes(
                scanResult,
                hydrationRetries: historyHydrator?.retryDescriptors ?? [:],
                cache: &cache)
            retryRegistryToken.merge(historyHydrator?.retryRegistryToken ?? .init())
            var protectedHistoryPaths = Self.codexHistoryPathsToPreserve(cache: cache)
            protectedHistoryPaths.formUnion(scanResult.deferredCachePaths)
            filePathsInScan.formUnion(scanResult.scannedPaths.map {
                Self.codexPathKey(URL(fileURLWithPath: $0))
            })
            filePathsInScan.formUnion(protectedHistoryPaths.map {
                Self.codexPathKey(URL(fileURLWithPath: $0))
            })
            let processedWithoutCachePathKeys = Set(scanResult.processedPaths.compactMap { path -> String? in
                guard cache.files[path] == nil else { return nil }
                return Self.codexPathKey(URL(fileURLWithPath: path))
            })
            filePathsInScan.subtract(processedWithoutCachePathKeys)
            let pendingLookbackPathCount = shouldBoundCatchUp
                ? boundedQueuePathCount
                : activeLookbackState.pendingFilePaths.count
            let pendingLookbackPaths = Set(activeLookbackState.pendingFilePaths.prefix(pendingLookbackPathCount))
            let completedScheduledPaths = Self.completedCodexActiveLookbackPaths(
                scheduledFiles: filesScheduledForRefresh,
                pendingPaths: pendingLookbackPaths,
                attemptedPaths: scanResult.attemptedPaths,
                processedPaths: scanResult.processedPaths,
                cache: cache)
            var finalizedLookbackState = Self.finalizedCodexActiveLookbackState(
                activeLookbackState,
                completedFilePaths: completedScheduledPaths,
                servicedFilePaths: scanResult.processedPaths,
                completionCandidateCount: pendingLookbackPathCount,
                requiresBoundedDiscoveryCompletion: shouldPageDiscovery,
                retainCompletedStateForExactValidation: (scanBudget.hasTimeLimit && pendingLookbackPathCount > 0)
                    || !metadataRefreshCandidates.isEmpty,
                workRecorder: options.codexScanWorkRecorderForTesting)
            if var retainedLookbackState = finalizedLookbackState {
                let servicedQueuePaths = Set(scanResult.processedPaths.map {
                    Self.codexResolvedPath(URL(fileURLWithPath: $0))
                }).intersection(pendingLookbackPaths)
                if let promotedPendingPath, servicedQueuePaths.contains(promotedPendingPath) {
                    let waitingCount = max(0, activeLookbackState.pendingFilePaths.count - 1)
                    let debt = min(Self.codexCatchUpHydrationPathLimit - 1, waitingCount)
                    retainedLookbackState.priorityAdmissionDebt = max(
                        0, debt - (servicedQueuePaths.count - 1))
                } else if let debt = retainedLookbackState.priorityAdmissionDebt, debt > 0 {
                    retainedLookbackState.priorityAdmissionDebt = max(0, debt - servicedQueuePaths.count)
                }
                if (retainedLookbackState.priorityAdmissionDebt ?? 0) > 0 {
                    Self.appendCodexActiveLookbackPaths(
                        metadataRefreshCandidates,
                        state: &retainedLookbackState)
                } else {
                    Self.reseedCodexActiveLookbackPathKeys(
                        metadataRefreshCandidates.map(\.path),
                        state: &retainedLookbackState)
                }
                finalizedLookbackState = retainedLookbackState
            }
            if !scanResult.deferredParentPaths.isEmpty {
                var dependencyLookbackState = finalizedLookbackState ?? activeLookbackState
                Self.reseedCodexActiveLookbackPathKeys(
                    scanResult.deferredParentPaths.sorted(), state: &dependencyLookbackState)
                let processedPaths = Set(scanResult.processedPaths.map {
                    Self.codexResolvedPath(URL(fileURLWithPath: $0))
                })
                if let promotedPendingPath,
                   !processedPaths.contains(Self.codexResolvedPath(URL(fileURLWithPath: promotedPendingPath)))
                {
                    // A child deferred before processing still owes its queued parent a FIFO
                    // turn; otherwise the next refresh would promote that same child again.
                    dependencyLookbackState.priorityAdmissionDebt = max(
                        1, dependencyLookbackState.priorityAdmissionDebt ?? 0)
                }
                finalizedLookbackState = dependencyLookbackState
            }
            cache.codexActiveLookbackState = finalizedLookbackState
            if scanBudget.resumedPartialFileCount > 0
                || scanBudget.deferredByBudgetFileCount > 0
                || scanBudget.deferredByTimeBudgetFileCount > 0
            {
                Self.log.info(
                    "Codex cost scan applied work limits",
                    metadata: [
                        "partialFiles": "\(scanBudget.resumedPartialFileCount)",
                        "deferredByBudget": "\(scanBudget.deferredByBudgetFileCount)",
                        "deferredByTime": "\(scanBudget.deferredByTimeBudgetFileCount)",
                        "bytesConsumed": "\(scanBudget.bytesConsumed)",
                        "maxFileBytes": "\(scanBudget.maxFileBytes)",
                        "maxBytesPerRefresh": "\(scanBudget.maxBytesPerRefresh)",
                    ])
            }
            try checkCancellation?()

            Self.pruneForceRescanFilesOutsideWindow(
                cache: &cache,
                range: range,
                isForceRescan: options.forceRescan,
                preservingPaths: protectedHistoryPaths)

            let shouldDropAllUnscannedFiles = options.forceRescan || plan.rootsChanged || cache.files.isEmpty
                || plan.needsProjectMetadataMigration
            if !shouldPageDiscovery {
                for key in cache.files.keys
                    where !filePathsInScan.contains(Self.codexPathKey(URL(fileURLWithPath: key)))
                {
                    guard !protectedHistoryPaths.contains(key) else { continue }
                    guard let old = cache.files[key] else { continue }
                    if plan.preserveUnavailableHistoryDuringRecovery,
                       !FileManager.default.fileExists(atPath: key),
                       Self.codexUnavailableHistoryNeedsRecovery(old, range: range) { continue }
                    let shouldDrop = shouldDropAllUnscannedFiles ||
                        old.touchesCodexScanWindow(
                            sinceKey: range.scanSinceKey,
                            untilKey: range.scanUntilKey,
                            calendar: range.calendar)
                    guard shouldDrop else { continue }
                    Self.applyFileDays(cache: &cache, fileDays: old.days, sign: -1)
                    cache.files.removeValue(forKey: key)
                }

                for key in cache.files.keys {
                    guard !shouldDropAllUnscannedFiles else { break }
                    guard !protectedHistoryPaths.contains(key) else { continue }
                    guard let old = cache.files[key] else { continue }
                    guard old.touchesCodexScanWindow(
                        sinceKey: range.scanSinceKey,
                        untilKey: range.scanUntilKey,
                        calendar: range.calendar)
                    else { continue }
                    guard FileManager.default.fileExists(atPath: key) else {
                        if plan.preserveUnavailableHistoryDuringRecovery,
                           Self.codexUnavailableHistoryNeedsRecovery(old, range: range) { continue }
                        Self.applyFileDays(cache: &cache, fileDays: old.days, sign: -1)
                        cache.files.removeValue(forKey: key)
                        continue
                    }
                }
            }

            try fileIndex.resumePendingDiscovery()

            let shouldRetainWiderWindow = !options.forceRescan && !plan
                .priorityMetadataChanged && !plan.needsTurnIDCacheMigration && !plan.needsProjectMetadataMigration
            let retainedWindow = Self.rollingCodexRetentionWindow(
                cachedSinceKey: shouldRetainWiderWindow ? cachedSinceKey : nil,
                cachedUntilKey: shouldRetainWiderWindow ? cachedUntilKey : nil,
                cachedRetainedLookbackDays: shouldRetainWiderWindow ? cache.codexRetainedLookbackDays : nil,
                requestedSinceKey: range.scanSinceKey,
                requestedUntilKey: parserMigrationPending
                    ? max(range.scanUntilKey, cachedUntilKey ?? range.scanUntilKey)
                    : range.scanUntilKey,
                calendar: range.calendar)
            let retainedSinceKey = retainedWindow.sinceKey
            let retainedUntilKey = retainedWindow.untilKey
            let canReuseApproximateProgress = !options.forceRescan
                && !plan.rootsChanged
                && !plan.windowExpanded
                && !plan.requiresAllFilesForCacheWideMigration
                && !cacheWideMigrationNeedsQueueReseed
                && cachedSinceKey == retainedSinceKey
                && cachedUntilKey == retainedUntilKey
            Self.pruneDays(cache: &cache, sinceKey: retainedSinceKey, untilKey: retainedUntilKey)
            cache.roots = plan.rootsFingerprint
            cache.scanSinceKey = retainedSinceKey
            cache.scanUntilKey = retainedUntilKey
            cache.codexRetainedLookbackDays = retainedWindow.rememberedLookbackDays
            cache.codexPricingKey = plan.codexPricingKey
            cache.codexProjectMetadataVersion = Self.codexProjectMetadataVersion
            let hasDeferredWork = scanBudget.resumedPartialFileCount > 0
                || scanBudget.deferredByBudgetFileCount > 0
                || scanBudget.deferredByTimeBudgetFileCount > 0
                || !scanResult.deferredCachePaths.isEmpty
                || cache.codexHistoryHydrationRetries?.isEmpty == false
            let hasExhaustedVisitBudget = refreshSelection.exhaustedVisitBudget
                || hydrationDeferredCandidates
            let hasKnownBoundedWork = hasDeferredWork
                || hasExhaustedVisitBudget
                || cache.codexActiveLookbackState != nil
                || fileIndex.hasPendingDiscovery
                || (options.useCodexCatchUpWorkingSet && fileIndex.hasPendingMetadataInventory)
            // Active/archive overlap can intentionally collapse multiple physical files into one
            // canonical cache row. Once unbounded work is complete, validate that post-dedupe
            // inventory; bounded passes remain conservative about every discovered candidate.
            let progressInventoryPaths = hasKnownBoundedWork
                ? filePathsInScan
                : filePathsInScan.intersection(Set(cache.files.keys.map {
                    Self.codexPathKey(URL(fileURLWithPath: $0))
                }))
            let progressUpdate = Self.updateCodexScanProgress(
                cache: &cache,
                context: CodexScanProgressUpdateContext(
                    inventoryPaths: progressInventoryPaths,
                    hasKnownBoundedWork: hasKnownBoundedWork,
                    hasDeferredWork: hasDeferredWork,
                    hasExhaustedVisitBudget: hasExhaustedVisitBudget,
                    canReuseApproximateProgress: canReuseApproximateProgress,
                    pendingQueuePathCount: cache.codexActiveLookbackState?.pendingFilePaths.count,
                    isDiscoveryComplete: !fileIndex.hasPendingDiscovery,
                    completionStatesBeforeScan: completionStatesBeforeScan,
                    workRecorder: options.codexScanWorkRecorderForTesting))
            let scanProgress = progressUpdate.summary
            let canValidateExactInventory = progressUpdate.isExact
            cache.codexScanProcessedBytes = scanProgress.processedBytes
            cache.codexScanTotalBytes = scanProgress.totalBytes
            cache.codexScanCompletedFiles = scanProgress.completedFiles
            cache.codexScanTotalFiles = scanProgress.totalFiles
            cache.codexSessionDiscovery = fileIndex.persistedState
            let catchUpPending = !canValidateExactInventory
                || scanProgress.completedFiles < scanProgress.totalFiles
                || cache.files.values.contains(where: \.hasPendingCodexScanWork)
                || cache.codexHistoryHydrationRetries?.isEmpty == false
                || (options.useCodexCatchUpWorkingSet && fileIndex.hasPendingMetadataInventory)
            cache.codexScanCatchUpPending = catchUpPending
            cache.codexPreviousReport = catchUpPending ? previousReport : nil
            let hasPendingPriorityReprocessing = options.useCodexCatchUpWorkingSet
                && !plan.changedPriorityTurnIDs.isEmpty
                && cache.codexActiveLookbackState?.pendingFilePaths.isEmpty == false
            if !hasPendingPriorityReprocessing {
                cache.codexPriorityMetadataKey = plan.codexPriorityMetadataKey
                if options.useCodexCatchUpWorkingSet, !plan.changedPriorityTurnIDs.isEmpty {
                    cache.codexActiveLookbackState?.cacheWideMigrationQueueActive = nil
                    cache.codexActiveLookbackState?.priorityMigrationGenerationKey = nil
                }
            }
            if plan.hasPriorityMetadata, !hasPendingPriorityReprocessing {
                cache.codexPriorityTurnKeys = Self.mergePriorityDayValues(
                    existing: shouldRetainWiderWindow ? cache.codexPriorityTurnKeys : nil,
                    new: plan.priorityTurnKeys,
                    range: range,
                    retainedSinceKey: retainedSinceKey,
                    retainedUntilKey: retainedUntilKey,
                    workRecorder: options.codexScanWorkRecorderForTesting)
                cache.codexPriorityTurnIDsByDay = Self.mergePriorityDayValues(
                    existing: shouldRetainWiderWindow ? cache.codexPriorityTurnIDsByDay : nil,
                    new: plan.priorityTurnIDsByDay,
                    range: range,
                    retainedSinceKey: retainedSinceKey,
                    retainedUntilKey: retainedUntilKey,
                    workRecorder: options.codexScanWorkRecorderForTesting)
                if plan.inspectedPriorityTurns {
                    // Only inspected refreshes observe the live memo; skip writing otherwise so
                    // a nil plan cursor cannot clobber a previously persisted one.
                    cache.codexPriorityTurnsCursor = plan.priorityTurnsCursor
                }
            }
            cache.lastScanUnixMs = nowMs
            try checkCancellation?()
            let independentlyVerifiedCodexWindow = Self.independentlyVerifiedCodexWindow(
                cache: cache,
                roots: plan.roots,
                range: range)
            let independentlyVerifiedDayKeys = Self.independentlyVerifiedCodexDayKeys(
                cache: cache,
                roots: plan.roots,
                now: now,
                range: range)
            historyHydrator?.applyHydratedSnapshots(to: &cache)
            Self.saveCodexCache(
                &cache,
                loadedCache: loadedCache,
                range: range,
                previousReport: previousReport,
                hydratedPaths: options.useCodexCatchUpWorkingSet
                    ? hydratedCodexPaths.union(scanResult.scannedPaths.map {
                        Self.codexResolvedPath(URL(fileURLWithPath: $0))
                    })
                    : nil,
                confirmedAbsentHistoryRetryPaths: scanResult.confirmedAbsentHistoryRetryPaths,
                retryRegistryToken: retryRegistryToken,
                independentlyVerifiedCodexWindow: independentlyVerifiedCodexWindow,
                independentlyVerifiedDayKeys: independentlyVerifiedDayKeys)
        }

        if let previous = Self.codexPreviousReport(
            cache: cache,
            range: range,
            rootsFingerprint: plan.rootsFingerprint)
        {
            return Self.scopedPreviousReport(previous, range: range)
        }
        if options.useCodexCatchUpWorkingSet {
            // Bounded hydration keeps only scheduled file details in memory. Build the
            // published report from the durable file ledger after saving so an unchanged
            // parent or other unhydrated session still contributes its request count.
            let projection = CostUsageStoreAccess.readCodexReportProjection(
                store: loadedCache.store,
                calendar: range.calendar,
                temporalRange: (range.sinceKey, range.untilKey))
            return CostUsageCodexReportProjectionBuilder.build(
                projection: projection,
                roots: plan.roots,
                range: range,
                cacheRoot: options.cacheRoot,
                includeBreakdowns: false).report
        }
        return Self.buildCodexReportFromCache(
            cache: cache,
            range: range,
            modelsDevCatalog: plan.modelsDevCatalog,
            modelsDevCacheRoot: options.cacheRoot,
            priorityTurns: plan.priorityTurns)
    }

    private struct CodexScanProgressSummary {
        let processedBytes: Int64
        let totalBytes: Int64
        let completedFiles: Int
        let totalFiles: Int
    }

    private struct CodexScanProgressUpdateContext {
        let inventoryPaths: Set<String>
        let hasKnownBoundedWork: Bool
        let hasDeferredWork: Bool
        let hasExhaustedVisitBudget: Bool
        let canReuseApproximateProgress: Bool
        let pendingQueuePathCount: Int?
        let isDiscoveryComplete: Bool
        let completionStatesBeforeScan: [String: Bool]
        let workRecorder: CodexScanWorkRecorder?
    }

    private static func updateCodexScanProgress(
        cache: inout CostUsageCache,
        context: CodexScanProgressUpdateContext) -> (summary: CodexScanProgressSummary, isExact: Bool)
    {
        if !context.hasKnownBoundedWork {
            let summary = Self.codexScanProgress(
                paths: context.inventoryPaths,
                cache: cache,
                workRecorder: context.workRecorder)
            guard summary.completedFiles == summary.totalFiles else {
                cache.codexScanInventoryPaths = nil
                return (CodexScanProgressSummary(
                    processedBytes: 0,
                    totalBytes: 0,
                    completedFiles: summary.completedFiles,
                    totalFiles: summary.totalFiles), false)
            }
            cache.codexScanInventoryPaths = context.inventoryPaths.sorted()
            return (summary, true)
        }

        let statesBeforeScan = context.canReuseApproximateProgress
            ? context.completionStatesBeforeScan
            : context.completionStatesBeforeScan.mapValues { _ in false }
        let statesAfterScan = Self.codexCompletionStates(
            paths: context.completionStatesBeforeScan.keys,
            cache: cache,
            includePreviouslyCompletedSnapshots: false)
        let completionDelta = statesBeforeScan.reduce(into: 0) { delta, entry in
            let after = statesAfterScan[entry.key] ?? false
            delta += (after ? 1 : 0) - (entry.value ? 1 : 0)
        }
        let previousCompletedFiles = context.canReuseApproximateProgress
            ? max(0, cache.codexScanCompletedFiles ?? 0)
            : 0
        let previousTotalFiles = context.canReuseApproximateProgress
            ? max(0, cache.codexScanTotalFiles ?? 0)
            : 0
        var completedFiles = max(0, previousCompletedFiles + completionDelta)
        let totalFiles = max(previousTotalFiles, context.inventoryPaths.count, 1)
        if let pendingQueuePathCount = context.pendingQueuePathCount {
            completedFiles = max(completedFiles, max(0, totalFiles - pendingQueuePathCount))
        }

        // Bounded work previously kept one slot open until an exact traversal, which stalled
        // 471/472 when only one large file remained. Allow that final file to close only after
        // both the pending queue and file discovery have drained; catch-up still waits for the
        // exact inventory validation below. Keep deferred bounded work below full progress:
        // selection exhaustion or time/budget deferral must not publish 100% prematurely.
        let incompleteSelectedFiles = statesAfterScan.values.count(where: { !$0 })
        let canCloseFinalFile = context.isDiscoveryComplete
            && !context.hasDeferredWork
            && !context.hasExhaustedVisitBudget
            && incompleteSelectedFiles == 0
            && (context.pendingQueuePathCount ?? 0) <= 1
        if canCloseFinalFile {
            completedFiles = min(completedFiles, totalFiles)
        } else {
            completedFiles = min(completedFiles, max(0, totalFiles - max(1, incompleteSelectedFiles)))
        }

        cache.codexScanInventoryPaths = nil
        return (CodexScanProgressSummary(
            processedBytes: 0,
            totalBytes: 0,
            completedFiles: completedFiles,
            totalFiles: totalFiles), false)
    }

    private static func codexCompletionStates(
        files: some Sequence<URL>,
        cache: CostUsageCache,
        includePreviouslyCompletedSnapshots: Bool) -> [String: Bool]
    {
        self.codexCompletionStates(
            paths: files.map(\.path),
            cache: cache,
            includePreviouslyCompletedSnapshots: includePreviouslyCompletedSnapshots)
    }

    private static func codexCompletionStates(
        paths: some Sequence<String>,
        cache: CostUsageCache,
        includePreviouslyCompletedSnapshots: Bool) -> [String: Bool]
    {
        paths.reduce(into: [String: Bool]()) { result, path in
            let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            guard let usage = cache.files[path] ?? cache.files[standardizedPath],
                  usage.hasCurrentCodexParser,
                  !usage.hasPendingCodexReplacementScan,
                  !usage.hasPendingCodexForkRetry
            else {
                result[path] = false
                return
            }
            let isComplete = usage.codexScanComplete != false
            let wasCompletedSnapshot = includePreviouslyCompletedSnapshots
                && (usage.parsedBytes ?? -1) >= max(0, usage.size)
            result[path] = isComplete || wasCompletedSnapshot
        }
    }

    private static func codexScanProgress(
        paths: Set<String>,
        cache: CostUsageCache,
        workRecorder: CodexScanWorkRecorder? = nil) -> CodexScanProgressSummary
    {
        var processedBytes: Int64 = 0
        var totalBytes: Int64 = 0
        var completedFiles = 0
        var totalFiles = 0
        var seenIdentities: Set<String> = []

        for path in paths.sorted() {
            workRecorder?.recordCodexProgressAccountingVisit()
            let fileURL = URL(fileURLWithPath: path)
            let metadata = Self.codexFileMetadata(fileURL: fileURL)
            let identity = metadata.fileId ?? fileURL.standardizedFileURL.path
            guard seenIdentities.insert(identity).inserted else { continue }
            totalFiles += 1
            totalBytes += max(0, metadata.size)

            let usage = cache.files[path] ?? cache.files[fileURL.standardizedFileURL.path]
            guard let usage else { continue }
            let identityMatches = usage.codexScanFileId == nil || usage.codexScanFileId == metadata.fileId
            guard identityMatches,
                  usage.hasCurrentCodexParser,
                  usage.mtimeUnixMs == metadata.mtimeUnixMs,
                  usage.size == metadata.size
            else { continue }
            let parsedBytes = min(
                max(0, metadata.size),
                max(0, usage.parsedBytes ?? (usage.codexScanComplete == false ? 0 : usage.size)))
            processedBytes += parsedBytes
            if usage.codexScanComplete != false,
               parsedBytes >= metadata.size,
               !usage.hasPendingCodexForkRetry
            {
                completedFiles += 1
            }
        }

        return CodexScanProgressSummary(
            processedBytes: processedBytes,
            totalBytes: totalBytes,
            completedFiles: completedFiles,
            totalFiles: totalFiles)
    }

    private struct CodexFileScanResult {
        let scannedPaths: Set<String>
        let attemptedPaths: Set<String>
        let processedPaths: Set<String>
        let deferredParentPaths: Set<String>
        let deferredCachePaths: Set<String>
        let historyHydrationRetries: [String: CodexHistoryHydrationRetry]
        let completedHistoryRetryTargets: Set<String>
        let confirmedAbsentHistoryRetryPaths: Set<String>

        func unioning(
            scannedPaths: Set<String> = [],
            attemptedPaths: Set<String> = [],
            processedPaths: Set<String> = []) -> Self
        {
            Self(
                scannedPaths: self.scannedPaths.union(scannedPaths),
                attemptedPaths: self.attemptedPaths.union(attemptedPaths),
                processedPaths: self.processedPaths.union(processedPaths),
                deferredParentPaths: self.deferredParentPaths,
                deferredCachePaths: self.deferredCachePaths,
                historyHydrationRetries: self.historyHydrationRetries,
                completedHistoryRetryTargets: self.completedHistoryRetryTargets,
                confirmedAbsentHistoryRetryPaths: self.confirmedAbsentHistoryRetryPaths)
        }

        func merging(_ other: Self) -> Self {
            var retries = self.historyHydrationRetries
            for (path, retry) in other.historyHydrationRetries {
                if var existing = retries[path] {
                    existing.merge(retry)
                    retries[path] = existing
                } else {
                    retries[path] = retry
                }
            }
            return Self(
                scannedPaths: self.scannedPaths.union(other.scannedPaths),
                attemptedPaths: self.attemptedPaths.union(other.attemptedPaths),
                processedPaths: self.processedPaths.union(other.processedPaths),
                deferredParentPaths: self.deferredParentPaths.union(other.deferredParentPaths),
                deferredCachePaths: self.deferredCachePaths.union(other.deferredCachePaths),
                historyHydrationRetries: retries,
                completedHistoryRetryTargets: self.completedHistoryRetryTargets
                    .union(other.completedHistoryRetryTargets),
                confirmedAbsentHistoryRetryPaths: self.confirmedAbsentHistoryRetryPaths
                    .union(other.confirmedAbsentHistoryRetryPaths))
        }
    }

    private static func codexCommittedResponseRows(
        cache: CostUsageCache,
        replacingPaths: Set<String>) -> [String: CodexUsageRow]
    {
        var rows: [String: CodexUsageRow] = [:]
        for (path, usage) in cache.files where !replacingPaths.contains(path)
            && usage.hasCurrentCodexParser && usage.codexScanComplete == true
            && !usage.hasPendingCodexReplacementScan
        {
            for row in usage.codexRows ?? [] where row.responseID != nil {
                let key = Self.codexUsageRowKey(sessionId: usage.sessionId, fileIdentity: path, row: row)
                if let previous = rows[key],
                   (previous.timestampUnixMs ?? .max) <= (row.timestampUnixMs ?? .max) { continue }
                rows[key] = row
            }
        }
        return rows
    }

    private static func scanCodexFiles(
        _ files: [URL],
        context: CodexFileScanContext,
        cache: inout CostUsageCache,
        inheritedResolver: CodexInheritedTotalsResolver,
        hydratedPaths: Set<String>? = nil) throws -> CodexFileScanResult
    {
        var scanState = CodexScanState()
        scanState.retainCandidateResponseDuplicates = true
        scanState.committedCodexResponseRows = Self.codexCommittedResponseRows(
            cache: cache,
            replacingPaths: Set(files.map { Self.codexResolvedPath($0) }))
        var bufferedForkRetries: [URL] = []
        var visitedPaths: Set<String> = []
        var scannedPaths: Set<String> = []
        var attemptedPaths: Set<String> = []
        var processedPaths: Set<String> = []
        var deferredParentPaths: Set<String> = []
        for fileURL in files {
            if context.scanBudget?.shouldStopBeforeNextFile() == true {
                break
            }
            context.workRecorder?.recordCodexFileScanAttempt(path: Self.codexPathKey(fileURL))
            attemptedPaths.insert(fileURL.path)
            scannedPaths.insert(fileURL.path)
            visitedPaths.insert(fileURL.standardizedFileURL.path)
            let outcome = try Self.scanCodexFile(
                fileURL: fileURL,
                context: context,
                cache: &cache,
                state: &scanState)
            if case .processed = outcome {
                processedPaths.insert(fileURL.path)
            }
            let usage = cache.files[fileURL.path]
            inheritedResolver.updateCachedUsage(fileURL: fileURL, usage: usage)
            if Self.shouldRetryBufferedCodexFork(usage) {
                bufferedForkRetries.append(fileURL)
            }
        }

        // Parents outside the requested history window are discovered only after parsing their
        // children. Scan those dependencies through the same budgeted path and retain their cache
        // entries so later passes can resume instead of restarting from byte zero.
        var dependencyState = CodexScanState()
        dependencyScan: while true {
            let pendingParents = inheritedResolver.takePendingParentFiles().filter {
                visitedPaths.insert($0.standardizedFileURL.path).inserted
            }
            guard !pendingParents.isEmpty else { break }
            for fileURL in pendingParents {
                let parentPath = Self.codexResolvedPath(fileURL)
                let parentIsCached = cache.files.index(forKey: parentPath) != nil
                    || cache.files.index(forKey: fileURL.path) != nil
                    || cache.files.index(forKey: fileURL.standardizedFileURL.path) != nil
                // A compact working-set entry is inventory, not hydrated history. Treating it
                // as a fresh scanned parent would persist nil detail rows over its stored ledger.
                // Admit it through the durable queue on the next bounded refresh instead.
                if let hydratedPaths, parentIsCached,
                   !hydratedPaths.contains(parentPath), !scannedPaths.contains(fileURL.path)
                {
                    deferredParentPaths.insert(parentPath)
                    continue
                }
                if context.scanBudget?.shouldStopBeforeNextFile() == true {
                    break dependencyScan
                }
                context.workRecorder?.recordCodexFileScanAttempt(path: Self.codexPathKey(fileURL))
                scannedPaths.insert(fileURL.path)
                attemptedPaths.insert(fileURL.path)
                let outcome = try Self.scanCodexFile(
                    fileURL: fileURL,
                    context: context,
                    cache: &cache,
                    state: &dependencyState)
                if case .processed = outcome {
                    processedPaths.insert(fileURL.path)
                } else if hydratedPaths != nil {
                    deferredParentPaths.insert(parentPath)
                }
                let usage = cache.files[fileURL.path]
                inheritedResolver.updateCachedUsage(fileURL: fileURL, usage: usage)
                if Self.shouldRetryBufferedCodexFork(usage) {
                    bufferedForkRetries.append(fileURL)
                }
            }
        }

        // Newest-first ordering commonly encounters a child before its parent. Once this
        // refresh has indexed the parent, replay the child's compact parsed events in memory.
        // A fork can itself inherit from another fork, so repeat while replays resolve more
        // parents. The depth cap matches inheritedTotals' cycle/depth guard.
        var retryState = CodexScanState()
        var retriedPaths: Set<String> = []
        let retries = bufferedForkRetries.reversed().filter { retriedPaths.insert($0.path).inserted }
        for _ in 0..<min(64, retries.count) {
            var resolvedAny = false
            for fileURL in retries {
                guard Self.shouldRetryBufferedCodexFork(cache.files[fileURL.path]) else { continue }
                scannedPaths.insert(fileURL.path)
                attemptedPaths.insert(fileURL.path)
                let outcome = try Self.scanCodexFile(
                    fileURL: fileURL,
                    context: context,
                    cache: &cache,
                    state: &retryState)
                if case .processed = outcome {
                    processedPaths.insert(fileURL.path)
                }
                inheritedResolver.updateCachedUsage(
                    fileURL: fileURL,
                    usage: cache.files[fileURL.path])
                resolvedAny = resolvedAny || !Self.shouldRetryBufferedCodexFork(cache.files[fileURL.path])
            }
            if !resolvedAny { break }
        }
        var historyRetries: [String: CodexHistoryHydrationRetry] = [:]
        let allStates = [scanState, dependencyState, retryState]
        for state in allStates {
            for (path, retry) in state.historyHydrationRetries {
                if var existing = historyRetries[path] {
                    existing.merge(retry)
                    historyRetries[path] = existing
                } else {
                    historyRetries[path] = retry
                }
            }
        }
        Self.reconcileCodexRequestMirrors(cache: &cache, context: context)
        return CodexFileScanResult(
            scannedPaths: scannedPaths,
            attemptedPaths: attemptedPaths,
            processedPaths: processedPaths,
            deferredParentPaths: deferredParentPaths,
            deferredCachePaths: allStates.reduce(into: Set<String>()) {
                $0.formUnion($1.deferredCachePaths)
            }.union(deferredParentPaths),
            historyHydrationRetries: historyRetries,
            completedHistoryRetryTargets: allStates.reduce(into: Set<String>()) {
                $0.formUnion($1.completedHistoryRetryTargets)
            },
            confirmedAbsentHistoryRetryPaths: allStates.reduce(into: Set<String>()) {
                $0.formUnion($1.confirmedAbsentHistoryRetryPaths)
            })
    }

    private static func shouldRetryBufferedCodexFork(_ usage: CostUsageFileUsage?) -> Bool {
        guard let usage else { return false }
        return usage.forkedFromId != nil
            && usage.hasBufferedCodexForkRetryLines
    }

    private static func codexFileScanContext(
        range: CostUsageDayRange,
        options: Options,
        plan: CodexRefreshPlan,
        resources: CodexScanResources,
        checkCancellation: CancellationCheck?,
        scanBudget: CodexScanBudget? = nil) -> CodexFileScanContext
    {
        CodexFileScanContext(
            range: range,
            forceFullScan: options.forceRescan || plan.windowExpanded
                || plan.needsProjectMetadataMigration,
            forceFullScanPathKeys: plan.forceFullScanHistoryRetryPathKeys,
            sourceRowRecoveryPathKeys: plan.sourceRowRecoveryPathKeys,
            preserveUnavailableHistoryDuringRecovery: plan.preserveUnavailableHistoryDuringRecovery,
            dropDeferredCodexRows: options.forceRescan || plan.needsTurnIDCacheMigration,
            requiresTurnIDCache: plan.needsTurnIDCacheMigration,
            changedPriorityTurnIDs: plan.changedPriorityTurnIDs,
            resources: resources,
            checkCancellation: checkCancellation,
            scanBudget: scanBudget,
            workRecorder: options.codexScanWorkRecorderForTesting)
    }

    static func sortedCodexSessionFilesNewestFirst(
        _ files: [URL],
        metadata reader: CodexListingMetadataReader? = nil) -> [URL]
    {
        let metadata = files.reduce(into: [String: CodexFileMetadata]()) { result, fileURL in
            guard result[fileURL.path] == nil else { return }
            result[fileURL.path] = reader?(fileURL) ?? Self.codexFileMetadata(fileURL: fileURL)
        }
        return files.sorted { lhs, rhs in
            let left = metadata[lhs.path] ?? Self.codexFileMetadata(fileURL: lhs)
            let right = metadata[rhs.path] ?? Self.codexFileMetadata(fileURL: rhs)
            if left.mtimeUnixMs != right.mtimeUnixMs {
                return left.mtimeUnixMs > right.mtimeUnixMs
            }
            if left.size != right.size {
                return left.size > right.size
            }
            return lhs.path < rhs.path
        }
    }

    private static func reconcileCodexCachePathAliases(
        metadata: CodexFileMetadata,
        cache: inout CostUsageCache,
        aliasIndex: CodexCachePathAliasIndex,
        existingAliases: [String])
    {
        guard let fileID = metadata.fileId else { return }
        var aliases = existingAliases
        guard !aliases.isEmpty else { return }

        if cache.files[metadata.path] == nil, let migratedPath = aliases.first {
            cache.files[metadata.path] = cache.files.removeValue(forKey: migratedPath)
            aliasIndex.remove(path: migratedPath)
            aliasIndex.update(path: metadata.path, fileID: fileID)
            aliases.removeFirst()
        }
        for alias in aliases {
            if let stale = cache.files[alias] {
                Self.applyFileDays(cache: &cache, fileDays: stale.days, sign: -1)
                cache.files.removeValue(forKey: alias)
            }
            aliasIndex.remove(path: alias)
        }
    }
}

// swiftlint:enable type_body_length
