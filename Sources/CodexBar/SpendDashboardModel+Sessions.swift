import CodexBarCore
import Foundation

/// Session row projection keeps native inspection metadata scoped to the dashboard's source window.
extension SpendDashboardModel {
    static func sessionRows(
        summaries: [InputSummary],
        bounds: ClosedRange<Date>,
        calendar: Calendar,
        selectedDay: Date? = nil) -> [SessionRow]
    {
        let rows = summaries.flatMap { summary -> [SessionRow] in
            let reportingRange = SessionUsagePresentation.toolActivityRange(
                snapshot: summary.input.snapshot, calendar: calendar)
            return summary.input.snapshot.sessions.compactMap { session -> SessionRow? in
                let day = calendar.startOfDay(for: session.lastActivity)
                // Provider-specific by design: only the native Codex ledger has validated turn timing.
                let nativeSamples = summary.input.provider == .codex && summary.input.sourceKind == .native
                    ? session.turnPerformanceSamples : []
                let performanceSamples = nativeSamples.filter {
                    let completionDay = calendar.startOfDay(for: $0.completedAt)
                    return bounds.contains(completionDay) &&
                        (selectedDay == nil || completionDay == selectedDay)
                }
                guard bounds.contains(day) || !performanceSamples.isEmpty else { return nil }
                let modelName = session.modelBreakdowns.max {
                    ($0.totalTokens ?? 0) < ($1.totalTokens ?? 0)
                }?.modelName
                return SessionRow(
                    id: "\(summary.input.id):\(session.sessionID)",
                    rank: 0,
                    sessionID: session.sessionID,
                    sourceID: summary.input.id,
                    provider: summary.input.provider,
                    title: session.title,
                    projectName: session.projectName,
                    projectPath: session.projectPath,
                    lastActivity: session.lastActivity,
                    totalTokens: session.totalTokens,
                    totalCost: session.costUSD.map { $0 * summary.costMultiplier },
                    modelName: modelName,
                    turnPerformance: CostUsageTurnPerformanceSummary(samples: performanceSamples),
                    // Provider-specific by design: Only native Codex logs supply owned item_completed tool records.
                    toolActivitySource: summary.input.provider == .codex && summary.input.sourceKind == .native
                        ? session.toolActivitySource : nil,
                    usage: session.withInspectionMetadata(
                        toolActivitySource: summary.input.provider == .codex && summary.input.sourceKind == .native
                            ? session.toolActivitySource : nil,
                        turnPerformanceSamples: nativeSamples),
                    sourceName: summary.input.displayName,
                    costMultiplier: summary.costMultiplier,
                    reportingRange: reportingRange,
                    reportingPeriod: summary.input.snapshot.reportingPeriod)
            }
        }
        .sorted(by: Self.sessionOrder)
        return rows.enumerated().map { rank, row in
            var ranked = row
            ranked.rank = rank + 1
            return ranked
        }
    }

    private static func sessionOrder(_ lhs: SessionRow, _ rhs: SessionRow) -> Bool {
        switch (lhs.totalCost, rhs.totalCost) {
        case let (left?, right?) where left != right: return left > right
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        switch (lhs.totalTokens, rhs.totalTokens) {
        case let (left?, right?) where left != right: return left > right
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if lhs.lastActivity != rhs.lastActivity { return lhs.lastActivity > rhs.lastActivity }
        return lhs.id < rhs.id
    }
}
