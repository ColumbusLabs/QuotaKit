import Foundation
import Testing
@testable import CodexBarMobile

/// iOS port of `Tests/CodexBarTests/ClaudePeakHoursTests.swift` (Mac
/// upstream v0.24 PR #611). Same peak-window contract (8am–2pm
/// America/New_York, weekdays only); same per-minute granularity.
///
/// **Important distinction from Mac tests**: iOS labels go through
/// `String(localized:)` which resolves per simulator locale. So we
/// pin only `isPeak` (the logic contract) plus a duration-substring
/// check on the label (e.g. assert "1h 45m" appears) — exact label
/// text varies by locale and is verified separately via xcstrings
/// audit, not here.
@Suite("Claude peak hours")
struct ClaudePeakHoursTests {
    private static let eastern = TimeZone(identifier: "America/New_York")!

    private func date(
        year: Int = 2026,
        month: Int = 3,
        day: Int,
        hour: Int,
        minute: Int = 0,
        second: Int = 0) -> Date
    {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.eastern
        return cal.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second))!
    }

    @Test("Weekday morning before peak: isPeak=false, ~1h remaining")
    func weekdayMorningBeforePeak() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 7))
        #expect(!status.isPeak)
        #expect(status.label.contains("1h"))
    }

    @Test("Weekday just before peak: 15m countdown")
    func weekdayJustBeforePeak() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 7, minute: 45))
        #expect(!status.isPeak)
        #expect(status.label.contains("15m"))
    }

    @Test("Weekday peak start: isPeak=true, 6h remaining")
    func weekdayPeakStart() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 8))
        #expect(status.isPeak)
        #expect(status.label.contains("6h"))
    }

    @Test("Weekday mid-peak: 2h 30m remaining")
    func weekdayMidPeak() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 11, minute: 30))
        #expect(status.isPeak)
        #expect(status.label.contains("2h 30m"))
    }

    @Test("Weekday peak end boundary (13:59 ET) — still peak with 1m left")
    func weekdayPeakEndBoundary() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 13, minute: 59))
        #expect(status.isPeak)
        #expect(status.label.contains("1m"))
    }

    @Test("Weekday 14:00 ET — peak just ended, 18h to next")
    func weekdayAfterPeak() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 14))
        #expect(!status.isPeak)
        #expect(status.label.contains("18h"))
    }

    @Test("Weekday late evening — 9h to next morning peak")
    func weekdayLateEvening() {
        let status = ClaudePeakHours.status(at: self.date(day: 26, hour: 23))
        #expect(!status.isPeak)
        #expect(status.label.contains("9h"))
    }

    @Test("Saturday morning — 46h to Monday peak (weekend skip)")
    func saturdayMorning() {
        let status = ClaudePeakHours.status(at: self.date(day: 28, hour: 10))
        #expect(!status.isPeak)
        #expect(status.label.contains("46h"))
    }

    @Test("Sunday evening — 11h to Monday peak")
    func sundayEvening() {
        let status = ClaudePeakHours.status(at: self.date(day: 29, hour: 21))
        #expect(!status.isPeak)
        #expect(status.label.contains("11h"))
    }

    @Test("Friday after peak — 65h skip to Monday (full weekend)")
    func fridayAfterPeak() {
        let status = ClaudePeakHours.status(at: self.date(day: 27, hour: 15))
        #expect(!status.isPeak)
        #expect(status.label.contains("65h"))
    }

    @Test("Friday peak — same window as other weekdays")
    func fridayPeak() {
        let status = ClaudePeakHours.status(at: self.date(day: 27, hour: 12))
        #expect(status.isPeak)
        #expect(status.label.contains("2h"))
    }

    /// Cause: DST transitions (spring forward / fall back) on
    /// America/New_York could shift the calculated hour offset. Pin
    /// behavior on a known DST weekend so we'd notice a Calendar API
    /// regression.
    @Test("Spring forward weekend (Sunday before DST)")
    func springForwardWeekend() {
        let status = ClaudePeakHours.status(at: self.date(day: 7, hour: 10))
        #expect(!status.isPeak)
        #expect(status.label.contains("45h"))
    }

    @Test("Monday midnight — 8h to peak")
    func mondayMidnight() {
        let status = ClaudePeakHours.status(at: self.date(day: 23, hour: 0))
        #expect(!status.isPeak)
        #expect(status.label.contains("8h"))
    }

    @Test("Peak with minute granularity (12:15 → 1h 45m left)")
    func peakWithMinuteGranularity() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 12, minute: 15))
        #expect(status.isPeak)
        #expect(status.label.contains("1h 45m"))
    }

    @Test("Saturday midnight — 56h to Monday peak")
    func saturdayMidnight() {
        let status = ClaudePeakHours.status(at: self.date(day: 28, hour: 0))
        #expect(!status.isPeak)
        #expect(status.label.contains("56h"))
    }

    /// Cause: seconds-granularity rounding. Floor-to-minute truncation
    /// in `dateInterval(of: .minute, for:)` MUST keep the seconds value
    /// from rolling the minute count up — otherwise "1m" countdowns
    /// would jitter as the seconds tick.
    @Test("Weekday 7:45:30 → still 15m before peak (seconds floored)")
    func secondsFlooredToMinute() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 7, minute: 45, second: 30))
        #expect(!status.isPeak)
        #expect(status.label.contains("15m"))
    }

    @Test("Weekday 7:59:30 → 1m before peak")
    func oneMinuteBeforePeakWithSeconds() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 7, minute: 59, second: 30))
        #expect(!status.isPeak)
        #expect(status.label.contains("1m"))
    }

    @Test("Weekday 7:59:59 → still 1m before peak (last second)")
    func lastSecondBeforePeak() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 7, minute: 59, second: 59))
        #expect(!status.isPeak)
        #expect(status.label.contains("1m"))
    }

    @Test("Weekday peak start with seconds (8:00:30)")
    func peakStartWithSeconds() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 8, minute: 0, second: 30))
        #expect(status.isPeak)
        #expect(status.label.contains("6h"))
    }

    /// All labels must be non-empty regardless of locale. Sanity check
    /// against a future regression where someone removes the
    /// `String(localized:)` fallback and a missing key produces "".
    @Test("Cause: label is never empty across the day cycle")
    func labelNeverEmpty() {
        for hour in 0..<24 {
            let status = ClaudePeakHours.status(at: self.date(day: 25, hour: hour))
            #expect(!status.label.isEmpty, "label was empty at hour=\(hour)")
        }
    }
}
