import Foundation

public enum UsageFormatter {
    public static func usageLine(remaining: Double, used: Double) -> String {
        String(format: "%.0f%% left", remaining)
    }

    public static func resetDescription(from date: Date, now: Date = .init()) -> String {
        // Human-friendly phrasing: today / tomorrow / date+time.
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return "today at \(date.formatted(date: .omitted, time: .shortened))"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow)
        {
            return "tomorrow at \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    public static func updatedString(from date: Date, now: Date = .init()) -> String {
        let delta = now.timeIntervalSince(date)
        if abs(delta) < 60 {
            return "Updated just now"
        }
        if let hours = Calendar.current.dateComponents([.hour], from: date, to: now).hour, hours < 24 {
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .abbreviated
            return "Updated \(rel.localizedString(for: date, relativeTo: now))"
        } else {
            return "Updated \(date.formatted(date: .omitted, time: .shortened))"
        }
    }

    public static func creditsString(from value: Double) -> String {
        let number = NumberFormatter()
        number.numberStyle = .decimal
        number.maximumFractionDigits = 2
        let formatted = number.string(from: NSNumber(value: value)) ?? String(Int(value))
        return "\(formatted) left"
    }

    public static func creditEventSummary(_ event: CreditEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let number = NumberFormatter()
        number.numberStyle = .decimal
        number.maximumFractionDigits = 2
        let credits = number.string(from: NSNumber(value: event.creditsUsed)) ?? "0"
        return "\(formatter.string(from: event.date)) · \(event.service) · \(credits) credits"
    }

    public static func creditEventCompact(_ event: CreditEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let number = NumberFormatter()
        number.numberStyle = .decimal
        number.maximumFractionDigits = 2
        let credits = number.string(from: NSNumber(value: event.creditsUsed)) ?? "0"
        return "\(formatter.string(from: event.date)) — \(event.service): \(credits)"
    }

    public static func creditShort(_ value: Double) -> String {
        if value >= 1000 {
            let k = value / 1000
            return String(format: "%.1fk", k)
        }
        return String(format: "%.0f", value)
    }

    public static func truncatedSingleLine(_ text: String, max: Int = 80) -> String {
        let single = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard single.count > max else { return single }
        let idx = single.index(single.startIndex, offsetBy: max)
        return "\(single[..<idx])…"
    }
}
