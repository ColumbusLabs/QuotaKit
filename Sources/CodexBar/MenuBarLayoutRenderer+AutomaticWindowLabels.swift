import AppKit
import CodexBarCore
import Foundation

extension MenuBarLayoutRenderer {
    static func labelAutomaticItem(
        _ rendered: (value: NSAttributedString, accessibilityText: String?),
        token: MenuBarLayoutToken,
        data: MenuBarLayoutRenderData,
        options: MenuBarLayoutRenderOptions,
        attributes: [NSAttributedString.Key: Any])
        -> (value: NSAttributedString, accessibilityText: String?)
    {
        switch token {
        case .percent(window: .automatic), .pace(window: .automatic), .resetCountdown, .resetAbsolute,
             .windowResetCountdown(window: .automatic), .windowResetAbsolute(window: .automatic): break
        default: return rendered
        }
        guard let label = self.automaticWindowLabel(data: data) else { return rendered }
        return (
            self.prefixedValue(
                options.showWindowLabels ? label.short : "",
                value: rendered.value,
                attributes: attributes),
            rendered.accessibilityText.map { L("%@: %@", label.full, $0) })
    }

    private static func automaticWindowLabel(data: MenuBarLayoutRenderData) -> (short: String, full: String)? {
        guard let automatic = data.automatic, data.automaticText == nil else { return nil }
        let semantic: [PercentWindow] = [.session, .weekly, .scopedWeekly]
        let lanes: [MenuBarLayoutLane] = [.primary, .secondary, .tertiary]
        let extras = data.extraRateWindows.filter { data.extraTitle($0.id) != nil }
        let windows = semantic.compactMap { self.window($0, data: data) }
            + lanes.compactMap { self.laneWindow($0, data: data) } + extras.compactMap(\.window)
        // Semantic aliases must not make a single quota look like multiple windows.
        guard Set(windows).count > 1 else { return nil }
        // Match the complete selected window, never its percentage or formatted pace alone.
        let matches = semantic.filter { self.window($0, data: data) == automatic }
        let laneMatches = lanes.filter { self.laneWindow($0, data: data) == automatic }
        let extraMatches = extras.filter { $0.window == automatic }
        guard laneMatches.count + extraMatches.count <= 1 else { return nil }
        if matches.count == 1, let selected = matches.first {
            return (self.windowPrefix(selected, data: data), self.windowAccessibilityLabel(selected, data: data))
        }
        guard matches.isEmpty else { return nil }
        if laneMatches.count == 1, let lane = laneMatches.first {
            let title = data.laneLabels.label(for: lane)
            return (self.laneShortLabel(lane, data: data) ?? String(title.prefix(1)).uppercased(), title)
        }
        guard laneMatches.isEmpty else { return nil }
        guard extraMatches.count == 1, let extra = extraMatches.first, let title = data.extraTitle(extra.id)
        else { return nil }
        let short = data.provider.flatMap { provider in
            ProviderDescriptorRegistry.descriptor(for: provider).menuBarMetrics.namedExtraShortLabels[extra.id]
        } ?? title
        return (short, title)
    }
}
