import Foundation

public enum MiniMaxProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static let credentials = ProviderCredentialAdapter(
        supportsAPIKeyOverride: true,
        usesRegion: true,
        environmentProjections: [.apiKey(MiniMaxAPISettingsReader.apiTokenKey)],
        tokenResolver: { kind, environment, _ in
            let token: String? = switch kind {
            case .primary: MiniMaxAPISettingsReader.apiToken(environment: environment)
            case .secondary: MiniMaxSettingsReader.cookieHeader(environment: environment)
            case .projectID: nil
            }
            guard let token else { return nil }
            return ProviderTokenResolution(token: token, source: .environment)
        },
        tokenAccountSupport: TokenAccountSupport(
            title: "Session tokens",
            subtitle: "Store multiple MiniMax Cookie headers.",
            placeholder: "Cookie: …",
            injection: .cookieHeader,
            requiresManualCookieSource: true,
            cookieName: nil),
        diagnosticSummary: { _, _, environment, settings in
            let apiToken = MiniMaxAPISettingsReader.apiToken(environment: environment)
            let cookie = MiniMaxSettingsReader.cookieHeader(environment: environment)
                ?? CookieHeaderNormalizer.normalize(settings?.minimax?.manualCookieHeader)
            let mode = MiniMaxAuthMode.resolve(apiToken: apiToken, cookieHeader: cookie)
            return ProviderDiagnosticAuthSummary(
                configured: mode.usesAPIToken || mode.usesCookie,
                modes: mode == .none ? [] : [mode.description])
        },
        configValidator: ProviderCredentialAdapter.regionValidator(
            displayName: "MiniMax",
            isValid: { MiniMaxAPIRegion(rawValue: $0) != nil }),
        missingCredentialMessage: { _ in MiniMaxAPISettingsError.missingToken.errorDescription })

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .minimax,
            settingsSection: .init(
                MiniMaxProviderSettingsKey.self,
                cookieSettings: { settings in
                    CookieProviderSettings(
                        cookieSource: settings.cookieSource,
                        manualCookieHeader: settings.manualCookieHeader)
                },
                credentialSettings: { context in
                    let settings = context.cookieSettings(for: .minimax)
                    let region = context.config?.sanitizedRegion
                        .flatMap(MiniMaxAPIRegion.init(rawValue:)) ?? .global
                    return MiniMaxProviderSettings(
                        cookieSource: settings.cookieSource,
                        manualCookieHeader: settings.manualCookieHeader,
                        apiRegion: region)
                }),
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .minimax,
                displayName: "MiniMax",
                sessionLabel: "Prompts",
                weeklyLabel: "Window",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show MiniMax usage",
                cliName: "minimax",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                sharePlanLabels: [
                    "free": "Free", "pro": "Pro", "plus": "Plus", "max": "Max", "ultra": "Ultra",
                    "minimax star": "MiniMax Star", "combo star": "Combo Star", "coding plan pro": "Coding Plan Pro",
                    "token plan pro": "Token Plan Pro", "token plan · tokenplanplus-年度会员": "Token Plan Plus",
                    "tokenplanplus-年度会员": "Token Plan Plus", "tokenplanmax-年度会员": "Token Plan Max",
                    "tokenplanultra-年度会员": "Token Plan Ultra",
                ],
                browserCookieOrder: ProviderBrowserCookieDefaults.defaultImportOrder,
                dashboardURL: "https://platform.minimax.io/user-center/payment/coding-plan?cycle_type=3",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .minimax),
                iconResourceName: "ProviderIcon-minimax",
                color: ProviderColor(
                    red: 239 / 255,
                    green: 68 / 255,
                    blue: 68 / 255),
                confettiPalette: [
                    ProviderColor(hex: 0x181E25),
                    ProviderColor(hex: 0x86909C),
                    ProviderColor(hex: 0xF7F8FA),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "MiniMax cost summary is not supported." }),
            presentation: ProviderUsagePresentation(
                costPresenter: { snapshot in
                    let style: ProviderCostMenuCardStyle = snapshot.providerCost?.period == "MiniMax points balance"
                        ? .pointsBalance
                        : .generic
                    return ProviderCostPresentation(menuCardStyle: style)
                },
                automaticSelectionPrioritizesExhaustedWindow: false,
                menuBarWindowResolver: { context in
                    guard context.metric == .automatic else { return .unhandled }
                    return .automaticCandidates([
                        context.snapshot.primary,
                        context.snapshot.secondary,
                        context.snapshot.tertiary,
                    ].compactMap(\.self))
                },
                optionalDetails: ProviderOptionalDetailsPresentation(
                    hiddenTitlesWithoutOptionalUsage: ["Billing history"],
                    costSummaryTitles: ["Billing history"])),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: self.resolveStrategies)),
            cli: ProviderCLIConfig(
                name: "minimax",
                aliases: ["mini-max"],
                versionDetector: nil,
                browserSupportExemption: { sourceMode, environment, _ in
                    // Standard sk-api keys select the Coding Plan web strategy; other tokens use HTTPS directly.
                    guard sourceMode == .auto, let environment,
                          MiniMaxAPISettingsReader.apiToken(environment: environment) != nil else { return false }
                    return MiniMaxAPISettingsReader.apiKeyKind(environment: environment) != .standard
                }))
    }

    private static func resolveStrategies(context: ProviderFetchContext) async -> [any ProviderFetchStrategy] {
        switch context.sourceMode {
        case .web:
            return [MiniMaxCodingPlanFetchStrategy()]
        case .api:
            return [MiniMaxAPIFetchStrategy()]
        case .cli, .oauth:
            return []
        case .auto:
            break
        }
        let apiToken = ProviderTokenResolver.token(for: .minimax, environment: context.env)
        let apiKeyKind = MiniMaxAPISettingsReader.apiKeyKind(token: apiToken)
        let authMode = MiniMaxAuthMode.resolve(
            apiToken: apiToken,
            cookieHeader: ProviderTokenResolver.token(
                for: .minimax,
                kind: .secondary,
                environment: context.env))
        if authMode.usesAPIToken {
            if apiKeyKind == .standard {
                return [MiniMaxCodingPlanFetchStrategy()]
            }
            return [MiniMaxAPIFetchStrategy(), MiniMaxCodingPlanFetchStrategy()]
        }
        return [MiniMaxCodingPlanFetchStrategy()]
    }
}

struct MiniMaxAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "minimax.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        let authMode = MiniMaxAuthMode.resolve(
            apiToken: ProviderTokenResolver.token(
                for: .minimax,
                environment: context.env),
            cookieHeader: ProviderTokenResolver.token(
                for: .minimax,
                kind: .secondary,
                environment: context.env))
        if let kind = MiniMaxAPISettingsReader.apiKeyKind(environment: context.env),
           kind == .standard
        {
            return false
        }
        return authMode.usesAPIToken
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiToken = ProviderTokenResolver.token(for: .minimax, environment: context.env) else {
            throw MiniMaxAPISettingsError.missingToken
        }
        let region = context.settings?.minimax?.apiRegion ?? .global
        let usage = try await MiniMaxUsageFetcher.fetchUsage(apiToken: apiToken, region: region)
        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "api")
    }

    func shouldFallback(on error: Error, context _: ProviderFetchContext) -> Bool {
        guard let minimaxError = error as? MiniMaxUsageError else { return false }
        switch minimaxError {
        case .invalidCredentials:
            return true
        case let .apiError(message):
            return message.contains("HTTP 404")
        case .networkError, .parseFailed:
            return false
        }
    }
}

struct MiniMaxCodingPlanFetchStrategy: ProviderFetchStrategy {
    let id: String = "minimax.web"
    let kind: ProviderFetchKind = .web
    private static let log = CodexBarLog.logger(LogCategories.provider(.minimax, scope: "web"))

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        if Self.resolveCookieOverride(context: context) != nil {
            return true
        }
        guard (context.settings?.minimax?.cookieSource ?? .auto) == .auto else { return false }
        #if os(macOS)
        let region = context.settings?.minimax?.apiRegion ?? .global
        if Self.loadScopedCache(region: region) != nil { return true }
        guard Self.allowsBrowserCookieImport(context: context) else {
            return false
        }
        return (try? MiniMaxCookieImporter.sessionCandidates(
            browserDetection: context.browserDetection,
            region: region).first(where: { _ in true })) != nil
        #else
        return false
        #endif
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let fetchContext = FetchContext(
            region: context.settings?.minimax?.apiRegion ?? .global,
            environment: context.env,
            includeBillingHistory: context.includeOptionalUsage)
        if let override = Self.resolveCookieOverride(context: context) {
            Self.log.debug("Using MiniMax cookie header from settings/env")
            let snapshot = try await MiniMaxUsageFetcher.fetchUsage(
                cookieHeader: override.cookieHeader,
                authorizationToken: override.authorizationToken,
                groupID: override.groupID,
                region: fetchContext.region,
                environment: fetchContext.environment,
                includeBillingHistory: context.includeOptionalUsage)
            return self.makeResult(
                usage: snapshot.toUsageSnapshot(),
                sourceLabel: "web")
        }

        guard (context.settings?.minimax?.cookieSource ?? .auto) == .auto else {
            throw MiniMaxSettingsError.missingCookie
        }
        #if os(macOS)
        var lastError: Error?
        let scope = Self.cacheScope(region: fetchContext.region)
        var observedCache = CookieHeaderCache.load(provider: .minimax, scope: scope)
        if let cached = Self.decodeScopedCache(observedCache, region: fetchContext.region) {
            do {
                let snapshot = try await Self.fetchScoped(cached, context: fetchContext)
                return self.makeResult(usage: snapshot.toUsageSnapshot(), sourceLabel: "web")
            } catch {
                lastError = error
                guard Self.shouldTryNextBrowser(for: error) else { throw error }
                if CookieHeaderCache.clearIfCurrent(provider: .minimax, scope: scope, expected: observedCache) {
                    observedCache = nil
                }
            }
        }

        guard Self.allowsBrowserCookieImport(context: context) else {
            if let lastError { throw lastError }
            throw MiniMaxSettingsError.missingCookie
        }

        let sessions = (try? MiniMaxCookieImporter.sessionCandidates(
            browserDetection: context.browserDetection,
            region: fetchContext.region)) ?? AnySequence([])
        var tokenContexts: [String: ([MiniMaxLocalStorageImporter.TokenInfo], [String: String])] = [:]
        for session in sessions {
            guard let authority = session.authority, let scopeDomain = session.scopeDomain,
                  let hostOnly = session.hostOnly, !session.scopedRecords.isEmpty else { continue }
            if tokenContexts[authority] == nil {
                tokenContexts[authority] = (
                    MiniMaxLocalStorageImporter.importAccessTokens(
                        browserDetection: context.browserDetection,
                        authority: authority),
                    MiniMaxLocalStorageImporter.importGroupIDs(
                        browserDetection: context.browserDetection,
                        authority: authority))
            }
            guard let (tokens, groups) = tokenContexts[authority] else { continue }
            let candidates = tokens.filter {
                Self.normalizeStorageLabel($0.sourceLabel) == Self.normalizeStorageLabel(session.sourceLabel)
                    && URL(string: $0.origin)?.host?.lowercased() == scopeDomain
                    && Self.matchesCookieAccount(
                        token: $0.accessToken,
                        groupID: $0.groupID,
                        origin: $0.origin,
                        records: session.scopedRecords)
            }
            var attempts: [(String?, String?, String?, Bool)] = candidates.map { candidate in
                let matchedGroup = Self.matchesCookieAccount(
                    token: nil,
                    groupID: candidate.groupID,
                    origin: candidate.origin,
                    records: session.scopedRecords)
                    ? candidate.groupID : nil
                return (candidate.accessToken, matchedGroup, candidate.origin, false)
            }
            let prefix = Self.normalizeStorageLabel(session.sourceLabel) + "|"
            for (key, groupID) in groups where key.hasPrefix(prefix) {
                let origin = String(key.dropFirst(prefix.count))
                guard URL(string: origin)?.host?.lowercased() == scopeDomain,
                      Self.matchesCookieAccount(
                          token: nil,
                          groupID: groupID,
                          origin: origin,
                          records: session.scopedRecords) else { continue }
                attempts.append((nil, groupID, origin, false))
            }
            attempts.append((nil, nil, nil, true))
            attempts.append((nil, nil, nil, false))
            for (token, groupID, origin, useSessionBearer) in attempts {
                let scoped = ScopedBrowserCache(
                    authority: authority,
                    scopeDomain: scopeDomain,
                    hostOnly: hostOnly,
                    sourceLabel: session.sourceLabel,
                    records: session.scopedRecords,
                    authorizationToken: token,
                    authorizationOrigin: origin,
                    groupID: groupID,
                    useSessionBearer: useSessionBearer)
                do {
                    let snapshot = try await Self.fetchScoped(scoped, context: fetchContext)
                    Self.storeScopedCache(scoped, region: fetchContext.region, expected: observedCache)
                    return self.makeResult(usage: snapshot.toUsageSnapshot(), sourceLabel: "web")
                } catch {
                    lastError = error
                    guard Self.shouldTryNextBrowser(for: error) else { throw error }
                }
            }
        }

        if let lastError {
            throw lastError
        }
        #endif

        throw MiniMaxSettingsError.missingCookie
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    static func allowsBrowserCookieImport(context: ProviderFetchContext) -> Bool {
        context.runtime == .app && (context.settings?.minimax?.cookieSource ?? .auto) == .auto
    }

    #if os(macOS)
    struct ScopedBrowserCache: Codable {
        let authority: String
        let scopeDomain: String
        let hostOnly: Bool
        let sourceLabel: String
        let records: [ProviderPluginCookieRecord]
        let authorizationToken: String?
        let authorizationOrigin: String?
        let groupID: String?
        let useSessionBearer: Bool
    }

    static func matchesCookieAccount(
        token: String?,
        groupID: String?,
        origin: String,
        records: [ProviderPluginCookieRecord]) -> Bool
    {
        guard let url = URL(string: origin),
              let header = ProviderPluginCookieRecord.header(records, for: url) else { return false }
        let pairs = CookieHeaderNormalizer.pairs(from: header)
        let sessions = Set(pairs.filter { $0.name.caseInsensitiveCompare("HERTZ-SESSION") == .orderedSame }
            .map(\.value))
        guard sessions.count == 1 else { return false }
        // The group field can come from a different storage entry in the same profile.
        // Only byte-identical session tokens prove that a bearer belongs to this cookie.
        if let token { return sessions.contains(token) }
        guard let groupID, !groupID.isEmpty,
              let cookieGroup = MiniMaxCookieHeader.override(from: header)?.groupID else { return false }
        return groupID == cookieGroup
    }

    private static func cacheScope(region: MiniMaxAPIRegion) -> CookieHeaderCache.Scope {
        .providerVariant("minimax-scoped-v1-\(region.rawValue)")
    }

    private static func loadScopedCache(region: MiniMaxAPIRegion) -> ScopedBrowserCache? {
        self.decodeScopedCache(
            CookieHeaderCache.load(provider: .minimax, scope: self.cacheScope(region: region)), region: region)
    }

    static func decodeScopedCache(_ entry: CookieHeaderCacheEntry?, region: MiniMaxAPIRegion) -> ScopedBrowserCache? {
        guard let entry, entry.cookieHeader.hasPrefix("scoped="),
              let data = Data(base64Encoded: String(entry.cookieHeader.dropFirst("scoped=".count))),
              let cache = try? JSONDecoder().decode(ScopedBrowserCache.self, from: data),
              MiniMaxCookieImporter.isAllowed(authority: cache.authority, region: region),
              !cache.records.isEmpty,
              cache.records.allSatisfy({ $0.domain == cache.scopeDomain && $0.hostOnly == cache.hostOnly }),
              MiniMaxCookieImporter.authority(for: cache.scopeDomain) == cache.authority,
              cache.authorizationOrigin == nil || cache.authorizationOrigin.flatMap({ URL(string: $0) })
                  .flatMap(\.host)?.lowercased() == cache.scopeDomain,
                  cache.authorizationToken == nil || cache.authorizationOrigin.map({ self.matchesCookieAccount(
                      token: cache.authorizationToken,
                      groupID: nil,
                      origin: $0,
                      records: cache.records) }) == true,
                  cache.groupID == nil || cache.authorizationOrigin.map({ self.matchesCookieAccount(
                      token: nil,
                      groupID: cache.groupID,
                      origin: $0,
                      records: cache.records) }) == true
        else { return nil }
        return cache
    }

    private static func storeScopedCache(
        _ cache: ScopedBrowserCache, region: MiniMaxAPIRegion, expected: CookieHeaderCacheEntry?)
    {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        _ = CookieHeaderCache.storeIfCurrent(
            provider: .minimax,
            scope: self.cacheScope(region: region),
            expected: expected,
            cookieHeader: "scoped=" + data.base64EncodedString(),
            sourceLabel: cache.sourceLabel)
    }

    private static func fetchScoped(_ cache: ScopedBrowserCache, context: FetchContext) async throws
        -> MiniMaxUsageSnapshot
    {
        try await MiniMaxUsageFetcher.fetchUsage(MiniMaxUsageFetcher.WebFetchInput(
            cookieHeader: "scoped=1",
            authorizationToken: cache.authorizationToken,
            groupID: cache.groupID,
            region: context.region,
            environment: context.environment,
            includeBillingHistory: context.includeBillingHistory,
            transport: ProviderHTTPClient.shared,
            now: Date(),
            browserCookieRecords: cache.records,
            authorizationOrigin: cache.authorizationOrigin,
            useSessionBearer: cache.useSessionBearer))
    }
    #endif

    private struct FetchContext {
        let region: MiniMaxAPIRegion
        @ProcessEnvironment private(set) var environment: [String: String]
        let includeBillingHistory: Bool
    }

    private enum FetchAttemptResult {
        case success(MiniMaxUsageSnapshot)
        case failure(Error)
    }

    private static func resolveCookieOverride(context: ProviderFetchContext) -> MiniMaxCookieOverride? {
        if let settings = context.settings?.minimax {
            guard settings.cookieSource == .manual else { return nil }
            return MiniMaxCookieHeader.override(from: settings.manualCookieHeader)
        }
        guard let raw = ProviderTokenResolver.token(for: .minimax, kind: .secondary, environment: context.env) else {
            return nil
        }
        return MiniMaxCookieHeader.override(from: raw)
    }

    private static func normalizeStorageLabel(_ label: String) -> String {
        let suffixes = [" (Session Storage)", " (IndexedDB)"]
        for suffix in suffixes where label.hasSuffix(suffix) {
            return String(label.dropLast(suffix.count))
        }
        return label
    }

    private static func shouldTryNextBrowser(for error: Error) -> Bool {
        if case MiniMaxUsageError.invalidCredentials = error {
            return true
        }
        if case MiniMaxUsageError.parseFailed = error {
            return true
        }
        return false
    }
}
