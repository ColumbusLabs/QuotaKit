import Foundation

/// The pace shown under one window's bar: "3% in reserve" on the left, "Lasts until reset" on the right.
public struct PaceDetail: Sendable, Equatable {
    public let pace: UsagePace
    public let leftLabel: String
    public let rightLabel: String?
}

/// Port of the full app's pace wording (Sources/CodexBar/UsagePaceText.swift), as plain English strings
/// (068 §7.5). The history-based "(N% risk)" suffix isn't ported.
public enum PaceText {
    /// Pace for one window, or nil when the full app would show none.
    ///
    /// Session windows follow `UsagePaceText.sessionPace`: hidden once depleted or in the first 3% of the window.
    /// Weekly windows use the optional workday weighting. Projected windows get no pace, because their value
    /// isn't real usage.
    public static func detail(
        for window: QuotaWindow,
        provider: LiteProvider,
        now: Date = .init(),
        workDays: Int? = nil,
        calendar: Calendar = .current) -> PaceDetail?
    {
        guard !window.isProjected else { return nil }
        let pace: UsagePace
        switch window.lane {
        case .session:
            guard window.remainingPercent > 0,
                  let sessionPace = UsagePace.weekly(
                      usedPercent: window.usedPercent,
                      windowMinutes: window.windowMinutes,
                      resetsAt: window.resetsAt,
                      now: now,
                      defaultWindowMinutes: 300),
                  sessionPace.expectedUsedPercent >= 3
            else { return nil }
            pace = sessionPace
        case .weekly:
            guard let weeklyPace = UsagePace.weekly(
                usedPercent: window.usedPercent,
                windowMinutes: window.windowMinutes,
                resetsAt: window.resetsAt,
                now: now,
                workDays: workDays,
                calendar: calendar)
            else { return nil }
            pace = weeklyPace
        }
        return PaceDetail(
            pace: pace,
            leftLabel: self.leftLabel(for: pace),
            rightLabel: self.rightLabel(
                for: pace,
                lane: window.lane,
                showsHeadroomHint: provider.showsHeadroomHint,
                now: now))
    }

    public static func leftLabel(for pace: UsagePace) -> String {
        let deltaValue = Int(abs(pace.deltaPercent).rounded())
        if deltaValue == 0 {
            return "On pace"
        }
        if pace.deltaPercent > 0 {
            return "\(deltaValue)% in deficit"
        }
        if pace.deltaPercent < 0 {
            return "\(deltaValue)% in reserve"
        }
        return "On pace"
    }

    public static func rightLabel(
        for pace: UsagePace,
        lane: QuotaWindow.Lane,
        showsHeadroomHint: Bool,
        now: Date) -> String?
    {
        if pace.willLastToReset {
            guard showsHeadroomHint, let speedLabel = self.speedHintLabel(for: pace) else {
                return "Lasts until reset"
            }
            return "Lasts until reset · \(speedLabel)"
        }
        guard let etaSeconds = pace.etaSeconds else { return nil }
        let etaText = self.durationText(seconds: etaSeconds, now: now)
        switch lane {
        case .session:
            return etaText == "now" ? "Projected empty now" : "Projected empty in \(etaText)"
        case .weekly:
            return etaText == "now" ? "Runs out now" : "Runs out in \(etaText)"
        }
    }

    private static func speedHintLabel(for pace: UsagePace) -> String? {
        guard pace.deltaPercent < -15,
              let multiplier = pace.speedMultiplierToReset,
              multiplier >= 1.5
        else { return nil }
        return "1.5× headroom"
    }

    private static func durationText(seconds: TimeInterval, now: Date) -> String {
        let countdown = ResetText.countdown(to: now.addingTimeInterval(seconds), now: now)
        if countdown.hasPrefix("in ") {
            return String(countdown.dropFirst(3))
        }
        return countdown
    }
}

/// Port of `UsageFormatter.resetCountdownDescription` (Sources/CodexBarCore/UsageFormatter.swift).
public enum ResetText {
    /// "now", "in 45m", "in 2h 14m", "in 1d 4h", or "Unknown" for an unrepresentable date.
    public static func countdown(to date: Date, now: Date = .init()) -> String {
        let seconds = date.timeIntervalSince(now)
        guard let ceilingMinutes = Int(exactly: ceil(seconds / 60)) else { return "Unknown" }
        let totalMinutes = seconds < 1 ? 0 : max(1, ceilingMinutes)
        if totalMinutes == 0 {
            return "now"
        }
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60

        if days > 0 {
            if hours > 0 {
                return "in \(days)d \(hours)h"
            }
            if minutes > 0 {
                return "in \(days)d \(minutes)m"
            }
            return "in \(days)d"
        }
        if hours > 0 {
            if minutes > 0 {
                return "in \(hours)h \(minutes)m"
            }
            return "in \(hours)h"
        }
        return "in \(totalMinutes)m"
    }
}
