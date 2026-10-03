import Foundation

/// Compact report input read from one WAL snapshot. It excludes token and usage ledgers.
struct CostUsageStoreCodexReportProjection: Sendable {
    var cache: CostUsageCache
    var fileDayAggregates: [CostUsageStoreFileDayAggregate]
    /// Aggregates copied only after a complete scan. Unlike `fileDayAggregates`, these rows
    /// remain stable while a bounded catch-up replaces individual files.
    var verifiedDayAggregates: [CostUsageStoreDayAggregate] = []
    var verifiedDayKeys: [String] = []
    var verifiedDayEvidence: [String: CostUsageDayEvidence] = [:]
    var fileTemporalAggregates: [CostUsageStoreTemporalAggregate] = []
    var verifiedTemporalAggregates: [CostUsageStoreTemporalAggregate] = []
    var fileTemporalCoverageIsComplete: Bool = false
    var verifiedTemporalCoverageIsComplete: Bool = false
    var verifiedScanSinceKey: String?
    var verifiedScanUntilKey: String?
    var verifiedUpdatedAtUnixMs: Int64?
    var verifiedTimeZoneIdentifier: String?
    var verifiedRootPaths: [String]?
}

extension CostUsageStore {
    func readCodexReportProjection(
        calendar: Calendar,
        temporalRange: (sinceDay: String, untilDay: String)? = nil,
        loadTemporal: Bool = true) -> CostUsageStoreCodexReportProjection
    {
        let snapshot = self.readCodexWorkingSetSnapshot(
            hydratingPaths: [],
            loadTemporal: loadTemporal,
            temporalRange: temporalRange)
        guard snapshot.metadata.timeZoneIdentifier == nil
            || snapshot.metadata.timeZoneIdentifier == calendar.timeZone.identifier
        else {
            return CostUsageStoreCodexReportProjection(cache: CostUsageCache(), fileDayAggregates: [])
        }
        return CostUsageStoreCodexReportProjection(
            cache: Self.codexManifestCache(from: snapshot),
            fileDayAggregates: snapshot.fileDayAggregates,
            verifiedDayAggregates: snapshot.verifiedDayAggregates,
            verifiedDayKeys: snapshot.verifiedDayKeys,
            verifiedDayEvidence: snapshot.verifiedDayEvidence,
            fileTemporalAggregates: snapshot.fileTemporalAggregates,
            verifiedTemporalAggregates: snapshot.verifiedTemporalAggregates,
            fileTemporalCoverageIsComplete: snapshot.fileTemporalCoverageIsComplete,
            verifiedTemporalCoverageIsComplete: snapshot.verifiedTemporalCoverageIsComplete,
            verifiedScanSinceKey: snapshot.metadata.verifiedScanSinceDay,
            verifiedScanUntilKey: snapshot.metadata.verifiedScanUntilDay,
            verifiedUpdatedAtUnixMs: snapshot.metadata.verifiedUpdatedAtUnixMs,
            verifiedTimeZoneIdentifier: snapshot.metadata.verifiedTimeZoneIdentifier,
            verifiedRootPaths: snapshot.metadata.verifiedRootPaths)
    }
}

extension CostUsageStoreAccess {
    static func readCodexReportProjection(
        store: CostUsageStore,
        calendar: Calendar,
        temporalRange: (sinceDay: String, untilDay: String)? = nil,
        loadTemporal: Bool = true) -> CostUsageStoreCodexReportProjection
    {
        store.syncReadCodexReportProjection(
            calendar: calendar,
            temporalRange: temporalRange,
            loadTemporal: loadTemporal)
    }

    static func readCodexReportProjection(
        cacheRoot: URL?,
        calendar: Calendar,
        temporalRange: (sinceDay: String, untilDay: String)? = nil,
        loadTemporal: Bool = true) async -> CostUsageStoreCodexReportProjection
    {
        await CostUsageStore(cacheRoot: cacheRoot).readCodexReportProjection(
            calendar: calendar,
            temporalRange: temporalRange,
            loadTemporal: loadTemporal)
    }
}
