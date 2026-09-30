import Foundation

public enum ZoomMateProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .zoommate,
            settingsSection: .init(ZoomMateProviderSettingsKey.self, cookieSettings: ZoomMateProviderSettings.self),
            metadata: ProviderMetadata(
                id: .zoommate,
                displayName: "ZoomMate",
                sessionLabel: "Credits",
                weeklyLabel: "Credits",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: true,
                creditsHint: "Shows used/remaining credits against your ZoomMate budget cap.",
                toggleTitle: "Show ZoomMate usage",
                cliName: "zoommate",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                debugLogUnavailableMessage: "ZoomMate debug log not yet implemented",
                debugPane: ProviderDebugPaneCapabilities(errorSimulationOrder: 7),
                browserCookieOrder: BrowserCookieImportSupport.chromeOnly(
                    reason: "Avoid surprise permission prompts from other browser stores"),
                dashboardURL: "https://zoommate.zoom.us/#/?settings=credit-usage",
                subscriptionDashboardURL: nil,
                statusPageURL: "https://www.zoomstatus.com/",
                statusComponentAllowlist: [
                    "Zoom Meetings",
                    "ZoomMate",
                    "My Notes",
                    "Zoom Workflows",
                    "Zoom Developer Platform",
                    "Zoom Support",
                    "Zoom Website",
                ]),
            branding: ProviderBranding(
                iconStyle: .init(provider: .zoommate),
                iconResourceName: "ProviderIcon-zoommate",
                // Zoom Brand Center "Visual identity > Color", retrieved 2026-07-18:
                // https://brand.zoom.com/document/1#/visual-identity/color
                // Bloom is primary; Dawn and Midnight are supporting core colors.
                color: ProviderColor(red: 64 / 255, green: 176 / 255, blue: 255 / 255),
                confettiPalette: [
                    ProviderColor(hex: 0x40B0FF),
                    ProviderColor(hex: 0xB4D0F8),
                    ProviderColor(hex: 0x00053D),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "ZoomMate cost summary is not supported." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [ZoomMateWebFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "zoommate",
                aliases: [],
                versionDetector: nil,
                browserSupportExemption: { _, _, settings in
                    settings?.zoommate?.cookieSource == .manual &&
                        CookieHeaderNormalizer.normalize(settings?.zoommate?.manualCookieHeader) != nil
                }))
    }
}

/// Single unified strategy (modeled on `T3ChatWebFetchStrategy`) branching internally on the
/// selected `cookieSource`: `.auto` resolves a cookie session — the `CookieHeaderCache`d host map
/// first, else a fresh browser import whose validated headers are persisted back through the cache —
/// and mints a bearer JWT via `ZoomMateUsageFetcher.mintBearerToken`, reusing a still-valid token
/// from `ZoomMateBearerTokenCache` across refreshes; `.manual` uses the pasted cURL capture.
/// Cookies outlive the ~hourly JWT by weeks, so minting from cookies (and caching the result until
/// it nears expiry) avoids the manual re-paste entirely as long as the underlying browser session
/// stays valid, and the persisted headers let background refreshes and the bundled CLI reuse that
/// session without rereading Chrome. A rejected session clears the cached header and retries once
/// with a fresh import (see `fetch`).
struct ZoomMateWebFetchStrategy: ProviderFetchStrategy {
    let id: String = "zoommate.web"
    let kind: ProviderFetchKind = .web

    private struct CredentialRejection: Error {
        let mayRetryWithFreshImport: Bool
    }

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        let cookieSource = context.settings?.zoommate?.cookieSource ?? .auto
        guard cookieSource != .off else { return false }
        if cookieSource == .manual {
            return true
        }
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let cookieSource = context.settings?.zoommate?.cookieSource ?? .auto
        do {
            return try await self.fetchOnce(context, allowCachedCookieHeader: true)
        } catch let rejection as CredentialRejection where cookieSource == .auto {
            guard rejection.mayRetryWithFreshImport else {
                throw ZoomMateUsageError.invalidCredentials
            }
            do {
                return try await self.fetchOnce(context, allowCachedCookieHeader: false)
            } catch is CredentialRejection {
                throw ZoomMateUsageError.invalidCredentials
            }
        } catch let rejection as ZoomMateCachedCookieRejection where cookieSource == .auto {
            guard rejection.mayRetryWithFreshImport else {
                throw ZoomMateUsageError.invalidCredentials
            }
            do {
                return try await self.fetchOnce(context, allowCachedCookieHeader: false)
            } catch is CredentialRejection {
                throw ZoomMateUsageError.invalidCredentials
            }
        } catch is CredentialRejection {
            throw ZoomMateUsageError.invalidCredentials
        } catch is ZoomMateCachedCookieRejection {
            throw ZoomMateUsageError.invalidCredentials
        } catch ZoomMateUsageError.invalidCredentials where cookieSource == .auto {
            // A login-bootstrap rejection has no request-owned cached receipt yet. Retry once
            // through the existing import gate without clearing state owned by another refresh.
            do {
                return try await self.fetchOnce(context, allowCachedCookieHeader: false)
            } catch is CredentialRejection {
                throw ZoomMateUsageError.invalidCredentials
            }
        }
    }

    private func fetchOnce(
        _ context: ProviderFetchContext,
        allowCachedCookieHeader: Bool) async throws -> ProviderFetchResult
    {
        let fetcher = ZoomMateUsageFetcher(browserDetection: context.browserDetection)
        let manual = Self.manualCookieHeader(from: context)
        let logger: (@Sendable (String) -> Void)? = context.verbose
            ? { @Sendable msg in CodexBarLog.logger(LogCategories.provider(.zoommate)).verbose(msg) }
            : nil
        let requestContext = try await fetcher.resolveRequestContext(
            manualCaptureOverride: manual,
            allowCachedCookieHeader: allowCachedCookieHeader,
            timeout: context.webTimeout,
            logger: logger)
        let snapshot: ZoomMateUsageSnapshot
        do {
            snapshot = try await ZoomMateUsageFetcher.fetchCreditsStatus(
                context: requestContext,
                timeout: context.webTimeout)
        } catch ZoomMateUsageError.invalidCredentials {
            // Clear only the exact bearer and cookie observations used by this request. A newer
            // login or token generation owns the current state and suppresses the stale retry.
            let bearerCurrent = await Self.invalidateCachedBearerToken(for: requestContext)
            let cookieClear: CookieHeaderCache.ConditionalMutationResult = if bearerCurrent,
                                                                              let observation = requestContext
                                                                                  .cookieObservation
            {
                CookieHeaderCache.clearIfObservationCurrent(
                    provider: .zoommate,
                    expected: observation)
            } else {
                .rejected
            }
            throw CredentialRejection(
                mayRetryWithFreshImport: bearerCurrent && cookieClear == .stored)
        }

        // The Today/30-day history chart (design.md D3) is a non-fatal adjunct: a failure here
        // (e.g. a transient credits/history error) must never block the primary credits/status
        // snapshot from being usable, mirroring ZaiUsageStats.fetchUsageWithModelUsage's
        // secondary-fetch pattern.
        var history: ZoomMateCreditsHistorySnapshot?
        do {
            let now = Date()
            let startTime = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
            history = try await ZoomMateCreditsHistoryFetcher.fetch(
                context: requestContext,
                startTime: startTime,
                endTime: now,
                creditStatus: snapshot.creditStatus,
                timeout: context.webTimeout)
        } catch ZoomMateUsageError.invalidCredentials {
            await Self.invalidateCachedBearerToken(for: requestContext)
            CodexBarLog.logger(LogCategories.provider(.zoommate))
                .info("ZoomMate credits history fetch failed (non-fatal): invalid credentials")
            history = nil
        } catch {
            CodexBarLog.logger(LogCategories.provider(.zoommate))
                .info("ZoomMate credits history fetch failed (non-fatal): \(error.localizedDescription)")
            history = nil
        }

        return self.makeResult(
            usage: snapshot.toUsageSnapshot(history: history, accountEmail: requestContext.accountEmail),
            sourceLabel: "web")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func manualCookieHeader(from context: ProviderFetchContext) -> String? {
        guard context.settings?.zoommate?.cookieSource == .manual else { return nil }
        return context.settings?.zoommate?.manualCookieHeader ?? ""
    }

    @discardableResult
    private static func invalidateCachedBearerToken(for requestContext: ZoomMateUsageFetcher
        .RequestContext) async -> Bool
    {
        guard let observation = requestContext.bearerObservation else { return true }
        return await ZoomMateBearerTokenCache.shared.invalidateIfCurrent(observation)
    }
}
