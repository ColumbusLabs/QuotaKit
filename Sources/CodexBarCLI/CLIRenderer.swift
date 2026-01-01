import CodexBarCore
import Foundation

enum CLIRenderer {
    static func renderText(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        credits: CreditsSnapshot?,
        context: RenderContext) -> String
    {
        let meta = ProviderDescriptorRegistry.descriptor(for: provider).metadata
        var lines: [String] = []
        lines.append(self.headerLine(context.header, useColor: context.useColor))

        if let primary = snapshot.primary {
            lines.append(self.rateLine(title: meta.sessionLabel, window: primary, useColor: context.useColor))
            if let reset = self.resetLine(for: primary, style: context.resetStyle) {
                lines.append(reset)
            }
        } else if let cost = snapshot.providerCost {
            // Fallback to cost/quota display if no primary rate window
            let label = cost.currencyCode == "Quota" ? "Quota" : "Cost"
            lines.append("\(label): \(String(format: "%.1f", cost.used)) / \(String(format: "%.1f", cost.limit))")
        }

        if let weekly = snapshot.secondary {
            lines.append(self.rateLine(title: meta.weeklyLabel, window: weekly, useColor: context.useColor))
            if let reset = self.resetLine(for: weekly, style: context.resetStyle) {
                lines.append(reset)
            }
        }

        if meta.supportsOpus, let opus = snapshot.tertiary {
            lines.append(self.rateLine(title: meta.opusLabel ?? "Sonnet", window: opus, useColor: context.useColor))
            if let reset = self.resetLine(for: opus, style: context.resetStyle) {
                lines.append(reset)
            }
        }

        if provider == .codex, let credits {
            lines.append("Credits: \(UsageFormatter.creditsString(from: credits.remaining))")
        }

        if let email = snapshot.accountEmail(for: provider), !email.isEmpty {
            lines.append("Account: \(email)")
        }
        if let plan = snapshot.loginMethod(for: provider), !plan.isEmpty {
            lines.append("Plan: \(plan.capitalized)")
        }

        if let status = context.status {
            let statusLine = "Status: \(status.indicator.label)\(status.descriptionSuffix)"
            lines.append(self.colorize(statusLine, indicator: status.indicator, useColor: context.useColor))
        }

        return lines.joined(separator: "\n")
    }

    static func rateLine(title: String, window: RateWindow, useColor: Bool) -> String {
        let text = UsageFormatter.usageLine(remaining: window.remainingPercent, used: window.usedPercent)
        let colored = self.colorizeUsage(text, remainingPercent: window.remainingPercent, useColor: useColor)
        return "\(title): \(colored)"
    }

    private static func resetLine(for window: RateWindow, style: ResetTimeDisplayStyle) -> String? {
        UsageFormatter.resetLine(for: window, style: style)
    }

    private static func headerLine(_ header: String, useColor: Bool) -> String {
        guard useColor else { return header }
        return self.ansi("1;36", header)
    }

    private static func colorizeUsage(_ text: String, remainingPercent: Double, useColor: Bool) -> String {
        guard useColor else { return text }

        let code = switch remainingPercent {
        case ..<10:
            "31" // red
        case ..<25:
            "33" // yellow
        default:
            "32" // green
        }
        return self.ansi(code, text)
    }

    private static func colorize(
        _ text: String,
        indicator: ProviderStatusPayload.ProviderStatusIndicator,
        useColor: Bool)
        -> String
    {
        guard useColor else { return text }
        let code = switch indicator {
        case .none: "32" // green
        case .minor: "33" // yellow
        case .major, .critical: "31" // red
        case .maintenance: "34" // blue
        case .unknown: "90" // gray
        }
        return self.ansi(code, text)
    }

    private static func ansi(_ code: String, _ text: String) -> String {
        "\u{001B}[\(code)m\(text)\u{001B}[0m"
    }
}

struct RenderContext {
    let header: String
    let status: ProviderStatusPayload?
    let useColor: Bool
    let resetStyle: ResetTimeDisplayStyle
}
