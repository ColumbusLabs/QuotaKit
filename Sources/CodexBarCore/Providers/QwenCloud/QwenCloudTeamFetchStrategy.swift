import Foundation

enum QwenCloudTeamUnavailable: LocalizedError {
    case noActiveSubscription

    var errorDescription: String? {
        "No active Qwen Cloud Team Token Plan."
    }
}

struct QwenCloudTeamFetchStrategy: ProviderFetchStrategy {
    typealias CookieResolver = @Sendable (ProviderFetchContext, Bool) throws -> QwenCloudCookieHeaders
    let id = "qwen-cloud.team"
    let kind: ProviderFetchKind = .web
    var transport: any ProviderHTTPTransport = ProviderHTTPClient.shared
    var now = Date()
    var cookieResolver: CookieResolver = QwenCloudWebFetchStrategy.resolveCookieHeaders

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        guard Self.supports(context) else { return false }
        return await QwenCloudWebFetchStrategy().isAvailable(context)
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        try Task.checkCancellation()
        guard Self.supports(context) else { throw ProviderFetchError.noAvailableStrategy(.qwencloud) }
        do {
            return try await self.fetch(context, headers: self.cookieResolver(context, true))
        } catch let error as ProviderFetchClassifiedError
            where error.kind == .authenticationExpired && context.settings?.qwenCloud?.cookieSource != .manual
        {
            try Task.checkCancellation()
            return try await self.fetch(context, headers: self.cookieResolver(context, false))
        }
    }

    private func fetch(
        _ context: ProviderFetchContext, headers: QwenCloudCookieHeaders) async throws -> ProviderFetchResult
    {
        let runtime = try ProviderPluginRuntime(bundledPlugin: "qwencloud-team", transport: self.transport, timeout: 30)
        let usage = try await runtime.fetchUsage(
            now: self.now,
            sourceMode: context.sourceMode,
            cookieSource: .manual,
            cookieResolver: { provider, domain in
                guard provider == .qwencloud, domain == "home.qwencloud.com" else {
                    throw QwenCloudSettingsError.invalidCookie
                }
                return headers.dashboardCookieHeader
            })
        try Task.checkCancellation()
        guard usage.primary != nil else { throw QwenCloudTeamUnavailable.noActiveSubscription }
        return self.makeResult(usage: usage, sourceLabel: "web")
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
