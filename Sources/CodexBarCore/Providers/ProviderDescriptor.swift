import Foundation

public enum ProviderRuntime: Sendable {
    case app
    case cli
}

public enum ProviderSourceMode: String, CaseIterable, Sendable {
    case auto
    case web
    case cli
    case oauth

    public var usesWeb: Bool {
        self == .auto || self == .web
    }
}

public struct ProviderSettingsSnapshot: Sendable {
    public let debugMenuEnabled: Bool
    public let claudeUsageDataSource: ClaudeUsageDataSource?
    public let claudeWebExtrasEnabled: Bool
    public let zaiAPIToken: String?
    public let copilotAPIToken: String?

    public init(
        debugMenuEnabled: Bool,
        claudeUsageDataSource: ClaudeUsageDataSource?,
        claudeWebExtrasEnabled: Bool,
        zaiAPIToken: String?,
        copilotAPIToken: String?)
    {
        self.debugMenuEnabled = debugMenuEnabled
        self.claudeUsageDataSource = claudeUsageDataSource
        self.claudeWebExtrasEnabled = claudeWebExtrasEnabled
        self.zaiAPIToken = zaiAPIToken
        self.copilotAPIToken = copilotAPIToken
    }
}

public struct ProviderFetchContext: Sendable {
    public let runtime: ProviderRuntime
    public let sourceMode: ProviderSourceMode
    public let includeCredits: Bool
    public let webTimeout: TimeInterval
    public let webDebugDumpHTML: Bool
    public let verbose: Bool
    public let env: [String: String]
    public let settings: ProviderSettingsSnapshot?
    public let fetcher: UsageFetcher
    public let claudeFetcher: any ClaudeUsageFetching

    public init(
        runtime: ProviderRuntime,
        sourceMode: ProviderSourceMode,
        includeCredits: Bool,
        webTimeout: TimeInterval,
        webDebugDumpHTML: Bool,
        verbose: Bool,
        env: [String: String],
        settings: ProviderSettingsSnapshot?,
        fetcher: UsageFetcher,
        claudeFetcher: any ClaudeUsageFetching)
    {
        self.runtime = runtime
        self.sourceMode = sourceMode
        self.includeCredits = includeCredits
        self.webTimeout = webTimeout
        self.webDebugDumpHTML = webDebugDumpHTML
        self.verbose = verbose
        self.env = env
        self.settings = settings
        self.fetcher = fetcher
        self.claudeFetcher = claudeFetcher
    }
}

public struct ProviderFetchResult: Sendable {
    public let usage: UsageSnapshot
    public let credits: CreditsSnapshot?
    public let dashboard: OpenAIDashboardSnapshot?
    public let sourceOverride: String?

    public init(
        usage: UsageSnapshot,
        credits: CreditsSnapshot?,
        dashboard: OpenAIDashboardSnapshot?,
        sourceOverride: String?)
    {
        self.usage = usage
        self.credits = credits
        self.dashboard = dashboard
        self.sourceOverride = sourceOverride
    }
}

public enum ProviderFetchError: LocalizedError, Sendable {
    case noAvailableStrategy(UsageProvider)

    public var errorDescription: String? {
        switch self {
        case let .noAvailableStrategy(provider):
            "No available fetch strategy for \(provider.rawValue)."
        }
    }
}

public enum ProviderFetchKind: Sendable {
    case cli
    case web
    case oauth
    case apiToken
    case localProbe
    case webDashboard
}

public protocol ProviderFetchStrategy: Sendable {
    var id: String { get }
    var kind: ProviderFetchKind { get }
    func isAvailable(_ context: ProviderFetchContext) async -> Bool
    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult
    func shouldFallback(on error: Error, context: ProviderFetchContext) -> Bool
}

public struct ProviderFetchPipeline: Sendable {
    public let resolveStrategies: @Sendable (ProviderFetchContext) async -> [any ProviderFetchStrategy]

    public init(resolveStrategies: @escaping @Sendable (ProviderFetchContext) async -> [any ProviderFetchStrategy]) {
        self.resolveStrategies = resolveStrategies
    }

    public func fetch(context: ProviderFetchContext, provider: UsageProvider) async throws -> ProviderFetchResult {
        let strategies = await self.resolveStrategies(context)
        for strategy in strategies where await strategy.isAvailable(context) {
            do {
                return try await strategy.fetch(context)
            } catch {
                if strategy.shouldFallback(on: error, context: context) {
                    continue
                }
                throw error
            }
        }
        throw ProviderFetchError.noAvailableStrategy(provider)
    }
}

public struct ProviderColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct ProviderBranding: Sendable {
    public let iconStyle: IconStyle
    public let iconResourceName: String
    public let color: ProviderColor

    public init(iconStyle: IconStyle, iconResourceName: String, color: ProviderColor) {
        self.iconStyle = iconStyle
        self.iconResourceName = iconResourceName
        self.color = color
    }
}

public struct ProviderTokenCostConfig: Sendable {
    public let supportsTokenCost: Bool
    public let noDataMessage: @Sendable () -> String

    public init(supportsTokenCost: Bool, noDataMessage: @escaping @Sendable () -> String) {
        self.supportsTokenCost = supportsTokenCost
        self.noDataMessage = noDataMessage
    }
}

public struct ProviderCLIConfig: Sendable {
    public let name: String
    public let aliases: [String]
    public let sourceLabel: String
    public let versionDetector: (@Sendable () -> String?)?
    public let sourceModes: Set<ProviderSourceMode>

    public init(
        name: String,
        aliases: [String] = [],
        sourceLabel: String,
        versionDetector: (@Sendable () -> String?)?,
        sourceModes: Set<ProviderSourceMode>)
    {
        self.name = name
        self.aliases = aliases
        self.sourceLabel = sourceLabel
        self.versionDetector = versionDetector
        self.sourceModes = sourceModes
    }
}

public struct ProviderDescriptor: Sendable {
    public let id: UsageProvider
    public let metadata: ProviderMetadata
    public let branding: ProviderBranding
    public let tokenCost: ProviderTokenCostConfig
    public let sourceLabel: String
    public let cli: ProviderCLIConfig
    public let fetchPipeline: ProviderFetchPipeline

    public init(
        id: UsageProvider,
        metadata: ProviderMetadata,
        branding: ProviderBranding,
        tokenCost: ProviderTokenCostConfig,
        sourceLabel: String,
        cli: ProviderCLIConfig,
        fetchPipeline: ProviderFetchPipeline)
    {
        self.id = id
        self.metadata = metadata
        self.branding = branding
        self.tokenCost = tokenCost
        self.sourceLabel = sourceLabel
        self.cli = cli
        self.fetchPipeline = fetchPipeline
    }

    public func fetch(context: ProviderFetchContext) async throws -> ProviderFetchResult {
        try await self.fetchPipeline.fetch(context: context, provider: self.id)
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
