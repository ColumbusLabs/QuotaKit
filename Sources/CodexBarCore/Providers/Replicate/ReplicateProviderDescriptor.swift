import Foundation
import SweetCookieKit

public enum ReplicateProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static let credentials = ProviderCredentialAdapter(tokenAccountSupport: TokenAccountSupport(
        title: "Session tokens",
        subtitle: "Store multiple Replicate Cookie headers.",
        placeholder: "Cookie: …",
        injection: .cookieHeader,
        requiresManualCookieSource: true,
        cookieName: nil))

    /// Chrome is the documented default; avoid unrelated browser keychains and Full Disk Access prompts.
    private static var browserCookieOrder: BrowserCookieImportOrder? {
        #if os(macOS)
        [.chrome]
        #else
        nil
        #endif
    }

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .replicate,
            menuBarMetrics: ProviderMenuBarMetricCapabilities(supported: [.automatic]),
            settingsSection: .init(ReplicateProviderSettingsKey.self, cookieSettings: ReplicateProviderSettings.self),
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .replicate,
                displayName: "Replicate",
                sessionLabel: "Spend",
                weeklyLabel: "Spend",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Replicate usage",
                cliName: "replicate",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: self.browserCookieOrder,
                dashboardURL: "https://replicate.com/account/billing",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .replicate),
                iconResourceName: "ProviderIcon-replicate",
                color: ProviderColor(red: 0, green: 0, blue: 0),
                confettiPalette: [
                    ProviderColor(hex: 0x000000),
                    ProviderColor(hex: 0x525252),
                    ProviderColor(hex: 0xFFFFFF),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Replicate spend comes from the billing summary page; cost history is not tracked." }),
            presentation: ProviderUsagePresentation(
                costPresenter: { _ in
                    ProviderCostPresentation(showsGenericFallback: false, menuCardStyle: .hidden)
                }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [ReplicateWebFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "replicate",
                aliases: ["r8"],
                versionDetector: nil,
                browserSupportExemption: { _, _, settings in
                    settings?.replicate?.cookieSource == .manual
                }))
    }
}

struct ReplicateResolvedSession: Sendable {
    let cookieHeader: String
    let sourceLabel: String
}

struct ReplicateWebFetchStrategy: ProviderFetchStrategy {
    typealias UsageLoader = @Sendable (String) async throws -> UsageSnapshot
    typealias SessionLoader = @Sendable (BrowserDetection) throws -> [ReplicateResolvedSession]
    typealias CacheObservation = CookieHeaderCache.ConditionalMutationObservation
    typealias CacheLoader = @Sendable () -> CacheObservation
    typealias CacheClearer = @Sendable (CookieHeaderCache.Entry?) -> Bool
    typealias CacheWriter = @Sendable (CacheObservation, ReplicateResolvedSession) -> Bool

    let id = "replicate.web"
    let kind: ProviderFetchKind = .web
    private let usageLoader: UsageLoader
    private let sessionLoader: SessionLoader
    private let cacheLoader: CacheLoader
    private let cacheClearer: CacheClearer
    private let cacheWriter: CacheWriter

    init(
        usageLoader: @escaping UsageLoader = ReplicateWebFetchStrategy.fetchUsage,
        sessionLoader: @escaping SessionLoader = ReplicateWebFetchStrategy.loadSessions,
        cacheLoader: @escaping CacheLoader = { CookieHeaderCache.observeForConditionalMutation(provider: .replicate) },
        cacheClearer: @escaping CacheClearer = { CookieHeaderCache.clearIfCurrent(provider: .replicate, expected: $0) },
        cacheWriter: @escaping CacheWriter = { expected, session in
            CookieHeaderCache.storeIfObservationCurrent(
                provider: .replicate,
                expected: expected,
                cookieHeader: session.cookieHeader,
                sourceLabel: session.sourceLabel)
        })
    {
        self.usageLoader = usageLoader
        self.sessionLoader = sessionLoader
        self.cacheLoader = cacheLoader
        self.cacheClearer = cacheClearer
        self.cacheWriter = cacheWriter
    }

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        context.settings?.replicate?.cookieSource != .off
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        try Task.checkCancellation()
        let settings = context.settings?.replicate
        guard settings?.cookieSource != .off else { throw ReplicateCredentialError.disabled }
        if settings?.cookieSource == .manual {
            guard let header = CookieHeaderNormalizer.normalize(settings?.manualCookieHeader),
                  CookieHeaderNormalizer.pairs(from: header).contains(where: {
                      $0.name == "sessionid" && !$0.value.isEmpty
                  })
            else { throw ReplicateCredentialError.invalidCookie }
            let usage = try await self.usageLoader(header)
            try Task.checkCancellation()
            return self.makeResult(usage: usage, sourceLabel: "manual")
        }

        var observation = self.cacheLoader()
        guard case .authoritative = observation else { throw ReplicateCredentialError.cacheUnavailable }
        if let cached = observation.entry {
            do {
                let usage = try await self.usageLoader(cached.cookieHeader)
                try Task.checkCancellation()
                return self.makeResult(usage: usage, sourceLabel: cached.sourceLabel)
            } catch {
                try Task.checkCancellation()
                guard Self.isAuthenticationFailure(error) else { throw error }
                guard cached.authenticationFailurePolicy != .stopFallback else { throw error }
                guard self.cacheClearer(cached) else { throw error }
                observation = observation.afterOwnedClear()
            }
        }

        try Task.checkCancellation()
        let sessions = try self.sessionLoader(context.browserDetection)
        guard !sessions.isEmpty else { throw ReplicateCredentialError.missingCookie }
        return try await ProviderCandidateRetryRunner.run(
            sessions,
            shouldRetry: Self.isAuthenticationFailure,
            attempt: { session in
                try Task.checkCancellation()
                let usage = try await self.usageLoader(session.cookieHeader)
                try Task.checkCancellation()
                guard self.cacheWriter(observation, session) else {
                    throw ReplicateCredentialError.cacheChanged
                }
                return self.makeResult(usage: usage, sourceLabel: session.sourceLabel)
            })
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func isAuthenticationFailure(_ error: Error) -> Bool {
        (error as? ProviderFetchClassifiedError)?.kind == .authenticationExpired
    }

    private static func fetchUsage(cookieHeader: String) async throws -> UsageSnapshot {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = ProviderHTTPClient.redirectGuardedSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let runtime = try ProviderPluginRuntime(
            bundledPlugin: "replicate",
            transport: ProviderHTTPClient(session: session))
        return try await runtime.fetchUsage(cookieResolver: { provider, domain in
            guard provider == .replicate, domain == "replicate.com" else {
                throw ReplicateCredentialError.invalidCookie
            }
            return cookieHeader
        })
    }

    private static func loadSessions(browserDetection: BrowserDetection) throws -> [ReplicateResolvedSession] {
        #if os(macOS)
        try ReplicateCookieImporter.importSessions(browserDetection: browserDetection).map {
            ReplicateResolvedSession(cookieHeader: $0.cookieHeader, sourceLabel: $0.sourceLabel)
        }
        #else
        throw ReplicateCredentialError.missingCookie
        #endif
    }
}

enum ReplicateCredentialError: LocalizedError, Equatable {
    case missingCookie
    case invalidCookie
    case disabled
    case cacheUnavailable
    case cacheChanged

    var errorDescription: String? {
        switch self {
        case .missingCookie:
            "No Replicate session cookies found. Sign in at replicate.com/account/billing or paste a Cookie header."
        case .invalidCookie:
            "Replicate needs a Cookie header containing a nonempty sessionid from the billing page."
        case .disabled:
            "Replicate cookies are disabled."
        case .cacheUnavailable:
            "Replicate's saved session is temporarily unavailable. Unlock the Keychain and retry."
        case .cacheChanged:
            "Replicate's saved session changed during refresh. Retry to use the current account."
        }
    }
}
