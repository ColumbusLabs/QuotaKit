import Foundation
import SweetCookieKit

public enum CursorProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static let credentials = ProviderCredentialAdapter(tokenAccountSupport: TokenAccountSupport(
        title: "Session tokens",
        subtitle: "Store multiple Cursor Cookie headers.",
        placeholder: "Cookie: …",
        injection: .cookieHeader,
        requiresManualCookieSource: true,
        cookieName: nil,
        selectedAccountRequiresManualCookieSource: true))

    /// Active Cursor sessions often live only in Safari; Chromium profiles may carry stale tokens.
    private static var browserCookieOrder: BrowserCookieImportOrder? {
        #if os(macOS)
        [.safari] + Browser.defaultImportOrder.filter { $0 != .safari }
        #else
        nil
        #endif
    }

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .cursor,
            menuBarMetrics: ProviderMenuBarMetricCapabilities(
                supported: [.automatic, .primary, .secondary, .tertiary, .extraUsage],
                tertiaryRequiresWindow: true,
                namedExtras: [CursorSandUsageStatus.extraWindowID: CursorSandUsageStatus.extraWindowTitle],
                // Match QuotaKit’s Total, Auto and API lane names, including older saved layouts.
                laneShortLabels: [.primary: "T", .secondary: "A", .tertiary: "API"],
                namedExtraShortLabels: [CursorSandUsageStatus.extraWindowID: "GB"]),
            settingsSection: .init(CursorProviderSettingsKey.self, cookieSettings: CursorProviderSettings.self),
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .cursor,
                displayName: "Cursor",
                sessionLabel: "Total",
                weeklyLabel: "Auto",
                opusLabel: "API",
                supportsOpus: true,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Cursor usage",
                cliName: "cursor",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                sharePlanLabels: [
                    "free": "Cursor Free", "cursor free": "Cursor Free",
                    "hobby": "Cursor Hobby", "cursor hobby": "Cursor Hobby",
                    "pro": "Cursor Pro", "cursor pro": "Cursor Pro",
                    "team": "Cursor Team", "cursor team": "Cursor Team",
                    "business": "Cursor Business", "cursor business": "Cursor Business",
                    "enterprise": "Cursor Enterprise", "cursor enterprise": "Cursor Enterprise",
                    "ultra": "Cursor Ultra", "cursor ultra": "Cursor Ultra",
                ],
                debugPane: ProviderDebugPaneCapabilities(probeLogOrder: 2),
                browserCookieOrder: self.browserCookieOrder
                    ?? ProviderBrowserCookieDefaults.defaultImportOrder,
                dashboardURL: "https://cursor.com/dashboard?tab=usage",
                statusPageURL: "https://status.cursor.com",
                statusLinkURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .cursor),
                iconResourceName: "ProviderIcon-cursor",
                color: ProviderColor(hex: 0xF54E00),
                confettiPalette: [
                    ProviderColor(hex: 0x1B1913),
                    ProviderColor(hex: 0xEDECEC),
                ],
                progressColorStyle: .label),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: true,
                noDataMessage: { "No Cursor cost usage found. Sign in to Cursor in your browser or the Cursor app." },
                menuHintLines: [.estimate],
                supportsTokenSnapshot: self.supportsTokenSnapshot,
                settingsStatusOrder: 2,
                estimateDisclaimer: "From Cursor's usage dashboard at vendor token rates; may differ from your " +
                    "invoice."),
            pace: ProviderPaceCapability(resetWindowPace: .windowDurationPresent),
            presentation: ProviderUsagePresentation(
                rateWindowLabeler: { metadata, snapshot, _ in
                    if let weekly = Self.primaryLabel(snapshot: snapshot) {
                        return ProviderRateWindowLabels(
                            primary: weekly,
                            secondary: weekly,
                            tertiary: metadata.opusLabel ?? "Sonnet",
                            showsTertiary: metadata.supportsOpus)
                    }
                    return Self.rateWindowLabels(metadata: metadata, snapshot: snapshot)
                },
                extraRateWindowSelector: { snapshot in
                    (snapshot.extraRateWindows ?? []).filter { $0.id == CursorSandUsageStatus.extraWindowID }
                },
                semanticWindowResolver: self.semanticWindows,
                requestedMenuBarLaneOrders: [
                    .tertiary: [.tertiary, .secondary, .primary],
                ],
                automaticSelectionPrioritizesExhaustedWindow: false,
                menuBarWindowResolver: self.menuBarWindow,
                menuCard: ProviderMenuCardPresentation(
                    costVisibilityResolver: { $0.showOptionalUsage },
                    supportsInlineTokenCostDashboard: true,
                    primaryDetailKind: .requestQuota)),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .cli, .web],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [CursorStatusFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "cursor",
                versionDetector: nil,
                supportsCostCommand: self.supportsCostCommand,
                browserSupportExemption: { sourceMode, _, settings in
                    #if os(Linux)
                    guard settings?.cursor?.cookieSource != .off else { return false }
                    if settings?.cursor?.cookieSource == .manual {
                        return CookieHeaderNormalizer.normalize(settings?.cursor?.manualCookieHeader) != nil
                    }
                    // App auth needs no browser integration. Explicit web mode still requires a manual cookie.
                    return sourceMode == .auto || sourceMode == .cli
                    #else
                    false
                    #endif
                }),
            nativeAppBundleIdentifiers: ["com.todesktop.230313mzl4w4u92"])
    }

    /// Persisted Cursor layouts can place Auto/API in the first two slots instead of Total/Auto/API.
    private static func rateWindowLabels(
        metadata: ProviderMetadata,
        snapshot: UsageSnapshot) -> ProviderRateWindowLabels
    {
        let labels: (String, String) = switch snapshot.cursorRateWindowLayout {
        case .requests: ("Requests", metadata.weeklyLabel)
        case .plan: ("Plan", metadata.weeklyLabel)
        case .apiOnly: ("API", metadata.weeklyLabel)
        case .autoOnly: ("Auto", metadata.weeklyLabel)
        case .autoAPI: ("Auto", "API")
        case .none:
            (
                snapshot.cursorRequests == nil && snapshot.detailRow(label: "Request quota") == nil
                    ? metadata.sessionLabel : "Requests",
                metadata.weeklyLabel)
        }
        return ProviderRateWindowLabels(
            primary: labels.0,
            secondary: labels.1,
            tertiary: metadata.opusLabel ?? "Tertiary",
            showsTertiary: metadata.supportsOpus)
    }

    /// The X Subscription's shared weekly pool replaces the monthly Auto lane as the primary window.
    public static func primaryLabel(snapshot: UsageSnapshot) -> String? {
        self.sharedWeeklyPool(snapshot: snapshot) == nil ? nil : "Weekly"
    }

    /// Monthly Cursor billing cycles do not span exactly seven days, so this identifies the shared pool.
    public static func sharedWeeklyPool(snapshot: UsageSnapshot) -> RateWindow? {
        guard let primary = snapshot.primary, primary.windowMinutes == 10080, snapshot.secondary == nil,
              snapshot.detailRow(label: "Request quota") == nil
        else {
            return nil
        }
        return primary
    }

    /// Keep saved Grok Bot menu-bar tokens attached after the allowance becomes the primary pool.
    public static func menuBarExtras(snapshot: UsageSnapshot) -> [NamedRateWindow] {
        guard let window = self.sharedWeeklyPool(snapshot: snapshot) else { return snapshot.extraRateWindows ?? [] }
        return [NamedRateWindow(
            id: CursorSandUsageStatus.extraWindowID,
            title: CursorSandUsageStatus.extraWindowTitle,
            window: window)]
    }

    private static var supportsCostCommand: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// Grok Bot is a named extra 7-day allowance. Cursor's monthly Auto bar is the secondary lane
    /// (`weeklyLabel` "Cursor"), so it is the semantic weekly window. The default duration matcher
    /// would pick Grok Bot instead and paint that weekly pace onto Cursor Auto after a billing reset.
    private static func semanticWindows(snapshot: UsageSnapshot) -> ProviderSemanticWindows {
        let weekly = snapshot.secondary.flatMap { window -> RateWindow? in
            guard !window.isSyntheticPlaceholder else { return nil }
            return window
        } ?? Self.sharedWeeklyPool(snapshot: snapshot)
        return ProviderSemanticWindows(session: Self.sharedWeeklyPool(snapshot: snapshot), weekly: weekly)
    }

    private static func menuBarWindow(
        context: ProviderMenuBarWindowContext) -> ProviderMenuBarWindowResolution
    {
        guard context.metric == .automatic else { return .unhandled }
        let snapshot = context.snapshot
        let grokBot = Self.menuBarExtras(snapshot: snapshot).first {
            $0.id == CursorSandUsageStatus.extraWindowID && $0.usageKnown
        }?.window
        if let sharedWeeklyPool = Self.sharedWeeklyPool(snapshot: snapshot) {
            return .resolved(sharedWeeklyPool)
        }
        if let layout = snapshot.cursorRateWindowLayout {
            return switch layout {
            case .autoAPI:
                .automaticCandidates(Self.automaticQuotaCandidates(
                    total: nil,
                    auto: snapshot.primary,
                    api: snapshot.secondary,
                    grokBot: grokBot))
            case .requests:
                .resolved(snapshot.primary)
            case .autoOnly:
                .automaticCandidates(Self.automaticQuotaCandidates(
                    total: nil,
                    auto: snapshot.primary,
                    api: nil,
                    grokBot: grokBot))
            case .apiOnly:
                .automaticCandidates(Self.automaticQuotaCandidates(
                    total: nil,
                    auto: nil,
                    api: snapshot.primary,
                    grokBot: grokBot))
            case .plan:
                .automaticCandidates(Self.automaticQuotaCandidates(
                    total: snapshot.primary,
                    auto: nil,
                    api: nil,
                    grokBot: grokBot))
            }
        }
        if snapshot.tertiary == nil {
            // Backward compatibility for snapshots written before Cursor's explicit layout
            // discriminator: the two stored lanes were Auto and API, not Total and Auto.
            return .automaticCandidates(Self.automaticQuotaCandidates(
                total: nil,
                auto: snapshot.primary,
                api: snapshot.secondary,
                grokBot: grokBot))
        }
        return .automaticCandidates(Self.automaticQuotaCandidates(
            total: snapshot.primary,
            auto: snapshot.secondary,
            api: snapshot.tertiary,
            grokBot: grokBot))
    }

    private static func automaticQuotaCandidates(
        total: RateWindow?,
        auto: RateWindow?,
        api: RateWindow?,
        grokBot: RateWindow?) -> [RateWindow]
    {
        let subquotas = [auto, api, grokBot].compactMap(\.self)
        let usableSubquotas = subquotas.filter { $0.remainingPercent > 0 }
        if let total, total.remainingPercent <= 0 {
            return [total]
        }
        if !subquotas.isEmpty, usableSubquotas.isEmpty {
            return subquotas
        }
        return [total].compactMap(\.self) + usableSubquotas
    }

    private static var supportsTokenSnapshot: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}

struct CursorStatusFetchStrategy: ProviderFetchStrategy {
    let id: String = "cursor.web"
    let kind: ProviderFetchKind = .web

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        guard context.settings?.cursor?.cookieSource != .off else { return false }
        return true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let probe = CursorStatusProbe(browserDetection: context.browserDetection)
        let manual = Self.manualCookieHeader(from: context)
        let logger: ((String) -> Void)? = context.verbose
            ? { message in CodexBarLog.logger(LogCategories.provider(.cursor)).verbose(message) }
            : nil
        let snap = try await probe.fetch(
            cookieHeaderOverride: manual,
            allowAppAuthFallback: context.sourceMode != .web,
            logger: logger)
        return self.makeResult(
            usage: snap.toUsageSnapshot(),
            sourceLabel: "web")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func manualCookieHeader(from context: ProviderFetchContext) -> String? {
        guard context.settings?.cursor?.cookieSource == .manual else { return nil }
        return CookieHeaderNormalizer.normalize(context.settings?.cursor?.manualCookieHeader)
    }
}
