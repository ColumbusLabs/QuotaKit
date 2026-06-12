import CodexBarSync
import Foundation

enum QuotaKitWidgetDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case both
    case session
    case weekly

    var id: String {
        self.rawValue
    }

    var localizedTitle: String {
        switch self {
        case .both:
            String(localized: "Both")
        case .session:
            String(localized: "Session")
        case .weekly:
            String(localized: "Weekly")
        }
    }
}

enum QuotaKitWidgetDisplayModeStore {
    static let key = "com.columbuslabs.quotakit.widgets.displayMode"

    static func appGroupDefaults(
        appGroupIdentifier: String = ProductConfig.appGroupIdentifier) -> UserDefaults?
    {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func load(
        defaults: UserDefaults? = nil,
        appGroupDefaults: () -> UserDefaults? = { Self.appGroupDefaults() }) -> QuotaKitWidgetDisplayMode
    {
        guard let storage = defaults ?? appGroupDefaults() else {
            return .both
        }
        guard let rawValue = storage.string(forKey: Self.key),
              let mode = QuotaKitWidgetDisplayMode(rawValue: rawValue)
        else {
            return .both
        }
        return mode
    }

    static func save(
        _ mode: QuotaKitWidgetDisplayMode,
        defaults: UserDefaults? = nil,
        appGroupDefaults: () -> UserDefaults? = { Self.appGroupDefaults() })
    {
        guard let storage = defaults ?? appGroupDefaults() else {
            return
        }
        storage.set(mode.rawValue, forKey: Self.key)
    }
}

enum QuotaKitWidgetEntryDisplayModeResolver {
    static func resolve(
        isPreview: Bool,
        defaults: UserDefaults? = nil,
        appGroupDefaults: () -> UserDefaults? = { QuotaKitWidgetDisplayModeStore.appGroupDefaults() })
        -> QuotaKitWidgetDisplayMode
    {
        isPreview
            ? .both
            : QuotaKitWidgetDisplayModeStore.load(
                defaults: defaults,
                appGroupDefaults: appGroupDefaults)
    }
}
