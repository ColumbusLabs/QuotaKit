import Foundation

/// Charm Hyper's balance, denominated in Hypercredits (HC), not USD.
public struct SyncHyperBalance: Codable, Sendable, Equatable {
    public let balance: Double
    public let updatedAt: Date

    public init(balance: Double, updatedAt: Date) {
        self.balance = balance
        self.updatedAt = updatedAt
    }
}
