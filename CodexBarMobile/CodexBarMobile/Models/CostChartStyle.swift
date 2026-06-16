import Foundation

enum CostChartStyle: String, CaseIterable, Identifiable {
    case bars
    case line

    var id: String {
        self.rawValue
    }

    var title: String {
        switch self {
        case .bars:
            String(localized: "Bar Chart")
        case .line:
            String(localized: "Line Chart")
        }
    }
}
