import Foundation

enum FeatureGate: String, CaseIterable, Identifiable, Sendable {
    case unlimitedProviders
    case homeScreenWidgets
    case lockScreenWidgets
    case notifications
    case fullCostDashboard
    case usageHistory
    case shareCards
    case advancedMergeViews
    case exports

    var id: String { self.rawValue }

    var requiresPro: Bool { true }

    var title: String {
        switch self {
        case .unlimitedProviders: "Unlimited provider cards"
        case .homeScreenWidgets: "Home Screen widgets"
        case .lockScreenWidgets: "Lock Screen widgets"
        case .notifications: "Quota notifications"
        case .fullCostDashboard: "Full cost dashboard"
        case .usageHistory: "Usage history charts"
        case .shareCards: "Share cards"
        case .advancedMergeViews: "Advanced merge views"
        case .exports: "Export features"
        }
    }
}
