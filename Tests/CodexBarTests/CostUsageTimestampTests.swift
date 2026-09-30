import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageTimestampTests {
    private static func formatterDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return fractional.date(from: text) ?? plain.date(from: text)
    }

    @Test
    func `native RFC3339 parser matches formatter precision`() {
        for year in [1900, 1960, 1969, 1970, 2000, 2024, 2026, 2100, 2400, 9999] {
            for monthDay in ["01-01", "02-28", "03-01", "12-31"] {
                for time in ["00:00:00", "12:34:56", "23:59:59"] {
                    for fraction in ["", ".0", ".1", ".01", ".123", ".999", ".123456", ".999999999"] {
                        for zone in ["Z", "+00:00", "-00:00", "+05:30", "-08:00"] {
                            let text = "\(year)-\(monthDay)T\(time)\(fraction)\(zone)"
                            #expect(CostUsageScanner.dateFromTimestamp(text) == Self.formatterDate(text), "\(text)")
                        }
                    }
                }
            }
        }
    }

    @Test(arguments: [
        "2024-02-29T23:59:59.999Z", "2000-02-29T12:00:00Z",
        "2026-08-30T12:34:56+0530", "2026-08-30T12:34:56+05",
        "2026-08-30T12:34:56.123456789012Z", "1582-10-04T12:34:56Z",
        "0001-01-01T00:00:00Z", "2026-08-30T12:34:56+23:59",
        "2026-08-30T12:34:56Ztrailing", "2026-02-30T12:34:56Z",
        "1900-02-29T12:00:00Z", "2026-08-30T24:00:00Z",
        "2016-12-31T23:59:60Z", "", "2026-08-30", "not-a-date",
        "2026-08-30t12:34:56z", "2026-13-01T00:00:00Z",
        "2026-08-30T12:34:56.123", "2026-08-30T12:34:56+25:00",
    ])
    func `historical spellings and malformed values preserve formatter behavior`(_ text: String) {
        #expect(CostUsageScanner.dateFromTimestamp(text) == Self.formatterDate(text))
    }

    @Test(arguments: ["America/Los_Angeles", "Asia/Kolkata", "Pacific/Kiritimati", "UTC"])
    func `Claude date and day key come from the same parsed instant`(_ timeZone: String) throws {
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = try #require(TimeZone(identifier: timeZone))
        for text in [
            "2026-03-08T09:59:59.999999Z", "2026-03-08T10:00:00.000Z",
            "2026-11-01T08:59:59.999999Z", "2026-11-01T09:00:00Z",
            "2026-08-30T23:59:59.999999999-08:00", "2024-02-29T23:59:59.999+05:30",
            "1969-12-31T23:59:59.999999Z", "2026-08-30T12:34:56+0530",
            "2026-02-30T12:00:00Z",
        ] {
            guard let expectedDate = Self.formatterDate(text) else {
                #expect(CostUsageScanner.claudeTimestampAndDayKey(text, calendar: calendar) == nil)
                continue
            }
            let expectedDay = CostUsageScanner.dayKeyFromTimestamp(text, calendar: calendar)
                ?? CostUsageScanner.CostUsageDayRange.dayKey(from: expectedDate, calendar: calendar)
            let actual = try #require(CostUsageScanner.claudeTimestampAndDayKey(text, calendar: calendar))
            #expect(actual.date == expectedDate)
            #expect(actual.dayKey == expectedDay)
        }
    }
}
