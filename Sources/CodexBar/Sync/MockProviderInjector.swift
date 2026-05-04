// swiftlint:disable multiline_arguments
import CodexBarSync
import Foundation

/// Synthetic provider data for end-to-end iCloud sync testing without
/// real provider subscriptions.
///
/// **Mix design** (Mac 0.23.5+): 6 mocks use real provider IDs (`codex`,
/// `claude`, `perplexity`) so iOS renders them with first-class provider
/// styling — exercising the critical multi-account first-class rendering
/// path that real users hit. The remaining 2 mocks use `_mock_*`
/// prefixed IDs to also exercise the unknown-provider fallback rendering
/// path (forward-compat insurance: when a future Mac adds a new provider
/// the iOS app doesn't yet know about, that fallback path must still
/// work).
///
/// 8 total `ProviderUsageSnapshot` entries across 5 distinct
/// `providerID` values:
///
/// 1. **`codex`** × 3 (Alice / Bob / Carol) — REAL providerID. Exercises
///    R1 Codex multi-account cache + per-account record emission +
///    cross-Mac `accountIdentities` merge — and renders with **the real
///    Codex card UI on iPhone** (icon, color, native multi-account
///    affordances). This is the critical "3 Codex accounts on Mac, 1 on
///    iPhone" path the user originally hit.
/// 2. **`claude`** × 2 (Personal / Work) — REAL providerID. Exercises R2
///    token-based multi-account expansion + Claude-specific UI (3-lane
///    Sonnet/Opus rendering when present).
/// 3. **`perplexity`** × 1 — REAL providerID. Exercises Perplexity's
///    3-segment credit breakdown card on iPhone (recurring + promo +
///    purchased + plan badge + renewal countdown).
/// 4. **`_mock_cursor_unknown`** × 1 — fallback test. Mock providerID
///    iOS doesn't recognize → renders generic blue fallback card. Carries
///    `isError = true` + statusMessage so the fallback's error-state
///    rendering is also exercised.
/// 5. **`_mock_synthetic_unknown`** × 1 — fallback test. Mock providerID
///    + 30-day utilization history + 3-lane rate windows + budget. Tests
///    that fallback rendering doesn't choke on rich data.
///
/// All real-providerID mocks include synthetic cost data (session +
/// 30-day total + daily breakdown for Alice) so iPhone's Cost dashboard
/// aggregation (Daily Spend, per-provider share, model breakdown,
/// month-over-month) is end-to-end testable.
///
/// **Account email convention**: every mock uses the `*-mock@*.test` TLD
/// (RFC 6761 reserved for testing) so even though some mocks share
/// providerID with real providers, the synthetic accounts are
/// unambiguously distinguishable on iPhone via email subtitle. iOS
/// 1.5.2+ also uses the `.test` TLD as the trigger for the MOCK badge +
/// purple-striped card treatment.
///
/// **Activation** (any one method):
/// - Environment variable `CODEXBAR_MOCK_PROVIDERS=1` (set on launch)
/// - UserDefaults flag `CodexBarMockProvidersEnabled` (`defaults write
///   com.o1xhack.codexbar CodexBarMockProvidersEnabled -bool true`)
/// - Settings UI: Mac CodexBar → Settings → Mobile → Debug · Mock
///   Provider Data toggle (Mac 0.23.5+).
///
/// **Production safety**:
/// - Default is OFF; user must explicitly opt in. Normal users (App
///   Store / Sparkle install) never accidentally enable.
/// - Mock account emails always use `.test` TLD (RFC 6761 reserved).
///   Synthetic providerID branches use `_mock_` prefix.
/// - Mock CKRecords are stored under composite keys distinct from real
///   data: `{deviceID}|{providerID}|*-mock@*.test` does NOT collide with
///   any real `{deviceID}|{providerID}|{realEmail}` because the email
///   bucket is different.
/// - When the flag is turned off, the next sync cycle stops emitting
///   mock records and the L1 ghost-records cleanup automatically deletes
///   the orphaned CKRecords from CloudKit. Real provider data is in
///   different CKRecords and is never touched.
///
/// **Cost data + your real numbers**: Daily Spend / per-provider share /
/// model breakdown on iPhone aggregates ALL providers' cost. While mocks
/// are active, totals are inflated by ~$48/30day from synthetic data.
/// Once you toggle off and CloudKit cleanup runs (~1 cycle / ~30s), real
/// numbers automatically restore. Real CKRecords are never modified.
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
            self.mockPerplexityPro(),
            self.mockCursorErrorFallback(),
            self.mockSyntheticThreeLaneFallback(),
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

    /// Real provider IDs that some mocks intentionally borrow so iOS
    /// renders them with first-class provider UI. Mocks using these IDs
    /// always pair them with `*-mock@*.test` accountEmails so the
    /// synthetic account is unambiguously distinct from any real account
    /// the user has on the same provider.
    static let realProviderIDsBorrowedByMocks: Set<String> = [
        "codex", "claude", "perplexity",
    ]

    /// Synthetic providerIDs unique to mocks. Always prefixed `_mock_`.
    /// iOS treats these as unknown providers and renders fallback cards.
    static let syntheticProviderIDs: Set<String> = [
        "_mock_cursor_unknown", "_mock_synthetic_unknown",
    ]

    /// All mock providerIDs (real-borrowed ∪ synthetic). Convenience
    /// for tests that need to gate "is this a mock provider?" without
    /// caring about which subset.
    static var allMockProviderIDs: Set<String> {
        realProviderIDsBorrowedByMocks.union(syntheticProviderIDs)
    }

    /// Universal mock-account email TLD. iOS 1.5.2+ inspects this to
    /// gate the MOCK badge + purple-striped card treatment.
    static let mockEmailTLD = ".test"

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

    // MARK: - Cost helper

    /// Builds a SyncCostSummary with optional 30-day daily breakdown.
    /// `dailyTotals.count` should be 30 for a complete history; can be
    /// fewer if testing partial windows.
    private static func makeCostSummary(
        sessionUSD: Double,
        sessionTokens: Int,
        thirtyDayUSD: Double,
        thirtyDayTokens: Int,
        dailyTotals: [Double] = [],
        isEstimated: Bool? = false) -> SyncCostSummary
    {
        // dayKey format `YYYY-MM-DD` (UTC) matches the real cost
        // scanner's emission format. Days are ordered oldest→newest.
        let now = Self.nowReference
        let oneDay: TimeInterval = 86400
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dailyPoints: [SyncDailyPoint] = dailyTotals.enumerated().map { idx, dailyUSD in
            let captured = now.addingTimeInterval(
                -Double(dailyTotals.count - 1 - idx) * oneDay)
            return SyncDailyPoint(
                dayKey: formatter.string(from: captured),
                costUSD: dailyUSD,
                totalTokens: Int(dailyUSD * 50000), // synthetic token ratio
                modelBreakdowns: [
                    SyncCostBreakdown(
                        label: "claude-sonnet-4-6",
                        costUSD: dailyUSD * 0.7,
                        isEstimated: false),
                    SyncCostBreakdown(
                        label: "claude-opus-4-7",
                        costUSD: dailyUSD * 0.3,
                        isEstimated: false),
                ],
                serviceBreakdowns: [],
                isEstimated: false)
        }
        return SyncCostSummary(
            sessionCostUSD: sessionUSD,
            sessionTokens: sessionTokens,
            last30DaysCostUSD: thirtyDayUSD,
            last30DaysTokens: thirtyDayTokens,
            daily: dailyPoints,
            isEstimated: isEstimated)
    }

    // MARK: - Codex multi-account (R1) — 3 managed-account-style entries

    // All three use the real `codex` providerID so iOS renders them with
    // the native Codex multi-account UI.

    private static func mockCodexAlice() -> ProviderUsageSnapshot {
        // Alice uses a non-ASCII email (`café-mock@codex.test`) on
        // purpose to exercise UTF-8 + percent-encoding round-trip
        // through the wire format and the AccountIdentityComputer.
        // She is the ONLY mock with a 30-day daily cost breakdown so
        // the iOS Cost dashboard's day-by-day chart + model-breakdown
        // pie path is end-to-end testable.
        let dailySpend: [Double] = (0..<30).map { day in
            // Sinusoidal $0.20–$0.80/day pattern.
            0.5 + 0.3 * sin(Double(day) * 0.4)
        }
        let totalUSD = dailySpend.reduce(0, +)
        return ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex (Alice · Mock)",
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
            costSummary: Self.makeCostSummary(
                sessionUSD: 0.42,
                sessionTokens: 12345,
                thirtyDayUSD: totalUSD,
                thirtyDayTokens: Int(totalUSD * 50000),
                dailyTotals: dailySpend),
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
                "codex:email:caf%C3%A9-mock%40codex.test",
            ])
    }

    private static func mockCodexBob() -> ProviderUsageSnapshot {
        // Bob exercises the 100% boundary (weekly fully consumed) so
        // iOS rendering of "quota depleted" state is testable.
        ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex (Bob · Mock)",
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
            costSummary: self.makeCostSummary(
                sessionUSD: 1.27,
                sessionTokens: 45678,
                thirtyDayUSD: 18.20,
                thirtyDayTokens: 910_000),
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
                "codex:email:bob-mock%40codex.test",
            ])
    }

    private static func mockCodexCarol() -> ProviderUsageSnapshot {
        // Carol exercises the 0% boundary (just-reset window) so iOS
        // rendering of "quota empty / fresh" state is testable.
        ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex (Carol · Mock)",
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
            costSummary: self.makeCostSummary(
                sessionUSD: 0.05,
                sessionTokens: 1234,
                thirtyDayUSD: 1.10,
                thirtyDayTokens: 55000),
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
                "codex:email:carol-mock%40codex.test",
            ])
    }

    // MARK: - Claude multi-account (R2) — 2 token-account-style entries

    // Both use the real `claude` providerID so iOS renders the native
    // Claude card. Personal carries 3-lane rateWindows (5h + Weekly
    // Sonnet + Weekly Opus) which exercises the Claude-specific 3-lane
    // detail view.

    private static func mockClaudePersonal() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude (Personal · Mock)",
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
            costSummary: self.makeCostSummary(
                sessionUSD: 0.08,
                sessionTokens: 4200,
                thirtyDayUSD: 3.80,
                thirtyDayTokens: 190_000),
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
                "claude:email:personal-mock%40claude.test",
            ])
    }

    private static func mockClaudeWork() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude (Work · Mock)",
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
            costSummary: self.makeCostSummary(
                sessionUSD: 0.15,
                sessionTokens: 6800,
                thirtyDayUSD: 6.20,
                thirtyDayTokens: 310_000),
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
                "claude:email:work-mock%40claude.test",
            ])
    }

    // MARK: - Perplexity (real ID) — 1 entry with rich credit breakdown

    private static func mockPerplexityPro() -> ProviderUsageSnapshot {
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
            providerID: "perplexity",
            providerName: "Perplexity (Pro · Mock)",
            primary: primary,
            secondary: nil,
            accountEmail: "pro-mock@perplexity.test",
            loginMethod: "Pro $20",
            statusMessage: nil,
            isError: false,
            lastUpdated: Self.nowReference,
            costSummary: Self.makeCostSummary(
                sessionUSD: 0.03,
                sessionTokens: 1500,
                thirtyDayUSD: 2.30,
                thirtyDayTokens: 115_000),
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
                "perplexity:email:pro-mock%40perplexity.test",
            ])
    }

    // MARK: - Fallback: Cursor in error state (synthetic providerID)

    // Uses `_mock_cursor_unknown` so iOS treats it as an unknown
    // provider → renders the generic blue fallback card. Combined with
    // `isError = true` + statusMessage, this exercises both the
    // fallback path AND the error-state rendering.

    private static func mockCursorErrorFallback() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "_mock_cursor_unknown",
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

    // MARK: - Fallback: 3-lane + utilization history (synthetic providerID)

    // Uses `_mock_synthetic_unknown` to verify that the fallback
    // rendering path can handle rich data (3 rate windows + 30-day
    // utilization history + budget) without choking. This is forward-
    // compat insurance: when a future provider gets added that iOS
    // doesn't yet know about, the fallback must still render its data.

    private static func mockSyntheticThreeLaneFallback() -> ProviderUsageSnapshot {
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
            providerID: "_mock_synthetic_unknown",
            providerName: "Mock Synthetic (3-lane fallback)",
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
                "_mock_synthetic_unknown:email:lanes-mock%40synthetic.test",
            ])
    }
}

// swiftlint:enable multiline_arguments
