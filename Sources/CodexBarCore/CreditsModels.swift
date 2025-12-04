import Foundation

public struct CreditEvent: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public let date: Date
    public let service: String
    public let creditsUsed: Double

    public init(id: UUID = UUID(), date: Date, service: String, creditsUsed: Double) {
        self.id = id
        self.date = date
        self.service = service
        self.creditsUsed = creditsUsed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case service
        case creditsUsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.date = try container.decode(Date.self, forKey: .date)
        self.service = try container.decode(String.self, forKey: .service)
        self.creditsUsed = try container.decode(Double.self, forKey: .creditsUsed)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.date, forKey: .date)
        try container.encode(self.service, forKey: .service)
        try container.encode(self.creditsUsed, forKey: .creditsUsed)
    }
}

public struct CreditsSnapshot: Equatable, Codable, Sendable {
    public let remaining: Double
    public let events: [CreditEvent]
    public let updatedAt: Date

    public init(remaining: Double, events: [CreditEvent], updatedAt: Date) {
        self.remaining = remaining
        self.events = events
        self.updatedAt = updatedAt
    }
}
