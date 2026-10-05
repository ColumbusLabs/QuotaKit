import Foundation

/// Display-safe inventory from Claude Web's or OAuth's `cedar_ember` usage block.
///
/// Grant identifiers are redemption handles and are intentionally never decoded. This snapshot is
/// live-only; `UsageSnapshot` does not encode or decode it.
public struct ClaudeRateLimitResetCreditsSnapshot: Sendable, Equatable {
    static let detailLabel = "Limit Reset Credits"

    /// Expiry of each available reset. A nil expiry means the reset does not expire.
    public let expirations: [Date?]
    public let updatedAt: Date

    public init(expirations: [Date?], updatedAt: Date) {
        self.expirations = expirations
        self.updatedAt = updatedAt
    }

    /// Available reset expirations, soonest first; resets without an expiry sort last.
    public func availableExpirations(at date: Date) -> [Date?] {
        self.expirations
            .filter { $0.map { $0 > date } ?? true }
            .sorted { lhs, rhs in
                switch (lhs, rhs) {
                case let (lhs?, rhs?): lhs < rhs
                case (_?, nil): true
                default: false
                }
            }
    }

    /// A compact safe summary for text/JSON usage surfaces. It contains no grant identifiers.
    func detailSections(now: Date) -> [ProviderDetailSection] {
        let available = self.availableExpirations(at: now)
        guard !available.isEmpty else { return [] }
        let countText = available.count == 1 ? "1 available" : "\(available.count) available"
        let nextExpiry = available.first.flatMap(\.self)
        let row = try? ProviderDetailSection.Row(
            label: Self.detailLabel,
            value: countText,
            secondaryValue: nextExpiry.map { "Expires \(UsageFormatter.resetDescription(from: $0, now: now))" })
        guard let row else { return [] }
        return [.makeSection(rows: [row])]
    }
}

/// Decoded `cedar_ember` block. Invalid grant records are discarded individually.
struct ClaudeLimitResetStatusResponse: Decodable {
    static let maximumResets = 50
    static let maximumGrantRecords = 200

    let eligible: Bool
    let grants: [ClaudeLimitResetGrantResponse]

    private enum CodingKeys: String, CodingKey {
        case eligible
        case grants
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.eligible = try container.decode(Bool.self, forKey: .eligible)
        var records = try container.nestedUnkeyedContainer(forKey: .grants)
        var grants: [ClaudeLimitResetGrantResponse] = []
        while !records.isAtEnd {
            guard records.currentIndex < Self.maximumGrantRecords else {
                throw DecodingError.dataCorruptedError(
                    forKey: .grants,
                    in: container,
                    debugDescription: "Too many reset grants")
            }
            if let grant = try records.decode(LossyGrant.self).grant {
                grants.append(grant)
            }
        }
        self.grants = grants
    }

    func snapshot(updatedAt: Date) -> ClaudeRateLimitResetCreditsSnapshot? {
        guard self.eligible else { return nil }
        var expirations: [Date?] = []
        for grant in self.grants where grant.isAvailable(at: updatedAt) {
            guard grant.resetsLeft <= Self.maximumResets - expirations.count else { return nil }
            expirations.append(contentsOf: repeatElement(grant.endsAt, count: grant.resetsLeft))
        }
        guard !expirations.isEmpty else { return nil }
        return ClaudeRateLimitResetCreditsSnapshot(expirations: expirations, updatedAt: updatedAt)
    }

    private struct LossyGrant: Decodable {
        let grant: ClaudeLimitResetGrantResponse?

        init(from decoder: Decoder) throws {
            self.grant = try? ClaudeLimitResetGrantResponse(from: decoder)
        }
    }
}

struct ClaudeLimitResetGrantResponse: Decodable {
    let resetsLeft: Int
    let startsAt: Date?
    let endsAt: Date?
    let paused: Bool

    private enum CodingKeys: String, CodingKey {
        case resetsLeft = "resets_left"
        case resetsTotal = "resets_total"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case paused
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let resetsLeft = try container.decode(Int.self, forKey: .resetsLeft)
        let resetsTotal = try container.decodeIfPresent(Int.self, forKey: .resetsTotal)
        guard resetsLeft >= 0, resetsTotal.map({ $0 >= resetsLeft }) ?? true else {
            throw DecodingError.dataCorruptedError(
                forKey: .resetsLeft,
                in: container,
                debugDescription: "resets_left must be nonnegative and no greater than resets_total")
        }
        self.resetsLeft = resetsLeft
        self.startsAt = try Self.decodeBound(container, forKey: .startsAt)
        self.endsAt = try Self.decodeBound(container, forKey: .endsAt)
        self.paused = try container.decode(Bool.self, forKey: .paused)
    }

    func isAvailable(at date: Date) -> Bool {
        guard !self.paused, self.resetsLeft > 0 else { return false }
        if let startsAt = self.startsAt, startsAt > date { return false }
        if let endsAt = self.endsAt, endsAt <= date { return false }
        return true
    }

    private static func decodeBound(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys) throws -> Date?
    {
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let date = ISO8601DateParser.parse(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Unreadable ISO-8601 grant bound")
        }
        return date
    }
}
