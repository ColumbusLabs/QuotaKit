import Foundation

/// Compact report input read from one WAL snapshot. It excludes token and usage ledgers.
struct CostUsageStoreCodexReportProjection: Sendable {
    var cache: CostUsageCache
    var fileDayAggregates: [CostUsageStoreFileDayAggregate]
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
            fileDayAggregates: snapshot.fileDayAggregates)
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
