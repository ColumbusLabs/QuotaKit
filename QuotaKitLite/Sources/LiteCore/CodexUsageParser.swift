import Foundation

/// Parses the `GET /backend-api/wham/usage` body (068 §2.1 "Codex request details", §4.2 step 3).
///
/// Follows `CodexUsageResponse` (`CodexOAuthUsageFetcher.swift`) and `CodexRateWindowNormalizer`. Every field is
/// read with `decodeIfPresent` and a failure to read one window never discards the other (§8). Only a body with no
/// usable window at all, or a body that isn't a JSON object, is an `unrecognizedResponse`.
public enum CodexUsageParser {
    public static func parse(_ data: Data, auth: CodexAuth) -> Result<ProbeResult, ProbeFailure> {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            return .failure(.unrecognizedResponse)
        }
        let slots = Self.assignSlots(
            primary: response.rateLimit?.primaryWindow,
            secondary: response.rateLimit?.secondaryWindow)
        var windows: [QuotaWindow] = []
        for (window, slot) in [(slots.session, QuotaWindow.Lane.session), (slots.weekly, .weekly)] {
            guard let window else { continue }
            // The weekly rule wins over the slot, as in the full app's sync mapping, so two 7-day windows
            // don't both claim the session lane. A lane already taken keeps its first window.
            let lane: QuotaWindow.Lane = window.minutes == Self.weeklyMinutes ? .weekly : slot
            guard !windows.contains(where: { $0.lane == lane }) else { continue }
            windows.append(QuotaWindow(
                label: lane == .weekly ? "Weekly" : "Session",
                lane: lane,
                usedPercent: window.usedPercent,
                windowMinutes: window.minutes,
                resetsAt: window.resetsAt))
        }
        guard !windows.isEmpty else { return .failure(.unrecognizedResponse) }
        return .success(ProbeResult(
            windows: windows,
            plan: CodexPlanName.displayName(response.planType),
            accountEmail: auth.email,
            accountIdentities: auth.accountIdentities))
    }

    // MARK: - Window mapping

    private static let sessionMinutes = 300
    private static let weeklyMinutes = 10080

    private enum Role {
        case session
        case weekly
        case unknown
    }

    private static func role(of window: RawWindow) -> Role {
        switch window.minutes {
        case self.sessionMinutes: .session
        case self.weeklyMinutes: .weekly
        default: .unknown
        }
    }

    /// Port of `CodexRateWindowNormalizer.normalize`. A 300-minute window fills the session slot and a
    /// 10080-minute window the weekly slot, whichever of `primary_window` / `secondary_window` carried it.
    /// A window of any other length keeps the slot its position implies (`primary_window` is the session slot,
    /// `secondary_window` the weekly one), unless it sits beside a known window that claims that slot. The label
    /// and lane follow the slot but `windowMinutes` stays the real length, so pace never assumes 5 hours for a
    /// 9-hour window.
    private static func assignSlots(
        primary: RawWindow?,
        secondary: RawWindow?) -> (session: RawWindow?, weekly: RawWindow?)
    {
        switch (primary, secondary) {
        case let (.some(first), .some(second)):
            switch (self.role(of: first), self.role(of: second)) {
            case (.weekly, .session), (.weekly, .unknown):
                (second, first)
            default:
                (first, second)
            }
        case let (.some(only), .none), let (.none, .some(only)):
            self.role(of: only) == .weekly ? (nil, only) : (only, nil)
        case (.none, .none):
            (nil, nil)
        }
    }

    // MARK: - Decoding

    private struct RawWindow: Decodable {
        let usedPercent: Double
        let resetsAt: Date?
        let minutes: Int
        private enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }

        /// Throws unless the window has a finite `used_percent` and a `limit_window_seconds` of at least a minute.
        /// `reset_at` is optional here (the full app requires it): a percentage without a reset time still shows.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let used = Self.flexibleDouble(container, .usedPercent), used.isFinite,
                  let seconds = Self.flexibleInt(container, .limitWindowSeconds), seconds >= 60
            else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unusable window"))
            }
            self.usedPercent = used
            self.minutes = seconds / 60
            self.resetsAt = Self.flexibleInt(container, .resetAt)
                .flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
        }

        private static func flexibleDouble(
            _ container: KeyedDecodingContainer<CodingKeys>,
            _ key: CodingKeys) -> Double?
        {
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return nil
        }

        private static func flexibleInt(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                return Int(exactly: value.rounded(.towardZero))
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return nil
        }
    }

    private struct Response: Decodable {
        let planType: String?
        let rateLimit: RateLimit?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.planType = try? container.decodeIfPresent(String.self, forKey: .planType)
            self.rateLimit = try? container.decodeIfPresent(RateLimit.self, forKey: .rateLimit)
        }
    }

    private struct RateLimit: Decodable {
        let primaryWindow: RawWindow?
        let secondaryWindow: RawWindow?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.primaryWindow = try? container.decodeIfPresent(RawWindow.self, forKey: .primaryWindow)
            self.secondaryWindow = try? container.decodeIfPresent(RawWindow.self, forKey: .secondaryWindow)
        }
    }
}

/// Plan-name display mapping, ported from `CodexPlanFormatting` (`Sources/CodexBarCore/Providers/Codex/`).
public enum CodexPlanName {
    private static let exactDisplayNames: [String: String] = [
        "pro": "Pro 20x",
        "prolite": "Pro 5x",
        "pro_lite": "Pro 5x",
        "pro-lite": "Pro 5x",
        "pro lite": "Pro 5x",
    ]

    private static let uppercaseWords: Set<String> = ["cbp", "k12"]

    /// "pro" is "Pro 20x", "prolite" is "Pro 5x", and anything else is title-cased word by word
    /// ("free_workspace" is "Free Workspace"). Nil for a missing or blank plan.
    public static func displayName(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let exact = Self.exactDisplayNames[raw.lowercased()] {
            return exact
        }
        let candidate = Self.cleaned(raw)
        if let exact = Self.exactDisplayNames[candidate.lowercased()] {
            return exact
        }
        let words = candidate
            .split(whereSeparator: { $0 == "_" || $0 == "-" || $0.isWhitespace })
            .map { Self.capitalised(String($0)) }
        return words.isEmpty ? candidate : words.joined(separator: " ")
    }

    /// The part of `UsageFormatter.cleanPlanName` that applies to Codex plan names: drops the words
    /// claude, codex, account and plan, collapses whitespace, and capitalises a lowercase first letter.
    private static func cleaned(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: #"(?i)\b(claude|codex|account|plan)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            cleaned = text
        }
        if let first = cleaned.first, first.isLowercase {
            cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
        return cleaned
    }

    private static func capitalised(_ word: String) -> String {
        let lower = word.lowercased()
        if Self.uppercaseWords.contains(lower) {
            return lower.uppercased()
        }
        if word == word.uppercased(), word.contains(where: \.isLetter) {
            return word
        }
        if let first = word.first, first.isLowercase {
            return word.prefix(1).uppercased() + word.dropFirst()
        }
        return word
    }
}
