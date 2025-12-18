import Foundation

public enum OpenAIDashboardParser {
    /// Extracts the signed-in email from the embedded `client-bootstrap` JSON payload, if present.
    ///
    /// The Codex usage dashboard currently ships a JSON blob in:
    /// `<script type="application/json" id="client-bootstrap">…</script>`.
    /// WebKit `document.body.innerText` often does not include the email, so we parse it from HTML.
    public static func parseSignedInEmailFromClientBootstrap(html: String) -> String? {
        guard let data = self.clientBootstrapJSONData(fromHTML: html) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }

        // Fast path: common structure.
        if let dict = json as? [String: Any] {
            if let session = dict["session"] as? [String: Any],
               let user = session["user"] as? [String: Any],
               let email = user["email"] as? String,
               email.contains("@")
            {
                return email.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let user = dict["user"] as? [String: Any],
               let email = user["email"] as? String,
               email.contains("@")
            {
                return email.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Fallback: BFS scan for an email key/value.
        var queue: [Any] = [json]
        var seen = 0
        while !queue.isEmpty, seen < 4000 {
            let cur = queue.removeFirst()
            seen += 1
            if let dict = cur as? [String: Any] {
                for (k, v) in dict {
                    if k.lowercased() == "email", let email = v as? String, email.contains("@") {
                        return email.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    queue.append(v)
                }
            } else if let arr = cur as? [Any] {
                queue.append(contentsOf: arr)
            }
        }
        return nil
    }

    /// Extracts the auth status from `client-bootstrap`, if present.
    /// Expected values include `logged_in` and `logged_out`.
    public static func parseAuthStatusFromClientBootstrap(html: String) -> String? {
        guard let data = self.clientBootstrapJSONData(fromHTML: html) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard let dict = json as? [String: Any] else { return nil }
        if let authStatus = dict["authStatus"] as? String, !authStatus.isEmpty {
            return authStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

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

    // MARK: - Private

    private static func clientBootstrapJSONData(fromHTML html: String) -> Data? {
        let needle = "id=\"client-bootstrap\""
        guard let idRange = html.range(of: needle) else { return nil }

        // Find the end of the opening <script ...> tag.
        guard let openTagEnd = html[idRange.lowerBound...].firstIndex(of: ">") else { return nil }
        let contentStart = html.index(after: openTagEnd)

        guard let closeRange = html.range(of: "</script>", range: contentStart..<html.endIndex) else { return nil }
        let raw = html[contentStart..<closeRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return Data(raw.utf8)
    }
}
