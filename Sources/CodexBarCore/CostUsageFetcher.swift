import Foundation

// swiftlint:disable file_length

public enum CostUsageError: LocalizedError, Sendable {
    case unsupportedProvider(UsageProvider)
    case timedOut(seconds: Int)
    case cursorPaginationIncomplete(expected: Int?, received: Int)
    case cursorPaginationInconsistent(expected: Int, received: Int)
    case cachedSnapshotUnavailable

    public var errorDescription: String? {
        switch self {
        case let .unsupportedProvider(provider):
            return "Cost summary is not supported for \(provider.rawValue)."
        case let .timedOut(seconds):
            if seconds >= 60, seconds % 60 == 0 {
                return "Cost refresh timed out after \(seconds / 60)m."
            }
            return "Cost refresh timed out after \(seconds)s."
        case let .cursorPaginationIncomplete(expected, received):
            if let expected {
                return "Cursor cost refresh was incomplete (received \(received) of \(expected) events)."
            }
            return "Cursor cost refresh reached its pagination safety limit after \(received) events."
        case let .cursorPaginationInconsistent(expected, received):
            return "Cursor cost pagination was inconsistent (expected \(expected), received \(received) events)."
        case .cachedSnapshotUnavailable:
            return "The completed cost scan did not produce a readable cached snapshot."
        }
    }
}

// swiftlint:disable:next type_body_length
public struct CostUsageFetcher: Sendable {
    private static let codexAutomaticScanDurationPerRefresh: TimeInterval = 2

    package static func piRootScope(environment: [String: String]) async throws -> String {
        let contexts = await LocalAgentSessionScanner().piSessionProcessContexts(environment: environment)
        return try await CostUsageScanExecutor.run { checkCancellation in
            try checkCancellation()
            return PiSessionCostScanner.scopeFingerprint(
                options: PiSessionCostScanner.Options(
                    environment: environment,
                    processContexts: contexts))
        }
    }

    package struct CachedCodexTokenSnapshotResult: Sendable {
        package let snapshot: CostUsageTokenSnapshot
        package var accounting: PiSnapshotAccounting?
        package let lastRefreshAt: Date?
        package let staleSnapshotUpdatedAt: Date?
        /// True only when the snapshot's current-day Codex row comes from a complete,
        /// metadata-validated inventory rather than an in-progress bounded history scan.
        package let currentDayIsFullyVerified: Bool
    }

    package struct CodexScanCatchUpStatus: Sendable, Equatable {
        package let pending: Bool
        package let progressKey: String
        package let processedBytes: Int64
        package let totalBytes: Int64
        package let completedFiles: Int
        package let totalFiles: Int
        package let staleSnapshotUpdatedAt: Date?

        package init(
            pending: Bool,
            progressKey: String,
            processedBytes: Int64 = 0,
            totalBytes: Int64 = 0,
            completedFiles: Int = 0,
            totalFiles: Int = 0,
            staleSnapshotUpdatedAt: Date? = nil)
        {
            self.pending = pending
            self.progressKey = progressKey
            self.processedBytes = max(0, processedBytes)
            self.totalBytes = max(0, totalBytes)
            self.completedFiles = max(0, completedFiles)
            self.totalFiles = max(0, totalFiles)
            self.staleSnapshotUpdatedAt = staleSnapshotUpdatedAt
        }
    }

    private let scannerOptions: CostUsageScanner.Options?

    public init(cacheRoot: URL? = nil, calendar: Calendar? = nil) {
        self.scannerOptions = cacheRoot == nil && calendar == nil
            ? nil : CostUsageScanner.Options(cacheRoot: cacheRoot, calendar: calendar ?? .current)
    }

    init(scannerOptions: CostUsageScanner.Options) {
        self.scannerOptions = scannerOptions
    }

    public func loadCachedCodexTokenSnapshot(
        now: Date = Date(),
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        calendar: Calendar? = nil) async -> CostUsageTokenSnapshot?
    {
        await Self.loadCachedCodexTokenSnapshot(
            now: now,
            codexHomePath: codexHomePath,
            historyDays: historyDays,
            scannerOptions: self.scannerOptions(calendar: calendar))
    }

    package func loadCachedCodexTokenActivity(
        now: Date = Date(),
        codexHomePath: String? = nil,
        maximumDays: Int = 365,
        calendar: Calendar? = nil) async -> CostUsageTokenActivityCache?
    {
        await Self.loadCachedCodexTokenActivity(
            now: now,
            codexHomePath: codexHomePath,
            maximumDays: maximumDays,
            scannerOptions: self.scannerOptions(calendar: calendar))
    }

    package func loadCachedCodexTokenSnapshotResult(
        now: Date = Date(),
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        allowScopedCodexHome: Bool = false,
        includePiSessions: Bool = true,
        includeProjectAndSessionBreakdowns: Bool = true,
        requireCompleteHistory: Bool = false,
        calendar: Calendar? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment) async -> CachedCodexTokenSnapshotResult?
    {
        await Self.loadCachedCodexTokenSnapshotResult(
            now: now,
            codexHomePath: codexHomePath,
            historyDays: historyDays,
            allowScopedCodexHome: allowScopedCodexHome,
            includePiSessions: includePiSessions,
            includeProjectAndSessionBreakdowns: includeProjectAndSessionBreakdowns,
            requireCompleteHistory: requireCompleteHistory,
            scannerOptions: self.scannerOptions(calendar: calendar),
            environment: environment)
    }

    package func loadCachedCodexTokenSnapshotForScopedHome(
        now: Date = Date(),
        codexHomePath: String,
        historyDays: Int = 30,
        includePiSessions: Bool = false,
        includeProjectAndSessionBreakdowns: Bool = false,
        calendar: Calendar? = nil) async -> CostUsageTokenSnapshot?
    {
        await Self.loadCachedCodexTokenSnapshot(
            now: now,
            codexHomePath: codexHomePath,
            historyDays: historyDays,
            allowScopedCodexHome: true,
            includePiSessions: includePiSessions,
            includeProjectAndSessionBreakdowns: includeProjectAndSessionBreakdowns,
            scannerOptions: self.scannerOptions(calendar: calendar))
    }

    public func loadCachedCodexLocalProjectUsageSnapshot(
        now: Date = Date(),
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        hidePersonalInfo: Bool) async -> CodexLocalProjectUsageSnapshot?
    {
        await Self.loadCachedCodexLocalProjectUsageSnapshot(
            now: now,
            codexHomePath: codexHomePath,
            historyDays: historyDays,
            hidePersonalInfo: hidePersonalInfo,
            scannerOptions: self.scannerOptions)
    }

    public func loadCodexLocalProjectUsageSnapshot(
        now: Date = Date(),
        forceRefresh: Bool = false,
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        hidePersonalInfo: Bool,
        progress: (@Sendable (CodexLocalProjectUsageIndexProgress) -> Void)? = nil)
        async throws -> CodexLocalProjectUsageSnapshot
    {
        try await Self.loadCodexLocalProjectUsageSnapshot(
            now: now,
            forceRefresh: forceRefresh,
            codexHomePath: codexHomePath,
            historyDays: historyDays,
            hidePersonalInfo: hidePersonalInfo,
            progress: progress,
            scannerOptions: self.scannerOptions)
    }

    public func clearCachedCodexLocalProjectUsageSnapshot(codexHomePath: String? = nil) async {
        await Self.clearCachedCodexLocalProjectUsageSnapshot(
            codexHomePath: codexHomePath,
            scannerOptions: self.scannerOptions)
    }

    public func loadTokenSnapshot(
        provider: UsageProvider,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date(),
        forceRefresh: Bool = false,
        allowVertexClaudeFallback: Bool = false,
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        cursorCookieHeaderOverride: String? = nil,
        allowPricingRefresh: Bool = true,
        refreshPricingInBackground: Bool = true,
        includePiSessions: Bool = true,
        piWorkingDirectories: [URL] = [],
        piSessionProcessContexts: [PiSessionProcessContext] = []) async throws -> CostUsageTokenSnapshot
    {
        try await Self.loadTokenSnapshot(
            provider: provider,
            environment: environment,
            now: now,
            forceRefresh: forceRefresh,
            allowVertexClaudeFallback: allowVertexClaudeFallback,
            codexHomePath: codexHomePath,
            historyDays: historyDays,
            cursorCookieHeaderOverride: cursorCookieHeaderOverride,
            allowPricingRefresh: allowPricingRefresh,
            refreshPricingInBackground: refreshPricingInBackground,
            includePiSessions: includePiSessions,
            bypassScannerDebounce: false,
            piWorkingDirectories: piWorkingDirectories,
            piSessionProcessContexts: piSessionProcessContexts,
            scannerOptions: self.scannerOptions)
    }

    package func loadTokenSnapshot(
        provider: UsageProvider,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date(),
        forceRefresh: Bool = false,
        allowVertexClaudeFallback: Bool = false,
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        cursorCookieHeaderOverride: String? = nil,
        allowPricingRefresh: Bool = true,
        refreshPricingInBackground: Bool = true,
        includePiSessions: Bool = true,
        piWorkingDirectories: [URL] = [],
        piSessionProcessContexts: [PiSessionProcessContext] = [],
        bypassScannerDebounce: Bool,
        calendar: Calendar? = nil) async throws -> CostUsageTokenSnapshot
    {
        try await Self.loadTokenSnapshot(
            provider: provider,
            environment: environment,
            now: now,
            forceRefresh: forceRefresh,
            allowVertexClaudeFallback: allowVertexClaudeFallback,
            codexHomePath: codexHomePath,
            historyDays: historyDays,
            cursorCookieHeaderOverride: cursorCookieHeaderOverride,
            allowPricingRefresh: allowPricingRefresh,
            refreshPricingInBackground: refreshPricingInBackground,
            includePiSessions: includePiSessions,
            bypassScannerDebounce: bypassScannerDebounce,
            piWorkingDirectories: piWorkingDirectories,
            piSessionProcessContexts: piSessionProcessContexts,
            scannerOptions: self.scannerOptions(calendar: calendar))
    }

    package func loadTokenResult(
        provider: UsageProvider,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date(),
        forceRefresh: Bool = false,
        allowVertexClaudeFallback: Bool = false,
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        cursorCookieHeaderOverride: String? = nil,
        allowPricingRefresh: Bool = true,
        refreshPricingInBackground: Bool = true,
        includePiSessions: Bool = true,
        piWorkingDirectories: [URL] = [],
        piSessionProcessContexts: [PiSessionProcessContext] = [],
        bypassScannerDebounce: Bool,
        calendar: Calendar? = nil,
        reportContext: CostUsageReportContext = .regular) async throws -> CostUsageTokenResult
    {
        try await Self.loadTokenResult(
            provider: provider,
            environment: environment,
            now: now,
            forceRefresh: forceRefresh,
            allowVertexClaudeFallback: allowVertexClaudeFallback,
            codexHomePath: codexHomePath,
            historyDays: historyDays,
            cursorCookieHeaderOverride: cursorCookieHeaderOverride,
            allowPricingRefresh: allowPricingRefresh,
            refreshPricingInBackground: refreshPricingInBackground,
            includePiSessions: includePiSessions,
            bypassScannerDebounce: bypassScannerDebounce,
            piWorkingDirectories: piWorkingDirectories,
            piSessionProcessContexts: piSessionProcessContexts,
            scannerOptions: self.scannerOptions(calendar: calendar),
            reportContext: reportContext)
    }

    @available(*, deprecated, message: "Codex token-cost scans are uncapped; this limit is ignored.")
    public func loadTokenSnapshot(
        provider: UsageProvider,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date(),
        forceRefresh: Bool = false,
        allowVertexClaudeFallback: Bool = false,
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        allowPricingRefresh: Bool = true,
        refreshPricingInBackground: Bool = true,
        automaticCodexScanByteLimit _: Int64?) async throws -> CostUsageTokenSnapshot
    {
        try await self.loadTokenSnapshot(
            provider: provider,
            environment: environment,
            now: now,
            forceRefresh: forceRefresh,
            allowVertexClaudeFallback: allowVertexClaudeFallback,
            codexHomePath: codexHomePath,
            historyDays: historyDays,
            allowPricingRefresh: allowPricingRefresh,
            refreshPricingInBackground: refreshPricingInBackground)
    }

    private func scannerOptions(calendar: Calendar?) -> CostUsageScanner.Options? {
        guard calendar != nil || self.scannerOptions != nil else { return self.scannerOptions }
        var options = self.scannerOptions ?? CostUsageScanner.Options()
        if let calendar {
            options.calendar = calendar
        }
        return options
    }

    package func codexScanCatchUpStatus(
        codexHomePath: String? = nil,
        calendar: Calendar? = nil) async -> CodexScanCatchUpStatus
    {
        // Provider-specific by design: Codex exposes bounded background catch-up for its incremental JSONL scanner.
        let options = Self.resolvedScannerOptions(
            self.scannerOptions(calendar: calendar),
            provider: .codex,
            codexHomePath: codexHomePath)
        return await (try? CostUsageScanExecutor.run { checkCancellation in
            try checkCancellation()
            return Self.codexScanCatchUpStatus(options: options)
        }) ?? CodexScanCatchUpStatus(pending: false, progressKey: "unavailable")
    }

    package func advanceCodexScanCatchUp(
        now: Date = Date(),
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        scanDurationPerRefresh: TimeInterval? = nil,
        calendar: Calendar? = nil) async throws -> CostUsageScanExecutor.TimedResult<CodexScanCatchUpStatus>
    {
        var options = Self.resolvedScannerOptions(
            self.scannerOptions(calendar: calendar),
            provider: .codex, // Provider-specific by design: this catch-up operation is owned by Codex's ledger.
            codexHomePath: codexHomePath)
        options.forceRescan = false
        options.refreshMinIntervalSeconds = 0
        options.useCodexCatchUpWorkingSet = true
        let clampedHistoryDays = max(1, min(365, historyDays))
        options.maxCodexScanDurationPerRefresh =
            scanDurationPerRefresh ?? Self.codexAutomaticScanDurationPerRefresh
        let since = CostReportingPeriod.rolling(days: clampedHistoryDays)
            .bounds(now: now, calendar: options.calendar).lowerBound
        let scanOptions = options
        // Provider-specific by design: this catch-up step advances only the Codex incremental scanner.
        return try await CostUsageScanExecutor.runTimed { checkCancellation in
            _ = try CostUsageScanner.loadDailyReportCancellable(
                provider: .codex,
                since: since,
                until: now,
                now: now,
                options: scanOptions,
                checkCancellation: checkCancellation)
            try checkCancellation()
            return Self.codexScanCatchUpStatus(options: scanOptions)
        }
    }

    private static func codexScanCatchUpStatus(
        options: CostUsageScanner.Options) -> CodexScanCatchUpStatus
    {
        let roots = CostUsageScanner.codexSessionsRoots(options: options)
        let rootsFingerprint = CostUsageScanner.codexRootsFingerprint(options: options)
        let projection = CostUsageStoreAccess.readCodexCatchUpProjection(
            cacheRoot: options.cacheRoot,
            calendar: options.calendar)
        guard projection.rootMtimes == rootsFingerprint else {
            return CodexScanCatchUpStatus(pending: false, progressKey: "scope-mismatch")
        }

        let scopedFiles = projection.files.filter {
            CostUsageScanner.isWithinCodexRoots(
                fileURL: URL(fileURLWithPath: $0.path),
                roots: roots)
        }
        let progressKey = self.codexScanProgressKey(
            projection: projection,
            scopedFiles: scopedFiles)
        let hasIncompleteFile = scopedFiles.contains { !$0.scanComplete }
        let needsIdentityValidation = CostUsageStore.codexCatchUpProjectionNeedsIdentityValidation(
            files: scopedFiles,
            rootMtimes: projection.rootMtimes)
        let pending = projection.catchUpPending || hasIncompleteFile || needsIdentityValidation
        let staleSnapshotUpdatedAt = projection.previousReportUpdatedAtUnixMs.flatMap { timestamp -> Date? in
            guard timestamp > 0 else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        }
        return CodexScanCatchUpStatus(
            pending: pending,
            progressKey: progressKey,
            processedBytes: projection.processedBytes ?? 0,
            totalBytes: projection.totalBytes ?? 0,
            completedFiles: projection.completedFiles ?? 0,
            totalFiles: projection.totalFiles ?? 0,
            staleSnapshotUpdatedAt: pending ? staleSnapshotUpdatedAt : nil)
    }

    private static func codexHistoryCoverageIsEstablished(
        options: CostUsageScanner.Options) -> Bool
    {
        let status = self.codexScanCatchUpStatus(options: options)
        return !status.pending && status.progressKey != "scope-mismatch"
    }

    private static let establishedEmptyCodexDailyReport = CostUsageDailyReport(data: [], summary: nil)

    private static func codexCachedHistoryCoverageIsEstablished(
        cache: CostUsageCache,
        range: CostUsageScanner.CostUsageDayRange,
        rootsFingerprint: [String: Int64]) -> Bool
    {
        guard cache.lastScanUnixMs > 0,
              cache.timeZoneIdentifier == range.calendar.timeZone.identifier,
              cache.roots == rootsFingerprint,
              cache.codexScanCatchUpPending != true,
              !cache.files.values.contains(where: {
                  $0.codexScanComplete == false || $0.hasBufferedCodexForkRetryLines
              }),
              !CostUsageScanner.requestedWindowExpandsCache(range: range, cache: cache)
        else { return false }
        return true
    }

    private static func codexVerifiedHistoryCoverageContains(
        projection: CostUsageStoreCodexReportProjection,
        cache: CostUsageCache,
        range: CostUsageScanner.CostUsageDayRange,
        rootsFingerprint: [String: Int64]) -> Bool
    {
        guard cache.timeZoneIdentifier == range.calendar.timeZone.identifier,
              cache.roots == rootsFingerprint,
              projection.verifiedTimeZoneIdentifier == range.calendar.timeZone.identifier,
              projection.verifiedRootPaths == rootsFingerprint.keys.sorted(),
              let since = projection.verifiedScanSinceKey,
              let until = projection.verifiedScanUntilKey
        else { return false }
        if projection.verifiedDayAggregates.isEmpty {
            guard !cache.files.values.contains(where: {
                $0.codexScanComplete == false || $0.hasBufferedCodexForkRetryLines
            }) else { return false }
            guard let updatedAt = projection.verifiedUpdatedAtUnixMs, updatedAt > 0 else {
                return false
            }
            let updatedDate = Date(timeIntervalSince1970: TimeInterval(updatedAt) / 1000)
            let updatedDay = CostUsageScanner.CostUsageDayRange.dayKey(
                from: updatedDate,
                calendar: range.calendar)
            guard updatedDay == range.untilKey else { return false }
        }
        return since <= range.sinceKey && until >= range.untilKey
    }

    private static func resolvedScannerOptions(
        _ override: CostUsageScanner.Options?,
        provider: UsageProvider,
        codexHomePath: String?) -> CostUsageScanner.Options
    {
        var options = override ?? CostUsageScanner.Options()
        // Provider-specific by design: Codex managed profiles relocate sessions and archived_sessions roots.
        if provider == .codex,
           let codexHomePath = codexHomePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHomePath.isEmpty
        {
            options.codexSessionsRoot = URL(fileURLWithPath: codexHomePath, isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        }
        return options
    }

    static func loadTokenSnapshot(
        provider: UsageProvider,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date(),
        forceRefresh: Bool = false,
        allowVertexClaudeFallback: Bool = false,
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        cursorCookieHeaderOverride: String? = nil,
        allowPricingRefresh: Bool = true,
        refreshPricingInBackground: Bool = true,
        includePiSessions: Bool = true,
        bypassScannerDebounce: Bool = false,
        piWorkingDirectories: [URL] = [],
        piSessionProcessContexts: [PiSessionProcessContext] = [],
        scannerOptions overrideScannerOptions: CostUsageScanner.Options? = nil,
        piScannerOptions overridePiScannerOptions: PiSessionCostScanner
            .Options? = nil,
        modelsDevClient: ModelsDevClient = ModelsDevClient(),
        retryUnknownPricing: Bool = true) async throws -> CostUsageTokenSnapshot
    {
        try await self.loadTokenResult(
            provider: provider,
            environment: environment,
            now: now,
            forceRefresh: forceRefresh,
            allowVertexClaudeFallback: allowVertexClaudeFallback,
            codexHomePath: codexHomePath,
            historyDays: historyDays,
            cursorCookieHeaderOverride: cursorCookieHeaderOverride,
            allowPricingRefresh: allowPricingRefresh,
            refreshPricingInBackground: refreshPricingInBackground,
            includePiSessions: includePiSessions,
            bypassScannerDebounce: bypassScannerDebounce,
            piWorkingDirectories: piWorkingDirectories,
            piSessionProcessContexts: piSessionProcessContexts,
            scannerOptions: overrideScannerOptions,
            piScannerOptions: overridePiScannerOptions,
            modelsDevClient: modelsDevClient,
            retryUnknownPricing: retryUnknownPricing).snapshot
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func loadTokenResult(
        provider: UsageProvider,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date(),
        forceRefresh: Bool = false,
        allowVertexClaudeFallback: Bool = false,
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        cursorCookieHeaderOverride: String? = nil,
        allowPricingRefresh: Bool = true,
        refreshPricingInBackground: Bool = true,
        includePiSessions: Bool = true,
        bypassScannerDebounce: Bool = false,
        piWorkingDirectories: [URL] = [],
        piSessionProcessContexts: [PiSessionProcessContext] = [],
        scannerOptions overrideScannerOptions: CostUsageScanner.Options? = nil,
        piScannerOptions overridePiScannerOptions: PiSessionCostScanner
            .Options? = nil,
        modelsDevClient: ModelsDevClient = ModelsDevClient(),
        retryUnknownPricing: Bool = true,
        reportContext: CostUsageReportContext? = nil) async throws -> CostUsageTokenResult
    {
        guard self.supportsTokenSnapshot(provider) else {
            throw CostUsageError.unsupportedProvider(provider)
        }

        let clampedHistoryDays = max(1, min(365, historyDays))

        var remoteSnapshot: CostUsageTokenSnapshot?
        var remoteError: Error?
        do {
            // Provider-specific by design: Bedrock uses AWS billing while Cursor uses its macOS dashboard session.
            let calendar = overrideScannerOptions?.calendar ?? .current
            let since = CostReportingPeriod.rolling(days: clampedHistoryDays).bounds(now: now, calendar: calendar)
                .lowerBound
            if provider == .bedrock {
                let daily = try await Self.loadBedrockDailyReport(
                    environment: environment,
                    since: since,
                    until: now)
                remoteSnapshot = Self.tokenSnapshot(
                    from: CostUsageDailyReport(
                        data: CostReportingPeriod.rolling(days: clampedHistoryDays)
                            .entries(daily.data, now: now, calendar: calendar),
                        summary: nil),
                    now: now,
                    historyDays: clampedHistoryDays,
                    useCurrentLocalDayForSession: false,
                    calendar: calendar,
                    historyCoverageIsEstablished: CostUsageLocalDay.key(from: now, calendar: calendar)
                        <= CostUsageLocalDay.key(
                            from: now, calendar: CostUsageBucketTimeZone.calendar(identifier: "UTC")),
                    costProvenance: .vendorMetered)
            }

            #if os(macOS)
            // Provider-specific by design: Cursor retries failed web cost queries against local CSV history.
            if provider == .cursor {
                remoteSnapshot = try await self.loadCursorTokenSnapshot(
                    now: now,
                    since: since,
                    historyDays: clampedHistoryDays,
                    calendar: calendar,
                    cookieHeaderOverride: cursorCookieHeaderOverride)
            }
            #endif
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw error
            }
            if provider != .cursor, provider != .antigravity {
                throw error
            }
            remoteError = error
        }
        if let remoteSnapshot {
            return CostUsageTokenResult(snapshot: remoteSnapshot)
        }

        // Provider-specific by design: local readers backfill providers without remote history.
        let fallbackOptions = Self.resolvedScannerOptions(
            overrideScannerOptions,
            provider: provider,
            codexHomePath: codexHomePath)
        let fallbackCalendar = fallbackOptions.calendar
        if provider == .muse {
            let snapshot = try await Self.loadMuseLocalSnapshot(
                environment: environment,
                now: now,
                historyDays: clampedHistoryDays,
                options: fallbackOptions)
            return CostUsageTokenResult(snapshot: snapshot)
        }
        if provider == .cursor {
            if let local = await self.loadCursorLocalSnapshot(
                now: now, historyDays: clampedHistoryDays, calendar: fallbackCalendar)
            {
                return CostUsageTokenResult(snapshot: local)
            }
            if let remoteError {
                throw remoteError
            }
            return CostUsageTokenResult(snapshot: Self.tokenSnapshot(
                from: CostUsageDailyReport(data: [], summary: nil),
                now: now,
                historyDays: clampedHistoryDays,
                calendar: fallbackCalendar,
                historyCoverageIsEstablished: false))
        }
        // Provider-specific by design: Antigravity uses recognized local stores without generic pricing or cache scans.
        if provider == .antigravity {
            let pricing = AntigravityPricingOptions(
                cacheRoot: overrideScannerOptions?.cacheRoot,
                refresh: PricingRefreshOptions(
                    provider: .antigravity,
                    isAllowed: allowPricingRefresh,
                    retryUnknown: retryUnknownPricing,
                    inBackground: refreshPricingInBackground || !forceRefresh),
                client: modelsDevClient)
            if let local = try await self.loadPricedAntigravityLocalSnapshot(
                environment: environment,
                now: now,
                historyDays: clampedHistoryDays,
                calendar: fallbackCalendar,
                pricing: pricing)
            {
                return CostUsageTokenResult(snapshot: local)
            }
            if let remoteError {
                throw remoteError
            }
            return CostUsageTokenResult(snapshot: Self.tokenSnapshot(
                from: CostUsageDailyReport(data: [], summary: nil),
                now: now,
                historyDays: clampedHistoryDays,
                calendar: fallbackCalendar,
                historyCoverageIsEstablished: false))
        }
        if let remoteError {
            throw remoteError
        }

        // Provider-specific by design: Pi has an independent aggregate token-cost history over its local JSONL logs.
        if provider == .pi {
            var piOptionsOnly = overridePiScannerOptions ?? PiSessionCostScanner.Options()
            if piOptionsOnly.cacheRoot == nil {
                piOptionsOnly.cacheRoot = overrideScannerOptions?.cacheRoot
            }
            if piOptionsOnly.piSessionsRoot == nil, piOptionsOnly.ompSessionsRoot == nil {
                piOptionsOnly.environment = environment
            }
            // Provider-specific by design: Pi scans receive live process project roots for project-level settings.
            if piOptionsOnly.workingDirectories.isEmpty, !piWorkingDirectories.isEmpty {
                piOptionsOnly.workingDirectories = piWorkingDirectories
            }
            if piOptionsOnly.processContexts.isEmpty, !piSessionProcessContexts.isEmpty {
                piOptionsOnly.processContexts = piSessionProcessContexts
            }
            if overrideScannerOptions != nil {
                piOptionsOnly.calendar = Self.resolvedScannerOptions(
                    overrideScannerOptions,
                    provider: .pi,
                    codexHomePath: codexHomePath).calendar
            }
            if forceRefresh || bypassScannerDebounce {
                piOptionsOnly.refreshMinIntervalSeconds = 0
            }
            piOptionsOnly.forceRescan = piOptionsOnly.forceRescan || forceRefresh
            let piOptions = piOptionsOnly
            let piSince = piOptionsOnly.calendar.date(byAdding: .day, value: -(clampedHistoryDays - 1), to: now) ?? now
            await Self.refreshPricingIfAllowed(
                options: PricingRefreshOptions(
                    provider: .claude,
                    isAllowed: allowPricingRefresh,
                    retryUnknown: retryUnknownPricing,
                    inBackground: refreshPricingInBackground),
                now: now,
                cacheRoot: piOptionsOnly.cacheRoot,
                client: modelsDevClient)
            let piScanResult: PiSessionCostScanner.DailyReportResult = try await CostUsageScanExecutor
                .run { checkCancellation in
                    try PiSessionCostScanner.loadDailyReportResultCancellable(
                        // Provider-specific by design: this call reads Pi's local aggregate session ledger.
                        provider: .pi,
                        since: piSince,
                        until: now,
                        now: now,
                        options: piOptions,
                        checkCancellation: checkCancellation)
                }
            let piDaily = piScanResult.report
            if allowPricingRefresh, retryUnknownPricing {
                var didRefresh = false
                // Provider-specific by design: Pi model names reuse the Codex and Claude pricing catalogs.
                for pricingProvider in [UsageProvider.codex, UsageProvider.claude] {
                    if let request = Self.unknownPricingRefreshRequest(
                        provider: pricingProvider,
                        daily: piDaily,
                        now: now,
                        cacheRoot: piOptionsOnly.cacheRoot,
                        client: modelsDevClient),
                        await Self.refreshUnknownPricingIfNeeded(request, inBackground: refreshPricingInBackground)
                    {
                        didRefresh = true
                    }
                }
                if didRefresh, !refreshPricingInBackground {
                    return try await self.loadTokenResult(
                        provider: provider,
                        environment: environment,
                        now: now,
                        forceRefresh: forceRefresh,
                        allowVertexClaudeFallback: allowVertexClaudeFallback,
                        codexHomePath: codexHomePath,
                        historyDays: historyDays,
                        cursorCookieHeaderOverride: cursorCookieHeaderOverride,
                        allowPricingRefresh: allowPricingRefresh,
                        refreshPricingInBackground: false,
                        includePiSessions: includePiSessions,
                        piWorkingDirectories: piWorkingDirectories,
                        piSessionProcessContexts: piSessionProcessContexts,
                        scannerOptions: overrideScannerOptions,
                        piScannerOptions: piOptionsOnly,
                        modelsDevClient: modelsDevClient,
                        retryUnknownPricing: false)
                }
            }
            let snapshot = Self.tokenSnapshot(
                from: piDaily,
                now: now,
                historyDays: clampedHistoryDays,
                calendar: piOptionsOnly.calendar,
                historyCoverageIsEstablished: piScanResult.isComplete,
                costProvenance: .listPriceEstimate,
                projects: [],
                sessions: [],
                // An incomplete Pi scan may be serving a retained cache report. Preserve its
                // scan time; if there is none, mark the age unknown rather than freshly read.
                updatedAt: piScanResult.isComplete ? now : piScanResult.lastScanAt ?? .distantPast)
            return CostUsageTokenResult(
                snapshot: snapshot,
                accounting: piScanResult.scopeFingerprint.map { .piOnly(scope: $0) })
        }

        var options = Self.resolvedScannerOptions(
            overrideScannerOptions,
            provider: provider,
            codexHomePath: codexHomePath)
        // Rolling window is inclusive, so a 30-day display starts 29 days before `now`.
        let since = options.calendar.date(byAdding: .day, value: -(clampedHistoryDays - 1), to: now) ?? now
        let scopedCodexHomePath = codexHomePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Provider-specific by design: scoped Codex homes exclude ambient Pi sessions from managed-profile totals.
        let shouldMergePiUsage = provider != .codex || scopedCodexHomePath?.isEmpty != false
        await Self.refreshPricingIfAllowed(
            options: PricingRefreshOptions(
                provider: provider,
                isAllowed: allowPricingRefresh,
                retryUnknown: retryUnknownPricing,
                inBackground: refreshPricingInBackground),
            now: now,
            cacheRoot: options.cacheRoot,
            client: modelsDevClient)

        Self.configureScannerRefresh(
            &options,
            provider: provider,
            allowVertexClaudeFallback: allowVertexClaudeFallback,
            forceRefresh: forceRefresh,
            bypassScannerDebounce: bypassScannerDebounce)
        var resolvedPiOptions = overridePiScannerOptions ?? PiSessionCostScanner.Options()
        if resolvedPiOptions.cacheRoot == nil {
            resolvedPiOptions.cacheRoot = options.cacheRoot
        }
        if resolvedPiOptions.piSessionsRoot == nil, resolvedPiOptions.ompSessionsRoot == nil {
            resolvedPiOptions.environment = environment
        }
        if resolvedPiOptions.workingDirectories.isEmpty, !piWorkingDirectories.isEmpty {
            resolvedPiOptions.workingDirectories = piWorkingDirectories
        }
        if resolvedPiOptions.processContexts.isEmpty, !piSessionProcessContexts.isEmpty {
            resolvedPiOptions.processContexts = piSessionProcessContexts
        }
        resolvedPiOptions.calendar = options.calendar
        if forceRefresh || bypassScannerDebounce {
            resolvedPiOptions.refreshMinIntervalSeconds = 0
        }
        resolvedPiOptions.forceRescan = resolvedPiOptions.forceRescan || forceRefresh
        let piOptions = resolvedPiOptions

        let scanOptions = options
        let localScanOptions = LocalTokenScanOptions(
            allowVertexClaudeFallback: allowVertexClaudeFallback,
            includePiSessions: includePiSessions,
            shouldMergePiUsage: shouldMergePiUsage,
            scanOptions: scanOptions,
            environment: environment,
            piOptions: piOptions,
            reportContext: reportContext)
        let scanResult = try await Self.loadLocalTokenScanResult(
            provider: provider,
            since: since,
            now: now,
            options: localScanOptions)

        if allowPricingRefresh,
           retryUnknownPricing,
           let request = Self.unknownPricingRefreshRequest(
               provider: provider,
               daily: scanResult.inclusive.daily,
               now: now,
               cacheRoot: options.cacheRoot,
               client: modelsDevClient),
           await Self.refreshUnknownPricingIfNeeded(request, inBackground: refreshPricingInBackground)
        {
            return try await self.loadTokenResult(
                provider: provider,
                environment: environment,
                now: now,
                forceRefresh: forceRefresh,
                allowVertexClaudeFallback: allowVertexClaudeFallback,
                codexHomePath: codexHomePath,
                historyDays: historyDays,
                cursorCookieHeaderOverride: cursorCookieHeaderOverride,
                allowPricingRefresh: allowPricingRefresh,
                refreshPricingInBackground: false,
                includePiSessions: includePiSessions,
                piWorkingDirectories: piWorkingDirectories,
                piSessionProcessContexts: piSessionProcessContexts,
                scannerOptions: options,
                piScannerOptions: piOptions,
                modelsDevClient: modelsDevClient,
                retryUnknownPricing: false,
                reportContext: reportContext)
        }

        let snapshot = Self.tokenSnapshot(
            from: scanResult.inclusive.daily,
            now: now,
            historyDays: clampedHistoryDays,
            calendar: scanOptions.calendar,
            historyCoverageIsEstablished: scanResult.inclusive.historyCoverageIsEstablished,
            historySinceDayKey: scanResult.inclusive.historySinceDayKey,
            historyUntilDayKey: scanResult.inclusive.historyUntilDayKey,
            costProvenance: .listPriceEstimate,
            projects: scanResult.inclusive.projects,
            sessions: scanResult.inclusive.sessions,
            updatedAt: scanResult.inclusive.staleSnapshotUpdatedAt)
        // Provider-specific by design: native projections exist for the two transcript families.
        let accounting: PiSnapshotAccounting? = if let scope = scanResult.piScope {
            .includesPi(scope: scope, native: Self.tokenSnapshot(
                from: scanResult.native.daily,
                now: now,
                historyDays: clampedHistoryDays,
                calendar: scanOptions.calendar,
                historyCoverageIsEstablished: scanResult.native.historyCoverageIsEstablished,
                costProvenance: .listPriceEstimate,
                projects: scanResult.native.projects,
                sessions: scanResult.native.sessions,
                updatedAt: scanResult.native.staleSnapshotUpdatedAt))
        } else if provider == .codex || provider == .claude {
            .nativeOnly
        } else {
            nil
        }
        return CostUsageTokenResult(snapshot: snapshot, accounting: accounting)
    }

    private struct LocalTokenScanReport: Sendable {
        let daily: CostUsageDailyReport
        let projects: [CostUsageProjectBreakdown]
        let sessions: [CostUsageSessionBreakdown]
        let staleSnapshotUpdatedAt: Date?
        let historyCoverageIsEstablished: Bool
        let historySinceDayKey: String
        let historyUntilDayKey: String
    }

    private struct LocalTokenScanResult: Sendable {
        let inclusive: LocalTokenScanReport
        let native: LocalTokenScanReport
        let piScope: String?
    }

    private struct LocalTokenScanOptions: Sendable {
        let allowVertexClaudeFallback: Bool
        let includePiSessions: Bool
        let shouldMergePiUsage: Bool
        let scanOptions: CostUsageScanner.Options
        let environment: [String: String]
        let piOptions: PiSessionCostScanner.Options
        let reportContext: CostUsageReportContext?
    }

    private static func unavailableLocalSnapshot(
        now: Date,
        historyDays: Int,
        calendar: Calendar) -> CostUsageTokenSnapshot
    {
        self.tokenSnapshot(
            from: CostUsageDailyReport(data: [], summary: nil),
            now: now,
            historyDays: historyDays,
            calendar: calendar,
            historyCoverageIsEstablished: false)
    }

    private static func loadLocalTokenScanResult(
        provider: UsageProvider,
        since: Date,
        now: Date,
        options: LocalTokenScanOptions) async throws -> LocalTokenScanResult
    {
        try Task.checkCancellation()
        var configuredScanOptions = options.scanOptions
        if provider == .codex {
            // Routine Codex refreshes need only the compact manifest and selected delta paths.
            // The scanner's working-set loader preserves exact aggregate/report semantics while
            // avoiding materialization of the persisted token and usage-row ledgers.
            configuredScanOptions.useCodexCatchUpWorkingSet = true
        }
        let scanOptions = configuredScanOptions
        let historyRange = CostUsageScanner.CostUsageDayRange(
            since: since,
            until: now,
            calendar: scanOptions.calendar)
        // Provider-specific by design: Codex owns project/session attribution and optional Pi merge state, while
        // Claude/Vertex share the transcript scanner with mutually exclusive filters.
        // These synchronous scans can run for minutes on large archives. The dedicated queue keeps
        // them off the cooperative pool and bridges task cancellation into scanner-level checks.
        return try await CostUsageScanExecutor.run { checkCancellation in
            var daily = try CostUsageScanner.loadDailyReportCancellable(
                provider: provider,
                since: since,
                until: now,
                now: now,
                options: scanOptions,
                reportContext: options.reportContext,
                checkCancellation: checkCancellation)
            try checkCancellation()

            if provider == .vertexai,
               !options.allowVertexClaudeFallback,
               scanOptions.claudeLogProviderFilter == .vertexAIOnly,
               daily.data.isEmpty
            {
                var fallback = scanOptions
                fallback.claudeLogProviderFilter = .all
                daily = try CostUsageScanner.loadDailyReportCancellable(
                    provider: provider,
                    since: since,
                    until: now,
                    now: now,
                    options: fallback,
                    reportContext: options.reportContext,
                    checkCancellation: checkCancellation)
                try checkCancellation()
            }

            var projects: [CostUsageProjectBreakdown] = []
            var sessions: [CostUsageSessionBreakdown] = []
            var piScanIsComplete = true
            var staleSnapshotUpdatedAt: Date?
            if provider == .codex {
                let roots = CostUsageScanner.codexSessionsRoots(options: scanOptions)
                let projection = CostUsageStore(cacheRoot: scanOptions.cacheRoot)
                    .syncReadCodexReportProjection(calendar: scanOptions.calendar)
                let cache = CostUsageScanner.codexCache(
                    projection.cache,
                    scopedTo: roots)
                let range = CostUsageScanner.CostUsageDayRange(
                    since: since, until: now, calendar: scanOptions.calendar)
                if let previous = CostUsageScanner.codexPreviousReport(
                    cache: cache,
                    range: range,
                    rootsFingerprint: CostUsageScanner.codexRootsFingerprint(options: scanOptions))
                {
                    let retained = Self.cachedCodexPreviousReportProjection(
                        CachedCodexPreviousReportProjectionInput(
                            previous: previous,
                            projection: projection,
                            cache: cache,
                            roots: roots,
                            range: range,
                            cacheRoot: scanOptions.cacheRoot,
                            includeBreakdowns: true,
                            now: now))
                    daily = retained.report
                    projects = retained.projects
                    sessions = retained.sessions
                    staleSnapshotUpdatedAt = retained.updatedAt
                } else {
                    let projected = CostUsageCodexReportProjectionBuilder.build(
                        projection: projection,
                        roots: roots,
                        range: range,
                        cacheRoot: scanOptions.cacheRoot,
                        includeBreakdowns: true)
                    daily = projected.report
                    projects = projected.projects
                    sessions = projected.sessions
                }
            }
            if provider == .codex {
                sessions = Self.codexSessionsWithThreadTitles(
                    sessions,
                    sessionsRoot: CostUsageScanner.codexSessionsRoots(options: scanOptions).first,
                    environment: options.environment)
            }
            let native = LocalTokenScanReport(
                daily: daily,
                projects: projects,
                sessions: sessions,
                staleSnapshotUpdatedAt: staleSnapshotUpdatedAt,
                historyCoverageIsEstablished: provider != .codex
                    || Self.codexHistoryCoverageIsEstablished(options: scanOptions),
                historySinceDayKey: historyRange.sinceKey,
                historyUntilDayKey: historyRange.untilKey)
            var piScope: String?
            if options.includePiSessions,
               provider == .claude || (provider == .codex && options.shouldMergePiUsage)
            {
                let piScanResult = try PiSessionCostScanner.loadDailyReportResultCancellable(
                    provider: provider,
                    since: since,
                    until: now,
                    now: now,
                    options: options.piOptions,
                    checkCancellation: checkCancellation)
                try checkCancellation()
                piScanIsComplete = piScanResult.isComplete
                if !piScanResult.isComplete, let piLastScanAt = piScanResult.lastScanAt {
                    staleSnapshotUpdatedAt = [staleSnapshotUpdatedAt, piLastScanAt]
                        .compactMap(\.self).min()
                }
                if provider == .codex {
                    if let project = Self.unknownProjectBreakdown(from: piScanResult.report) {
                        projects.append(project)
                        sessions = []
                    }
                }
                piScope = piScanResult.scopeFingerprint
                daily = CostUsageDailyReport.merged(
                    [daily, piScanResult.report], calendar: scanOptions.calendar)
            }
            if provider == .codex {
                projects = Self.mergedProjectBreakdowns(projects)
            }
            return LocalTokenScanResult(
                inclusive: LocalTokenScanReport(
                    daily: daily,
                    projects: projects,
                    sessions: sessions,
                    staleSnapshotUpdatedAt: staleSnapshotUpdatedAt,
                    historyCoverageIsEstablished: native.historyCoverageIsEstablished && piScanIsComplete,
                    historySinceDayKey: historyRange.sinceKey,
                    historyUntilDayKey: historyRange.untilKey),
                native: native,
                piScope: piScope)
        }
    }

    /// Codex thread titles live outside rollout files; resolve them after the cost scan.
    static func codexSessionsWithThreadTitles(
        _ sessions: [CostUsageSessionBreakdown],
        sessionsRoot: URL?,
        environment: [String: String] = ProcessInfo.processInfo.environment) -> [CostUsageSessionBreakdown]
    {
        guard !sessions.isEmpty,
              let sessionsRoot,
              sessionsRoot.lastPathComponent == "sessions"
        else { return sessions }
        let home = sessionsRoot.deletingLastPathComponent()
        let indexedNames = CodexThreadMetadataReader.indexedThreadNames(
            codexHomeDirectory: home,
            sessionIDs: Set(sessions.map(\.sessionID)))
        let groups = Dictionary(grouping: sessions) { session in
            CodexThreadMetadataReader(
                codexHomeDirectory: home,
                environment: environment,
                resolvedWorkingDirectory: session.workingDirectory.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                }).databaseURL
        }
        var metadata: [String: CodexThreadMetadata] = [:]
        for (database, group) in groups {
            metadata.merge(CodexThreadMetadataReader(databaseURL: database).metadata(
                for: Set(group.map(\.sessionID)), indexedNames: indexedNames)) { _, latest in latest }
        }
        return sessions.map { session in
            guard let title = metadata[session.sessionID]?.title else { return session }
            return session.withTitle(title)
        }
    }

    private struct PricingRefreshOptions: Sendable {
        let provider: UsageProvider
        let isAllowed: Bool
        let retryUnknown: Bool
        let inBackground: Bool
    }

    private struct AntigravityPricingOptions {
        let cacheRoot: URL?
        let refresh: PricingRefreshOptions
        let client: ModelsDevClient
    }

    private static func refreshPricingIfAllowed(
        options: PricingRefreshOptions,
        now: Date,
        cacheRoot: URL?,
        client: ModelsDevClient) async
    {
        guard options.isAllowed,
              options.retryUnknown,
              options.provider == .codex || options.provider == .claude || options.provider == .antigravity
        else { return }

        if options.inBackground {
            Task.detached(priority: .utility) {
                await ModelsDevPricingPipeline.refreshIfNeeded(now: now, cacheRoot: cacheRoot, client: client)
            }
        } else {
            await ModelsDevPricingPipeline.refreshIfNeeded(now: now, cacheRoot: cacheRoot, client: client)
        }
    }

    private static func loadPricedAntigravityLocalSnapshot(
        environment: [String: String],
        now: Date,
        historyDays: Int,
        calendar: Calendar,
        pricing: AntigravityPricingOptions) async throws -> CostUsageTokenSnapshot?
    {
        let context = AntigravityLocalReader.Context(environment: environment)
        let snapshot = try await self.loadAntigravityLocalSnapshot(
            context: context,
            now: now,
            historyDays: historyDays,
            calendar: calendar,
            pricingCacheRoot: pricing.cacheRoot)
        // Provider-specific by design: Antigravity returns before the shared scan path, so it is the
        // one provider that has to request its own unknown-model pricing refresh; without it a
        // newly released model stays unpriced forever.
        guard let snapshot, !snapshot.daily.isEmpty,
              pricing.refresh.isAllowed,
              pricing.refresh.retryUnknown
        else { return snapshot }
        guard let request = Self.unknownPricingRefreshRequest(
            provider: .antigravity,
            daily: CostUsageDailyReport(data: snapshot.daily, summary: nil),
            now: now,
            cacheRoot: pricing.cacheRoot,
            client: pricing.client)
        else {
            await self.refreshPricingIfAllowed(
                options: PricingRefreshOptions(
                    provider: pricing.refresh.provider, isAllowed: true, retryUnknown: true, inBackground: true),
                now: now,
                cacheRoot: pricing.cacheRoot,
                client: pricing.client)
            return snapshot
        }
        guard await Self.refreshUnknownPricingIfNeeded(request, inBackground: pricing.refresh.inBackground)
        else { return snapshot }
        let repriced = try await self.loadAntigravityLocalSnapshot(
            context: context,
            now: now,
            historyDays: historyDays,
            calendar: calendar,
            pricingCacheRoot: pricing.cacheRoot)
        // A pricing download must not replace a complete scan with history truncated in the meantime.
        guard let repriced, snapshot.historyScanIsPartial || !repriced.historyScanIsPartial else { return snapshot }
        return repriced
    }

    private struct UnknownPricingRefreshRequest: Sendable {
        let targets: Set<ModelsDevPricingTarget>
        let now: Date
        let cacheRoot: URL?
        let client: ModelsDevClient
    }

    private static func unknownPricingRefreshRequest(
        provider: UsageProvider,
        daily: CostUsageDailyReport,
        now: Date,
        cacheRoot: URL?,
        client: ModelsDevClient) -> UnknownPricingRefreshRequest?
    {
        guard provider == .codex || provider == .claude || provider == .antigravity else { return nil }
        var targets = Set<ModelsDevPricingTarget>()
        for entry in daily.data {
            for breakdown in entry.modelBreakdowns ?? [] {
                guard breakdown.costUSD == nil else { continue }
                if provider == .antigravity {
                    // Antigravity prices through the Claude resolver, and its routing variants
                    // resolve against the base vendor model, so both IDs are worth fetching.
                    let names = [breakdown.modelName]
                        + [AntigravityLocalReader.pricingBaseModelID(for: breakdown.modelName)].compactMap(\.self)
                    for name in names {
                        for target in CostUsagePricing.claudeModelsDevPricingTargets(for: name) {
                            targets.insert(ModelsDevPricingTarget(
                                providerID: target.providerID,
                                modelID: target.modelID))
                        }
                    }
                } else if provider == .codex {
                    guard OpenCodexRouteDispatcher.countsTowardCodexSubscription(modelName: breakdown.modelName)
                    else { continue }
                    guard !CostUsagePricing.isCodexUnattributedModel(breakdown.modelName) else { continue }
                    for target in CostUsagePricing.codexModelsDevPricingTargets(for: breakdown.modelName) {
                        targets.insert(ModelsDevPricingTarget(providerID: target.providerID, modelID: target.modelID))
                    }
                } else {
                    for target in CostUsagePricing.claudeModelsDevPricingTargets(for: breakdown.modelName) {
                        targets.insert(ModelsDevPricingTarget(
                            providerID: target.providerID,
                            modelID: target.modelID))
                    }
                }
            }
        }
        guard !targets.isEmpty else { return nil }

        return UnknownPricingRefreshRequest(
            targets: targets,
            now: now,
            cacheRoot: cacheRoot,
            client: client)
    }

    private static func refreshUnknownPricingIfNeeded(
        _ request: UnknownPricingRefreshRequest,
        inBackground: Bool) async -> Bool
    {
        func refreshTargets() async -> Bool {
            let targetsByProvider = Dictionary(grouping: request.targets, by: \.providerID)
            for providerID in targetsByProvider.keys.sorted() {
                let modelIDs = Set(targetsByProvider[providerID, default: []].map(\.modelID))
                let outcome = await ModelsDevPricingPipeline.refreshForUnknownModelsIfNeeded(
                    providerID: providerID,
                    modelIDs: modelIDs,
                    now: request.now,
                    cacheRoot: request.cacheRoot,
                    client: request.client)
                if outcome == .pricingAvailable {
                    return true
                }
            }
            // An earlier group may refresh the shared catalog without resolving its own alias.
            let catalog = ModelsDevCache.load(now: request.now, cacheRoot: request.cacheRoot).artifact?.catalog
            return request.targets.contains {
                catalog?.pricing(providerID: $0.providerID, modelID: $0.modelID) != nil
            }
        }

        if inBackground {
            Task.detached(priority: .utility) {
                _ = await refreshTargets()
            }
            return false
        }
        return await refreshTargets()
    }

    static func loadCachedCodexTokenSnapshot(
        now: Date = Date(),
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        allowScopedCodexHome: Bool = false,
        includePiSessions: Bool = true,
        includeProjectAndSessionBreakdowns: Bool = true,
        requireCompleteHistory: Bool = false,
        scannerOptions overrideScannerOptions: CostUsageScanner.Options? = nil,
        piScannerOptions: PiSessionCostScanner.Options? = nil) async -> CostUsageTokenSnapshot?
    {
        await self.loadCachedCodexTokenSnapshotResult(
            now: now,
            codexHomePath: codexHomePath,
            historyDays: historyDays,
            allowScopedCodexHome: allowScopedCodexHome,
            includePiSessions: includePiSessions,
            includeProjectAndSessionBreakdowns: includeProjectAndSessionBreakdowns,
            requireCompleteHistory: requireCompleteHistory,
            scannerOptions: overrideScannerOptions,
            piScannerOptions: piScannerOptions)?.snapshot
    }

    static func loadCachedCodexTokenActivity(
        now: Date = Date(),
        codexHomePath: String? = nil,
        maximumDays: Int = 365,
        scannerOptions overrideScannerOptions: CostUsageScanner.Options? = nil) async
        -> CostUsageTokenActivityCache?
    {
        let projectionOptions = Self.resolvedScannerOptions(
            overrideScannerOptions,
            provider: .codex,
            codexHomePath: codexHomePath)
        let persistedProjection = await CostUsageStoreAccess.readCodexReportProjection(
            cacheRoot: projectionOptions.cacheRoot,
            calendar: projectionOptions.calendar)
        let cachedActivity: CostUsageTokenActivityCache?? = try? await CostUsageScanExecutor.run { _ in
            let options = projectionOptions
            let days = max(1, min(365, maximumDays))
            let since = options.calendar.date(byAdding: .day, value: -(days - 1), to: now) ?? now
            let requestedRange = CostUsageScanner.CostUsageDayRange(
                since: since,
                until: now,
                calendar: options.calendar)
            let roots = CostUsageScanner.codexSessionsRoots(options: options)
            let rootsFingerprint = CostUsageScanner.codexRootsFingerprint(options: options)
            let cache = CostUsageScanner.codexCache(
                persistedProjection.cache,
                scopedTo: roots)
            guard cache.timeZoneIdentifier == options.calendar.timeZone.identifier,
                  cache.roots == rootsFingerprint,
                  cache.codexScanCatchUpPending != true,
                  !cache.files.values.contains(where: {
                      $0.codexScanComplete == false || $0.hasBufferedCodexForkRetryLines
                  }),
                  let cachedSince = cache.scanSinceKey,
                  let cachedUntil = cache.scanUntilKey
            else { return nil }

            let coverageSince = max(cachedSince, requestedRange.scanSinceKey)
            let coverageUntil = min(cachedUntil, requestedRange.scanUntilKey)
            guard coverageSince <= coverageUntil else { return nil }
            let daily = cache.days.keys
                .filter { $0 >= coverageSince && $0 <= coverageUntil }
                .sorted()
                .map { day -> CostUsageDailyReport.Entry in
                    var total = 0
                    for (model, packed) in cache.days[day, default: [:]] {
                        guard OpenCodexRouteDispatcher.countsTowardCodexSubscription(modelName: model) else {
                            continue
                        }
                        for value in [packed[safe: 0] ?? 0, packed[safe: 2] ?? 0] {
                            let addition = total.addingReportingOverflow(max(0, value))
                            total = addition.overflow ? Int.max : addition.partialValue
                        }
                    }
                    return CostUsageDailyReport.Entry(
                        date: day,
                        inputTokens: nil,
                        outputTokens: nil,
                        totalTokens: total,
                        costUSD: nil,
                        modelsUsed: nil,
                        modelBreakdowns: nil)
                }
            return CostUsageTokenActivityCache(
                daily: daily,
                coverageSinceKey: coverageSince,
                coverageUntilKey: coverageUntil)
        }
        return cachedActivity.flatMap(\.self)
    }

    // Cached projection hydration deliberately keeps native, retained-history, and Pi merge
    // evidence in one closure so the publication flags cannot drift from the assembled snapshot.
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func loadCachedCodexTokenSnapshotResult(
        now: Date = Date(),
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        allowScopedCodexHome: Bool = false,
        includePiSessions: Bool = true,
        includeProjectAndSessionBreakdowns: Bool = true,
        requireCompleteHistory: Bool = false,
        scannerOptions overrideScannerOptions: CostUsageScanner.Options? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        piScannerOptions: PiSessionCostScanner.Options? = nil) async
        -> CachedCodexTokenSnapshotResult?
    {
        let scopedCodexHomePath = codexHomePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard scopedCodexHomePath?.isEmpty != false || allowScopedCodexHome else { return nil }
        let piHistoryRequested = includePiSessions && scopedCodexHomePath?.isEmpty != false
        let processContexts: [PiSessionProcessContext] = if piHistoryRequested, piScannerOptions == nil {
            await LocalAgentSessionScanner().piSessionProcessContexts(environment: environment)
        } else {
            []
        }

        let projectionOptions = Self.resolvedScannerOptions(
            overrideScannerOptions,
            provider: .codex,
            codexHomePath: codexHomePath)
        let persistedProjection = await CostUsageStoreAccess.readCodexReportProjection(
            cacheRoot: projectionOptions.cacheRoot,
            calendar: projectionOptions.calendar)

        // Projection assembly touches only compact manifests and day/model aggregates. Keep
        // pricing and project/session rollups off the cooperative pool, but never hydrate the
        // token-snapshot or usage-row ledgers for cached presentation.
        let cachedSnapshot: CachedCodexTokenSnapshotResult?? = try? await CostUsageScanExecutor.run { _ in
            let clampedHistoryDays = max(1, min(365, historyDays))
            // Provider-specific by design: cached Codex token publication uses the Codex scanner and its roots.
            let options = Self.resolvedScannerOptions(
                overrideScannerOptions,
                provider: .codex,
                codexHomePath: codexHomePath)
            let until = now
            let since = options.calendar.date(
                byAdding: .day,
                value: -(clampedHistoryDays - 1),
                to: now) ?? now
            let range = CostUsageScanner.CostUsageDayRange(
                since: since,
                until: until,
                calendar: options.calendar)
            var shouldMergePiUsage = scopedCodexHomePath?.isEmpty != false
            let roots = CostUsageScanner.codexSessionsRoots(options: options)
            let rootsFingerprint = CostUsageScanner.codexRootsFingerprint(options: options)
            let loadedCache = persistedProjection.cache
            let cache = CostUsageScanner.codexCache(
                loadedCache,
                scopedTo: roots)
            var reports: [CostUsageDailyReport] = []
            var projects: [CostUsageProjectBreakdown] = []
            var sessions: [CostUsageSessionBreakdown] = []
            // Raw inputs for the derived result fields below: the native cache's own scan
            // time, every constituent scan time, and whether a second source joined the merge.
            var nativeScanAt: Date?
            var scanTimes: [Date] = []
            var piHistoryIsComplete = !piHistoryRequested
            var piMerged = false
            var accounting: PiSnapshotAccounting = .nativeOnly
            var staleSnapshotUpdatedAt: Date?
            var currentDayIsFullyVerified = false
            let nativeHistoryCoverageIsEstablished = Self.codexCachedHistoryCoverageIsEstablished(
                cache: cache,
                range: range,
                rootsFingerprint: rootsFingerprint)
            let verifiedHistoryCoverageIsEstablished = Self.codexVerifiedHistoryCoverageContains(
                projection: persistedProjection,
                cache: cache,
                range: range,
                rootsFingerprint: rootsFingerprint)
            let previousReport = CostUsageScanner.codexPreviousReport(
                cache: cache,
                range: range,
                rootsFingerprint: rootsFingerprint)
            let pendingWithoutNativeHistoryBaseline = cache.codexScanCatchUpPending == true
                && !verifiedHistoryCoverageIsEstablished
                && previousReport == nil
            shouldMergePiUsage = shouldMergePiUsage && !pendingWithoutNativeHistoryBaseline

            if cache.codexScanCatchUpPending == true,
               previousReport == nil,
               verifiedHistoryCoverageIsEstablished || !persistedProjection.verifiedDayAggregates.isEmpty
            {
                let retained = Self.cachedCodexVerifiedReportProjection(.init(
                    projection: persistedProjection,
                    cache: cache,
                    roots: roots,
                    rootsFingerprint: rootsFingerprint,
                    range: range,
                    cacheRoot: options.cacheRoot,
                    now: now))
                reports.append(retained.report)
                if let updatedAt = retained.updatedAt {
                    scanTimes.append(updatedAt)
                }
                nativeScanAt = retained.nativeScanAt
                staleSnapshotUpdatedAt = retained.updatedAt
                currentDayIsFullyVerified = retained.currentDayIsFullyVerified
            } else if let previous = previousReport {
                let retained = Self.cachedCodexPreviousReportProjection(.init(
                    previous: previous,
                    projection: persistedProjection,
                    cache: cache,
                    roots: roots,
                    range: range,
                    cacheRoot: options.cacheRoot,
                    includeBreakdowns: includeProjectAndSessionBreakdowns,
                    now: now))
                reports.append(retained.report)
                projects.append(contentsOf: retained.projects)
                sessions = retained.sessions
                if let updatedAt = retained.updatedAt {
                    scanTimes.append(updatedAt)
                }
                nativeScanAt = retained.nativeScanAt
                staleSnapshotUpdatedAt = previous.updatedAt
                currentDayIsFullyVerified = retained.currentDayIsFullyVerified
            } else if let currentDay = Self.cachedCodexIndependentlyVerifiedCurrentDay(
                CachedCodexVerifiedReportProjectionInput(
                    projection: persistedProjection,
                    cache: cache,
                    roots: roots,
                    rootsFingerprint: rootsFingerprint,
                    range: range,
                    cacheRoot: options.cacheRoot,
                    now: now))
            {
                reports.append(currentDay.report)
                nativeScanAt = currentDay.nativeScanAt
                currentDayIsFullyVerified = currentDay.currentDayIsFullyVerified
                if let scanAt = currentDay.nativeScanAt {
                    scanTimes.append(scanAt)
                }
            } else if cache.codexScanCatchUpPending != true,
                      cache.timeZoneIdentifier == range.calendar.timeZone.identifier,
                      !cache.days.isEmpty,
                      cache.roots == rootsFingerprint,
                      !CostUsageScanner.requestedWindowExpandsCache(range: range, cache: cache)
            {
                let projected = CostUsageCodexReportProjectionBuilder.build(
                    projection: persistedProjection,
                    roots: roots,
                    range: range,
                    cacheRoot: options.cacheRoot,
                    includeBreakdowns: includeProjectAndSessionBreakdowns)
                let daily = projected.report
                if !daily.data.isEmpty {
                    reports.append(daily)
                    let currentDayKey = CostUsageScanner.CostUsageDayRange.dayKey(
                        from: now,
                        calendar: range.calendar)
                    currentDayIsFullyVerified = daily.data.contains {
                        $0.date == currentDayKey && $0.costUSD != nil
                    } && CostUsageScanner.codexCurrentDayProjectionCanPublish(
                        cache: cache,
                        roots: roots,
                        dayKey: currentDayKey,
                        calendar: range.calendar)
                    if cache.lastScanUnixMs > 0 {
                        let scanAt = Date(timeIntervalSince1970: TimeInterval(cache.lastScanUnixMs) / 1000)
                        nativeScanAt = scanAt
                        scanTimes.append(scanAt)
                    }
                    if includeProjectAndSessionBreakdowns {
                        sessions = projected.sessions
                        if cache.codexProjectMetadataVersion == CostUsageScanner.codexProjectMetadataVersion {
                            projects.append(contentsOf: projected.projects)
                        }
                    }
                }
            }

            // A completed scan can legitimately have no rows (a fresh account or a quiet
            // window). Keep that established-empty state across app restarts instead of
            // collapsing it back to "unavailable" merely because the cache has no day map.
            if reports.isEmpty, nativeHistoryCoverageIsEstablished || verifiedHistoryCoverageIsEstablished {
                reports.append(Self.establishedEmptyCodexDailyReport)
                let establishedAt = verifiedHistoryCoverageIsEstablished
                    ? persistedProjection.verifiedUpdatedAtUnixMs
                    : cache.lastScanUnixMs
                if let establishedAt, establishedAt > 0 {
                    let scanAt = Date(timeIntervalSince1970: TimeInterval(establishedAt) / 1000)
                    nativeScanAt = scanAt
                    scanTimes.append(scanAt)
                }
            }

            let nativeSnapshot: CostUsageTokenSnapshot? = reports.isEmpty ? nil : Self.tokenSnapshot(
                from: CostUsageDailyReport.merged(reports),
                now: now,
                historyDays: clampedHistoryDays,
                calendar: options.calendar,
                historyCoverageIsEstablished: nativeHistoryCoverageIsEstablished
                    || verifiedHistoryCoverageIsEstablished
                    || (previousReport != nil && staleSnapshotUpdatedAt != nil),
                historySinceDayKey: range.sinceKey,
                historyUntilDayKey: range.untilKey,
                costProvenance: .listPriceEstimate,
                projects: Self.mergedProjectBreakdowns(projects),
                sessions: sessions,
                updatedAt: scanTimes.min())
            if piHistoryRequested, shouldMergePiUsage {
                let piOptions = piScannerOptions ?? PiSessionCostScanner.Options(
                    cacheRoot: options.cacheRoot,
                    calendar: options.calendar,
                    environment: environment,
                    processContexts: processContexts)
                let piResult = PiSessionCostScanner.loadCachedDailyReportResult(
                    provider: .codex,
                    since: since,
                    until: until,
                    now: now,
                    cacheRoot: options.cacheRoot,
                    calendar: options.calendar,
                    options: piOptions,
                    allowEstablishedEmpty: true)
                piHistoryIsComplete = piResult?.isComplete == true && piResult?.scopeFingerprint != nil
                if let piResult, let scope = piResult.scopeFingerprint {
                    accounting = nativeSnapshot.map { .includesPi(scope: scope, native: $0) }
                        ?? .piOnly(scope: scope)
                    reports.append(piResult.report)
                    piMerged = true
                    let currentDayKey = CostUsageScanner.CostUsageDayRange.dayKey(
                        from: now,
                        calendar: range.calendar)
                    if piResult.report.data.contains(where: { $0.date == currentDayKey }) {
                        currentDayIsFullyVerified = false
                    }
                    if let piLastScanAt = piResult.lastScanAt {
                        scanTimes.append(piLastScanAt)
                    }
                    if let piProject = Self.unknownProjectBreakdown(from: piResult.report) {
                        projects.append(piProject)
                    }
                    if !piResult.report.data.isEmpty {
                        sessions = []
                    }
                }
            }

            guard !reports.isEmpty else { return nil }
            // `previous` is an exact report captured before the current bounded refresh became
            // pending. Its rows remain established even though native catch-up is still active;
            // `staleSnapshotUpdatedAt` keeps refresh scheduling and stale presentation explicit.
            let displayedHistoryCoverageIsEstablished = (nativeHistoryCoverageIsEstablished
                || verifiedHistoryCoverageIsEstablished
                // A previous report is an established snapshot retained across a pending
                // refresh. Sparse verified day rows use the same stale timestamp plumbing for
                // freshness, but must not turn their partial window into complete coverage.
                || (previousReport != nil && staleSnapshotUpdatedAt != nil)) && piHistoryIsComplete
            guard !requireCompleteHistory || displayedHistoryCoverageIsEstablished else { return nil }
            // updatedAt keeps the caches' real (oldest) scan time; stamping the hydration time
            // would let stale token rows inherit app-start freshness (#1964). lastRefreshAt
            // drives TTL suppression and stays native-only: a merged load must never delay a
            // rescan on the strength of another source's scan.
            return CachedCodexTokenSnapshotResult(
                snapshot: Self.tokenSnapshot(
                    from: CostUsageDailyReport.merged(reports, calendar: options.calendar),
                    now: now,
                    historyDays: clampedHistoryDays,
                    calendar: options.calendar,
                    historyCoverageIsEstablished: displayedHistoryCoverageIsEstablished,
                    historySinceDayKey: range.sinceKey,
                    historyUntilDayKey: range.untilKey,
                    costProvenance: .listPriceEstimate,
                    projects: Self.mergedProjectBreakdowns(projects),
                    sessions: Self.codexSessionsWithThreadTitles(sessions, sessionsRoot: roots.first),
                    updatedAt: scanTimes.min()),
                accounting: accounting,
                lastRefreshAt: piMerged || staleSnapshotUpdatedAt != nil ? nil : nativeScanAt,
                staleSnapshotUpdatedAt: staleSnapshotUpdatedAt,
                currentDayIsFullyVerified: currentDayIsFullyVerified)
        }
        return cachedSnapshot.flatMap(\.self)
    }

    private static func replacingDay(
        _ dayKey: String,
        in established: CostUsageDailyReport,
        with replacement: CostUsageDailyReport.Entry) -> CostUsageDailyReport
    {
        let retained = CostUsageDailyReport(
            data: established.data.filter { $0.date != dayKey },
            summary: nil)
        let currentDay = CostUsageDailyReport(data: [replacement], summary: nil)
        return CostUsageDailyReport.merged([retained, currentDay])
    }

    private static func replacingVerifiedDays(
        in established: CostUsageDailyReport,
        with verified: CostUsageDailyReport) -> CostUsageDailyReport
    {
        let verifiedDays = Set(verified.data.map(\.date))
        let retained = CostUsageDailyReport(
            data: established.data.filter { !verifiedDays.contains($0.date) },
            summary: nil)
        return CostUsageDailyReport.merged([retained, verified])
    }

    private struct CachedCodexPreviousReportProjectionInput {
        let previous: CostUsageCodexPreviousReport
        let projection: CostUsageStoreCodexReportProjection
        let cache: CostUsageCache
        let roots: [URL]
        let range: CostUsageScanner.CostUsageDayRange
        let cacheRoot: URL?
        let includeBreakdowns: Bool
        let now: Date
    }

    private struct CachedCodexPreviousReportProjectionResult {
        let report: CostUsageDailyReport
        let projects: [CostUsageProjectBreakdown]
        let sessions: [CostUsageSessionBreakdown]
        let updatedAt: Date?
        let nativeScanAt: Date?
        let currentDayIsFullyVerified: Bool
    }

    private struct CachedCodexVerifiedReportProjectionInput {
        let projection: CostUsageStoreCodexReportProjection
        let cache: CostUsageCache
        let roots: [URL]
        let rootsFingerprint: [String: Int64]
        let range: CostUsageScanner.CostUsageDayRange
        let cacheRoot: URL?
        let now: Date
    }

    private static func cachedCodexIndependentlyVerifiedCurrentDay(
        _ input: CachedCodexVerifiedReportProjectionInput) -> CachedCodexPreviousReportProjectionResult?
    {
        guard input.cache.codexScanCatchUpPending == true,
              input.cache.timeZoneIdentifier == input.range.calendar.timeZone.identifier,
              !input.cache.days.isEmpty,
              input.cache.roots == input.rootsFingerprint
        else { return nil }

        // A parser-compatible upgrade can inherit a durable ledger whose older verification
        // baseline predates the normalized verified table. Never publish incomplete history,
        // but do publish today's independently proven aggregate instead of returning nil.
        let projected = CostUsageCodexReportProjectionBuilder.build(
            projection: input.projection,
            roots: input.roots,
            range: input.range,
            cacheRoot: input.cacheRoot,
            includeBreakdowns: false)
        let currentDayKey = CostUsageScanner.CostUsageDayRange.dayKey(
            from: input.now,
            calendar: input.range.calendar)
        guard let currentDay = projected.report.data.first(where: {
            $0.date == currentDayKey && $0.costUSD != nil
        }), CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: input.cache,
            roots: input.roots,
            dayKey: currentDayKey,
            calendar: input.range.calendar)
        else { return nil }

        let scanAt = input.cache.lastScanUnixMs > 0
            ? Date(timeIntervalSince1970: TimeInterval(input.cache.lastScanUnixMs) / 1000)
            : nil
        return CachedCodexPreviousReportProjectionResult(
            report: CostUsageDailyReport(data: [currentDay], summary: nil),
            projects: [],
            sessions: [],
            updatedAt: scanAt,
            nativeScanAt: scanAt,
            currentDayIsFullyVerified: true)
    }

    private static func cachedCodexVerifiedReportProjection(
        _ input: CachedCodexVerifiedReportProjectionInput) -> CachedCodexPreviousReportProjectionResult
    {
        let established = CostUsageCodexReportProjectionBuilder.buildVerifiedReport(
            projection: input.projection,
            range: input.range,
            cacheRoot: input.cacheRoot)
        let currentDayKey = CostUsageScanner.CostUsageDayRange.dayKey(
            from: input.now,
            calendar: input.range.calendar)
        let projected = CostUsageCodexReportProjectionBuilder.build(
            projection: input.projection,
            roots: input.roots,
            range: input.range,
            cacheRoot: input.cacheRoot,
            includeBreakdowns: false)
        let freshCurrentDay = projected.report.data.first { $0.date == currentDayKey }
        let verifiedUpdatedAt = input.projection.verifiedUpdatedAtUnixMs.flatMap { timestamp -> Date? in
            guard timestamp > 0 else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        }
        let canPublishFreshCurrentDay = freshCurrentDay?.costUSD != nil
            && input.cache.lastScanUnixMs > (input.projection.verifiedUpdatedAtUnixMs ?? 0)
            && CostUsageScanner.codexCurrentDayProjectionCanPublish(
                cache: input.cache,
                roots: input.roots,
                dayKey: currentDayKey,
                calendar: input.range.calendar)
        guard canPublishFreshCurrentDay, let freshCurrentDay else {
            return CachedCodexPreviousReportProjectionResult(
                report: established,
                projects: [],
                sessions: [],
                updatedAt: verifiedUpdatedAt,
                nativeScanAt: nil,
                currentDayIsFullyVerified: false)
        }

        let scanAt = Date(timeIntervalSince1970: TimeInterval(input.cache.lastScanUnixMs) / 1000)
        return CachedCodexPreviousReportProjectionResult(
            report: Self.replacingDay(currentDayKey, in: established, with: freshCurrentDay),
            projects: [],
            sessions: [],
            updatedAt: scanAt,
            nativeScanAt: scanAt,
            currentDayIsFullyVerified: true)
    }

    private static func cachedCodexPreviousReportProjection(
        _ input: CachedCodexPreviousReportProjectionInput) -> CachedCodexPreviousReportProjectionResult
    {
        var retainedReport = CostUsageDailyReport(
            data: input.previous.report.data.filter {
                CostUsageScanner.CostUsageDayRange.isInRange(
                    dayKey: $0.date,
                    since: input.range.sinceKey,
                    until: input.range.untilKey)
            },
            summary: nil)
        if let verifiedUpdatedAt = input.projection.verifiedUpdatedAtUnixMs,
           verifiedUpdatedAt > input.previous.updatedAtUnixMs,
           !input.projection.verifiedDayAggregates.isEmpty
        {
            let verified = CostUsageCodexReportProjectionBuilder.buildVerifiedReport(
                projection: input.projection,
                range: input.range,
                cacheRoot: input.cacheRoot)
            if !verified.data.isEmpty {
                retainedReport = Self.replacingVerifiedDays(
                    in: retainedReport,
                    with: verified)
            }
        }
        let projected = CostUsageCodexReportProjectionBuilder.build(
            projection: input.projection,
            roots: input.roots,
            range: input.range,
            cacheRoot: input.cacheRoot,
            includeBreakdowns: input.includeBreakdowns)
        let currentDayKey = CostUsageScanner.CostUsageDayRange.dayKey(
            from: input.now,
            calendar: input.range.calendar)
        let freshCurrentDay = projected.report.data.first { $0.date == currentDayKey }
        let currentDayIsFullyVerified = freshCurrentDay?.costUSD != nil
            && CostUsageScanner.codexCurrentDayProjectionCanPublish(
                cache: input.cache,
                roots: input.roots,
                dayKey: currentDayKey,
                calendar: input.range.calendar)
        let retainedCurrentDay = retainedReport.data.first { $0.date == currentDayKey }
        let hasNewerEvidence = input.cache.lastScanUnixMs > input.previous.updatedAtUnixMs
            || (currentDayIsFullyVerified && freshCurrentDay != retainedCurrentDay)
        let canPublishFreshCurrentDay = freshCurrentDay?.costUSD != nil
            && hasNewerEvidence
            && currentDayIsFullyVerified
        guard canPublishFreshCurrentDay, let freshCurrentDay else {
            return CachedCodexPreviousReportProjectionResult(
                report: retainedReport,
                projects: [],
                sessions: [],
                updatedAt: input.previous.updatedAt,
                nativeScanAt: nil,
                currentDayIsFullyVerified: false)
        }

        let scanAt = Date(timeIntervalSince1970: TimeInterval(input.cache.lastScanUnixMs) / 1000)
        let projects = input.includeBreakdowns
            && input.cache.codexProjectMetadataVersion == CostUsageScanner.codexProjectMetadataVersion
            ? projected.projects
            : []
        return CachedCodexPreviousReportProjectionResult(
            report: Self.replacingDay(currentDayKey, in: retainedReport, with: freshCurrentDay),
            projects: projects,
            sessions: input.includeBreakdowns ? projected.sessions : [],
            updatedAt: scanAt,
            nativeScanAt: scanAt,
            currentDayIsFullyVerified: currentDayIsFullyVerified)
    }

    /// Providers whose token-cost snapshot `loadTokenSnapshot` can produce. Cursor is
    /// macOS-only because it reuses the macOS Cursor session resolution.
    static func supportsTokenSnapshot(_ provider: UsageProvider) -> Bool {
        ProviderDescriptorRegistry.descriptor(for: provider).tokenCost.supportsTokenSnapshot
    }

    static func loadCachedCodexLocalProjectUsageSnapshot(
        now: Date = Date(),
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        hidePersonalInfo: Bool,
        scannerOptions overrideScannerOptions: CostUsageScanner.Options? = nil) async -> CodexLocalProjectUsageSnapshot?
    {
        let cachedSnapshot: CodexLocalProjectUsageSnapshot?? = try? await CostUsageScanExecutor.run { _ in
            let options = Self.codexLocalScannerOptions(
                codexHomePath: codexHomePath,
                overrideScannerOptions: overrideScannerOptions)
            return CodexLocalProjectUsageIndexer.cachedSnapshot(
                now: now,
                historyDays: historyDays,
                options: CodexLocalProjectUsageIndexer.Options(scannerOptions: options))
        }
        return cachedSnapshot.flatMap(\.self)?.hidingPersonalInformation(hidePersonalInfo)
    }

    static func loadCodexLocalProjectUsageSnapshot(
        now: Date = Date(),
        forceRefresh: Bool = false,
        codexHomePath: String? = nil,
        historyDays: Int = 30,
        hidePersonalInfo: Bool,
        progress: (@Sendable (CodexLocalProjectUsageIndexProgress) -> Void)? = nil,
        scannerOptions overrideScannerOptions: CostUsageScanner
            .Options? = nil) async throws -> CodexLocalProjectUsageSnapshot
    {
        let options = Self.codexLocalScannerOptions(
            codexHomePath: codexHomePath,
            overrideScannerOptions: overrideScannerOptions)
        let scanOptions = options
        let snapshot = try await CostUsageScanExecutor.run { checkCancellation in
            try CodexLocalProjectUsageIndexer.loadSnapshot(
                now: now,
                historyDays: historyDays,
                forceRefresh: forceRefresh,
                options: CodexLocalProjectUsageIndexer.Options(scannerOptions: scanOptions),
                progress: progress,
                checkCancellation: checkCancellation)
        }
        return snapshot.hidingPersonalInformation(hidePersonalInfo)
    }

    static func clearCachedCodexLocalProjectUsageSnapshot(
        codexHomePath: String? = nil,
        scannerOptions overrideScannerOptions: CostUsageScanner.Options? = nil) async
    {
        _ = try? await CostUsageScanExecutor.run { _ in
            let options = Self.codexLocalScannerOptions(
                codexHomePath: codexHomePath,
                overrideScannerOptions: overrideScannerOptions)
            CodexWorkspaceUsageSidecar(cacheRoot: options.cacheRoot).clear()
        }
    }

    private static func codexLocalScannerOptions(
        codexHomePath: String?,
        overrideScannerOptions: CostUsageScanner.Options?) -> CostUsageScanner.Options
    {
        var options = overrideScannerOptions ?? CostUsageScanner.Options()
        if let codexHomePath = codexHomePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHomePath.isEmpty
        {
            options.codexSessionsRoot = URL(fileURLWithPath: codexHomePath, isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        }
        return CodexLocalDataScope.resolve(options: options).applying(to: options)
    }

    private static func loadBedrockDailyReport(
        environment: [String: String],
        since: Date,
        until: Date) async throws -> CostUsageDailyReport
    {
        let resolved = try await BedrockCredentialResolver.resolve(environment: environment)
        return try await BedrockUsageFetcher.fetchDailyReport(
            credentials: resolved.credentials,
            since: since,
            until: until,
            environment: environment)
    }

    #if os(macOS)
    /// Fetch Cursor's per-day token-cost plus its Cursor-metered total via the cookie-authenticated
    /// dashboard API, reusing the same session resolution as the Cursor status probe. Like Codex and
    /// Claude, the report covers the rolling `historyDays` window and the session line is tied to the
    /// current local day (so a stale latest entry is never labeled as Today).
    private static func loadCursorTokenSnapshot(
        now: Date,
        since: Date?,
        historyDays: Int,
        calendar: Calendar,
        cookieHeaderOverride: String? = nil) async throws -> CostUsageTokenSnapshot
    {
        let probe = CursorStatusProbe(browserDetection: BrowserDetection())
        let report = try await probe.fetchCostReport(
            since: since,
            until: now,
            calendar: calendar,
            cookieHeaderOverride: cookieHeaderOverride)
        return Self.tokenSnapshot(
            from: report.daily,
            now: now,
            historyDays: historyDays,
            useCurrentLocalDayForSession: true,
            calendar: calendar,
            meteredCostUSD: report.meteredCostUSD,
            costProvenance: Self.cursorCostProvenance(
                meteredCostUSD: report.meteredCostUSD,
                daily: report.daily.data),
            credentialScopeFingerprint: report.credentialScopeFingerprint)
    }
    #endif

    static func loadCursorLocalSnapshot(
        now: Date,
        historyDays: Int,
        calendar: Calendar = .current,
        paths overridePaths: [URL]? = nil) async -> CostUsageTokenSnapshot?
    {
        let paths = overridePaths ?? CursorLocalCSVReader.cachedCSVPaths()
        guard !paths.isEmpty else { return nil }
        var allRows: [CursorLocalCSVReader.Row] = []
        for url in paths {
            allRows.append(contentsOf: CursorLocalCSVReader.parseFile(at: url, calendar: calendar))
        }
        guard !allRows.isEmpty else { return nil }
        let full = CursorLocalCSVReader.makeDailyReport(from: allRows, calendar: calendar, now: now)
        let since = calendar.date(
            byAdding: .day,
            value: -(historyDays - 1),
            to: calendar.startOfDay(for: now)) ?? now
        let sinceKey = CostUsageLocalDay.key(from: since, calendar: calendar)
        let nowKey = CostUsageLocalDay.key(from: now, calendar: calendar)
        let filtered = full.data.filter { $0.date >= sinceKey && $0.date <= nowKey }
        guard !filtered.isEmpty else { return nil }
        let costValues = filtered.compactMap(\.costUSD)
        let totalCost: Double? = costValues.isEmpty ? nil : costValues.reduce(0, +)
        var sum = 0
        var overflowed = false
        for t in filtered.compactMap(\.totalTokens) {
            let (res, of) = sum.addingReportingOverflow(t)
            if of {
                overflowed = true
                break
            }
            sum = res
        }
        let totalTokens: Int? = overflowed ? nil : sum
        let filteredSummary: CostUsageDailyReport.Summary = .init(
            totalInputTokens: nil,
            totalOutputTokens: nil,
            totalTokens: totalTokens,
            totalCostUSD: totalCost)
        let daily = CostUsageDailyReport(data: filtered, summary: filteredSummary)
        return Self.tokenSnapshot(
            from: daily,
            now: now,
            historyDays: historyDays,
            useCurrentLocalDayForSession: true,
            calendar: calendar,
            costProvenance: .listPriceEstimate,
            ownership: .machineLocalUnowned)
    }

    private static func loadAntigravityLocalSnapshot(
        context: AntigravityLocalReader.Context,
        now: Date,
        historyDays: Int,
        calendar: Calendar = .current,
        pricingCacheRoot: URL?) async throws -> CostUsageTokenSnapshot?
    {
        let cal = calendar
        let reportResult = try await CostUsageScanExecutor.run { checkCancellation in
            try AntigravityLocalReader.makeDailyReportWithStatus(
                context: context,
                calendar: cal,
                estimateCost: true,
                pricingCacheRoot: pricingCacheRoot,
                checkCancellation: checkCancellation)
        }
        // A scan can be partial when an old Antigravity database has a missing WAL sidecar or the
        // safety budget stops early. Those rows are a trustworthy subset, so keep them as a marked
        // lower bound. Contradicted evidence is different in kind — the surviving rows may be
        // wrong, not merely incomplete — and stays unpublishable. The same applies to an
        // immutable SQLite read whose underlying files changed during the read.
        guard reportResult.isAvailable
            || (!reportResult.report.data.isEmpty && !reportResult.evidenceIsContradicted
                && !reportResult.evidenceIsUnstable)
        else { return nil }
        let report = reportResult.report
        if report.data.isEmpty {
            guard reportResult.isComplete else { return nil }
            return Self.tokenSnapshot(
                from: CostUsageDailyReport(data: [], summary: nil),
                now: now,
                historyDays: historyDays,
                useCurrentLocalDayForSession: true,
                calendar: cal,
                historyCoverageIsEstablished: true,
                costProvenance: .unknown,
                ownership: .machineLocalUnowned)
        }
        let since = cal.date(byAdding: .day, value: -(historyDays - 1), to: cal.startOfDay(for: now)) ?? now
        let sinceKey = CostUsageLocalDay.key(from: since, calendar: cal)
        let nowKey = CostUsageLocalDay.key(from: now, calendar: cal)
        let filtered = report.data.filter { $0.date >= sinceKey && $0.date <= nowKey }
        let costValues = filtered.compactMap(\.costUSD)
        let totalCost: Double? = costValues.isEmpty ? nil : costValues.reduce(0, +)
        var sum = 0
        var overflowed = false
        for t in filtered.compactMap(\.totalTokens) {
            let (res, of) = sum.addingReportingOverflow(t)
            if of {
                overflowed = true
                break
            }
            sum = res
        }
        let totalTokens: Int? = overflowed ? nil : sum
        let filteredSummary: CostUsageDailyReport.Summary? = filtered.isEmpty ? nil : .init(
            totalInputTokens: nil,
            totalOutputTokens: nil,
            totalTokens: totalTokens,
            totalCostUSD: totalCost)
        let daily = CostUsageDailyReport(data: filtered, summary: filteredSummary)
        return Self.tokenSnapshot(
            from: daily,
            now: now,
            historyDays: historyDays,
            useCurrentLocalDayForSession: true,
            calendar: cal,
            // A truncated scan must not claim the window: absence of a row is not proof of a zero
            // day. `historyScanIsPartial` keeps the rows it did read usable as a marked lower
            // bound, which is what separates "read part of it" from "could not read it".
            historyCoverageIsEstablished: reportResult.isComplete,
            historyScanIsPartial: !reportResult.isComplete,
            costProvenance: totalCost == nil ? .unknown : .listPriceEstimate,
            ownership: .machineLocalUnowned)
    }

    static func tokenSnapshot(
        from daily: CostUsageDailyReport,
        now: Date,
        historyDays: Int = 30,
        currencyCode: String = "USD",
        useCurrentLocalDayForSession: Bool = true,
        calendar: Calendar = .current,
        historyCoverageIsEstablished: Bool = true,
        historyScanIsPartial: Bool = false,
        historySinceDayKey: String? = nil,
        historyUntilDayKey: String? = nil,
        monetaryValuesAreAvailable: Bool = true,
        meteredCostUSD: Double? = nil,
        costProvenance: CostProvenance = .unknown,
        credentialScopeFingerprint: String? = nil,
        ownership: CostUsageTokenOwnership = .accountScoped,
        historyLabel: String? = nil,
        projects: [CostUsageProjectBreakdown] = [],
        sessions: [CostUsageSessionBreakdown] = [],
        updatedAt: Date? = nil) -> CostUsageTokenSnapshot
    {
        let sessionEntry = useCurrentLocalDayForSession
            ? CostUsageTokenSnapshot.entry(in: daily.data, forLocalDayContaining: now, calendar: calendar)
            : CostUsageTokenSnapshot.latestEntry(in: daily.data)
        let hasHistoricalRows = !daily.data.isEmpty
        let establishedEmptyHistory = historyCoverageIsEstablished && !historyScanIsPartial && daily.data.isEmpty
        let sessionTokens: Int? = if let sessionEntry {
            sessionEntry.totalTokens
        } else if hasHistoricalRows, historyCoverageIsEstablished {
            0
        } else if establishedEmptyHistory {
            0
        } else {
            nil
        }
        let sessionCostUSD: Double? = if !monetaryValuesAreAvailable {
            nil
        } else if let sessionEntry {
            sessionEntry.costUSD
        } else if hasHistoricalRows, historyCoverageIsEstablished {
            0
        } else if establishedEmptyHistory {
            0
        } else {
            nil
        }
        // Prefer summary totals when present; fall back to summing daily entries. A non-empty
        // row set where every row carries an explicit value is a known total even when it sums
        // to zero; keep nil only for genuinely missing values.
        let totalFromSummary = daily.summary?.totalCostUSD
        let totalFromEntries = daily.data.compactMap(\.costUSD).reduce(0, +)
        let allEntriesCarryCost = !daily.data.isEmpty && daily.data.allSatisfy {
            $0.costUSD != nil && ($0.unpricedRequestCount ?? 0) == 0
        }
        // A bounded Codex refresh may expose an explicitly partial projection. Keep its compact
        // subtotal useful when every materialized day is priced, while the coverage flag above
        // tells consumers that the subtotal is not an established window total. Never let a
        // known subset beside an unpriced day masquerade as a complete cost.
        let last30DaysCostUSD: Double? = if !monetaryValuesAreAvailable {
            nil
        } else if allEntriesCarryCost {
            totalFromSummary ?? totalFromEntries
        } else if establishedEmptyHistory {
            0
        } else {
            nil
        }
        let totalTokensFromSummary = daily.summary?.totalTokens
        let totalTokensFromEntries: Int? = {
            var sum = 0
            for t in daily.data.compactMap(\.totalTokens) {
                let (res, overflow) = sum.addingReportingOverflow(t)
                if overflow {
                    return nil
                }
                sum = res
            }
            return sum
        }()
        let allEntriesCarryTokens = !daily.data.isEmpty && daily.data.allSatisfy { $0.totalTokens != nil }
        let last30DaysTokens = totalTokensFromSummary
            ?? (allEntriesCarryTokens
                ? totalTokensFromEntries
                : establishedEmptyHistory ? 0 : nil)

        return CostUsageTokenSnapshot(
            sessionTokens: sessionTokens,
            sessionCostUSD: sessionCostUSD,
            sessionRequests: sessionEntry?.requestCount,
            last30DaysTokens: last30DaysTokens,
            last30DaysCostUSD: last30DaysCostUSD,
            last30DaysRequests: (establishedEmptyHistory || !daily.data.isEmpty)
                && daily.data.allSatisfy { $0.requestCount != nil }
                ? CheckedSum.integers(daily.data.compactMap(\.requestCount)) : nil,
            currencyCode: currencyCode,
            historyDays: historyDays,
            historyCoverageIsEstablished: historyCoverageIsEstablished,
            historyScanIsPartial: historyScanIsPartial,
            historySinceDayKey: historySinceDayKey,
            historyUntilDayKey: historyUntilDayKey,
            historyLabel: historyLabel,
            meteredCostUSD: monetaryValuesAreAvailable ? meteredCostUSD : nil,
            costProvenance: costProvenance,
            credentialScopeFingerprint: credentialScopeFingerprint,
            ownership: ownership,
            daily: daily.data,
            projects: projects,
            sessions: sessions,
            hourly: daily.hourly,
            quotaSlices: daily.quotaSlices,
            updatedAt: updatedAt ?? now)
    }

    package static func resolvedCodexScanDurationPerRefresh(
        provider: UsageProvider,
        bypassScannerDebounce: Bool,
        configuredDuration: TimeInterval?) -> TimeInterval?
    {
        // Provider-specific by design: only Codex refresh uses a bounded initial scan before background catch-up.
        guard provider == .codex,
              bypassScannerDebounce,
              configuredDuration == nil
        else { return configuredDuration }

        // UsageStore refreshes set bypassScannerDebounce. Bound that first app scan too,
        // so it can publish scan progress and hand remaining work to the persistent
        // catch-up loop instead of consuming the whole 512 MiB byte budget continuously.
        // When a prior complete report exists, the scanner keeps that report visible until
        // catch-up converges rather than exposing a partially rebuilt cost history.
        return self.codexAutomaticScanDurationPerRefresh
    }

    private static func cursorCostProvenance(
        meteredCostUSD: Double?,
        daily: [CostUsageDailyReport.Entry]) -> CostProvenance
    {
        let hasDailyCosts = daily.contains { $0.costUSD != nil }
        if meteredCostUSD != nil, hasDailyCosts {
            return .mixed
        }
        if meteredCostUSD != nil {
            return .vendorMetered
        }
        if hasDailyCosts {
            return .listPriceEstimate
        }
        return .unknown
    }

    private static func configureScannerRefresh(
        _ options: inout CostUsageScanner.Options,
        provider: UsageProvider,
        allowVertexClaudeFallback: Bool,
        forceRefresh: Bool,
        bypassScannerDebounce: Bool)
    {
        if provider == .vertexai {
            options.claudeLogProviderFilter = allowVertexClaudeFallback ? .all : .vertexAIOnly
        } else if provider == .claude {
            options.claudeLogProviderFilter = .excludeVertexAI
        }
        if forceRefresh || bypassScannerDebounce {
            options.refreshMinIntervalSeconds = 0
        }
        options.maxCodexScanDurationPerRefresh = self.resolvedCodexScanDurationPerRefresh(
            provider: provider,
            bypassScannerDebounce: bypassScannerDebounce,
            configuredDuration: options.maxCodexScanDurationPerRefresh)
    }

    private static func unknownProjectBreakdown(from daily: CostUsageDailyReport) -> CostUsageProjectBreakdown? {
        guard !daily.data.isEmpty else { return nil }
        return CostUsageProjectBreakdown(
            name: CostUsageProjectBreakdown.unknownProjectName,
            path: nil,
            totalTokens: daily.summary?.totalTokens,
            totalCostUSD: daily.summary?.totalCostUSD,
            daily: daily.data,
            modelBreakdowns: self.projectModelBreakdowns(from: daily.data),
            sources: [
                CostUsageProjectSourceBreakdown(
                    name: CostUsageProjectBreakdown.unknownProjectName,
                    path: nil,
                    totalTokens: daily.summary?.totalTokens,
                    totalCostUSD: daily.summary?.totalCostUSD,
                    daily: daily.data,
                    modelBreakdowns: self.projectModelBreakdowns(from: daily.data)),
            ])
    }

    private static func mergedProjectBreakdowns(
        _ projects: [CostUsageProjectBreakdown]) -> [CostUsageProjectBreakdown]
    {
        var dailyByPath: [String: [CostUsageDailyReport]] = [:]
        var namesByPath: [String: String] = [:]
        var sourceDailyByProjectPath: [String: [String: [CostUsageDailyReport]]] = [:]
        var sourceNamesByProjectPath: [String: [String: String]] = [:]
        for project in projects {
            let key = project.path ?? ""
            namesByPath[key] = project.name
            dailyByPath[key, default: []].append(CostUsageDailyReport(data: project.daily, summary: nil))
            let sources = project.sources.isEmpty
                ? [
                    CostUsageProjectSourceBreakdown(
                        name: project.name,
                        path: project.path,
                        totalTokens: project.totalTokens,
                        totalCostUSD: project.totalCostUSD,
                        daily: project.daily,
                        modelBreakdowns: project.modelBreakdowns),
                ]
                : project.sources
            for source in sources {
                let sourceKey = source.path ?? ""
                sourceNamesByProjectPath[key, default: [:]][sourceKey] = source.name
                sourceDailyByProjectPath[key, default: [:]][sourceKey, default: []]
                    .append(CostUsageDailyReport(data: source.daily, summary: nil))
            }
        }
        return dailyByPath.map { key, reports in
            let merged = CostUsageDailyReport.merged(reports)
            return CostUsageProjectBreakdown(
                name: namesByPath[key] ?? CostUsageProjectBreakdown.unknownProjectName,
                path: key.isEmpty ? nil : key,
                totalTokens: merged.summary?.totalTokens,
                totalCostUSD: merged.summary?.totalCostUSD,
                daily: merged.data,
                modelBreakdowns: Self.projectModelBreakdowns(from: merged.data),
                sources: Self.mergedProjectSources(
                    sourceDailyByPath: sourceDailyByProjectPath[key] ?? [:],
                    sourceNamesByPath: sourceNamesByProjectPath[key] ?? [:]))
        }
        .sorted { lhs, rhs in
            let lhsCost = lhs.totalCostUSD ?? -1
            let rhsCost = rhs.totalCostUSD ?? -1
            if lhsCost != rhsCost {
                return lhsCost > rhsCost
            }
            let lhsTokens = lhs.totalTokens ?? -1
            let rhsTokens = rhs.totalTokens ?? -1
            if lhsTokens != rhsTokens {
                return lhsTokens > rhsTokens
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func mergedProjectSources(
        sourceDailyByPath: [String: [CostUsageDailyReport]],
        sourceNamesByPath: [String: String]) -> [CostUsageProjectSourceBreakdown]
    {
        sourceDailyByPath.map { key, reports in
            let merged = CostUsageDailyReport.merged(reports)
            return CostUsageProjectSourceBreakdown(
                name: sourceNamesByPath[key] ?? CostUsageProjectBreakdown.unknownProjectName,
                path: key.isEmpty ? nil : key,
                totalTokens: merged.summary?.totalTokens,
                totalCostUSD: merged.summary?.totalCostUSD,
                daily: merged.data,
                modelBreakdowns: Self.projectModelBreakdowns(from: merged.data))
        }
        .sorted { lhs, rhs in
            let lhsCost = lhs.totalCostUSD ?? -1
            let rhsCost = rhs.totalCostUSD ?? -1
            if lhsCost != rhsCost {
                return lhsCost > rhsCost
            }
            let lhsTokens = lhs.totalTokens ?? -1
            let rhsTokens = rhs.totalTokens ?? -1
            if lhsTokens != rhsTokens {
                return lhsTokens > rhsTokens
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func projectModelBreakdowns(
        from entries: [CostUsageDailyReport.Entry]) -> [CostUsageDailyReport.ModelBreakdown]?
    {
        let summaries = CostUsageDailyReport.modelCostSummaries(from: entries)
        guard !summaries.isEmpty else { return nil }
        return summaries.sorted { lhs, rhs in
            let lhsCost = lhs.costUSD ?? -1
            let rhsCost = rhs.costUSD ?? -1
            if lhsCost != rhsCost {
                return lhsCost > rhsCost
            }
            let lhsTokens = lhs.totalTokens ?? -1
            let rhsTokens = rhs.totalTokens ?? -1
            if lhsTokens != rhsTokens {
                return lhsTokens > rhsTokens
            }
            return lhs.modelName > rhs.modelName
        }
    }

    static func selectCurrentSession(from sessions: [CostUsageSessionReport.Entry])
        -> CostUsageSessionReport.Entry?
    {
        if sessions.isEmpty {
            return nil
        }
        return sessions.max { lhs, rhs in
            let lDate = CostUsageDateParser.parse(lhs.lastActivity) ?? .distantPast
            let rDate = CostUsageDateParser.parse(rhs.lastActivity) ?? .distantPast
            if lDate != rDate {
                return lDate < rDate
            }
            let lCost = lhs.costUSD ?? -1
            let rCost = rhs.costUSD ?? -1
            if lCost != rCost {
                return lCost < rCost
            }
            let lTokens = lhs.totalTokens ?? -1
            let rTokens = rhs.totalTokens ?? -1
            if lTokens != rTokens {
                return lTokens < rTokens
            }
            return lhs.session < rhs.session
        }
    }

    static func selectMostRecentMonth(from months: [CostUsageMonthlyReport.Entry])
        -> CostUsageMonthlyReport.Entry?
    {
        if months.isEmpty {
            return nil
        }
        return months.max { lhs, rhs in
            let lDate = CostUsageDateParser.parseMonth(lhs.month) ?? .distantPast
            let rDate = CostUsageDateParser.parseMonth(rhs.month) ?? .distantPast
            if lDate != rDate {
                return lDate < rDate
            }
            let lCost = lhs.costUSD ?? -1
            let rCost = rhs.costUSD ?? -1
            if lCost != rCost {
                return lCost < rCost
            }
            let lTokens = lhs.totalTokens ?? -1
            let rTokens = rhs.totalTokens ?? -1
            if lTokens != rTokens {
                return lTokens < rTokens
            }
            return lhs.month < rhs.month
        }
    }
}

// swiftlint:enable file_length
