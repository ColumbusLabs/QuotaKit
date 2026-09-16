import Foundation

/// Inclusive producer-local day window for a rolling cost-history snapshot.
///
/// Keys are zero-padded `yyyy-MM-dd` strings in the snapshot's bucket calendar, so containment
/// and ordering are plain string comparisons. Day arithmetic goes through the calendar instead
/// of elapsed seconds so DST and time-zone boundaries stay on the correct local day.
public struct CostUsageDayWindow: Sendable, Equatable {
    public let sinceKey: String
    public let untilKey: String

    public init(sinceKey: String, untilKey: String) {
        self.sinceKey = sinceKey
        self.untilKey = untilKey
    }

    public func contains(_ dayKey: String) -> Bool {
        dayKey >= self.sinceKey && dayKey <= self.untilKey
    }

    /// Normalizes a daily entry's date (a `yyyy-MM-dd` key or a parseable timestamp) to the
    /// local day key in `calendar`, or `nil` when the raw value cannot be interpreted.
    public func normalizedDayKey(
        forEntryDate rawDate: String,
        calendar: Calendar = .current) -> String?
    {
        CostUsageLocalDay.key(fromEntryDate: rawDate, calendar: calendar)
    }

    public func contains(entryDate rawDate: String, calendar: Calendar = .current) -> Bool {
        guard let dayKey = self.normalizedDayKey(forEntryDate: rawDate, calendar: calendar)
        else { return false }
        return self.contains(dayKey)
    }

    /// Returns `dayKey` moved by `days` local calendar days in `calendar`.
    public static func dayKey(
        _ dayKey: String,
        advancedBy days: Int,
        calendar: Calendar = .current) -> String?
    {
        guard days != 0 else { return dayKey }
        guard let date = CostUsageScanner.parseDayKey(dayKey, calendar: calendar),
              let advanced = calendar.date(byAdding: .day, value: days, to: date)
        else { return nil }
        return CostUsageLocalDay.key(from: advanced, calendar: calendar)
    }
}

extension CostUsageTokenSnapshot {
    /// The inclusive local-day window this snapshot claims to cover.
    ///
    /// Prefers the exact producer bounds recorded at fetch time. Snapshots persisted before
    /// those bounds existed fall back to the `updatedAt` anchor and the requested
    /// `historyDays`, mirroring how `summary(forLastDays:)` derives its window.
    public func historyDayWindow(calendar: Calendar = .current) -> CostUsageDayWindow {
        if let sinceKey = self.historySinceDayKey,
           let untilKey = self.historyUntilDayKey,
           sinceKey <= untilKey
        {
            return CostUsageDayWindow(sinceKey: sinceKey, untilKey: untilKey)
        }
        let days = max(1, min(365, self.historyDays))
        let since = calendar.date(byAdding: .day, value: -(days - 1), to: self.updatedAt)
            ?? self.updatedAt
        return CostUsageDayWindow(
            sinceKey: CostUsageLocalDay.key(from: since, calendar: calendar),
            untilKey: CostUsageLocalDay.key(from: self.updatedAt, calendar: calendar))
    }
}
