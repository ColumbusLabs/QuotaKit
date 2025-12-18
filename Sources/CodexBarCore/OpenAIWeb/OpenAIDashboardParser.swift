import Foundation

public enum OpenAIDashboardParser {
    public static func parseCodeReviewRemainingPercent(bodyText: String) -> Double? {
        let cleaned = bodyText.replacingOccurrences(of: "\r", with: "\n")
        let patterns = [
            #"Code\s*review[^0-9%]*([0-9]{1,3})%\s*remaining"#,
            #"Core\s*review[^0-9%]*([0-9]{1,3})%\s*remaining"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            guard let match = regex.firstMatch(in: cleaned, options: [], range: range),
                  match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: cleaned)
            else { continue }
            if let val = Double(cleaned[r]) { return min(100, max(0, val)) }
        }
        return nil
    }

    public static func parseCreditEvents(rows: [[String]]) -> [CreditEvent] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"

        return rows.compactMap { row in
            guard row.count >= 3 else { return nil }
            let dateString = row[0]
            let service = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let amountString = row[2]
            guard let date = formatter.date(from: dateString) else { return nil }
            let creditsUsed = Self.parseCreditsUsed(amountString)
            return CreditEvent(date: date, service: service, creditsUsed: creditsUsed)
        }
        .sorted { $0.date > $1.date }
    }

    private static func parseCreditsUsed(_ text: String) -> Double {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "credits", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned) ?? 0
    }
}
