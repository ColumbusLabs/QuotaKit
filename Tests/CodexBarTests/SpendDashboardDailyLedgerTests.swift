import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct SpendDashboardDailyLedgerTests {
    @Test
    func `missing source request counts mark only the request subtotal as a lower bound`() {
        let day = SpendDashboardModel.DailySummary(
            day: Date(timeIntervalSince1970: 0),
            providers: [
                .init(
                    sourceID: "counted",
                    provider: .claude,
                    displayName: "Claude",
                    totalTokens: 300,
                    requestCount: 2,
                    totalCost: 1),
                .init(
                    sourceID: "uncounted",
                    provider: .codex,
                    displayName: "Codex",
                    totalTokens: 500,
                    requestCount: nil,
                    totalCost: 1),
            ],
            totalTokens: 800,
            requestCount: 2,
            totalCost: 2)

        #expect(day.requestsAreLowerBound)
        #expect(!day.hasPartialCounts)
        #expect(spendDashboardLedgerTokenText(day) == UsageFormatter.tokenCountString(800))
        #expect(spendDashboardLedgerRequestText(day).hasPrefix("≥"))
        #expect(spendDashboardLedgerRequestText(day).contains("2"))
    }

    @Test
    func `partial scan count marks both known totals as lower bounds`() {
        let day = SpendDashboardModel.DailySummary(
            day: Date(timeIntervalSince1970: 0),
            providers: [
                .init(
                    countsAreLowerBound: true,
                    sourceID: "partial",
                    provider: .codex,
                    displayName: "Codex",
                    totalTokens: 500,
                    requestCount: 2,
                    totalCost: 1),
            ],
            totalTokens: 500,
            requestCount: 2,
            totalCost: 1)

        #expect(spendDashboardLedgerTokenText(day).hasPrefix("≥"))
        #expect(spendDashboardLedgerRequestText(day).hasPrefix("≥"))
    }

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
