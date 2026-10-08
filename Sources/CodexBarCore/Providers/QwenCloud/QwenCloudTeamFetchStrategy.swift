import Foundation

enum QwenCloudTeamUnavailable: LocalizedError {
    case noActiveSubscription

    var errorDescription: String? {
        "No active Qwen Cloud Team Token Plan."
    }
}

struct QwenCloudTeamFetchStrategy: ProviderFetchStrategy {
    typealias CookieSessionResolver = @Sendable (ProviderFetchContext, Bool) throws -> ProviderPluginCookieSession?
    typealias CookieRecordImporter = @Sendable (ProviderFetchContext, String) throws
        -> [(records: [ProviderPluginCookieRecord], source: String)]
    let id = "qwen-cloud.team"
    let kind: ProviderFetchKind = .web
    var transport: any ProviderHTTPTransport = ProviderHTTPClient.shared
    var now = Date()
    var cookieSessionResolver: CookieSessionResolver?
    var cookieRecordImporter: CookieRecordImporter?

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        guard Self.supports(context) else { return false }
        return await QwenCloudWebFetchStrategy().isAvailable(context)
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        try Task.checkCancellation()
        guard Self.supports(context) else { throw ProviderFetchError.noAvailableStrategy(.qwencloud) }
        do {
            return try await self.fetch(context, allowCached: true)
        } catch let error as ProviderFetchClassifiedError
            where error.kind == .authenticationExpired && Self.cookieSettings(context).cookieSource != .manual
        {
            try Task.checkCancellation()
            return try await self.fetch(context, allowCached: false)
        }
    }

    private func fetch(_ context: ProviderFetchContext, allowCached: Bool) async throws -> ProviderFetchResult {
        let runtime = try ProviderPluginRuntime(bundledPlugin: "qwencloud-team", transport: self.transport, timeout: 30)
        let usage: UsageSnapshot
        if let cookieSessionResolver {
            usage = try await runtime.fetchUsage(
                now: self.now,
                sourceMode: context.sourceMode,
                cookieSource: Self.cookieSettings(context).cookieSource,
                cookieSessionResolver: { domain, _ in
                    guard domain == "home.qwencloud.com" else { throw QwenCloudSettingsError.invalidCookie }
                    return try cookieSessionResolver(context, allowCached)
                })
        } else {
            let cookies = self.cookieBroker(context, policy: runtime.manifest.cookiePolicy)
            usage = try await runtime.fetchResult(cookies: cookies, now: self.now, sourceMode: context.sourceMode).usage
        }
        try Task.checkCancellation()
        guard usage.primary != nil else { throw QwenCloudTeamUnavailable.noActiveSubscription }
        return self.makeResult(usage: usage, sourceLabel: "web")
    }

    private static func cookieSettings(
        _ context: ProviderFetchContext) -> ProviderSettingsSnapshot.CookieProviderSettings
    {
        if let settings = context.settings?.qwenCloud, settings.cookieSource == .manual {
            return .init(cookieSource: .manual, manualCookieHeader: settings.manualCookieHeader)
        }
        if let environmentCookie = QwenCloudSettingsReader.cookieHeader(environment: context.env) {
            return .init(cookieSource: .manual, manualCookieHeader: environmentCookie)
        }
        return context.settings.flatMap {
            ProviderDescriptorRegistry.descriptor(for: .qwencloud).settingsSection.cookieSettings(from: $0)
        } ?? .init(cookieSource: .auto, manualCookieHeader: nil)
    }

    private func cookieBroker(
        _ context: ProviderFetchContext,
        policy: ProviderPluginCookiePolicy?) -> ProviderPluginCookieBroker
    {
        let canImport = policy?.allowsImportAttempt(
            runtime: context.runtime,
            interaction: ProviderInteractionContext.current) ?? false
        let browserDetection = context.browserDetection
        let customImporter = self.cookieRecordImporter
        let jarImporter: ProviderPluginCookieBroker.JarImporter? = if canImport {
            { domain in
                guard domain == "home.qwencloud.com" else { return [] }
                if let customImporter { return try customImporter(context, domain) }
                #if os(macOS)
                let imported = try QwenCloudCookieImport.importSession(
                    browserDetection: browserDetection,
                    importOrder: QwenCloudWebFetchStrategy.browserOrder)
                guard let browserRecords = imported.records,
                      QwenCloudCookieImport.isAuthenticatedSession(records: browserRecords) else { return [] }
                return [(browserRecords.map(ProviderPluginCookieRecord.init(record:)), imported.sourceLabel)]
                #else
                return []
                #endif
            }
        } else {
            nil
        }
        return ProviderPluginCookieBroker(
            provider: .qwencloud,
            domains: ["home.qwencloud.com"],
            settings: Self.cookieSettings(context),
            batches: { _, _ in nil },
            usesCookieJar: true,
            jarImporter: jarImporter,
            policy: policy,
            background: ProviderInteractionContext.current != .userInitiated,
            accountID: context.selectedTokenAccountID)
    }

    func shouldFallback(on error: Error, context _: ProviderFetchContext) -> Bool {
        !(error is CancellationError)
    }

    static func fallbackError(previous: Error?, current: Error) -> Error {
        guard let previous, !(previous is QwenCloudTeamUnavailable) else { return current }
        return previous
    }

    private static func supports(_ context: ProviderFetchContext) -> Bool {
        // Existing overrides retain their Individual contract; never send them to the real Team endpoint.
        context.sourceMode.usesWeb && context.settings?.qwenCloud?.cookieSource != .off &&
            context.env["QWEN_CLOUD_HOST"] == nil && context.env["QWEN_CLOUD_QUOTA_URL"] == nil
    }
}
