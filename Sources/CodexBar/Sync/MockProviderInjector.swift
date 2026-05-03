// swiftlint:disable multiline_arguments
import CodexBarSync
import Foundation

/// Synthetic provider data for end-to-end iCloud sync testing without
/// real provider subscriptions.
///
/// Generates 5 mock provider IDs (8 total `ProviderUsageSnapshot` entries
/// because two of them are multi-account) that exercise the most critical
/// code paths in the R1–R5 multi-account work:
///
/// 1. **`_mock_codex_multi`** (3 accounts: alice/bob/carol) — exercises
///    Codex multi-account cache + per-account record emission + cross-Mac
///    `accountIdentities` merge. Most important path because user reported
///    the original "3 codex on Mac, 1 on iOS" bug here.
/// 2. **`_mock_claude_multi`** (2 accounts: personal/work) — exercises R2
///    token-based multi-account expansion via `accountSnapshots` list.
/// 3. **`_mock_perplexity_credit`** (1 account, rich Perplexity credit
///    breakdown) — exercises 3-segment recurring/promo/purchased rendering
///    + plan badge + renewal date.
/// 4. **`_mock_cursor_error`** (1 account, error state) — exercises iOS
///    error-state card rendering.
/// 5. **`_mock_synthetic_3lane`** (1 account, three rate-window lanes +
///    30-day utilization history) — exercises 5h/weekly/search labels
///    + utilization chart.
///
/// **Activation** (any one method):
/// - Environment variable `CODEXBAR_MOCK_PROVIDERS=1` (set on launch)
/// - UserDefaults flag `CodexBarMockProvidersEnabled` (`defaults write
///   com.steipete.codexbar CodexBarMockProvidersEnabled -bool true`)
///
/// **Production safety**:
/// - Default is OFF; user must explicitly opt in via env var or
///   `defaults write`. Normal users (App Store / Sparkle install) will
///   never accidentally enable.
/// - All mock providerIDs use the `_mock_` prefix so they're trivially
///   distinguishable from real providers in iOS, CloudKit dashboard,
///   logs, and database queries.
/// - All mock data is hardcoded synthetic — never reads real provider
///   state or credentials.
/// - When the flag is turned off, the next sync cycle stops emitting
///   mock records and the L1 ghost-records cleanup (with 2-cycle
///   confirmation) automatically deletes the orphaned CKRecords from
///   CloudKit.
///
/// **Future extension**: to add a new mock provider, append a static
/// factory function below and add its return value to the array in
/// `injectedSnapshots()`. iOS doesn't need any change — the existing
/// fallback rendering handles unknown provider IDs (per Research/020 R5
/// audit).
@MainActor
enum MockProviderInjector {
    /// Returns mock `ProviderUsageSnapshot` entries when activation is
    /// enabled; empty array otherwise. SyncCoordinator's default
    /// `mockInjector` closure calls this in production.
    static func injectedSnapshots() -> [ProviderUsageSnapshot] {
        guard self.isEnabled else { return [] }
        return self.allMocks()
    }

    /// Returns the 8 mock ProviderUsageSnapshot entries unconditionally,
    /// regardless of global activation state. Tests that want to
    /// exercise the SyncCoordinator hook with predictable mock data
    /// pass `mockInjector: { MockProviderInjector.allMocks() }` to
    /// SyncCoordinator's init — this avoids depending on the global
    /// `isEnabled` state, which doesn't isolate cleanly across
    /// parallel `@MainActor` test suites.
    static func allMocks() -> [ProviderUsageSnapshot] {
        [
            self.mockCodexAlice(),
            self.mockCodexBob(),
            self.mockCodexCarol(),
            self.mockClaudePersonal(),
            self.mockClaudeWork(),
            self.mockPerplexityCredit(),
            self.mockCursorError(),
            self.mockSyntheticThreeLane(),
        ]
    }

    /// True when mock provider injection is active. Reads env var first
    /// (`CODEXBAR_MOCK_PROVIDERS`), falls back to UserDefaults. Both
    /// default off. Accepts truthy values: `1`, `true`, `TRUE`, `yes`,
    /// `YES` (case-insensitive on the alpha forms).
    static var isEnabled: Bool {
        Self.isEnabled(
            environment: ProcessInfo.processInfo.environment,
            userDefaults: UserDefaults.standard)
    }

    /// Testable variant — same logic as `isEnabled`, but with injected
    /// environment + UserDefaults so unit tests can verify the env-var
    /// parsing and precedence rules without spawning a subprocess or
    /// mutating the real launch environment.
    static func isEnabled(
        environment: [String: String],
        userDefaults: UserDefaults) -> Bool
    {
        if let raw = environment[environmentVariableName] {
            let normalized = raw.lowercased()
            let truthy: Set<String> = ["1", "true", "yes"]
            if truthy.contains(normalized) {
                return true
            }
        }
        return userDefaults.bool(forKey: Self.userDefaultsKey)
    }

    static let environmentVariableName = "CODEXBAR_MOCK_PROVIDERS"
    static let userDefaultsKey = "CodexBarMockProvidersEnabled"

    // MARK: - Reference timestamp

    /// Reference timestamp captured per-call (NOT cached across calls).
    /// Each mock generation cycle uses a fresh `Date()`, which means
    /// `lastUpdated` and `resetsAt` track wall-clock and the mock data
    /// looks "live" on iOS. Side effect: every push generates a unique
    /// hash so the per-provider hash cache always uploads fresh records;
    /// this is acceptable because mock activation is opt-in and rare.
    private static var nowReference: Date {
        Date()
    }

    // MARK: - Codex multi-account (R1) — 3 managed-account-style entries

    private static func mockCodexAlice() -> ProviderUsageSnapshot {
        // Alice uses a non-ASCII email (`café-mock@codex.test`) on
        // purpose to exercise UTF-8 + percent-encoding round-trip
        // through the wire format and the AccountIdentityComputer.
        ProviderUsageSnapshot(
            providerID: "_mock_codex_multi",
            providerName: "Mock Codex (Alice)",
            primary: SyncRateWindow(
                label: "5h",
                usedPercent: 35,
                windowMinutes: 300,
                resetsAt: self.nowReference.addingTimeInterval(2700),
                resetDescription: "in 45 min"),
            secondary: SyncRateWindow(
                label: "Weekly",
                usedPercent: 60,
                windowMinutes: 10080,
                resetsAt: self.nowReference.addingTimeInterval(345_600),
                resetDescription: "in 4 days"),
            accountEmail: "café-mock@codex.test",
            loginMethod: "Pro $200",
            statusMessage: nil,
            isError: false,
            lastUpdated: self.nowReference,
            costSummary: SyncCostSummary(
                sessionCostUSD: 0.42,
                sessionTokens: 12345,
                last30DaysCostUSD: 28.50,
                last30DaysTokens: 1_234_567,
                daily: []),
            budget: nil,
            rateWindows: [
                SyncRateWindow(
                    label: "5h", usedPercent: 35,
                    windowMinutes: 300,
                    resetsAt: self.nowReference.addingTimeInterval(2700),
                    resetDescription: "in 45 min"),
                SyncRateWindow(
                    label: "Weekly", usedPercent: 60,
                    windowMinutes: 10080,
                    resetsAt: self.nowReference.addingTimeInterval(345_600),
                    resetDescription: "in 4 days"),
            ],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: [
                "_mock_codex_multi:email:caf%C3%A9-mock%40codex.test",
            ])
    }

    private static func mockCodexBob() -> ProviderUsageSnapshot {
        // Bob exercises the 100% boundary (weekly fully consumed) so
        // iOS rendering of "quota depleted" state is testable.
        ProviderUsageSnapshot(
            providerID: "_mock_codex_multi",
            providerName: "Mock Codex (Bob)",
            primary: SyncRateWindow(
                label: "5h",
                usedPercent: 75,
                windowMinutes: 300,
                resetsAt: self.nowReference.addingTimeInterval(1800),
                resetDescription: "in 30 min"),
            secondary: SyncRateWindow(
                label: "Weekly",
                usedPercent: 100, // boundary: fully consumed
                windowMinutes: 10080,
                resetsAt: self.nowReference.addingTimeInterval(345_600),
                resetDescription: "in 4 days"),
            accountEmail: "bob-mock@codex.test",
            loginMethod: "Pro $20",
            statusMessage: nil,
            isError: false,
            lastUpdated: self.nowReference,
            costSummary: SyncCostSummary(
                sessionCostUSD: 1.27,
                sessionTokens: 45678,
                last30DaysCostUSD: 87.20,
                last30DaysTokens: 3_456_789,
                daily: []),
            budget: nil,
            rateWindows: [
                SyncRateWindow(
                    label: "5h", usedPercent: 75,
                    windowMinutes: 300,
                    resetsAt: self.nowReference.addingTimeInterval(1800),
                    resetDescription: "in 30 min"),
                SyncRateWindow(
                    label: "Weekly", usedPercent: 100, // boundary
                    windowMinutes: 10080,
                    resetsAt: self.nowReference.addingTimeInterval(345_600),
                    resetDescription: "in 4 days"),
            ],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: [
                "_mock_codex_multi:email:bob-mock%40codex.test",
            ])
    }

    private static func mockCodexCarol() -> ProviderUsageSnapshot {
        // Carol exercises the 0% boundary (just-reset window) so iOS
        // rendering of "quota empty / fresh" state is testable.
        ProviderUsageSnapshot(
            providerID: "_mock_codex_multi",
            providerName: "Mock Codex (Carol)",
            primary: SyncRateWindow(
                label: "5h",
                usedPercent: 0, // boundary: fresh / just reset
                windowMinutes: 300,
                resetsAt: self.nowReference.addingTimeInterval(14400),
                resetDescription: "in 4 hours"),
            secondary: SyncRateWindow(
                label: "Weekly",
                usedPercent: 12,
                windowMinutes: 10080,
                resetsAt: self.nowReference.addingTimeInterval(345_600),
                resetDescription: "in 4 days"),
            accountEmail: "carol-mock@codex.test",
            loginMethod: "Plus $20",
            statusMessage: nil,
            isError: false,
            lastUpdated: self.nowReference,
            costSummary: SyncCostSummary(
                sessionCostUSD: 0.05,
                sessionTokens: 1234,
                last30DaysCostUSD: 4.80,
                last30DaysTokens: 234_567,
                daily: []),
            budget: nil,
            rateWindows: [
                SyncRateWindow(
                    label: "5h", usedPercent: 0, // boundary
                    windowMinutes: 300,
                    resetsAt: self.nowReference.addingTimeInterval(14400),
                    resetDescription: "in 4 hours"),
                SyncRateWindow(
                    label: "Weekly", usedPercent: 12,
                    windowMinutes: 10080,
                    resetsAt: self.nowReference.addingTimeInterval(345_600),
                    resetDescription: "in 4 days"),
            ],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: [
                "_mock_codex_multi:email:carol-mock%40codex.test",
            ])
    }

    // MARK: - Claude multi-account (R2) — 2 token-account-style entries

    private static func mockClaudePersonal() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "_mock_claude_multi",
            providerName: "Mock Claude (Personal)",
            primary: SyncRateWindow(
                label: "5h",
                usedPercent: 50,
                windowMinutes: 300,
                resetsAt: self.nowReference.addingTimeInterval(3600),
                resetDescription: "in 1 hour"),
            secondary: SyncRateWindow(
                label: "Weekly Sonnet",
                usedPercent: 65,
                windowMinutes: 10080,
                resetsAt: self.nowReference.addingTimeInterval(259_200),
                resetDescription: "in 3 days"),
            accountEmail: "personal-mock@claude.test",
            loginMethod: "Pro $20",
            statusMessage: nil,
            isError: false,
            lastUpdated: self.nowReference,
            costSummary: nil,
            budget: nil,
            rateWindows: [
                SyncRateWindow(
                    label: "5h", usedPercent: 50,
                    windowMinutes: 300,
                    resetsAt: self.nowReference.addingTimeInterval(3600),
                    resetDescription: "in 1 hour"),
                SyncRateWindow(
                    label: "Weekly Sonnet", usedPercent: 65,
                    windowMinutes: 10080,
                    resetsAt: self.nowReference.addingTimeInterval(259_200),
                    resetDescription: "in 3 days"),
                SyncRateWindow(
                    label: "Weekly Opus", usedPercent: 90,
                    windowMinutes: 10080,
                    resetsAt: self.nowReference.addingTimeInterval(259_200),
                    resetDescription: "in 3 days"),
            ],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: [
                "_mock_claude_multi:email:personal-mock%40claude.test",
            ])
    }

    private static func mockClaudeWork() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "_mock_claude_multi",
            providerName: "Mock Claude (Work)",
            primary: SyncRateWindow(
                label: "5h",
                usedPercent: 22,
                windowMinutes: 300,
                resetsAt: self.nowReference.addingTimeInterval(7200),
                resetDescription: "in 2 hours"),
            secondary: SyncRateWindow(
                label: "Weekly Sonnet",
                usedPercent: 38,
                windowMinutes: 10080,
                resetsAt: self.nowReference.addingTimeInterval(259_200),
                resetDescription: "in 3 days"),
            accountEmail: "work-mock@claude.test",
            loginMethod: "Team $30",
            statusMessage: nil,
            isError: false,
            lastUpdated: self.nowReference,
            costSummary: nil,
            budget: nil,
            rateWindows: [
                SyncRateWindow(
                    label: "5h", usedPercent: 22,
                    windowMinutes: 300,
                    resetsAt: self.nowReference.addingTimeInterval(7200),
                    resetDescription: "in 2 hours"),
                SyncRateWindow(
                    label: "Weekly Sonnet", usedPercent: 38,
                    windowMinutes: 10080,
                    resetsAt: self.nowReference.addingTimeInterval(259_200),
                    resetDescription: "in 3 days"),
            ],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: [
                "_mock_claude_multi:email:work-mock%40claude.test",
            ])
    }

    // MARK: - Perplexity rich credit breakdown

    private static func mockPerplexityCredit() -> ProviderUsageSnapshot {
        // Perplexity primary metric is "credits remaining" not a rate
        // window, but we synthesize a daily-message rate window so the
        // record isn't filtered as ghost in the per-provider write path
        // and so iOS can render a usage bar alongside the credit
        // breakdown.
        let primary = SyncRateWindow(
            label: "Daily messages",
            usedPercent: 32,
            windowMinutes: 1440,
            resetsAt: Self.nowReference.addingTimeInterval(28800),
            resetDescription: "in 8 hours")
        return ProviderUsageSnapshot(
            providerID: "_mock_perplexity_credit",
            providerName: "Mock Perplexity (Pro)",
            primary: primary,
            secondary: nil,
            accountEmail: "pro-mock@perplexity.test",
            loginMethod: "Pro $20",
            statusMessage: nil,
            isError: false,
            lastUpdated: Self.nowReference,
            costSummary: nil,
            budget: nil,
            rateWindows: [primary],
            utilizationHistory: nil,
            perplexityCredits: SyncPerplexityCreditSummary(
                recurringTotalCents: 50000,
                recurringUsedCents: 32500,
                promoTotalCents: 10000,
                promoUsedCents: 4200,
                promoExpiresAt: Self.nowReference
                    .addingTimeInterval(15 * 86400),
                purchasedTotalCents: 25000,
                purchasedUsedCents: 7800,
                renewalAt: Self.nowReference
                    .addingTimeInterval(20 * 86400),
                planName: "Pro",
                balanceCents: 41000),
            accountIdentities: [
                "_mock_perplexity_credit:email:pro-mock%40perplexity.test",
            ])
    }

    // MARK: - Cursor in error state

    private static func mockCursorError() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "_mock_cursor_error",
            providerName: "Mock Cursor (Cookie expired)",
            primary: nil,
            secondary: nil,
            accountEmail: "expired-mock@cursor.test",
            loginMethod: nil,
            statusMessage: "Mock: Cookie expired — please sign in again.",
            isError: true,
            lastUpdated: self.nowReference,
            costSummary: nil,
            budget: nil,
            rateWindows: [],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: nil)
    }

    // MARK: - Synthetic 3-lane + utilization history

    private static func mockSyntheticThreeLane() -> ProviderUsageSnapshot {
        // Build 30 days of utilization entries.
        let oneDay: TimeInterval = 86400
        let now = Self.nowReference
        var sessionEntries: [SyncUtilizationEntry] = []
        var weeklyEntries: [SyncUtilizationEntry] = []
        var searchEntries: [SyncUtilizationEntry] = []
        for day in 0..<30 {
            let captured = now.addingTimeInterval(
                -Double(29 - day) * oneDay)
            let resets = captured.addingTimeInterval(oneDay)
            // Simple sinusoidal patterns so iOS chart shows variation.
            let sessionPct = 0.3 + 0.3 * sin(Double(day) * 0.5)
            let weeklyPct = 0.5 + 0.2 * cos(Double(day) * 0.3)
            let searchPct = 0.2 + 0.4 * sin(Double(day) * 0.7)
            sessionEntries.append(SyncUtilizationEntry(
                capturedAt: captured,
                usedPercent: max(0, min(1, sessionPct)),
                resetsAt: resets))
            weeklyEntries.append(SyncUtilizationEntry(
                capturedAt: captured,
                usedPercent: max(0, min(1, weeklyPct)),
                resetsAt: resets))
            searchEntries.append(SyncUtilizationEntry(
                capturedAt: captured,
                usedPercent: max(0, min(1, searchPct)),
                resetsAt: resets))
        }

        return ProviderUsageSnapshot(
            providerID: "_mock_synthetic_3lane",
            providerName: "Mock Synthetic (3-lane)",
            primary: SyncRateWindow(
                label: "5h",
                usedPercent: 45,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: "in 1 hour"),
            secondary: SyncRateWindow(
                label: "Weekly",
                usedPercent: 70,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(518_400),
                resetDescription: "in 6 days"),
            accountEmail: "lanes-mock@synthetic.test",
            loginMethod: "Builder",
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: nil,
            budget: SyncBudgetSnapshot(
                usedAmount: 18.50,
                limitAmount: 50,
                currencyCode: "USD",
                period: "monthly",
                resetsAt: now.addingTimeInterval(20 * 86400)),
            rateWindows: [
                SyncRateWindow(
                    label: "5h", usedPercent: 45,
                    windowMinutes: 300,
                    resetsAt: now.addingTimeInterval(3600),
                    resetDescription: "in 1 hour"),
                SyncRateWindow(
                    label: "Weekly", usedPercent: 70,
                    windowMinutes: 10080,
                    resetsAt: now.addingTimeInterval(518_400),
                    resetDescription: "in 6 days"),
                SyncRateWindow(
                    label: "Search hourly", usedPercent: 25,
                    windowMinutes: 60,
                    resetsAt: now.addingTimeInterval(900),
                    resetDescription: "in 15 min"),
            ],
            utilizationHistory: [
                SyncUtilizationSeries(
                    name: "session", windowMinutes: 300,
                    entries: sessionEntries),
                SyncUtilizationSeries(
                    name: "weekly", windowMinutes: 10080,
                    entries: weeklyEntries),
                SyncUtilizationSeries(
                    name: "search", windowMinutes: 60,
                    entries: searchEntries),
            ],
            perplexityCredits: nil,
            accountIdentities: [
                "_mock_synthetic_3lane:email:lanes-mock%40synthetic.test",
            ])
    }
}

// swiftlint:enable multiline_arguments
