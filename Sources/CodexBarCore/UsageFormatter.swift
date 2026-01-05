import Foundation

public enum ResetTimeDisplayStyle: String, Codable, Sendable {
    case countdown
    case absolute
}

public enum UsageFormatter {
    public static func usageLine(remaining: Double, used: Double) -> String {
        String(format: "%.0f%% left", remaining)
    }

    public static func resetCountdownDescription(from date: Date, now: Date = .init()) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        if seconds < 1 { return "now" }

        let totalMinutes = max(1, Int(ceil(seconds / 60.0)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60

        if days > 0 {
            if hours > 0 { return "in \(days)d \(hours)h" }
            return "in \(days)d"
        }
        if hours > 0 {
            if minutes > 0 { return "in \(hours)h \(minutes)m" }
            return "in \(hours)h"
        }
        return "in \(totalMinutes)m"
    }

    public static func resetDescription(from date: Date, now: Date = .init()) -> String {
        // Human-friendly phrasing: today / tomorrow / date+time.
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow)
        {
            return "tomorrow, \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    public static func resetLine(
        for window: RateWindow,
        style: ResetTimeDisplayStyle,
        now: Date = .init()) -> String?
    {
        if let date = window.resetsAt {
            let text = style == .countdown
                ? self.resetCountdownDescription(from: date, now: now)
                : self.resetDescription(from: date, now: now)
            return "Resets \(text)"
        }

        if let desc = window.resetDescription {
            let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.lowercased().hasPrefix("resets") { return trimmed }
            return "Resets \(trimmed)"
        }
        return nil
    }

    public static func updatedString(from date: Date, now: Date = .init()) -> String {
        let delta = now.timeIntervalSince(date)
        if abs(delta) < 60 {
            return "Updated just now"
        }
        if let hours = Calendar.current.dateComponents([.hour], from: date, to: now).hour, hours < 24 {
            #if os(macOS)
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .abbreviated
            return "Updated \(rel.localizedString(for: date, relativeTo: now))"
            #else
            let seconds = max(0, Int(now.timeIntervalSince(date)))
            if seconds < 3600 {
                let minutes = max(1, seconds / 60)
                return "Updated \(minutes)m ago"
            }
            let wholeHours = max(1, seconds / 3600)
            return "Updated \(wholeHours)h ago"
            #endif
        } else {
            return "Updated \(date.formatted(date: .omitted, time: .shortened))"
        }
    }

    public static func creditsString(from value: Double) -> String {
        let number = NumberFormatter()
        number.numberStyle = .decimal
        number.maximumFractionDigits = 2
        // Use explicit locale for consistent formatting on all systems
        number.locale = Locale(identifier: "en_US_POSIX")
        let formatted = number.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "\(formatted) left"
    }

    /// Formats a USD value with proper negative handling and thousand separators.
    /// Uses direct string formatting to avoid NumberFormatter nil issues on non-US locales.
    /// See: https://developer.apple.com/forums/thread/731057
    public static func usdString(_ value: Double) -> String {
        formatUSD(value)
    }

    public static func currencyString(_ value: Double, currencyCode: String) -> String {
        // For USD, use direct string formatting to avoid locale-related NumberFormatter issues.
        // NumberFormatter with .currency style can return nil on some non-US locales (e.g., pt-BR)
        // even when explicitly setting locale to en_US_POSIX.
        // See: https://developer.apple.com/forums/thread/731057
        if currencyCode == "USD" {
            return formatUSD(value)
        }

        // For other currencies, try NumberFormatter but fall back to simple format if needed
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let formatted = formatter.string(from: NSNumber(value: value)) {
            return formatted
        }

        // Robust fallback for non-USD currencies
        return "\(currencyCode) \(String(format: "%.2f", value))"
    }

    /// Formats USD values with proper negative sign placement and optional thousand separators.
    /// Handles: -$1,234.56 (not $-1,234.56), $0.00, $54.72
    private static func formatUSD(_ value: Double) -> String {
        let isNegative = value < 0
        let absValue = abs(value)

        // Format with 2 decimal places
        let formatted = String(format: "%.2f", absValue)

        // Add thousand separators for values >= 1000
        let withSeparators: String
        if absValue >= 1000 {
            let parts = formatted.split(separator: ".")
            let integerPart = String(parts[0])
            let decimalPart = parts.count > 1 ? String(parts[1]) : "00"

            // Insert commas every 3 digits from the right
            var result = ""
            for (index, char) in integerPart.reversed().enumerated() {
                if index > 0 && index % 3 == 0 {
                    result = "," + result
                }
                result = String(char) + result
            }
            withSeparators = "\(result).\(decimalPart)"
        } else {
            withSeparators = formatted
        }

        // Place negative sign before dollar sign: -$54.72 (not $-54.72)
        return isNegative ? "-$\(withSeparators)" : "$\(withSeparators)"
    }

    public static func tokenCountString(_ value: Int) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""

        let units: [(threshold: Int, divisor: Double, suffix: String)] = [
            (1_000_000_000, 1_000_000_000, "B"),
            (1_000_000, 1_000_000, "M"),
            (1000, 1000, "K"),
        ]

        for unit in units where absValue >= unit.threshold {
            let scaled = Double(absValue) / unit.divisor
            let formatted: String
            if scaled >= 10 {
                formatted = String(format: "%.0f", scaled)
            } else {
                var s = String(format: "%.1f", scaled)
                if s.hasSuffix(".0") { s.removeLast(2) }
                formatted = s
            }
            return "\(sign)\(formatted)\(unit.suffix)"
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func creditEventSummary(_ event: CreditEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let number = NumberFormatter()
        number.numberStyle = .decimal
        number.maximumFractionDigits = 2
        number.locale = Locale(identifier: "en_US_POSIX")
        let credits = number.string(from: NSNumber(value: event.creditsUsed)) ?? "0"
        return "\(formatter.string(from: event.date)) · \(event.service) · \(credits) credits"
    }

    public static func creditEventCompact(_ event: CreditEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let number = NumberFormatter()
        number.numberStyle = .decimal
        number.maximumFractionDigits = 2
        number.locale = Locale(identifier: "en_US_POSIX")
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

    public static func modelDisplayName(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return raw }

        let patterns = [
            #"(?:-|\s)\d{8}$"#,
            #"(?:-|\s)\d{4}-\d{2}-\d{2}$"#,
            #"\s\d{4}\s\d{4}$"#,
        ]

        for pattern in patterns {
            if let range = cleaned.range(of: pattern, options: .regularExpression) {
                cleaned.removeSubrange(range)
                break
            }
        }

        if let trailing = cleaned.range(of: #"[ \t-]+$"#, options: .regularExpression) {
            cleaned.removeSubrange(trailing)
        }

        return cleaned.isEmpty ? raw : cleaned
    }

    /// Cleans a provider plan string: strip ANSI/bracket noise, drop boilerplate words, collapse whitespace, and
    /// ensure a leading capital if the result starts lowercase.
    public static func cleanPlanName(_ text: String) -> String {
        let stripped = TextParsing.stripANSICodes(text)
        let withoutCodes = stripped.replacingOccurrences(
            of: #"^\s*(?:\[\d{1,3}m\s*)+"#,
            with: "",
            options: [.regularExpression])
        let withoutBoilerplate = withoutCodes.replacingOccurrences(
            of: #"(?i)\b(claude|codex|account|plan)\b"#,
            with: "",
            options: [.regularExpression])
        var cleaned = withoutBoilerplate
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            cleaned = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.lowercased() == "oauth" {
            return "Ollama"
        }
        // Capitalize first letter only if lowercase, preserving acronyms like "AI"
        if let first = cleaned.first, first.isLowercase {
            return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
        return cleaned
    }
}
