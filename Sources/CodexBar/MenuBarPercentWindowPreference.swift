import CodexBarCore
import Foundation

/// Which quota window the menu bar percent reads from, expressed as a single choice.
///
/// The menu bar renders from a `MenuBarLayout`, whose `%` tokens each carry their own
/// `PercentWindow`. That is expressive but only reachable through the layout editor, so an account
/// whose stored preference resolves to the weekly lane can end up showing a nearly-full weekly
/// percent with no obvious way to switch to the session lane. This maps the common case — every
/// percent in the layout reading the same window — onto one picker.
///
/// Only top-level percent tokens are considered. A conditional token carries its own then/else
/// tokens, which stay under the layout editor's control. Monthly Plan is also exposed as a stored
/// provider metric, including when the layout has no percent token.
enum MenuBarPercentWindowPreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case session
    case weekly
    case monthlyPlan

    var id: String {
        self.rawValue
    }

    var percentWindow: PercentWindow {
        switch self {
        case .automatic: .automatic
        case .session: .session
        case .weekly: .weekly
        case .monthlyPlan: .automatic
        }
    }

    /// Metric stored for providers that expose Monthly Plan. Other picker choices return the
    /// metric to Automatic while applying their explicit percent window to the layout.
    var menuBarMetric: MenuBarMetricPreference {
        self == .monthlyPlan ? .monthlyPlan : .automatic
    }

    var label: String {
        switch self {
        case .automatic: L("menu_bar_layout_token_auto")
        case .session: L("menu_bar_layout_token_session")
        case .weekly: L("menu_bar_layout_token_weekly")
        case .monthlyPlan: MenuBarMetricPreference.monthlyPlan.label
        }
    }

    func label(for provider: UsageProvider) -> String {
        guard self != .automatic else { return self.label }
        if self == .monthlyPlan { return self.label }
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        let primary = Self.percentWindow(descriptor.presentation.primarySemanticWindow)
        let presentation = descriptor.presentation
        return L(self.percentWindow == primary
            ? presentation.menuBarLayoutPrimaryLabel ?? descriptor.metadata.sessionLabel
            : presentation.menuBarLayoutSecondaryLabel ?? descriptor.metadata.weeklyLabel)
    }

    /// Windows this provider can actually render as a menu-bar percent, in picker order.
    ///
    /// Extra-rate metrics and Monthly Plan map to Automatic for the percent token; Monthly Plan
    /// also gets a distinct option for providers that support the stored metric.
    static func available(
        metrics: ProviderMenuBarMetricCapabilities,
        primarySemanticWindow: ProviderSemanticWindow = .session,
        secondarySemanticWindow: ProviderSemanticWindow = .weekly) -> [Self]
    {
        var windows = Set<PercentWindow>()
        for metric in metrics.supported {
            windows.insert(Self.percentWindow(
                for: metric,
                primarySemanticWindow: primarySemanticWindow,
                secondarySemanticWindow: secondarySemanticWindow))
        }
        var options = Self.allCases.filter { preference in
            preference != .monthlyPlan && windows.contains(preference.percentWindow)
        }
        if metrics.supported.contains(.monthlyPlan) {
            options.append(.monthlyPlan)
        }
        return options
    }

    static func available(for provider: UsageProvider, layout: MenuBarLayout? = nil) -> [Self] {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        let options = Self.available(
            metrics: descriptor.menuBarMetrics,
            primarySemanticWindow: descriptor.presentation.primarySemanticWindow,
            secondarySemanticWindow: descriptor.presentation.secondarySemanticWindow)
        guard let layout, !Self.hasPercentToken(in: layout) else { return options }
        // With no percent token to rewrite, the picker only controls the metric-backed choices.
        return options.filter { $0 == .automatic || $0 == .monthlyPlan }
    }

    /// Ordinary window choices control percent layouts. Monthly Plan controls the stored provider
    /// metric too, so it remains available in every style and with an icon-only layout.
    static func isVisible(
        iconStyle: MenuBarIconStyle,
        layout: MenuBarLayout,
        available: [Self]) -> Bool
    {
        guard available.count > 1 else { return false }
        if available.contains(.monthlyPlan) { return true }
        return iconStyle == .iconAndPercent && self.hasPercentToken(in: layout)
    }

    static func isVisible(
        iconStyle: MenuBarIconStyle,
        layout: MenuBarLayout,
        provider: UsageProvider) -> Bool
    {
        self.isVisible(
            iconStyle: iconStyle,
            layout: layout,
            available: self.available(for: provider, layout: layout))
    }

    /// Writes the per-provider layout override without flipping `menuBarIconStyle`.
    @MainActor
    static func persist(
        _ preference: Self,
        appliedTo layout: MenuBarLayout,
        for provider: UsageProvider,
        settings: SettingsStore)
    {
        settings.setMenuBarLayout(preference.applied(to: layout), for: provider)
    }

    /// The preference a layout expresses, or nil when its percent tokens mix windows — a
    /// combination only the layout editor can describe, which the picker must not silently flatten.
    static func current(in layout: MenuBarLayout, metric: MenuBarMetricPreference? = nil) -> Self? {
        let windows = Self.percentWindows(in: layout)
        guard let first = windows.first else {
            guard let metric else { return nil }
            return metric == .monthlyPlan ? .monthlyPlan : .automatic
        }
        guard windows.allSatisfy({ $0 == first }) else { return nil }
        if first == .automatic, metric == .monthlyPlan { return .monthlyPlan }
        return Self.allCases.first { $0.percentWindow == first }
    }

    /// True when the layout shows a percent at all. A layout built from icon-only or reset-time
    /// tokens has nothing for this preference to act on.
    static func hasPercentToken(in layout: MenuBarLayout) -> Bool {
        !self.percentWindows(in: layout).isEmpty
    }

    /// Layout with every percent token pointed at this preference's window; all other tokens,
    /// including line breaks and separators, are left exactly as the user arranged them.
    func applied(to layout: MenuBarLayout) -> MenuBarLayout {
        MenuBarLayout(lines: layout.lines.map { line in
            line.map { token in
                if case .percent = token {
                    return .percent(window: self.percentWindow)
                }
                return token
            }
        })
    }

    private static func percentWindows(in layout: MenuBarLayout) -> [PercentWindow] {
        layout.lines.flatMap(\.self).compactMap { token in
            guard case let .percent(window) = token else { return nil }
            return window
        }
    }

    /// Same mapping the layout migration uses: primary/secondary become the provider's semantic
    /// session or weekly lane; every other metric, including monthly plan, stays on Automatic.
    private static func percentWindow(
        for metric: ProviderMenuBarMetric,
        primarySemanticWindow: ProviderSemanticWindow,
        secondarySemanticWindow: ProviderSemanticWindow) -> PercentWindow
    {
        switch metric {
        case .primary: self.percentWindow(primarySemanticWindow)
        case .secondary: self.percentWindow(secondarySemanticWindow)
        case .automatic, .primaryAndSecondary, .tertiary, .extraUsage, .average, .monthlyPlan:
            .automatic
        }
    }

    private static func percentWindow(_ window: ProviderSemanticWindow) -> PercentWindow {
        switch window {
        case .session: .session
        case .weekly: .weekly
        }
    }
}
