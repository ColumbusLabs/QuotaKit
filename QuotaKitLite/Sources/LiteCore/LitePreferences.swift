import Foundation

/// How the status item looks while the menu is closed (068 §7.3).
public enum MenuBarStyle: String, CaseIterable, Sendable {
    /// A logo and a percent for each provider: the full app's brand icon with percent mode.
    case percentages
    /// One logo and percent, for whichever provider has the least left.
    case mostConstrained
    /// Each provider's logo with two hairline bars under it, session on top and weekly underneath.
    case logosAndBars

    public var displayName: String {
        switch self {
        case .percentages: "Percentages"
        case .mostConstrained: "Most Constrained"
        case .logosAndBars: "Logos and Bars"
        }
    }
}

/// How often every enabled provider is refreshed while the user is at the Mac (068 §5, amended 2026-10-12).
///
/// Activity detection alone missed Claude used from the desktop app or the cloud, which write nothing Lite can
/// watch, so a timer runs too, as in the full app (which defaults to adaptive and is set to two minutes here).
public enum RefreshInterval: Int, CaseIterable, Sendable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case fifteenMinutes = 900

    public var seconds: TimeInterval {
        TimeInterval(self.rawValue)
    }

    public var displayName: String {
        switch self {
        case .oneMinute: "Every Minute"
        case .twoMinutes: "Every 2 Minutes"
        case .fiveMinutes: "Every 5 Minutes"
        case .fifteenMinutes: "Every 15 Minutes"
        }
    }
}

/// Lite's preferences, kept in `UserDefaults` and edited only through menu toggles (068 §7.4: no settings window).
public struct LitePreferences: Sendable {
    /// Providers Lite can fetch, in display order.
    public static let availableProviders: [LiteProvider] = [.claude, .codex, .antigravity]

    private enum Key {
        static let enabledProviders = "enabledProviders"
        static let menuBarStyle = "menuBarStyle"
        static let syncToIPhone = "syncToIPhone"
        static let macAlerts = "macAlerts"
        static let iPhoneAlerts = "iPhoneAlerts"
        static let alertThresholds = "alertThresholds"
        static let refreshInterval = "refreshInterval"
    }

    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The enabled providers in display order. Never empty: an empty or unreadable value means all of them.
    public var enabledProviders: [LiteProvider] {
        get {
            let stored = Set((self.defaults.stringArray(forKey: Key.enabledProviders) ?? [])
                .compactMap(LiteProvider.init(rawValue:)))
            let enabled = Self.availableProviders.filter { stored.contains($0) }
            return enabled.isEmpty ? Self.availableProviders : enabled
        }
        nonmutating set {
            self.defaults.set(newValue.map(\.rawValue), forKey: Key.enabledProviders)
        }
    }

    public var menuBarStyle: MenuBarStyle {
        get {
            self.defaults.string(forKey: Key.menuBarStyle).flatMap(MenuBarStyle.init(rawValue:)) ?? .percentages
        }
        nonmutating set {
            self.defaults.set(newValue.rawValue, forKey: Key.menuBarStyle)
        }
    }

    /// Sync to iPhone (068 §6). Off until turned on in the menu, so nothing reaches CloudKit unasked.
    public var syncToIPhone: Bool {
        get { self.defaults.bool(forKey: Key.syncToIPhone) }
        nonmutating set { self.defaults.set(newValue, forKey: Key.syncToIPhone) }
    }

    /// Mac banners for alerts (068 §6.4). On by default.
    public var macAlerts: Bool {
        get { self.defaults.object(forKey: Key.macAlerts) as? Bool ?? true }
        nonmutating set { self.defaults.set(newValue, forKey: Key.macAlerts) }
    }

    /// iPhone push alerts, written to CloudKit. Off until turned on, like Sync to iPhone.
    public var iPhoneAlerts: Bool {
        get { self.defaults.bool(forKey: Key.iPhoneAlerts) }
        nonmutating set { self.defaults.set(newValue, forKey: Key.iPhoneAlerts) }
    }

    public var alertThresholds: AlertThresholds {
        get {
            self.defaults.string(forKey: Key.alertThresholds).flatMap(AlertThresholds.init(rawValue:)) ?? .standard
        }
        nonmutating set { self.defaults.set(newValue.rawValue, forKey: Key.alertThresholds) }
    }

    public var refreshInterval: RefreshInterval {
        get {
            RefreshInterval(rawValue: self.defaults.integer(forKey: Key.refreshInterval)) ?? .twoMinutes
        }
        nonmutating set { self.defaults.set(newValue.rawValue, forKey: Key.refreshInterval) }
    }

    /// Turns one provider on or off. The last enabled provider can't be turned off, so the menu bar is never empty.
    public func toggle(_ provider: LiteProvider) {
        var enabled = self.enabledProviders
        if let index = enabled.firstIndex(of: provider) {
            guard enabled.count > 1 else { return }
            enabled.remove(at: index)
        } else {
            enabled.append(provider)
        }
        self.enabledProviders = Self.availableProviders.filter(enabled.contains)
    }
}
