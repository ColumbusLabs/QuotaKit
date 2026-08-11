import CodexBarSync
import Foundation
import StoreKit

struct ProProductInfo: Equatable, Sendable {
    let id: String
    let displayName: String
    let description: String
    let displayPrice: String
}

enum StoreKitEntitlementStatus: Equatable, Sendable {
    case verified(productID: String, verifiedAt: Date)
    case unverified(productID: String)
    case revoked(productID: String)
    case none
}

struct StoreKitEntitlementSnapshot: Equatable, Sendable {
    let status: StoreKitEntitlementStatus
    let environment: ProEntitlementEnvironment
}

enum StoreKitPurchaseOutcome: Equatable, Sendable {
    case purchased(StoreKitEntitlementSnapshot)
    case pending
    case cancelled
}

protocol ProPurchaseServicing: Sendable {
    func loadProduct() async throws -> ProProductInfo?
    func purchase() async throws -> StoreKitPurchaseOutcome
    func restorePurchases() async throws -> StoreKitEntitlementSnapshot
    func currentEntitlementStatus() async -> StoreKitEntitlementSnapshot
    func transactionUpdates() -> AsyncStream<StoreKitEntitlementSnapshot>
}

enum StoreKitPurchaseServiceError: LocalizedError {
    case productUnavailable

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            "QuotaKit Pro is not available from the App Store right now."
        }
    }
}

struct StoreKitPurchaseService: ProPurchaseServicing {
    private let productID: String

    init(productID: String = ProductConfig.storeKitLifetimeProductID) {
        self.productID = productID
    }

    func loadProduct() async throws -> ProProductInfo? {
        let products = try await Product.products(for: [self.productID])
        guard let product = products.first(where: { $0.id == self.productID }) else {
            return nil
        }
        return ProProductInfo(
            id: product.id,
            displayName: product.displayName,
            description: product.description,
            displayPrice: product.displayPrice)
    }

    func purchase() async throws -> StoreKitPurchaseOutcome {
        let products = try await Product.products(for: [self.productID])
        guard let product = products.first(where: { $0.id == self.productID }) else {
            throw StoreKitPurchaseServiceError.productUnavailable
        }

        switch try await product.purchase() {
        case let .success(result):
            let snapshot = Self.entitlementSnapshot(from: result)
            if case let .verified(transaction) = result {
                await transaction.finish()
            }
            return .purchased(snapshot)
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func restorePurchases() async throws -> StoreKitEntitlementSnapshot {
        try await AppStore.sync()
        return await self.currentEntitlementStatus()
    }

    func currentEntitlementStatus() async -> StoreKitEntitlementSnapshot {
        for await result in Transaction.currentEntitlements {
            let snapshot = Self.entitlementSnapshot(from: result)
            if Self.matchesConfiguredProduct(snapshot.status, productID: self.productID) {
                return snapshot
            }
        }
        return await StoreKitEntitlementSnapshot(
            status: .none,
            environment: Self.currentAppEnvironment())
    }

    func transactionUpdates() -> AsyncStream<StoreKitEntitlementSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    let snapshot = Self.entitlementSnapshot(from: result)
                    guard Self.matchesConfiguredProduct(snapshot.status, productID: self.productID) else {
                        continue
                    }
                    continuation.yield(snapshot)
                    if case let .verified(transaction) = result {
                        await transaction.finish()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func entitlementSnapshot(
        from result: VerificationResult<Transaction>) -> StoreKitEntitlementSnapshot
    {
        switch result {
        case let .verified(transaction):
            StoreKitEntitlementSnapshot(
                status: Self.verifiedEntitlementStatus(
                    productID: transaction.productID,
                    verifiedAt: Date(),
                    revocationDate: transaction.revocationDate),
                environment: Self.entitlementEnvironment(transaction.environment))
        case let .unverified(transaction, _):
            StoreKitEntitlementSnapshot(
                status: .unverified(productID: transaction.productID),
                environment: Self.entitlementEnvironment(transaction.environment))
        }
    }

    private static func currentAppEnvironment() async -> ProEntitlementEnvironment {
        do {
            switch try await AppTransaction.shared {
            case let .verified(appTransaction):
                return Self.entitlementEnvironment(appTransaction.environment)
            case .unverified:
                return .unknown
            }
        } catch {
            return .unknown
        }
    }

    private static func entitlementEnvironment(
        _ environment: AppStore.Environment) -> ProEntitlementEnvironment
    {
        switch environment {
        case .production:
            .production
        case .sandbox:
            .sandbox
        case .xcode:
            .xcode
        default:
            .unknown
        }
    }

    /// A verified signature proves the transaction is authentic, not that it
    /// still grants access. StoreKit emits refunded/revoked transactions on
    /// `Transaction.updates`, so keep this mapping independently testable.
    static func verifiedEntitlementStatus(
        productID: String,
        verifiedAt: Date,
        revocationDate: Date?) -> StoreKitEntitlementStatus
    {
        if revocationDate != nil {
            return .revoked(productID: productID)
        }
        return .verified(productID: productID, verifiedAt: verifiedAt)
    }

    private static func matchesConfiguredProduct(
        _ status: StoreKitEntitlementStatus,
        productID: String) -> Bool
    {
        switch status {
        case let .verified(id, _), let .unverified(id), let .revoked(id):
            id == productID
        case .none:
            false
        }
    }
}
