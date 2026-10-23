import CodexBarCore
import CodexBarSync
import Foundation

/// A display-only allowlist for billing details that have no dedicated phone payload.
/// Values never become quota windows, budgets, or notification inputs.
enum SyncProviderBillingDetails {
    private enum ValueKind {
        case count
        case number
        case dollars(allowNegative: Bool)
        case credits
        case creditCount
        case creditLimit
        case allowance
        case month
        case resetDate
        case balance
        case currencyAmount(allowNegative: Bool, allowUnavailable: Bool)
        case fixed(Set<String>)
    }

    private struct SectionRule {
        let title: String
        let rows: [(String, ValueKind)]
    }

    static func map(provider: UsageProvider, snapshot: UsageSnapshot?) -> [SyncProviderDetailSection]? {
        guard let rules = self.rules(for: provider), let snapshot else { return nil }
        // The fixed rules bound both section and row counts. Merge duplicate input sections and
        // keep the first valid value per field; invalid duplicates cannot shadow a valid balance.
        // Successful empty results intentionally return [] so stored details can be cleared.
        return rules.compactMap { rule in
            let candidates = snapshot.details.filter { $0.title == rule.title }.flatMap(\.rows)
            let rows = rule.rows.compactMap { label, kind -> SyncProviderDetailSection.Row? in
                guard let row = candidates.first(where: { $0.label == label && self.isValid($0.value, kind: kind) })
                else { return nil }
                // No secondary values, chart data, IDs, progress, or actions cross this boundary.
                return .init(label: label, value: row.value)
            }
            return rows.isEmpty ? nil : SyncProviderDetailSection(title: rule.title, rows: rows)
        }
    }

    private static func rules(for provider: UsageProvider) -> [SectionRule]? {
        // Provider-specific by design: the mobile wire has no general billing schema;
        // each provider maps only explicit safe rows.
        switch provider {
        case .tavily:
            ["Account plan", "API key", "Pay as you go"].map {
                SectionRule(
                    title: $0,
                    rows: [("Used", .creditCount), ("Limit", .creditLimit), ("Remaining", .creditCount)])
            }
        case .exa:
            [.init(title: "API key this month (UTC)", rows: [("Spend", .dollars(allowNegative: false))])]
        case .linkup:
            [.init(title: "Account balance", rows: [("Credit balance", .dollars(allowNegative: true))])]
        case .tinyapi:
            [.init(title: "Credits", rows: [("Available credits", .credits)])]
        case .cosmic:
            ["Input tokens", "Output tokens"].map {
                SectionRule(title: $0, rows: [
                    ("Used", .count), ("Allowance", .allowance), ("Remaining", .count), ("Above allowance", .count),
                ])
            }
        case .aerostack:
            [.init(title: "Monthly AI tokens", rows: [
                ("Tokens used", .count), ("Allowance", .count), ("Remaining", .count),
                ("Above allowance", .count), ("Period", .month),
            ])]
        case .sailresearch:
            [.init(title: "Organization billing", rows: [
                ("Credit balance", .balance), ("Last hour spend", .dollars(allowNegative: false)),
                ("Last 6 hours spend", .dollars(allowNegative: false)),
                ("Last 24 hours spend", .dollars(allowNegative: false)),
                ("Last 7 days spend", .dollars(allowNegative: false)),
                ("Last 30 days spend", .dollars(allowNegative: false)),
                ("Billing-period spend", .dollars(allowNegative: false)),
            ])]
        case .sofya:
            [.init(title: "Account credits", rows: [
                ("Available credits", .number), ("Plan credits", .number), ("Purchased credits", .number),
                ("Monthly reset", .resetDate),
            ])]
        case .ollama:
            // Refill prose stays local; only complete wallet amounts are exported.
            [.init(title: "Credits", rows: [
                ("Credit balance", .dollars(allowNegative: false)),
                ("Monthly credits used", .dollars(allowNegative: false)),
            ])]
        // Provider-specific by design: typed display-only rows retain JetBrains top-up, xAI's estimate,
        // fal/FLORA and Parallel billing fields, and Claude Console's monthly spend details.
        case .jetbrains:
            [.init(title: "Top-up credits", rows: [("Remaining", .credits)])]
        case .xai:
            // The invoice preview is display-only enrichment; do not sync the posted balance or spend history here.
            [.init(title: "Billing summary", rows: [("Live remaining (est.)", .dollars(allowNegative: true))])]
        case .fal:
            [.init(title: "Account balance", rows: [
                ("Credit balance", .currencyAmount(allowNegative: true, allowUnavailable: false)),
            ])]
        case .flora:
            [.init(title: "Workspace balance", rows: [
                ("Available", .currencyAmount(allowNegative: true, allowUnavailable: false)),
                ("Member limit", .currencyAmount(allowNegative: false, allowUnavailable: false)),
                ("Spent this month", .currencyAmount(allowNegative: false, allowUnavailable: true)),
                ("Runs this month", .count),
            ])]
        case .parallel:
            [.init(title: "Account balance", rows: [
                ("Balance", .currencyAmount(allowNegative: true, allowUnavailable: false)),
                ("Pending debit", .currencyAmount(allowNegative: true, allowUnavailable: false)),
            ])]
        case .claudeplatform:
            [.init(title: "Billing", rows: [
                ("This month (UTC)", .currencyAmount(allowNegative: false, allowUnavailable: false)),
                ("Spend", .currencyAmount(allowNegative: false, allowUnavailable: true)),
            ])]
        case .soniox:
            [.init(title: "Billing", rows: [
                ("Prepaid", .fixed(["USD"])), ("Invoice billing", .fixed(["USD"])),
                ("Available balance", .dollars(allowNegative: true)),
                ("Monthly spend", .dollars(allowNegative: false)),
                ("Monthly budget", .dollars(allowNegative: false)),
            ])]
        case .traecn:
            [.init(title: "Credits", rows: [
                ("Used", .number), ("Total", .number), ("Remaining", .number),
            ])]
        default:
            nil
        }
    }

    private static func isValid(_ value: String, kind: ValueKind) -> Bool {
        guard !value.isEmpty, value.count <= 96 else { return false }
        switch kind {
        case .count:
            guard self.matches(value, #"^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)$"#) else { return false }
            return self.number(value).map { $0 <= 9_007_199_254_740_991 } ?? false
        case .number:
            return self.number(value).map { $0 >= 0 } ?? false
        case let .dollars(allowNegative):
            // USD formatting is explicitly en-US in the source plugins. Reject currency ambiguity,
            // suffixes, scientific notation, and arbitrary prose even under an allowed row label.
            guard self.matches(value, #"^-?\$(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]+)?$"#),
                  let amount = self.number(value.replacingOccurrences(of: "$", with: ""))
            else { return false }
            return allowNegative || amount >= 0
        case .credits:
            guard value.hasSuffix(" credits") else { return false }
            return self.number(String(value.dropLast(" credits".count))).map { $0 >= 0 } ?? false
        case .creditCount:
            guard value.hasSuffix(" credits") else { return false }
            return self.isValid(String(value.dropLast(" credits".count)), kind: .count)
        case .creditLimit:
            return value == "Unlimited" || self.isValid(value, kind: .creditCount)
        case .allowance:
            return value == "Unlimited" || value == "Not reported" || self.isValid(value, kind: .count)
        case .month:
            return self.matches(value, #"^[0-9]{4}-(?:0[1-9]|1[0-2])$"#)
        case .resetDate:
            return self.isResetDate(value)
        case .balance:
            return value == "Unavailable" || self.isValid(value, kind: .dollars(allowNegative: true))
        case let .currencyAmount(allowNegative, allowUnavailable):
            if allowUnavailable, value == "Unavailable" { return true }
            // Source plugins use en-US currency formatting. Preserve the currency symbol but reject prose,
            // localized suffixes, ungrouped junk, and non-finite numeric values.
            let prefixPattern = #"^-?(?:(?:[A-Z]{1,3}\s?)?\p{Sc}|[A-Z]{3}\s?)"#
            let amountPattern = #"(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]+)?$"#
            guard self.matches(value, prefixPattern + amountPattern) else { return false }
            let numeric = value.replacingOccurrences(
                of: prefixPattern,
                with: "",
                options: .regularExpression)
            let signed = value.hasPrefix("-") ? "-\(numeric)" : numeric
            return self.number(signed).map { allowNegative || $0 >= 0 } ?? false
        case let .fixed(values):
            return values.contains(value)
        }
    }

    private static func number(_ value: String) -> Double? {
        guard self.matches(value, #"^-?(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]+)?$"#),
              let number = Double(value.replacingOccurrences(of: ",", with: "")), number.isFinite
        else { return nil }
        return number
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isResetDate(_ value: String) -> Bool {
        guard self.matches(value, #"^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{3})? UTC$"#)
        else { return false }
        let iso = value.replacingOccurrences(of: " ", with: "T", range: value.range(of: " "))
            .replacingOccurrences(of: " UTC", with: "Z")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = value.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] :
            [.withInternetDateTime]
        guard let date = formatter.date(from: iso) else { return false }
        // Date parsers may normalize impossible civil dates; require the same calendar components.
        let calendar = DateFormatter()
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)
        calendar.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return calendar.string(from: date) == String(value.prefix(19))
    }
}
