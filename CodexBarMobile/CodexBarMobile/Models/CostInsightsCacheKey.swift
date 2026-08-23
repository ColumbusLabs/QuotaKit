import Foundation

enum CostInsightsCacheKey {
    static func make(
        isDemoMode: Bool,
        snapshotKey: SnapshotIdentityKey?,
        cwlEnabled: Bool,
        cwlWindowDays: Int,
        todayKey: String,
        freshnessRevision: Int = 0) -> String
    {
        let snapshotPart = if isDemoMode {
            "demo"
        } else if let snapshotKey {
            "\(snapshotKey.providerIDs)@\(snapshotKey.lastUpdated.timeIntervalSince1970)" +
                "#\(snapshotKey.costRevisionKey)"
        } else {
            "none"
        }
        let sourcePart = (cwlEnabled && !isDemoMode) ? "cwl\(cwlWindowDays)" : "blob"
        return "\(snapshotPart)|\(sourcePart)|\(todayKey)|freshness:\(freshnessRevision)"
    }
}
