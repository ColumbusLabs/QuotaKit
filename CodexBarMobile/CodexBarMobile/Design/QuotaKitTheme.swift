import SwiftUI
import UIKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .dark: String(localized: "Dark")
        case .light: String(localized: "Light")
        case .system: String(localized: "System")
        }
    }

    func resolvedColorScheme(_ system: ColorScheme) -> ColorScheme {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: system
        }
    }
}

enum QKElevation {
    case surface
    case elevated
    case chartPlot
}

struct QuotaKitTheme: Equatable {
    let canvas: Color
    let surface: Color
    let surfaceElevated: Color
    let border: Color
    let textPrimary: Color
    let textMuted: Color
    let accent: Color
    let spendWarm: Color
    let chartPlot: Color
    let isDark: Bool

    static let brandAccent = Color(red: 1.0, green: 0.73, blue: 0.08)

    func fill(for elevation: QKElevation) -> Color {
        switch elevation {
        case .surface: self.surface
        case .elevated: self.surfaceElevated
        case .chartPlot: self.chartPlot
        }
    }

    static func from(_ colorScheme: ColorScheme) -> QuotaKitTheme {
        colorScheme == .dark ? .dark : .light
    }

    static let dark = QuotaKitTheme(
        canvas: Color(red: 0.043, green: 0.051, blue: 0.071),
        surface: Color(red: 0.078, green: 0.094, blue: 0.125),
        surfaceElevated: Color(red: 0.110, green: 0.133, blue: 0.188),
        border: Color.white.opacity(0.06),
        textPrimary: Color(red: 0.941, green: 0.949, blue: 0.961),
        textMuted: Color(red: 0.545, green: 0.573, blue: 0.627),
        accent: QuotaKitTheme.brandAccent,
        spendWarm: Color(red: 0.95, green: 0.55, blue: 0.22),
        chartPlot: Color(red: 0.059, green: 0.071, blue: 0.094),
        isDark: true)

    static let light = QuotaKitTheme(
        canvas: Color(red: 0.957, green: 0.961, blue: 0.969),
        surface: .white,
        surfaceElevated: Color(red: 0.980, green: 0.980, blue: 0.980),
        border: Color.black.opacity(0.08),
        textPrimary: Color(red: 0.067, green: 0.067, blue: 0.067),
        textMuted: Color(red: 0.420, green: 0.447, blue: 0.502),
        accent: QuotaKitTheme.brandAccent,
        spendWarm: Color(red: 0.92, green: 0.48, blue: 0.12),
        chartPlot: Color(red: 0.925, green: 0.933, blue: 0.949),
        isDark: false)

    static func applyUIKitChrome(theme: QuotaKitTheme) {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(theme.surface).withAlphaComponent(0.92)
        tabAppearance.shadowColor = UIColor(theme.border)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = UIColor(theme.accent)

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(theme.canvas)
        navAppearance.shadowColor = UIColor(theme.border)
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        let searchField = theme.surfaceElevated
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).backgroundColor =
            UIColor(searchField)
    }
}

private struct QuotaKitThemeKey: EnvironmentKey {
    static let defaultValue = QuotaKitTheme.dark
}

extension EnvironmentValues {
    var quotaKitTheme: QuotaKitTheme {
        get { self[QuotaKitThemeKey.self] }
        set { self[QuotaKitThemeKey.self] = newValue }
    }
}

struct QuotaKitThemeProvider: ViewModifier {
    @AppStorage(MobileSettingsKeys.appearanceMode) private var appearanceModeRaw =
        AppearanceMode.dark.rawValue
    @Environment(\.colorScheme) private var systemColorScheme

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: self.appearanceModeRaw) ?? .dark
    }

    private var resolvedScheme: ColorScheme {
        self.appearanceMode.resolvedColorScheme(self.systemColorScheme)
    }

    private var theme: QuotaKitTheme {
        QuotaKitTheme.from(self.resolvedScheme)
    }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(self.appearanceMode == .system ? nil : self.resolvedScheme)
            .environment(\.quotaKitTheme, self.theme)
            .onAppear {
                QuotaKitTheme.applyUIKitChrome(theme: self.theme)
            }
            .onChange(of: self.appearanceModeRaw) { _, _ in
                QuotaKitTheme.applyUIKitChrome(theme: self.theme)
            }
            .onChange(of: self.systemColorScheme) { _, _ in
                guard self.appearanceMode == .system else { return }
                QuotaKitTheme.applyUIKitChrome(theme: self.theme)
            }
    }
}

extension View {
    func quotaKitThemed() -> some View {
        self.modifier(QuotaKitThemeProvider())
    }
}
