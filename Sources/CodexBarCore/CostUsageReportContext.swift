/// Keeps independently filtered Claude and Vertex transcript windows from sharing cached winners.
package enum CostUsageReportContext: Sendable, Equatable {
    case regular
    case spendDashboard
}
