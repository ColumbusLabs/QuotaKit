import AppKit
import CodexBarCore
import Foundation

struct AutomaticWindowLabelContext {
    let data: MenuBarLayoutRenderData
    let options: MenuBarLayoutRenderOptions
    let attributes: [NSAttributedString.Key: Any]
}

extension MenuBarLayoutRenderer {
    static func labelAutomaticItem(
        _ rendered: (value: NSAttributedString, accessibilityText: String?),
        token: MenuBarLayoutToken,
        context: AutomaticWindowLabelContext,
        lineWindowLabel: inout String?)
        -> (value: NSAttributedString, accessibilityText: String?)
    {
        switch token {
        case .percent(window: .automatic), .pace(window: .automatic), .resetCountdown, .resetAbsolute,
             .windowResetCountdown(window: .automatic), .windowResetAbsolute(window: .automatic): break
        case .space, .separatorDot, .separator:
            return rendered
        default:
            lineWindowLabel = rendered.value.length > 0
                ? rendered.value.attribute(NSAttributedString.Key("CodexBarWindowPrefix"), at: 0, effectiveRange: nil)
                as? String : nil
            return rendered
        }
        guard let label = self.automaticWindowLabel(data: context.data) else { return rendered }
        let showPrefix = context.options.showWindowLabels && label.short != lineWindowLabel
        lineWindowLabel = label.short
        return (
            self.prefixedValue(
                showPrefix ? label.short : "",
                value: rendered.value,
                attributes: context.attributes),
            rendered.accessibilityText.map { L("%@: %@", label.full, $0) })
    }

    /// nil == resolved to .hidden (render nothing, no separator). A returned .conditional
    /// means the id is dangling or the depth cap was hit; renderItem shows the placeholder.
    static func resolvedDisplayToken(
        _ token: MenuBarLayoutToken,
        data: MenuBarLayoutRenderData,
        conditionals: [UUID: MenuBarLayoutConditional],
        outcomes: [UUID: Bool],
        depth: Int = 0)
        -> MenuBarLayoutToken?
    {
        if data.provider == nil {
            let missing: Bool = switch token {
            case let .percent(window) where window == .session || window == .weekly:
                self.window(window, data: data) == nil
            case .lanePercent(lane: .tertiary): data.tertiary == nil
            case let .extraPercent(id): data.extraWindow(id) == nil
            default: false
            }
            if missing { return .percent(window: .automatic) }
        }
        switch token {
        case .hidden: return nil
        case let .extraPercent(id): return data.extraTitle(id) == nil ? nil : token
        case let .conditional(id):
            guard depth < MenuBarLayoutToken.maxConditionalDepth,
                  let conditional = conditionals[id],
                  let isTrue = outcomes[id]
            else { return token }
            let branch = isTrue ? conditional.thenToken : conditional.elseToken
            return self.resolvedDisplayToken(
                branch,
                data: data,
                conditionals: conditionals,
                outcomes: outcomes,
                depth: depth + 1)
        default: return token
        }
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
