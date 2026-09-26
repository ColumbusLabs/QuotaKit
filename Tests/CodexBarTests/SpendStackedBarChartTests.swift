import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct SpendStackedBarChartTests {
    private static func dailyPoint(
        sourceID: String,
        day: Date,
        stackStart: Double,
        stackEnd: Double) -> SpendDashboardModel.DailyPoint
    {
        SpendDashboardModel.DailyPoint(
            sourceID: sourceID,
            provider: .codex,
            providerName: sourceID,
            day: day,
            cost: stackEnd - stackStart,
            stackStart: stackStart,
            stackEnd: stackEnd)
    }

    private static func hourlyPoint(
        sourceID: String,
        hour: Date,
        stackStart: Double,
        stackEnd: Double) -> SpendDashboardModel.HourlyPoint
    {
        SpendDashboardModel.HourlyPoint(
            sourceID: sourceID,
            provider: .codex,
            providerName: sourceID,
            hour: hour,
            cost: stackEnd - stackStart,
            stackStart: stackStart,
            stackEnd: stackEnd)
    }

    @Test
    func `daily chart selects only the highest of multiple provider segments`() {
        let day = Date(timeIntervalSince1970: 0)
        let bottom = Self.dailyPoint(sourceID: "claude", day: day, stackStart: 0, stackEnd: 10)
        let middle = Self.dailyPoint(sourceID: "codex", day: day, stackStart: 10, stackEnd: 18)
        let top = Self.dailyPoint(sourceID: "cursor", day: day, stackStart: 18, stackEnd: 30)

        let topIDs = spendTopOfStackIDs(for: [bottom, middle, top], key: \.day, id: \.id, stackEnd: \.stackEnd)

        #expect(topIDs == [top.id])
    }

    @Test
    func `hourly chart selects a top segment independently for each hour`() {
        let firstHour = Date(timeIntervalSince1970: 0)
        let secondHour = Date(timeIntervalSince1970: 3600)
        let firstBottom = Self.hourlyPoint(sourceID: "claude", hour: firstHour, stackStart: 0, stackEnd: 10)
        let firstTop = Self.hourlyPoint(sourceID: "codex", hour: firstHour, stackStart: 10, stackEnd: 20)
        let secondOnly = Self.hourlyPoint(sourceID: "claude", hour: secondHour, stackStart: 0, stackEnd: 3)

        let topIDs = spendTopOfStackIDs(
            for: [firstBottom, firstTop, secondOnly],
            key: \.hour,
            id: \.id,
            stackEnd: \.stackEnd)

        #expect(topIDs == [firstTop.id, secondOnly.id])
    }

    @Test
    func `zero-height trailing segment does not replace the visible rounded top`() {
        let day = Date(timeIntervalSince1970: 0)
        let visible = Self.dailyPoint(sourceID: "claude", day: day, stackStart: 0, stackEnd: 10)
        let zeroHeight = Self.dailyPoint(sourceID: "codex", day: day, stackStart: 10, stackEnd: 10)

        let topIDs = spendTopOfStackIDs(
            for: [visible, zeroHeight],
            key: \.day,
            id: \.id,
            stackEnd: \.stackEnd)

        #expect(topIDs == [visible.id])
    }

    @Test
    func `empty points have no rounded stack tops`() {
        let topIDs = spendTopOfStackIDs(
            for: [SpendDashboardModel.DailyPoint](),
            key: \.day,
            id: \.id,
            stackEnd: \.stackEnd)

        #expect(topIDs.isEmpty)
    }
}
