import Foundation

/// What one window's row in a menu card shows. Built to match the full app's default `MetricRow`
/// (Sources/CodexBar/MenuCardMetricRow.swift): bars show the remaining share ("12% left") and resets are a
/// countdown, which are the full app's defaults.
public struct MetricPresentation: Sendable, Equatable {
    /// "Session 12% left": the window label and the remaining percent, as `Metric.linePresentation` formats it.
    public let title: String
    /// The bar's fill, 0–100: the remaining share.
    public let fillPercent: Double
    /// "Resets in 2h 14m", right-aligned next to the title.
    public let resetText: String?
    /// "3% in reserve · Lasts until reset" under the bar.
    public let metaText: String?
    /// Where the pace stripe sits on the bar (the expected remaining share), or nil when on track or unknown.
    public let pacePercent: Double?
    /// True when usage is at or below the expected pace: the stripe is green, otherwise red.
    public let paceOnTop: Bool
}

/// What one provider's card shows (the full app's `UsageMenuCardHeaderView` plus its usage section).
public struct CardPresentation: Sendable, Equatable {
    public let providerName: String
    public let email: String?
    /// "Updated 2m ago", or the status when the provider isn't showing live data.
    public let subtitle: String
    public let subtitleIsError: Bool
    public let plan: String?
    public let metrics: [MetricPresentation]
    /// Shown in place of the metrics when there are none ("No usage yet").
    public let placeholder: String?

    public init(state: ProviderState, now: Date, workDays: Int? = nil, calendar: Calendar = .current) {
        let projected = state.projected(at: now)
        self.providerName = state.provider.displayName
        self.email = state.accountEmail
        self.plan = Self.planName(for: state)
        (self.subtitle, self.subtitleIsError) = Self.subtitle(for: state, now: now)
        self.metrics = projected.windows.map {
            Self.metric(for: $0, provider: state.provider, now: now, workDays: workDays, calendar: calendar)
        }
        self.placeholder = projected.windows.isEmpty ? "No usage yet" : nil
    }

    static func metric(
        for window: QuotaWindow,
        provider: LiteProvider,
        now: Date,
        workDays: Int?,
        calendar: Calendar) -> MetricPresentation
    {
        let remaining = window.remainingPercent.clamped(to: 0...100)
        let pace = PaceText.detail(for: window, provider: provider, now: now, workDays: workDays, calendar: calendar)
        let metaText: String? = if window.isProjected {
            "Reset since last refresh"
        } else {
            pace.map { [$0.leftLabel, $0.rightLabel].compactMap(\.self).joined(separator: " · ") }
        }
        // `weeklyPaceDetail`/`sessionPaceDetail`: no stripe when on track; otherwise at the expected remaining share.
        let pacePercent: Double? = if let pace, pace.pace.stage != .onTrack {
            100 - pace.pace.expectedUsedPercent
        } else {
            nil
        }
        return MetricPresentation(
            title: "\(window.label) \(Self.percentText(remaining)) left",
            fillPercent: remaining,
            resetText: window.resetsAt.map { Self.resetText(to: $0, now: now) },
            metaText: metaText,
            pacePercent: pacePercent,
            paceOnTop: pace.map { $0.pace.actualUsedPercent <= $0.pace.expectedUsedPercent } ?? true)
    }

    /// `UsageFormatter.percentText`: "<1%" for a sliver, otherwise a whole percent.
    static func percentText(_ percent: Double) -> String {
        let clamped = percent.clamped(to: 0...100)
        if clamped > 0, clamped < 1 {
            return "<1%"
        }
        return "\(Int(clamped.rounded()))%"
    }

    /// `UsageFormatter.resetLine` in its countdown style.
    static func resetText(to date: Date, now: Date) -> String {
        let countdown = ResetText.countdown(to: date, now: now)
        if countdown == "now" {
            return "Resets now"
        }
        if countdown.hasPrefix("in ") {
            return "Resets in \(countdown.dropFirst(3))"
        }
        return "Resets \(countdown)"
    }

    static func subtitle(for state: ProviderState, now: Date) -> (text: String, isError: Bool) {
        let cli = state.provider == .codex ? "codex" : "claude"
        switch state.status {
        case .ok:
            guard let fetched = state.lastFetched else { return ("Waiting for first refresh", false) }
            return (Self.updatedText(since: fetched, now: now), false)
        case .tokenExpired:
            return ("Token expired — run \(cli) once", false)
        case .tokenUnavailable:
            return ("Claude token unavailable — run claude once", true)
        case .signInRequired:
            return ("Sign in to \(cli) again", true)
        case .notRunning:
            return ("Not running — showing last data", false)
        case .paused:
            return ("Paused — QuotaKit is running", false)
        case .unrecognizedResponse:
            return ("Unrecognized response — update Lite", true)
        case let .error(message):
            return (message, true)
        }
    }

    /// `UsageFormatter.updatedString`, without the localized relative formatter.
    static func updatedText(since date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 {
            return "Updated just now"
        }
        if seconds < 3600 {
            return "Updated \(seconds / 60)m ago"
        }
        if seconds < 24 * 3600 {
            return "Updated \(seconds / 3600)h ago"
        }
        return "Updated \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    /// The synced plan is the full app's raw `loginMethod`; the card shows a friendlier name.
    static func planName(for state: ProviderState) -> String? {
        guard let plan = state.plan, !plan.isEmpty else { return nil }
        switch state.provider {
        case .codex:
            return CodexPlanName.displayName(plan) ?? plan
        case .claude:
            return plan.hasPrefix("Claude ") ? String(plan.dropFirst("Claude ".count)) : plan
        case .antigravity:
            return plan
        }
    }
}
