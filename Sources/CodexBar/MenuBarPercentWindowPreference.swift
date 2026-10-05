import CodexBarCore
import Foundation

/// Maps the layout's common top-level percentage tokens onto one picker. Conditional branches
/// and direct primary/secondary lane tokens remain under the layout editor's control.
enum MenuBarPercentWindowPreference: Hashable, Identifiable, Sendable {
    case automatic
    case session
    case weekly
    case tertiary
    case monthlyPlan
    case extra(id: String)

    static let standardChoices: [Self] = [.automatic, .session, .weekly, .tertiary, .monthlyPlan]

    var id: String {
        if case let .extra(id) = self { return "extra:\(id)" }
        return String(describing: self)
    }

    private var percentWindow: PercentWindow? {
        switch self {
        case .automatic: .automatic
        case .session: .session
        case .weekly: .weekly
        case .tertiary, .monthlyPlan, .extra: nil
        }
    }

    private var layoutToken: MenuBarLayoutToken {
        if self == .tertiary { return .lanePercent(lane: .tertiary) }
        if case let .extra(id) = self { return .extraPercent(id: id) }
        return .percent(window: self.percentWindow ?? .automatic)
    }

    /// The metric stored for providers that expose Monthly Plan.
    var menuBarMetric: MenuBarMetricPreference {
        self == .monthlyPlan ? .monthlyPlan : .automatic
    }

    func label(for provider: UsageProvider) -> String {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        if case let .extra(id) = self {
            return L(descriptor.menuBarMetrics.namedExtras[id] ?? "Usage")
        }
        guard self != .automatic else { return L("menu_bar_layout_token_auto") }
        if self == .monthlyPlan { return MenuBarMetricPreference.monthlyPlan.label }
        if self == .tertiary {
            return MenuBarLayoutLaneLabels(provider: provider, snapshot: nil).label(for: .tertiary)
        }
        let primary = Self.percentWindow(descriptor.presentation.primarySemanticWindow)
        let presentation = descriptor.presentation
        return L(self.percentWindow == primary
            ? presentation.menuBarLayoutPrimaryLabel ?? descriptor.metadata.sessionLabel
            : presentation.menuBarLayoutSecondaryLabel ?? descriptor.metadata.weeklyLabel)
    }

    /// Semantic windows keep their existing mapping; tertiary and named allowances use their direct layout tokens.
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
        var options = Self.standardChoices.filter { preference in
            guard let window = preference.percentWindow else { return false }
            return windows.contains(window)
        }
        if metrics.supported.contains(.tertiary), !metrics.tertiaryRequiresWindow {
            options.append(.tertiary)
        }
        if metrics.supported.contains(.monthlyPlan) {
            options.append(.monthlyPlan)
        }
        return options + metrics.namedExtras.keys.sorted().map { .extra(id: $0) }
    }

    static func available(for provider: UsageProvider, layout: MenuBarLayout? = nil) -> [Self] {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        var options = Self.available(
            metrics: descriptor.menuBarMetrics,
            primarySemanticWindow: descriptor.presentation.primarySemanticWindow,
            secondarySemanticWindow: descriptor.presentation.secondarySemanticWindow)
        if let layout, !Self.percentWindows(in: layout).isEmpty, Self.hasTertiaryPercent(in: layout) {
            options.removeAll { $0 == .tertiary }
        }
        if let layout, Self.hasIndependentPercents(in: layout) {
            if Self.percentWindows(in: layout).isEmpty, !Self.hasTertiaryPercent(in: layout) { return [] }
            options.removeAll { preference in
                if case .extra = preference { return true }
                return false
            }
        }
        // Without a percent token, only the stored metric can change.
        if let layout, options.contains(.monthlyPlan), !Self.hasPercentToken(in: layout) {
            return [.automatic, .monthlyPlan]
        }
        return options
    }

    /// The picker controls percent layouts without changing the global icon style. Monthly Plan
    /// also selects the widget allowance, so it remains reachable in every style and layout.
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

    /// Ordinary percentages own the choice when a custom layout also has an independent token.
    static func current(in layout: MenuBarLayout, metric: MenuBarMetricPreference? = nil) -> Self? {
        let windows = Self.percentWindows(in: layout)
        guard let first = windows.first else {
            if Self.hasTertiaryPercent(in: layout) { return .tertiary }
            let extras = Self.extraIDs(in: layout)
            if let id = extras.first {
                return extras.allSatisfy { $0 == id } ? .extra(id: id) : nil
            }
            guard let metric else { return nil }
            return metric == .monthlyPlan ? .monthlyPlan : .automatic
        }
        guard windows.allSatisfy({ $0 == first }) else { return nil }
        if first == .automatic, metric == .monthlyPlan { return .monthlyPlan }
        return Self.standardChoices.first { $0.percentWindow == first }
    }

    static func hasPercentToken(in layout: MenuBarLayout) -> Bool {
        !self.percentWindows(in: layout).isEmpty || self.hasTertiaryPercent(in: layout)
            || !self.extraIDs(in: layout).isEmpty
    }

    /// Changes only the common percentage group, preserving pace, resets and custom tokens.
    func applied(to layout: MenuBarLayout) -> MenuBarLayout {
        let hasOrdinaryPercent = !Self.percentWindows(in: layout).isEmpty
        let hasTertiary = Self.hasTertiaryPercent(in: layout)
        if self == .tertiary, hasOrdinaryPercent, hasTertiary { return layout }
        if Self.hasIndependentPercents(in: layout) {
            if !hasOrdinaryPercent, !hasTertiary { return layout }
            if case .extra = self { return layout }
        }
        return MenuBarLayout(lines: layout.lines.map { line in
            line.map { token in
                if case .percent = token { return self.layoutToken }
                if !hasOrdinaryPercent, token == .lanePercent(lane: .tertiary) { return self.layoutToken }
                if !hasOrdinaryPercent, !hasTertiary, case .extraPercent = token { return self.layoutToken }
                return token
            }
        })
    }

    private static func hasTertiaryPercent(in layout: MenuBarLayout) -> Bool {
        layout.lines.joined().contains(.lanePercent(lane: .tertiary))
    }

    private static func hasIndependentPercents(in layout: MenuBarLayout) -> Bool {
        let groups = (Self.percentWindows(in: layout).isEmpty ? 0 : 1)
            + (Self.hasTertiaryPercent(in: layout) ? 1 : 0) + Set(Self.extraIDs(in: layout)).count
        return groups > 1
    }

    private static func extraIDs(in layout: MenuBarLayout) -> [String] {
        layout.lines.joined().compactMap { token in
            guard case let .extraPercent(id) = token else { return nil }
            return id
        }
    }

    private static func percentWindows(in layout: MenuBarLayout) -> [PercentWindow] {
        layout.lines.flatMap(\.self).compactMap { token in
            guard case let .percent(window) = token else { return nil }
            return window
        }
    }

    private static func percentWindow(
        for metric: ProviderMenuBarMetric,
        primarySemanticWindow: ProviderSemanticWindow,
        secondarySemanticWindow: ProviderSemanticWindow) -> PercentWindow
    {
        switch metric {
        case .primary: self.percentWindow(primarySemanticWindow)
        case .secondary: self.percentWindow(secondarySemanticWindow)
        case .automatic, .primaryAndSecondary, .tertiary, .extraUsage, .average, .monthlyPlan: .automatic
        }
    }

    private static func percentWindow(_ window: ProviderSemanticWindow) -> PercentWindow {
        switch window {
        case .session: .session
        case .weekly: .weekly
        }
    }
}
