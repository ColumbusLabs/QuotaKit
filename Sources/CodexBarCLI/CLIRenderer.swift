import CodexBarCore
import Foundation

enum CLIRenderer {
    static func renderText(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        credits: CreditsSnapshot?,
        context: RenderContext) -> String
    {
        let meta = ProviderDefaults.metadata[provider]!
        var lines: [String] = []
        lines.append(context.header)

        lines.append(self.rateLine(title: meta.sessionLabel, window: snapshot.primary))
        if let reset = snapshot.primary.resetDescription {
            lines.append("Resets \(reset)")
        }

        if let weekly = snapshot.secondary {
            lines.append(self.rateLine(title: meta.weeklyLabel, window: weekly))
            if let reset = weekly.resetDescription {
                lines.append("Resets \(reset)")
            }
        }

        if meta.supportsOpus, let opus = snapshot.tertiary {
            lines.append(self.rateLine(title: meta.opusLabel ?? "Sonnet", window: opus))
            if let reset = opus.resetDescription {
                lines.append("Resets \(reset)")
            }
        }

        if provider == .codex, let credits {
            lines.append("Credits: \(UsageFormatter.creditsString(from: credits.remaining))")
        }

        if let email = snapshot.accountEmail, !email.isEmpty {
            lines.append("Account: \(email)")
        }
        if let plan = snapshot.loginMethod, !plan.isEmpty {
            lines.append("Plan: \(plan.capitalized)")
        }

        if let status = context.status {
            let statusLine = "Status: \(status.indicator.label)\(status.descriptionSuffix)"
            lines.append(self.colorize(statusLine, indicator: status.indicator, useColor: context.useColor))
        }

        return lines.joined(separator: "\n")
    }

    static func rateLine(title: String, window: RateWindow) -> String {
        let text = UsageFormatter.usageLine(remaining: window.remainingPercent, used: window.usedPercent)
        return "\(title): \(text)"
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
        return "\u{001B}[\(code)m\(text)\u{001B}[0m"
    }
}

struct RenderContext {
    let header: String
    let status: ProviderStatusPayload?
    let useColor: Bool
}
