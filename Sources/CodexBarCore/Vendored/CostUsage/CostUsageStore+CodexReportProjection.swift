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
        let cache = Self.codexManifestCache(from: snapshot)
        // Released producers included marked authoritative dollars in aggregates. Keep their
        // exact totals and token evidence, but withhold partial estimates until committed rows
        // have been rebuilt by this producer. A staged replacement retains its prior revision.
        let fileAggregates = snapshot.fileDayAggregates.map { item in
            var item = item
            if item.aggregate.unpricedRequestCount > 0,
               cache.files[item.path]?.hasCurrentCodexParser != true
            {
                item.aggregate.partialPricingIsSafe = false
            }
            return item
        }
        var currentByDay: [String: [String: CostUsageStoreDayAggregate]] = [:]
        for item in fileAggregates {
            var aggregate = currentByDay[item.aggregate.day]?[item.aggregate.model]
                ?? .zero(day: item.aggregate.day, model: item.aggregate.model)
            aggregate.add(item.aggregate)
            currentByDay[item.aggregate.day, default: [:]][item.aggregate.model] = aggregate
        }
        let verifiedAggregates = snapshot.verifiedDayAggregates.map { aggregate in
            var aggregate = aggregate
            if aggregate.unpricedRequestCount > 0,
               currentByDay[aggregate.day]?[aggregate.model] != aggregate
            {
                // A saved subtotal is safe only when the current committed producer proves
                // precisely the same request, token, marker, and monetary aggregate.
                aggregate.partialPricingIsSafe = false
            }
            return aggregate
        }
        return CostUsageStoreCodexReportProjection(
            cache: cache,
            fileDayAggregates: fileAggregates,
            verifiedDayAggregates: verifiedAggregates,
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
