import Foundation

/// Compact report input read from one WAL snapshot. It excludes token and usage ledgers.
struct CostUsageStoreCodexReportProjection: Sendable {
    var cache: CostUsageCache
    var fileDayAggregates: [CostUsageStoreFileDayAggregate]
    /// Aggregates copied only after a complete scan. Unlike `fileDayAggregates`, these rows
    /// remain stable while a bounded catch-up replaces individual files.
    var verifiedDayAggregates: [CostUsageStoreDayAggregate] = []
    var verifiedScanSinceKey: String?
    var verifiedScanUntilKey: String?
    var verifiedUpdatedAtUnixMs: Int64?
    var verifiedTimeZoneIdentifier: String?
    var verifiedRootPaths: [String]?
}

extension CostUsageStore {
    func readCodexReportProjection(calendar: Calendar) -> CostUsageStoreCodexReportProjection {
        let snapshot = self.readCodexWorkingSetSnapshot(hydratingPaths: [])
        guard snapshot.metadata.timeZoneIdentifier == nil
            || snapshot.metadata.timeZoneIdentifier == calendar.timeZone.identifier
        else {
            return CostUsageStoreCodexReportProjection(cache: CostUsageCache(), fileDayAggregates: [])
        }
        return CostUsageStoreCodexReportProjection(
            cache: Self.codexManifestCache(from: snapshot),
            fileDayAggregates: snapshot.fileDayAggregates,
            verifiedDayAggregates: snapshot.verifiedDayAggregates,
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
        calendar: Calendar) -> CostUsageStoreCodexReportProjection
    {
        store.syncReadCodexReportProjection(calendar: calendar)
    }

    static func readCodexReportProjection(
        cacheRoot: URL?,
        calendar: Calendar) async -> CostUsageStoreCodexReportProjection
    {
        await CostUsageStore(cacheRoot: cacheRoot).readCodexReportProjection(calendar: calendar)
    }
}
