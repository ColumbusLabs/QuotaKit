import CodexBarCore
import Foundation

struct DashboardAccountsInput: Sendable {
    let accounts: [ProviderAccountUsageSnapshot]?
    let adapterError: String?
    let weeklyWorkDays: Int?
    let showSingleAccount: Bool

    init(
        accounts: [ProviderAccountUsageSnapshot]?,
        adapterError: String?,
        weeklyWorkDays: Int?,
        showSingleAccount: Bool = false)
    {
        self.accounts = accounts
        self.adapterError = adapterError
        self.weeklyWorkDays = weeklyWorkDays
        self.showSingleAccount = showSingleAccount
    }
}

/// Projects the CLI's provider usage and cost payloads into the stable,
/// display-oriented `/dashboard/v1/snapshot` contract.
enum DashboardSnapshotBuilder {
    private struct ProviderPresentation {
        let id: String
        let name: String
        let enabled: Bool
        let display: DashboardDisplayPayload
    }

    // swiftlint:disable:next function_parameter_count
    static func makeSnapshot(
        usagePayloads: [ProviderPayload],
        costPayloads: [CostPayload],
        config: CodexBarConfig,
        identityMode: DashboardIdentityMode,
        generatedAt: Date,
        refreshInterval: TimeInterval,
        codexBarVersion: String?,
        accountCollections: [UsageProvider: DashboardAccountsInput] = [:],
        usageBarsShowUsed: Bool = false,
        allAccounts: Bool = false) -> DashboardSnapshotPayload
    {
        var costByProvider: [String: CostPayload] = [:]
        for cost in costPayloads {
            costByProvider[cost.provider] = cost
        }
        var attachedProviders: Set<UsageProvider> = []
        let grouped = Dictionary(grouping: usagePayloads, by: \.provider)
        let selectedPayloads = self.selectedPayloads(usagePayloads, allAccounts: allAccounts)
        let providers = selectedPayloads.enumerated().map { index, payload in
            var rowAccounts: DashboardAccountsInput?
            if let provider = UsageProvider(rawValue: payload.provider), attachedProviders.insert(provider).inserted {
                rowAccounts = accountCollections[provider]
            }
            let presentation = self.providerPresentation(
                id: payload.provider,
                config: config,
                fallbackSortKey: 10000 + index)
            return self.makeProvider(
                payload: payload,
                cost: costByProvider[payload.provider],
                presentation: presentation,
                identityMode: identityMode,
                generatedAt: generatedAt,
                accountCollection: rowAccounts,
                accountCollectionIncomplete: allAccounts && self.accountCollectionIncomplete(
                    provider: payload.provider,
                    payloads: grouped[payload.provider] ?? [],
                    config: config),
                accountPayloads: allAccounts ? grouped[payload.provider] : nil)
        }

        let refreshSeconds = self.dashboardRefreshSeconds(refreshInterval)
        return DashboardSnapshotPayload(
            schemaVersion: 1,
            generatedAt: generatedAt,
            staleAfterSeconds: max(180, refreshSeconds * 3),
            host: DashboardHostPayload(
                codexBarVersion: codexBarVersion,
                refreshIntervalSeconds: refreshSeconds,
                usageBarsShowUsed: usageBarsShowUsed),
            providers: providers)
    }

    static func makeShellSnapshot(
        config: CodexBarConfig,
        providers requestedProviders: [UsageProvider]? = nil,
        generatedAt: Date,
        refreshInterval: TimeInterval,
        codexBarVersion: String?,
        usageBarsShowUsed: Bool = false) -> DashboardSnapshotPayload
    {
        let providers = requestedProviders
            ?? config.enabledProviders().compactMap(\.firstPartyProvider)
        let rows = providers.enumerated().map { index, provider in
            let presentation = self.providerPresentation(
                id: provider.rawValue,
                config: config,
                fallbackSortKey: 10000 + index)
            return DashboardProviderPayload(
                id: presentation.id,
                name: presentation.name,
                enabled: presentation.enabled,
                source: "",
                status: nil,
                identity: nil,
                windows: [],
                credits: nil,
                cost: nil,
                display: presentation.display,
                error: nil,
                updatedAt: nil,
                accounts: nil,
                accountsError: nil,
                detail: .shell)
        }
        let refreshSeconds = self.dashboardRefreshSeconds(refreshInterval)
        return DashboardSnapshotPayload(
            schemaVersion: 1,
            generatedAt: generatedAt,
            staleAfterSeconds: max(180, refreshSeconds * 3),
            host: DashboardHostPayload(
                codexBarVersion: codexBarVersion,
                refreshIntervalSeconds: refreshSeconds,
                usageBarsShowUsed: usageBarsShowUsed),
            providers: rows)
    }

    // swiftlint:disable:next function_parameter_count
    private static func makeProvider(
        payload: ProviderPayload,
        cost: CostPayload?,
        presentation: ProviderPresentation,
        identityMode: DashboardIdentityMode,
        generatedAt: Date,
        accountCollection: DashboardAccountsInput?,
        accountCollectionIncomplete: Bool,
        accountPayloads: [ProviderPayload]?) -> DashboardProviderPayload
    {
        let provider = UsageProvider(rawValue: payload.provider)
        let descriptor = provider.map { ProviderDescriptorRegistry.descriptor(for: $0) }
        let metadata = descriptor?.metadata

        let error = (payload.error ?? cost?.error).map {
            ProviderErrorPayload(
                code: $0.code,
                message: accountPayloads != nil && identityMode != .full ? "Account usage unavailable" : $0.message,
                kind: $0.kind)
        }
        let collectedAccounts = accountPayloads?.enumerated().compactMap { index, accountPayload in
            self.makeUsageAccount(accountPayload, identityMode: identityMode, number: index + 1)
        }
        var collectedByID: [String: DashboardAccountPayload] = [:]
        for account in collectedAccounts ?? [] where collectedByID[account.id] == nil {
            collectedByID[account.id] = account
        }
        let providerAccounts = accountCollection?.accounts?.filter { $0.provider == provider }
        // Provider-specific by design: Claude Swap hides one account row unless its display option is enabled.
        let projectedAccounts: [ProviderAccountUsageSnapshot]? = if provider == .claude,
                                                                    let providerAccounts,
                                                                    !providerAccounts.isEmpty,
                                                                    !ClaudeSwapAccountProjection.shouldPresentAccounts(
                                                                        accountCount: providerAccounts.count,
                                                                        showSingleAccount: accountCollection?
                                                                            .showSingleAccount == true)
        {
            nil
        } else {
            providerAccounts
        }
        // Provider-specific by design: saved managed Codex snapshots remain authoritative for matching accounts;
        // all-account RPC output adds only previously unseen profile and live accounts.
        var accounts = accountCollection?.adapterError == nil
            ? projectedAccounts?.enumerated().map { index, account in
                let saved = self.makeAccount(
                    account,
                    identityMode: identityMode,
                    weeklyWorkDays: accountCollection?.weeklyWorkDays,
                    generatedAt: generatedAt,
                    privateLabel: accountPayloads != nil && identityMode != .full ? "Account \(index + 1)" : nil)
                guard provider == .codex, let current = collectedByID[saved.id] else { return saved }
                return self.preferCurrentUsage(current, over: saved)
            }
            : nil
        if provider == .codex, let accountPayloads {
            var knownIDs = Set(accounts?.map(\.id) ?? [])
            let additional = (collectedAccounts ?? []).compactMap { account -> DashboardAccountPayload? in
                guard knownIDs.insert(account.id).inserted else { return nil }
                guard identityMode != .full else { return account }
                return self.relabel(account, as: "Account \(knownIDs.count)")
            }
            accounts = (accounts ?? []) + additional
        }
        let accountsError: String? = if let adapterError = accountCollection?.adapterError {
            accountPayloads != nil && identityMode != .full ? "Account list unavailable" : adapterError
        } else if accountCollectionIncomplete {
            "Account list incomplete"
        } else {
            nil
        }
        return DashboardProviderPayload(
            id: presentation.id,
            name: presentation.name,
            enabled: presentation.enabled,
            source: self.dashboardSource(from: payload.source),
            status: self.makeStatus(payload.status),
            identity: self.makeIdentity(provider: provider, usage: payload.usage, mode: identityMode),
            windows: self.makeWindows(provider: provider, metadata: metadata, usage: payload.usage),
            credits: self.makeCredits(
                payload.credits,
                provider: provider,
                providerCost: payload.usage?.providerCost),
            cost: cost != nil
                ? self.makeCost(cost, referenceDate: generatedAt)
                : self.makeReportedCost(payload.usage?.costUsage),
            display: presentation.display,
            error: error,
            updatedAt: self.updatedAt(
                payload: payload,
                cost: cost,
                error: error,
                generatedAt: generatedAt),
            accounts: accountCollection != nil ? accounts :
                (collectedAccounts?.isEmpty == false ? collectedAccounts : nil),
            accountsError: accountsError)
    }

    private static func accountCollectionIncomplete(
        provider: String,
        payloads: [ProviderPayload],
        config: CodexBarConfig) -> Bool
    {
        if payloads.contains(where: \.dashboardAccountsIncomplete) { return true }
        guard let provider = UsageProvider(rawValue: provider),
              TokenAccountSupportCatalog.support(for: provider) != nil,
              let accounts = config.providerConfig(for: provider.instanceID)?.tokenAccounts?.accounts
        else { return false }
        let collectedIDs = Set(payloads.compactMap { $0.dashboardAccount?.id })
        return accounts.contains { !collectedIDs.contains(DashboardUsageAccount.token($0, active: false).id) }
    }

    /// Preserve provider order while choosing the active account for each expanded top-level row.
    static func selectedPayloads(_ payloads: [ProviderPayload], allAccounts: Bool) -> [ProviderPayload] {
        guard allAccounts else { return payloads }
        let groups = Dictionary(grouping: payloads, by: \.provider)
        var seen = Set<String>()
        return payloads.compactMap { payload in
            guard seen.insert(payload.provider).inserted else { return nil }
            return groups[payload.provider]?.first(where: { $0.dashboardAccount?.active == true }) ?? payload
        }
    }

    private static func makeUsageAccount(
        _ payload: ProviderPayload,
        identityMode: DashboardIdentityMode,
        number: Int) -> DashboardAccountPayload?
    {
        guard let account = payload.dashboardAccount else { return nil }
        let provider = UsageProvider(rawValue: payload.provider)
        let metadata = provider.map { ProviderDescriptorRegistry.descriptor(for: $0).metadata }
        return DashboardAccountPayload(
            id: account.id,
            label: identityMode == .full ? (account.label.isEmpty ? "Account" : account.label) : "Account \(number)",
            active: account.active,
            identity: self.makeIdentity(provider: provider, usage: payload.usage, mode: identityMode),
            windows: self.makeWindows(provider: provider, metadata: metadata, usage: payload.usage),
            pace: payload.pace,
            error: payload.error.map { identityMode == .full ? $0.message : "Account usage unavailable" },
            updatedAt: payload.usage?.updatedAt)
    }

    private static func relabel(_ account: DashboardAccountPayload, as label: String) -> DashboardAccountPayload {
        DashboardAccountPayload(
            id: account.id,
            label: label,
            active: account.active,
            identity: account.identity,
            windows: account.windows,
            pace: account.pace,
            error: account.error,
            updatedAt: account.updatedAt)
    }

    private static func preferCurrentUsage(
        _ current: DashboardAccountPayload,
        over saved: DashboardAccountPayload) -> DashboardAccountPayload
    {
        guard current.error == nil, current.updatedAt != nil else {
            return DashboardAccountPayload(
                id: saved.id,
                label: saved.label,
                active: current.active,
                identity: saved.identity,
                windows: saved.windows,
                pace: saved.pace,
                error: saved.error,
                updatedAt: saved.updatedAt)
        }
        return DashboardAccountPayload(
            id: saved.id,
            label: saved.label,
            active: current.active,
            identity: current.identity ?? saved.identity,
            windows: current.windows,
            pace: current.pace ?? saved.pace,
            error: nil,
            updatedAt: current.updatedAt)
    }

    private static func providerPresentation(
        id: String,
        config: CodexBarConfig,
        fallbackSortKey: Int) -> ProviderPresentation
    {
        let provider = UsageProvider(rawValue: id)
        let descriptor = provider.map { ProviderDescriptorRegistry.descriptor(for: $0) }
        let enabledProviders = Set(config.enabledProviders().compactMap(\.firstPartyProvider))
        let sortKey = config.orderedProviders().firstIndex { $0.rawValue == id }.map { $0 * 10 }
            ?? fallbackSortKey
        let accentOverride = ProviderInstanceID(rawValue: id)
            .flatMap { config.providerConfig(for: $0)?.accentColor }
            .flatMap { ProviderColor(hexString: $0) }
        return ProviderPresentation(
            id: id,
            name: descriptor?.metadata.displayName ?? id,
            enabled: provider.map { enabledProviders.contains($0) } ?? true,
            display: DashboardDisplayPayload(
                accentColor: self.hexColor(accentOverride ?? descriptor?.branding.color),
                sortKey: sortKey,
                priority: "normal"))
    }

    private static func makeAccount(
        _ account: ProviderAccountUsageSnapshot,
        identityMode: DashboardIdentityMode,
        weeklyWorkDays: Int?,
        generatedAt: Date,
        privateLabel: String? = nil) -> DashboardAccountPayload
    {
        // Provider-specific by design: identity stays the source email. Aliases and organization labels can
        // contain personal or workspace-identifying text, so redacted output retains only the redacted mailbox.
        let sourceEmail: String? = {
            if let email = account.accountEmail, email.contains("@") { return email }
            if let email = account.snapshot?.identity(for: account.provider.instanceID)?.accountEmail,
               email.contains("@") { return email }
            return nil
        }()
        let presentedEmail = identityMode != .none && sourceEmail?.contains("@") == true
            ? self.dashboardEmail(sourceEmail, mode: identityMode)
            : nil
        // Provider-specific by design: claude-swap has no plan; Codex retains its saved account plan.
        let plan = account.provider == .codex
            ? self.makeIdentity(provider: account.provider, usage: account.snapshot, mode: identityMode)?.plan : nil
        let identity = presentedEmail.map { DashboardIdentityPayload(accountEmail: $0, plan: plan) }
        let trimmedLabel = account.displayLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackLabel = trimmedLabel.isEmpty ? "Account \(account.id.opaqueID)" : trimmedLabel
        let label = self.dashboardAccountLabel(
            displayLabel: fallbackLabel,
            sourceEmail: sourceEmail,
            presentedEmail: presentedEmail,
            accountID: account.id.opaqueID,
            identityMode: identityMode)
        let metadata = ProviderDescriptorRegistry.descriptor(for: account.provider).metadata
        return DashboardAccountPayload(
            id: "\(account.id.source):\(account.id.opaqueID)",
            label: privateLabel ?? label,
            active: account.isActive,
            identity: identity,
            windows: self.makeWindows(provider: account.provider, metadata: metadata, usage: account.snapshot),
            pace: account.snapshot.flatMap {
                CLIRenderer.providerPacePayload(
                    provider: account.provider,
                    snapshot: $0,
                    weeklyWorkDays: weeklyWorkDays,
                    now: generatedAt)
            },
            error: account.error.map { privateLabel != nil ? "Account usage unavailable" : $0 },
            updatedAt: account.snapshot?.updatedAt)
    }

    private static func dashboardAccountLabel(
        displayLabel: String,
        sourceEmail: String?,
        presentedEmail: String?,
        accountID: String,
        identityMode: DashboardIdentityMode) -> String
    {
        switch identityMode {
        case .full:
            return displayLabel
        case .none:
            return "Account \(accountID)"
        case .redacted:
            guard let presentedEmail, let sourceEmail else {
                return "Account \(accountID)"
            }
            if displayLabel == sourceEmail {
                return presentedEmail
            }
            if displayLabel.hasPrefix(sourceEmail) {
                return "\(presentedEmail) · Account \(accountID)"
            }
            return "Account \(accountID)"
        }
    }

    private static func dashboardSource(from source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private static func makeStatus(_ status: ProviderStatusPayload?) -> DashboardStatusPayload? {
        guard let status else { return nil }
        return DashboardStatusPayload(
            level: self.dashboardStatusLevel(status.indicator),
            label: status.indicator.label,
            updatedAt: status.updatedAt)
    }

    private static func dashboardStatusLevel(_ indicator: ProviderStatusPayload.ProviderStatusIndicator) -> String {
        switch indicator {
        case .none:
            "ok"
        case .minor, .maintenance:
            "warning"
        case .major, .critical:
            "critical"
        case .unknown:
            "unknown"
        }
    }

    private static func makeIdentity(
        provider: UsageProvider?,
        usage: UsageSnapshot?,
        mode: DashboardIdentityMode) -> DashboardIdentityPayload?
    {
        guard mode != .none,
              let provider,
              let identity = usage?.identity(for: provider.instanceID)
        else {
            return nil
        }

        let email = self.dashboardEmail(identity.accountEmail, mode: mode)
        let plan = self.dashboardPlan(identity.loginMethod, provider: provider)
        guard email != nil || plan != nil else { return nil }
        return DashboardIdentityPayload(accountEmail: email, plan: plan)
    }

    static func dashboardEmail(_ email: String?, mode: DashboardIdentityMode) -> String? {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty
        else {
            return nil
        }
        guard mode == .redacted else { return email }
        guard let at = email.lastIndex(of: "@") else { return "redacted" }
        return "redacted\(email[at...])"
    }

    private static func dashboardPlan(_ raw: String?, provider: UsageProvider) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }

        // Provider-specific by design: Codex plan aliases and Kilo's auto-top-up suffix require distinct cleanup.
        if provider == .codex {
            return CodexPlanFormatting.displayName(raw) ?? UsageFormatter.cleanPlanName(raw)
        }
        if provider == .kilo {
            let firstPlanSegment = raw
                .components(separatedBy: "·")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty && !$0.lowercased().hasPrefix("auto top-up:") }
            return firstPlanSegment.map(UsageFormatter.cleanPlanName)
        }
        return UsageFormatter.cleanPlanName(raw)
    }

    private static func makeWindows(
        provider: UsageProvider?,
        metadata: ProviderMetadata?,
        usage: UsageSnapshot?) -> [DashboardWindowPayload]
    {
        guard let usage else { return [] }
        // Provider-specific by design: Antigravity's primary and secondary are representatives
        // copied out of its own quota-summary lanes so the icon and menu bar have standard slots
        // to read. Emitting all three repeats two lanes under the generic session and weekly
        // labels, so the dashboard renders the summary lanes alone, one per quota bucket.
        if provider == .antigravity, let windows = self.antigravityQuotaSummaryWindows(usage) {
            return windows
        }
        let labels = self.rateWindowLabels(provider: provider, metadata: metadata, usage: usage)
        var windows: [DashboardWindowPayload] = []
        // Provider-specific by design: Amp subscription payloads model balance and orb as non-time-window kinds.
        let isAmpSubscription = provider == .amp && usage.secondary != nil

        if let primary = usage.primary {
            let kind = isAmpSubscription ? "other" : "session"
            windows.append(self.makeWindow(kind: kind, label: labels.primary, window: primary))
        }
        if let secondary = usage.secondary {
            let kind = isAmpSubscription ? "orb" : "weekly"
            windows.append(self.makeWindow(kind: kind, label: labels.secondary, window: secondary))
        }
        if let tertiary = usage.tertiary {
            windows.append(self.makeWindow(kind: "tertiary", label: labels.tertiary, window: tertiary))
        }
        for extra in usage.extraRateWindows ?? [] {
            windows.append(self.makeWindow(kind: extra.id, label: extra.title, window: extra.window))
        }

        return windows
    }

    /// Display lanes for an Antigravity quota-summary snapshot, or `nil` when the snapshot has no
    /// summary lanes and must keep the standard primary and secondary rows. Every family stays in the
    /// payload, because a script client reads the same document and must not lose a window. The lanes of
    /// a family that reports no usage carry `idle`, the same rule the menu card and the widget use to
    /// hide that family, so the web UI can drop those rows without repeating the rule in JavaScript.
    private static func antigravityQuotaSummaryWindows(_ usage: UsageSnapshot) -> [DashboardWindowPayload]? {
        let extras = usage.extraRateWindows ?? []
        guard extras.contains(where: { AntigravityStatusSnapshot.isQuotaSummaryWindowID($0.id) }) else {
            return nil
        }
        let idleWindowIDs = AntigravityQuotaFamilyVisibility.idleWindowIDs(in: usage)
        return extras.map {
            self.makeWindow(
                kind: $0.id,
                label: $0.title,
                window: $0.window,
                idle: idleWindowIDs.contains($0.id))
        }
    }

    private struct RateWindowLabels {
        let primary: String
        let secondary: String
        let tertiary: String
    }

    private static func rateWindowLabels(
        provider: UsageProvider?,
        metadata: ProviderMetadata?,
        usage: UsageSnapshot) -> RateWindowLabels
    {
        guard let provider else {
            return RateWindowLabels(
                primary: metadata?.sessionLabel ?? "Session",
                secondary: metadata?.weeklyLabel ?? "Weekly",
                tertiary: metadata?.opusLabel ?? "Tertiary")
        }
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        let labels = descriptor.presentation.rateWindowLabels(metadata: descriptor.metadata, snapshot: usage)
        return RateWindowLabels(
            primary: labels.primary,
            secondary: labels.secondary,
            tertiary: labels.tertiary)
    }

    private static func makeWindow(
        kind: String,
        label: String,
        window: RateWindow,
        idle: Bool = false) -> DashboardWindowPayload
    {
        let used = self.clampedPercent(window.usedPercent)
        let remaining = self.clampedPercent(100 - used)
        return DashboardWindowPayload(
            kind: kind,
            label: label,
            usedPercent: used,
            remainingPercent: remaining,
            resetAt: window.resetsAt,
            idle: idle)
    }

    private static func clampedPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private static func makeCredits(
        _ credits: CreditsSnapshot?,
        provider: UsageProvider?,
        providerCost: ProviderCostSnapshot?) -> DashboardCreditsPayload?
    {
        if let credits, credits.balanceReadSucceeded {
            return DashboardCreditsPayload(remaining: credits.remaining, unit: "credits")
        }
        guard provider == .grok,
              let providerCost,
              providerCost.currencyCode == "USD",
              let balance = providerCost.balance,
              balance.isFinite,
              balance >= 0
        else { return nil }
        return DashboardCreditsPayload(remaining: balance, unit: "USD")
    }

    private static func makeReportedCost(_ snapshot: CostUsageTokenSnapshot?) -> DashboardCostPayload? {
        guard let snapshot, snapshot.currencyCode == "USD", snapshot.historyDays == 30 else { return nil }
        let incompleteCount = CostUsageIncompleteRequests.sum(snapshot.daily.map(\.incompleteRequestCount))
        guard snapshot.last30DaysCostUSD != nil || incompleteCount > 0 else { return nil }
        // Provider history may use completed UTC days, which are not local Today.
        return DashboardCostPayload(
            todayUSD: nil,
            last30DaysUSD: snapshot.last30DaysCostUSD,
            last30DaysIncompleteRequestCount: incompleteCount > 0 ? incompleteCount : nil)
    }

    private static func makeCost(_ cost: CostPayload?, referenceDate: Date) -> DashboardCostPayload? {
        guard let cost else { return nil }
        let todayUSD = self.todayCostUSD(cost, referenceDate: referenceDate)
        guard todayUSD != nil || cost.last30DaysCostUSD != nil else { return nil }
        return DashboardCostPayload(
            todayUSD: todayUSD,
            last30DaysUSD: cost.last30DaysCostUSD)
    }

    private static func todayCostUSD(_ cost: CostPayload, referenceDate: Date) -> Double? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        let dayKey = String(format: "%04d-%02d-%02d", year, month, day)
        return cost.daily.first { String($0.date.prefix(10)) == dayKey }?.costUSD
    }

    private static func updatedAt(
        payload: ProviderPayload,
        cost: CostPayload?,
        error: ProviderErrorPayload?,
        generatedAt: Date) -> Date?
    {
        let newest = [payload.status?.updatedAt, payload.usage?.updatedAt, payload.credits?.updatedAt, cost?.updatedAt]
            .compactMap(\.self)
            .max()
        if let newest {
            return newest
        }
        return error == nil ? nil : generatedAt
    }

    private static func dashboardRefreshSeconds(_ refreshInterval: TimeInterval) -> Int {
        guard refreshInterval > 0 else { return 0 }
        let maximum = Int.max / 3
        guard refreshInterval < Double(maximum) else { return maximum }
        return min(maximum, Int(refreshInterval.rounded(.up)))
    }

    private static func hexColor(_ color: ProviderColor?) -> String {
        guard let color else { return "#6E6E6E" }
        let red = Int((self.clampedColor(color.red) * 255).rounded())
        let green = Int((self.clampedColor(color.green) * 255).rounded())
        let blue = Int((self.clampedColor(color.blue) * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func clampedColor(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
