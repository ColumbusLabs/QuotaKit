import Foundation

enum MobileResetCountdownFormatter {
    static func resetLine(from date: Date, now: Date = .init()) -> String {
        String(
            format: String(localized: "Resets %@"),
            self.countdownDescription(from: date, now: now))
    }

    static func countdownDescription(from date: Date, now: Date = .init()) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        if seconds < 1 { return String(localized: "now") }

        let totalMinutes = max(1, Int(ceil(seconds / 60.0)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60

        if days > 0 {
            if hours > 0 {
                return String(
                    format: String(localized: "in %lldd %lldh"),
                    Int64(days),
                    Int64(hours))
            }
            return String(
                format: String(localized: "in %lldd"),
                Int64(days))
        }
        if hours > 0 {
            if minutes > 0 {
                return String(
                    format: String(localized: "in %lldh %lldm"),
                    Int64(hours),
                    Int64(minutes))
            }
            return String(
                format: String(localized: "in %lldh"),
                Int64(hours))
        }
        return String(
            format: String(localized: "in %lldm"),
            Int64(totalMinutes))
    }
}

enum WidgetWindowBadgeFormatter {
    static func label(
        for window: QuotaKitWidgetSnapshot.Provider.Window,
        displayMode: QuotaKitWidgetDisplayMode) -> String
    {
        if let duration = self.durationLabel(from: window.title) {
            return duration
        }

        switch displayMode {
        case .weekly:
            return "7D"
        case .session, .both:
            return displayMode.localizedTitle
        }
    }

    private static func durationLabel(from title: String) -> String? {
        let tokens = title
            .localizedLowercase
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split { !$0.isLetter && !$0.isNumber }

        for (index, token) in tokens.enumerated() {
            let text = String(token)
            if let compact = self.compactDurationToken(text) {
                return compact
            }

            guard text.allSatisfy(\.isNumber),
                  index + 1 < tokens.count,
                  let unit = self.unitLabel(for: String(tokens[index + 1]))
            else { continue }
            return "\(text)\(unit)"
        }
        return nil
    }

    private static func compactDurationToken(_ token: String) -> String? {
        let digits = token.prefix(while: \.isNumber)
        guard !digits.isEmpty,
              let unit = self.unitLabel(for: String(token.dropFirst(digits.count)))
        else { return nil }
        return "\(digits)\(unit)"
    }

    private static func unitLabel(for token: String) -> String? {
        if token == "h" || token.hasPrefix("hour") { return "H" }
        if token == "d" || token.hasPrefix("day") { return "D" }
        if token == "w" || token.hasPrefix("week") { return "W" }
        return nil
    }
}
