import CodexBarSync
import Foundation

/// Deterministic companion-sync fixtures for the four providers QuotaKit supports.
///
/// Activation remains deliberately launch-gated: the environment variable must be
/// present before the persistent debug toggle can inject data. Mock accounts use
/// the reserved `.test` TLD so their CloudKit records cannot collide with real
/// account buckets.
@MainActor
enum MockProviderInjector {
    static let environmentVariableName = "CODEXBAR_MOCK_PROVIDERS"
    static let userDefaultsKey = "CodexBarMockProvidersEnabled"
    static let mockEmailTLD = ".test"

    static let realProviderIDsBorrowedByMocks: Set<String> = [
        "codex", "claude", "cursor", "grok",
    ]

    static let syntheticProviderIDs: Set<String> = []

    static var allMockProviderIDs: Set<String> {
        self.realProviderIDsBorrowedByMocks
    }

    static func injectedSnapshots() -> [ProviderUsageSnapshot] {
        guard self.isEnabled else { return [] }
        return self.allMocks()
    }

    static func allMocks() -> [ProviderUsageSnapshot] {
        let now = Date()
        return [
            self.codexMock(now: now),
            self.claudeMock(now: now),
            self.cursorMock(now: now),
            self.grokMock(now: now),
        ]
    }

    static var isEnabled: Bool {
        self.isEnabled(
            environment: ProcessInfo.processInfo.environment,
            userDefaults: UserDefaults.standard)
    }

    static func isEnabled(
        environment: [String: String],
        userDefaults: UserDefaults) -> Bool
    {
        guard let rawValue = environment[self.environmentVariableName] else {
            return false
        }
        if ["1", "true", "yes"].contains(rawValue.lowercased()) {
            return true
        }
        return userDefaults.bool(forKey: self.userDefaultsKey)
    }

    static var isMockToolingVisible: Bool {
        self.isMockToolingVisible(environment: ProcessInfo.processInfo.environment)
    }

    static func isMockToolingVisible(environment: [String: String]) -> Bool {
        environment[self.environmentVariableName] != nil
    }

    private static func codexMock(now: Date) -> ProviderUsageSnapshot {
        let session = self.window(
            label: "5h",
            usedPercent: 34,
            minutes: 300,
            resetAfter: 45 * 60,
            identity: .session,
            now: now)
        let weekly = self.window(
            label: "Weekly",
            usedPercent: 61,
            minutes: 10080,
            resetAfter: 4 * 86400,
            identity: .weekly,
            now: now)
        return ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex (Mock)",
            primary: session,
            secondary: weekly,
            accountEmail: "daily-mock@codex.test",
            loginMethod: "ChatGPT",
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: self.costSummary(sessionCost: 0.42, monthlyCost: 18.20),
            rateWindows: [session, weekly],
            accountIdentities: [
                "codex:account:mock-codex-account",
                "codex:email:daily-mock%40codex.test",
            ],
            codexWorkspace: SyncCodexWorkspaceContext(
                workspaceID: "mock-workspace",
                workspaceName: "Daily Workspace",
                weeklyPaceDelta: 0.08,
                weeklyPaceLabel: "Ahead of pace",
                updatedAt: now))
    }

    private static func claudeMock(now: Date) -> ProviderUsageSnapshot {
        let session = self.window(
            label: "5h",
            usedPercent: 27,
            minutes: 300,
            resetAfter: 2 * 3600,
            identity: .session,
            now: now)
        let weekly = self.window(
            label: "Weekly",
            usedPercent: 46,
            minutes: 10080,
            resetAfter: 3 * 86400,
            identity: .weekly,
            now: now)
        return ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude (Mock)",
            primary: session,
            secondary: weekly,
            accountEmail: "daily-mock@claude.test",
            loginMethod: "Claude Pro",
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: self.costSummary(sessionCost: 0.18, monthlyCost: 8.40),
            rateWindows: [session, weekly],
            accountIdentities: [
                "claude:oauth-sub:mock-claude-subject",
                "claude:email:daily-mock%40claude.test",
            ],
            claudeExtraUsage: SyncClaudeExtraUsage(
                utilization: 24,
                monthlySpendUSD: 12,
                monthlyLimitUSD: 50,
                balanceUSD: 38,
                isEnabled: true,
                planTier: "Pro",
                updatedAt: now))
    }

    private static func cursorMock(now: Date) -> ProviderUsageSnapshot {
        let total = self.window(
            label: "Total",
            usedPercent: 52,
            minutes: 43200,
            resetAfter: 12 * 86400,
            now: now)
        let auto = self.window(
            label: "Auto",
            usedPercent: 41,
            minutes: 43200,
            resetAfter: 12 * 86400,
            now: now)
        let api = self.window(
            label: "API",
            usedPercent: 67,
            minutes: 43200,
            resetAfter: 12 * 86400,
            now: now)
        return ProviderUsageSnapshot(
            providerID: "cursor",
            providerName: "Cursor (Mock)",
            primary: total,
            secondary: auto,
            accountEmail: "daily-mock@cursor.test",
            loginMethod: "Cursor Pro",
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: self.costSummary(sessionCost: 0.09, monthlyCost: 5.70),
            rateWindows: [total, auto, api],
            accountIdentities: ["cursor:email:daily-mock%40cursor.test"])
    }

    private static func grokMock(now: Date) -> ProviderUsageSnapshot {
        let monthly = self.window(
            label: "Monthly",
            usedPercent: 38,
            minutes: 43200,
            resetAfter: 18 * 86400,
            now: now)
        return ProviderUsageSnapshot(
            providerID: "grok",
            providerName: "Grok (Mock)",
            primary: monthly,
            secondary: nil,
            accountEmail: "daily-mock@grok.test",
            loginMethod: "Grok",
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: self.costSummary(sessionCost: 0.11, monthlyCost: 9.50),
            rateWindows: [monthly],
            accountIdentities: ["grok:email:daily-mock%40grok.test"],
            grokBilling: SyncGrokBilling(
                monthlyUsedPercent: 38,
                monthlySpendUSD: 9.50,
                monthlyLimitUSD: 25,
                billingPeriodEndDate: now.addingTimeInterval(18 * 86400),
                planTier: "Consumer",
                updatedAt: now))
    }

    private static func window(
        label: String,
        usedPercent: Double,
        minutes: Int,
        resetAfter: TimeInterval,
        identity: SyncRateWindowIdentity? = nil,
        now: Date) -> SyncRateWindow
    {
        SyncRateWindow(
            label: label,
            usedPercent: usedPercent,
            windowMinutes: minutes,
            resetsAt: now.addingTimeInterval(resetAfter),
            resetDescription: nil,
            identity: identity)
    }

    private static func costSummary(
        sessionCost: Double,
        monthlyCost: Double) -> SyncCostSummary
    {
        SyncCostSummary(
            sessionCostUSD: sessionCost,
            sessionTokens: Int(sessionCost * 50000),
            last30DaysCostUSD: monthlyCost,
            last30DaysTokens: Int(monthlyCost * 50000),
            daily: [],
            historyDays: 30,
            currencyCode: "USD")
    }
}
