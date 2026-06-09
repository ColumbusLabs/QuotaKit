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

    var id: String { self.rawValue }

    var requiresPro: Bool { true }

    var title: String {
        switch self {
        case .unlimitedProviders: String(localized: "Unlimited providers")
        case .homeScreenWidgets: String(localized: "Home Screen widgets")
        case .lockScreenWidgets: String(localized: "Lock Screen widgets")
        case .notifications: String(localized: "Quota notifications")
        case .fullCostDashboard: String(localized: "Full cost dashboard")
        case .usageHistory: String(localized: "Usage history charts")
        case .shareCards: String(localized: "Share cards")
        case .advancedMergeViews: String(localized: "Advanced merge views")
        }
    }
}
