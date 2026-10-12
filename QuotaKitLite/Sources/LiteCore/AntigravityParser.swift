import Foundation

/// Parses the Antigravity language server's responses (068 §4.3), following the full app's
/// `AntigravityQuotaSummaryParser` and `AntigravityStatusProbe` mapping.
public enum AntigravityParser {
    /// `RetrieveUserQuotaSummary`: one window per known 5-hour or weekly bucket, Gemini first, then Claude/GPT,
    /// session before weekly within a group. Labels match the full app ("Gemini 5-hour", "Claude/GPT weekly").
    /// Buckets with no cadence, disabled buckets and buckets without a remaining fraction are left out.
    public static func quotaWindows(from data: Data) throws -> [QuotaWindow] {
        let response: SummaryResponse
        do {
            response = try JSONDecoder().decode(SummaryResponse.self, from: data)
        } catch {
            throw ProbeFailure.unrecognizedResponse
        }
        if let code = response.code, !code.isOK {
            throw ProbeFailure.unrecognizedResponse
        }
        guard let payload = response.response ?? response.summary ?? response.rootPayload else {
            throw ProbeFailure.unrecognizedResponse
        }
        let groups = (payload.groups ?? []).enumerated().sorted { lhs, rhs in
            let ranks = (self.groupRank(lhs.element), self.groupRank(rhs.element))
            return ranks.0 != ranks.1 ? ranks.0 < ranks.1 : lhs.offset < rhs.offset
        }.map(\.element)

        var windows: [QuotaWindow] = []
        for group in groups {
            let title = self.groupTitle(group)
            let buckets = (group.buckets ?? []).compactMap { bucket -> (QuotaWindow.Lane, QuotaWindow)? in
                guard bucket.disabled != true,
                      let fraction = bucket.remainingFraction ?? bucket.remaining?.remainingFraction,
                      let lane = self.lane(for: bucket)
                else { return nil }
                let remaining = max(0, min(100, fraction * 100))
                return (lane, QuotaWindow(
                    label: "\(title) \(lane == .session ? "5-hour" : "weekly")",
                    lane: lane,
                    usedPercent: 100 - remaining,
                    windowMinutes: lane == .session ? 300 : 10080,
                    resetsAt: bucket.resetTime.flatMap(self.parseDate)))
            }
            windows += buckets.filter { $0.0 == .session }.map(\.1) + buckets.filter { $0.0 == .weekly }.map(\.1)
        }
        guard !windows.isEmpty else { throw ProbeFailure.unrecognizedResponse }
        return windows
    }

    /// `GetUserStatus`, read only for the account: the email and the plan, preferring `userTier.name` (the full
    /// app's note: `planInfo` shows "Pro" for Ultra users).
    public static func identity(from data: Data) -> (email: String?, plan: String?) {
        guard let response = try? JSONDecoder().decode(UserStatusResponse.self, from: data),
              response.code?.isOK ?? true,
              let status = response.userStatus
        else { return (nil, nil) }
        let plan = self.nonEmpty(status.userTier?.name)
            ?? [
                status.planStatus?.planInfo?.planDisplayName,
                status.planStatus?.planInfo?.displayName,
                status.planStatus?.planInfo?.productName,
                status.planStatus?.planInfo?.planName,
                status.planStatus?.planInfo?.planShortName,
            ].lazy.compactMap(self.nonEmpty).first
        return (self.nonEmpty(status.email), plan)
    }

    // MARK: - Mapping

    private static func groupRank(_ group: Group) -> Int {
        let name = (group.displayName ?? group.name ?? "").lowercased()
        if name.contains("gemini") { return 0 }
        if name.contains("claude") || name.contains("gpt") { return 1 }
        return 2
    }

    private static func groupTitle(_ group: Group) -> String {
        let title = (group.displayName ?? group.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = title.lowercased()
        if lower.contains("gemini") { return "Gemini" }
        if lower.contains("claude") || lower.contains("gpt") { return "Claude/GPT" }
        return title.isEmpty ? "Quota" : title
    }

    private static let sessionAliases: Set<String> = ["session", "5h", "5-hour", "five hour", "five-hour"]

    /// `quotaBucketKind`: an explicit `window` wins; otherwise the bucket id and name are matched, including
    /// suffixes like `gemini-5h` and "Weekly Limit".
    static func lane(for bucket: Bucket) -> QuotaWindow.Lane? {
        let explicit = bucket.window?.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = if let explicit, !explicit.isEmpty {
            [explicit]
        } else {
            [bucket.bucketId ?? bucket.id, bucket.displayName ?? bucket.name].compactMap(\.self)
        }
        var candidates: Set<String> = []
        for raw in values {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                .replacingOccurrences(of: "_", with: "-")
            guard !normalized.isEmpty else { continue }
            var forms = [normalized]
            if normalized.hasSuffix(" limit") {
                forms.append(String(normalized.dropLast(" limit".count)))
            }
            for form in forms {
                candidates.insert(form)
                for alias in self.sessionAliases.union(["weekly"]) where form.hasSuffix("-\(alias)") {
                    candidates.insert(alias)
                }
            }
        }
        if !candidates.isDisjoint(with: self.sessionAliases) { return .session }
        if candidates.contains("weekly") { return .weekly }
        return nil
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        return Double(value).map { Date(timeIntervalSince1970: $0) }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Wire types

    private struct SummaryResponse: Decodable {
        let code: Code?
        let response: Payload?
        let summary: Payload?
        let description: String?
        let groups: [Group]?

        var rootPayload: Payload? {
            self.groups.map { Payload(description: self.description, groups: $0) }
        }
    }

    private struct Payload: Decodable {
        let description: String?
        let groups: [Group]?
    }

    struct Group: Decodable {
        let displayName: String?
        let name: String?
        let buckets: [Bucket]?
    }

    struct Bucket: Decodable {
        let bucketId: String?
        let id: String?
        let displayName: String?
        let name: String?
        let disabled: Bool?
        let remainingFraction: Double?
        let remaining: Remaining?
        let resetTime: String?
        let window: String?
    }

    /// Either `{"remainingFraction": 0.5}` or the protobuf oneof shape `{"case": "remainingFraction", "value": 0.5}`.
    struct Remaining: Decodable {
        let remainingFraction: Double?

        private enum CodingKeys: String, CodingKey {
            case remainingFraction
            case oneofCase = "case"
            case value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let fraction = try container.decodeIfPresent(Double.self, forKey: .remainingFraction) {
                self.remainingFraction = fraction
                return
            }
            let oneof = try container.decodeIfPresent(String.self, forKey: .oneofCase)
            self.remainingFraction = oneof == "remainingFraction"
                ? try container.decodeIfPresent(Double.self, forKey: .value) : nil
        }
    }

    private struct UserStatusResponse: Decodable {
        let code: Code?
        let userStatus: UserStatus?
    }

    private struct UserStatus: Decodable {
        let email: String?
        let userTier: UserTier?
        let planStatus: PlanStatus?
    }

    private struct UserTier: Decodable {
        let name: String?
    }

    private struct PlanStatus: Decodable {
        let planInfo: PlanInfo?
    }

    private struct PlanInfo: Decodable {
        let planName: String?
        let planDisplayName: String?
        let displayName: String?
        let productName: String?
        let planShortName: String?
    }

    /// An int or string status code; 0, "ok" and "success" are fine.
    private enum Code: Decodable {
        case int(Int)
        case string(String)

        var isOK: Bool {
            switch self {
            case let .int(value): value == 0
            case let .string(value): ["ok", "success", "0"].contains(value.lowercased())
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Int.self) {
                self = .int(value)
            } else {
                self = try .string(container.decode(String.self))
            }
        }
    }
}
