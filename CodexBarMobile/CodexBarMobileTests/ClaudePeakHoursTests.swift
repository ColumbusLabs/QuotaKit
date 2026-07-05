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

    @Test
    func `Weekday morning before peak: isPeak=false, ~1h remaining`() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 7))
        #expect(!status.isPeak)
        #expect(status.label.contains("1h"))
    }

    @Test
    func `Weekday just before peak: 15m countdown`() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 7, minute: 45))
        #expect(!status.isPeak)
        #expect(status.label.contains("15m"))
    }

    @Test
    func `Weekday peak start: isPeak=true, 6h remaining`() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 8))
        #expect(status.isPeak)
        #expect(status.label.contains("6h"))
    }

    @Test
    func `Weekday mid-peak: 2h 30m remaining`() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 11, minute: 30))
        #expect(status.isPeak)
        #expect(status.label.contains("2h 30m"))
    }

    @Test
    func `Weekday peak end boundary (13:59 ET) — still peak with 1m left`() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 13, minute: 59))
        #expect(status.isPeak)
        #expect(status.label.contains("1m"))
    }

    @Test
    func `Weekday 14:00 ET — peak just ended, 18h to next`() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 14))
        #expect(!status.isPeak)
        #expect(status.label.contains("18h"))
    }

    @Test
    func `Weekday late evening — 9h to next morning peak`() {
        let status = ClaudePeakHours.status(at: self.date(day: 26, hour: 23))
        #expect(!status.isPeak)
        #expect(status.label.contains("9h"))
    }

    @Test
    func `Saturday morning — 46h to Monday peak (weekend skip)`() {
        let status = ClaudePeakHours.status(at: self.date(day: 28, hour: 10))
        #expect(!status.isPeak)
        #expect(status.label.contains("46h"))
    }

    @Test
    func `Sunday evening — 11h to Monday peak`() {
        let status = ClaudePeakHours.status(at: self.date(day: 29, hour: 21))
        #expect(!status.isPeak)
        #expect(status.label.contains("11h"))
    }

    @Test
    func `Friday after peak — 65h skip to Monday (full weekend)`() {
        let status = ClaudePeakHours.status(at: self.date(day: 27, hour: 15))
        #expect(!status.isPeak)
        #expect(status.label.contains("65h"))
    }

    @Test
    func `Friday peak — same window as other weekdays`() {
        let status = ClaudePeakHours.status(at: self.date(day: 27, hour: 12))
        #expect(status.isPeak)
        #expect(status.label.contains("2h"))
    }

    /// Cause: DST transitions (spring forward / fall back) on
    /// America/New_York could shift the calculated hour offset. Pin
    /// behavior on a known DST weekend so we'd notice a Calendar API
    /// regression.
    @Test
    func `Spring forward weekend (Sunday before DST)`() {
        let status = ClaudePeakHours.status(at: self.date(day: 7, hour: 10))
        #expect(!status.isPeak)
        #expect(status.label.contains("45h"))
    }

    @Test
    func `Monday midnight — 8h to peak`() {
        let status = ClaudePeakHours.status(at: self.date(day: 23, hour: 0))
        #expect(!status.isPeak)
        #expect(status.label.contains("8h"))
    }

    @Test
    func `Peak with minute granularity (12:15 → 1h 45m left)`() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 12, minute: 15))
        #expect(status.isPeak)
        #expect(status.label.contains("1h 45m"))
    }

    @Test
    func `Saturday midnight — 56h to Monday peak`() {
        let status = ClaudePeakHours.status(at: self.date(day: 28, hour: 0))
        #expect(!status.isPeak)
        #expect(status.label.contains("56h"))
    }

    /// Cause: seconds-granularity rounding. Floor-to-minute truncation
    /// in `dateInterval(of: .minute, for:)` MUST keep the seconds value
    /// from rolling the minute count up — otherwise "1m" countdowns
    /// would jitter as the seconds tick.
    @Test
    func `Weekday 7:45:30 → still 15m before peak (seconds floored)`() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 7, minute: 45, second: 30))
        #expect(!status.isPeak)
        #expect(status.label.contains("15m"))
    }

    @Test
    func `Weekday 7:59:30 → 1m before peak`() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 7, minute: 59, second: 30))
        #expect(!status.isPeak)
        #expect(status.label.contains("1m"))
    }

    @Test
    func `Weekday 7:59:59 → still 1m before peak (last second)`() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 7, minute: 59, second: 59))
        #expect(!status.isPeak)
        #expect(status.label.contains("1m"))
    }

    @Test
    func `Weekday peak start with seconds (8:00:30)`() {
        let status = ClaudePeakHours.status(at: self.date(day: 25, hour: 8, minute: 0, second: 30))
        #expect(status.isPeak)
        #expect(status.label.contains("6h"))
    }

    /// All labels must be non-empty regardless of locale. Sanity check
    /// against a future regression where someone removes the
    /// `String(localized:)` fallback and a missing key produces "".
    @Test
    func `Cause: label is never empty across the day cycle`() {
        for hour in 0..<24 {
            let status = ClaudePeakHours.status(at: self.date(day: 25, hour: hour))
            #expect(!status.label.isEmpty, "label was empty at hour=\(hour)")
        }
    }
}
