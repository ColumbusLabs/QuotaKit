import Foundation

/// iOS port of `Sources/CodexBarCore/Providers/Claude/ClaudePeakHours.swift`
/// from Mac (upstream v0.24 PR #611). Pure client-side time-of-day logic —
/// no wire payload involved. Mac and iOS compute the same status from the
/// same moment in time independently.
///
/// **Peak window**: Anthropic's published Claude peak hours are 8am–2pm
/// America/New_York, weekdays only. The label rotates between
/// "Peak ends in 1h 25m" / "Off-peak · peak in 5h" / "Off-peak" depending
/// on where the current time falls.
///
/// **Why a copy, not import**: Mac's `ClaudePeakHours` lives in the
/// `CodexBarCore` SwiftPM target which iOS can't import (different
/// platform; iOS lives in a separate Xcode project). Both sides must
/// stay in lockstep — if upstream changes the peak window, iOS needs a
/// follow-up patch. A `ClaudePeakHoursContractTests` integration check
/// could pin lockstep in CI; deferred to a future task.
enum ClaudePeakHours {
    private static let peakTimeZone = TimeZone(identifier: "America/New_York")!
    private static let peakStartHour = 8
    private static let peakEndHour = 14

    struct Status: Equatable {
        let isPeak: Bool
        let label: String
    }

    static func status(at date: Date) -> Status {
        let calendar = self.calendar()
        let date = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        let components = calendar.dateComponents([.hour, .minute, .weekday], from: date)

        guard let hour = components.hour,
              let minute = components.minute,
              let weekday = components.weekday
        else {
            return Status(isPeak: false, label: String(localized: "Off-peak"))
        }

        let isWeekday = weekday >= 2 && weekday <= 6
        let nowMinutes = hour * 60 + minute
        let peakStartMinutes = self.peakStartHour * 60
        let peakEndMinutes = self.peakEndHour * 60
        let isInPeakWindow = nowMinutes >= peakStartMinutes && nowMinutes < peakEndMinutes

        if isWeekday, isInPeakWindow {
            let remaining = peakEndMinutes - nowMinutes
            let formatted = self.formatDuration(minutes: remaining)
            return Status(
                isPeak: true,
                label: String(
                    format: String(localized: "Peak · ends in %@"),
                    formatted))
        }

        let nextPeak = self.nextPeakStart(after: date, calendar: calendar)
        let seconds = nextPeak.timeIntervalSince(date)
        let minutes = max(Int(seconds / 60), 0)
        let formatted = self.formatDuration(minutes: minutes)
        return Status(
            isPeak: false,
            label: String(
                format: String(localized: "Off-peak · peak in %@"),
                formatted))
    }

    private static func nextPeakStart(after date: Date, calendar: Calendar) -> Date {
        guard let todayPeak = calendar.date(
            bySettingHour: self.peakStartHour,
            minute: 0,
            second: 0,
            of: date) else { return date }

        let anchor = todayPeak > date ? todayPeak : calendar.date(byAdding: .day, value: 1, to: todayPeak) ?? date
        let weekday = calendar.component(.weekday, from: anchor)

        let skip = switch weekday {
        case 1: 1
        case 7: 2
        default: 0
        }

        if skip == 0 { return anchor }
        return calendar.date(byAdding: .day, value: skip, to: anchor) ?? anchor
    }

    private static func formatDuration(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 {
            return "\(m)m"
        }
        if m == 0 {
            return "\(h)h"
        }
        return "\(h)h \(m)m"
    }

    private static func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = self.peakTimeZone
        return cal
    }
}
