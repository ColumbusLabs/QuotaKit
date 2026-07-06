import CodexBarSync
import Foundation

struct QuotaKitWidgetDisplayWindow: Identifiable, Equatable {
    let mode: QuotaKitWidgetDisplayMode
    let window: QuotaKitWidgetSnapshot.Provider.Window
    let titleOverride: String?

    init(
        mode: QuotaKitWidgetDisplayMode,
        window: QuotaKitWidgetSnapshot.Provider.Window,
        titleOverride: String? = nil)
    {
        self.mode = mode
        self.window = window
        self.titleOverride = titleOverride
    }

    var id: String {
        "\(self.mode.rawValue)-\(self.window.title)"
    }

    var title: String {
        self.titleOverride ?? self.mode.localizedTitle
    }
}

enum QuotaKitWidgetPresentation {
    static func primaryWindow(
        for provider: QuotaKitWidgetSnapshot.Provider,
        displayMode: QuotaKitWidgetDisplayMode) -> QuotaKitWidgetSnapshot.Provider.Window?
    {
        switch displayMode {
        case .both:
            self.sessionWindow(for: provider, allowPrimaryFallback: true)
        case .session:
            self.sessionWindow(for: provider, allowPrimaryFallback: true)
        case .weekly:
            self.weeklyWindow(for: provider, allowPrimaryFallback: true)
        }
    }

    static func displayWindows(
        for provider: QuotaKitWidgetSnapshot.Provider,
        displayMode: QuotaKitWidgetDisplayMode) -> [QuotaKitWidgetDisplayWindow]
    {
        switch displayMode {
        case .both:
            if provider.id == "kimi" {
                return provider.windows.prefix(3).map { window in
                    QuotaKitWidgetDisplayWindow(
                        mode: window.identity == .weekly ? .weekly : .session,
                        window: window,
                        titleOverride: window.title)
                }
            }
            let weekly = Self.weeklyWindow(for: provider, allowPrimaryFallback: false)
            let session = Self.sessionWindowForBothMode(provider: provider, weekly: weekly)
            var result = session.map {
                [QuotaKitWidgetDisplayWindow(mode: .session, window: $0)]
            } ?? []
            if let weekly,
               session.map({ weekly != $0 }) ?? true
            {
                result.append(QuotaKitWidgetDisplayWindow(mode: .weekly, window: weekly))
            }
            return result
        case .session, .weekly:
            return self.primaryWindow(for: provider, displayMode: displayMode).map {
                [QuotaKitWidgetDisplayWindow(mode: displayMode, window: $0)]
            } ?? []
        }
    }

    static func accessoryDetailText(
        for provider: QuotaKitWidgetSnapshot.Provider,
        displayMode: QuotaKitWidgetDisplayMode) -> String
    {
        if displayMode == .both {
            let displayWindows = Self.displayWindows(for: provider, displayMode: displayMode)
            guard !displayWindows.isEmpty else {
                return provider.statusMessage ?? String(localized: "No quota window")
            }
            return displayWindows.map { displayWindow in
                String(
                    format: String(localized: "%@ %lld%%"),
                    displayWindow.title,
                    Int64(displayWindow.window.remainingPercent.rounded()))
            }.joined(separator: " · ")
        }

        guard let window = primaryWindow(for: provider, displayMode: displayMode) else {
            return provider.statusMessage ?? String(localized: "No quota window")
        }
        return String(
            format: String(localized: "%lld%% left · %@"),
            Int64(window.remainingPercent.rounded()),
            window.title)
    }

    private static func sessionWindow(
        for provider: QuotaKitWidgetSnapshot.Provider,
        allowPrimaryFallback: Bool) -> QuotaKitWidgetSnapshot.Provider.Window?
    {
        provider.windows.first(where: { $0.identity == .session })
            ?? provider.windows.first(where: self.isSessionWindow)
            ?? (allowPrimaryFallback ? provider.windows.first : nil)
    }

    private static func sessionWindowForBothMode(
        provider: QuotaKitWidgetSnapshot.Provider,
        weekly: QuotaKitWidgetSnapshot.Provider.Window?) -> QuotaKitWidgetSnapshot.Provider.Window?
    {
        if let typedSession = provider.windows.first(where: { $0.identity == .session }) {
            return typedSession
        }
        if let explicitSession = provider.windows.first(where: Self.isSessionWindow) {
            return explicitSession
        }
        if let weekly,
           let primary = provider.windows.first,
           primary != weekly
        {
            return primary
        }
        return weekly == nil ? provider.windows.first : nil
    }

    private static func weeklyWindow(
        for provider: QuotaKitWidgetSnapshot.Provider,
        allowPrimaryFallback: Bool) -> QuotaKitWidgetSnapshot.Provider.Window?
    {
        provider.windows.first(where: { $0.identity == .weekly })
            ?? provider.windows.first(where: self.isWeeklyWindow)
            ?? self.fallbackWeeklyWindow(for: provider)
            ?? (allowPrimaryFallback ? provider.windows.first : nil)
    }

    private static func fallbackWeeklyWindow(
        for provider: QuotaKitWidgetSnapshot.Provider) -> QuotaKitWidgetSnapshot.Provider.Window?
    {
        guard let candidate = provider.windows.dropFirst().first else { return nil }
        if let dayCount = Self.numericDayCount(in: candidate.title.localizedLowercase),
           !Self.weeklyDayCountRange.contains(dayCount)
        {
            return nil
        }
        return candidate
    }

    private static func isSessionWindow(_ window: QuotaKitWidgetSnapshot.Provider.Window) -> Bool {
        let title = window.title.localizedLowercase
        return title.contains("session")
            || title.contains("hour")
            || title.contains(String(localized: "Session").localizedLowercase)
    }

    private static func isWeeklyWindow(_ window: QuotaKitWidgetSnapshot.Provider.Window) -> Bool {
        let title = window.title.localizedLowercase
        return title.contains("week")
            || Self.hasWeeklyDayCountLabel(title)
            || title.contains(String(localized: "Weekly").localizedLowercase)
    }

    private static let weeklyDayCountRange = 5...9

    private static func hasWeeklyDayCountLabel(_ title: String) -> Bool {
        self.numericDayCount(in: title).map(self.weeklyDayCountRange.contains) ?? false
    }

    private static func numericDayCount(in title: String) -> Int? {
        let normalized = title
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let tokens = normalized.split { character in
            !character.isLetter && !character.isNumber
        }

        var previousToken: Substring?
        for token in tokens {
            let tokenText = String(token)
            if tokenText == "day" || tokenText == "days",
               previousToken?.allSatisfy(\.isNumber) == true,
               let count = previousToken.flatMap({ Int($0) })
            {
                return count
            }

            if tokenText.hasSuffix("day") {
                let prefix = tokenText.dropLast(3)
                if !prefix.isEmpty,
                   prefix.allSatisfy(\.isNumber),
                   let count = Int(prefix)
                {
                    return count
                }
            }

            if tokenText.hasSuffix("days") {
                let prefix = tokenText.dropLast(4)
                if !prefix.isEmpty,
                   prefix.allSatisfy(\.isNumber),
                   let count = Int(prefix)
                {
                    return count
                }
            }

            previousToken = token
        }
        return nil
    }
}
