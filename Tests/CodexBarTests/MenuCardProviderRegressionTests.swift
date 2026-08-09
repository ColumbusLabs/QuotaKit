import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

struct MenuCardProviderRegressionTests {
    @Test
    func `menu card keeps positive sub percent usage visible`() {
        let metric = UsageMenuCardView.Model.Metric(
            id: "sub-percent",
            title: "Monthly",
            percent: 0.1,
            percentStyle: .used,
            resetText: nil,
            detailText: nil,
            detailLeftText: nil,
            detailRightText: nil,
            pacePercent: nil,
            paceOnTop: false)

        #expect(metric.percentLabel == "<1% used")
    }

    @Test
    func `cursor progress color stays visible while descriptor brand stays black`() {
        #expect(UsageMenuCardView.Model.progressColor(for: .cursor) == Color(nsColor: .labelColor))
    }
}
