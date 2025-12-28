import Foundation

public struct ProviderTokenCostConfig: Sendable {
    public let supportsTokenCost: Bool
    public let noDataMessage: @Sendable () -> String

    public init(supportsTokenCost: Bool, noDataMessage: @escaping @Sendable () -> String) {
        self.supportsTokenCost = supportsTokenCost
        self.noDataMessage = noDataMessage
    }
}

public struct ProviderDescriptor: Sendable {
    public let id: UsageProvider
    public let metadata: ProviderMetadata
    public let branding: ProviderBranding
    public let tokenCost: ProviderTokenCostConfig
    public let fetchPlan: ProviderFetchPlan
    public let cli: ProviderCLIConfig

    public init(
        id: UsageProvider,
        metadata: ProviderMetadata,
        branding: ProviderBranding,
        tokenCost: ProviderTokenCostConfig,
        fetchPlan: ProviderFetchPlan,
        cli: ProviderCLIConfig)
    {
        self.id = id
        self.metadata = metadata
        self.branding = branding
        self.tokenCost = tokenCost
        self.fetchPlan = fetchPlan
        self.cli = cli
    }

    public func fetchOutcome(context: ProviderFetchContext) async -> ProviderFetchOutcome {
        await self.fetchPlan.fetchOutcome(context: context, provider: self.id)
    }

    public func fetch(context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let outcome = await self.fetchOutcome(context: context)
        return try outcome.result.get()
    }
}

public enum ProviderDescriptorRegistry {
    private final class Store: @unchecked Sendable {
        var ordered: [ProviderDescriptor] = []
        var byID: [UsageProvider: ProviderDescriptor] = [:]
    }

    private static let lock = NSLock()
    private static let store = Store()

    @discardableResult
    public static func register(_ descriptor: ProviderDescriptor) -> ProviderDescriptor {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.store.byID[descriptor.id] == nil {
            self.store.ordered.append(descriptor)
        }
        self.store.byID[descriptor.id] = descriptor
        return descriptor
    }

    public static var all: [ProviderDescriptor] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.store.ordered
    }

    public static var metadata: [UsageProvider: ProviderMetadata] {
        Dictionary(uniqueKeysWithValues: self.all.map { ($0.id, $0.metadata) })
    }

    public static func descriptor(for id: UsageProvider) -> ProviderDescriptor {
        if let found = self.store.byID[id] { return found }
        if let found = self.all.first(where: { $0.id == id }) { return found }
        fatalError("Missing ProviderDescriptor for \(id.rawValue)")
    }

    public static var cliNameMap: [String: UsageProvider] {
        var map: [String: UsageProvider] = [:]
        for descriptor in self.all {
            map[descriptor.cli.name] = descriptor.id
            for alias in descriptor.cli.aliases {
                map[alias] = descriptor.id
            }
        }
        return map
    }
}
