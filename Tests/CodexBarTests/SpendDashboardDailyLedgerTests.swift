import Foundation
import Testing
@testable import CodexBar

struct SpendDashboardDailyLedgerTests {
    @Test
    func `collapsed ledger shows newest thirty days and expansion preserves all days`() {
        let summaries = (0..<365).map { offset in
            SpendDashboardModel.DailySummary(
                day: Date(timeIntervalSince1970: Double(offset) * 86400),
                providers: [],
                totalTokens: nil,
                requestCount: nil,
                totalCost: nil)
        }

        let collapsed = spendDailyLedgerVisibleSummaries(
            summaries,
            showsAllRows: false,
            collapsedRowCount: SpendDailyLedger.collapsedRowCount)
        let expanded = spendDailyLedgerVisibleSummaries(
            summaries,
            showsAllRows: true,
            collapsedRowCount: SpendDailyLedger.collapsedRowCount)

        #expect(collapsed.count == 30)
        #expect(collapsed.map(\.day) == summaries.suffix(30).reversed().map(\.day))
        #expect(expanded.count == summaries.count)
        #expect(expanded.first?.day == summaries.last?.day)
        #expect(expanded.last?.day == summaries.first?.day)
    }
}
