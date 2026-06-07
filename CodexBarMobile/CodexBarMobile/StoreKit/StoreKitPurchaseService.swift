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
    case none
}

enum StoreKitPurchaseOutcome: Equatable, Sendable {
    case purchased(StoreKitEntitlementStatus)
    case pending
    case cancelled
}

protocol ProPurchaseServicing: Sendable {
    func loadProduct() async throws -> ProProductInfo?
    func purchase() async throws -> StoreKitPurchaseOutcome
    func restorePurchases() async throws -> StoreKitEntitlementStatus
    func currentEntitlementStatus() async -> StoreKitEntitlementStatus
    func transactionUpdates() -> AsyncStream<StoreKitEntitlementStatus>
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
        case .success(let result):
            let status = Self.entitlementStatus(from: result)
            if case .verified = status, case .verified(let transaction) = result {
                await transaction.finish()
            }
            return .purchased(status)
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func restorePurchases() async throws -> StoreKitEntitlementStatus {
        try await AppStore.sync()
        return await self.currentEntitlementStatus()
    }

    func currentEntitlementStatus() async -> StoreKitEntitlementStatus {
        for await result in Transaction.currentEntitlements {
            let status = Self.entitlementStatus(from: result)
            if Self.matchesConfiguredProduct(status, productID: self.productID) {
                return status
            }
        }
        return .none
    }

    func transactionUpdates() -> AsyncStream<StoreKitEntitlementStatus> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    let status = Self.entitlementStatus(from: result)
                    guard Self.matchesConfiguredProduct(status, productID: self.productID) else {
                        continue
                    }
                    continuation.yield(status)
                    if case .verified(let transaction) = result {
                        await transaction.finish()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func entitlementStatus(
        from result: VerificationResult<Transaction>) -> StoreKitEntitlementStatus
    {
        switch result {
        case .verified(let transaction):
            .verified(productID: transaction.productID, verifiedAt: Date())
        case .unverified(let transaction, _):
            .unverified(productID: transaction.productID)
        }
    }

    private static func matchesConfiguredProduct(
        _ status: StoreKitEntitlementStatus,
        productID: String) -> Bool
    {
        switch status {
        case .verified(let id, _), .unverified(let id):
            id == productID
        case .none:
            false
        }
    }
}
