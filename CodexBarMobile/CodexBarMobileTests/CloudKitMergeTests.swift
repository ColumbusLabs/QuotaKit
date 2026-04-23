import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Multi-device Merge Tests")
struct CloudKitMergeTests {
    private let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let newerDate = Date(timeIntervalSince1970: 1_700_100_000)

    private func makeProvider(
        id: String,
        name: String,
        email: String? = nil,
        lastUpdated: Date,
        usedPercent: Double = 50.0
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: SyncRateWindow(
                usedPercent: usedPercent,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: email,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated)
    }

    private func makeSnapshot(
        deviceName: String,
        deviceID: String,
        providers: [ProviderUsageSnapshot],
        timestamp: Date? = nil
    ) -> SyncedUsageSnapshot {
        SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: timestamp ?? providers.map(\.lastUpdated).max() ?? Date(),
            deviceName: deviceName,
            deviceID: deviceID)
    }

    // MARK: - Single device (degenerate case)

    @Test("Single device returns its data unchanged")
    func singleDevice() throws {
        let provider = makeProvider(id: "claude", name: "Claude", email: "a@b.com", lastUpdated: olderDate)
        let snapshot = makeSnapshot(deviceName: "MacBook Air", deviceID: "uuid-1", providers: [provider])

        let merged = try #require(CloudSyncReader.mergeSnapshots([snapshot]))
        #expect(merged.providers.count == 1)
        #expect(merged.providers[0].providerID == "claude")
        #expect(merged.providers[0].accountEmail == "a@b.com")
        #expect(merged.deviceName == "MacBook Air")
    }

    // MARK: - Same provider, same account → take newest

    @Test("Same provider + same account deduplicates to most recent")
    func sameProviderSameAccount() throws {
        let oldProvider = makeProvider(
            id: "claude", name: "Claude", email: "user@a.com",
            lastUpdated: olderDate, usedPercent: 30.0)
        let newProvider = makeProvider(
            id: "claude", name: "Claude", email: "user@a.com",
            lastUpdated: newerDate, usedPercent: 80.0)

        let macA = makeSnapshot(deviceName: "MacBook Air", deviceID: "uuid-a", providers: [oldProvider])
        let macB = makeSnapshot(deviceName: "Mac Mini", deviceID: "uuid-b", providers: [newProvider])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 1)
        #expect(merged.providers[0].primary?.usedPercent == 80.0) // Newer data wins
    }

    // MARK: - Same provider, different accounts → keep both

    @Test("Same provider + different accounts are preserved as separate entries")
    func sameProviderDifferentAccounts() throws {
        let accountA = makeProvider(
            id: "claude", name: "Claude", email: "personal@a.com", lastUpdated: olderDate)
        let accountB = makeProvider(
            id: "claude", name: "Claude", email: "work@b.com", lastUpdated: newerDate)

        let macA = makeSnapshot(deviceName: "MacBook Air", deviceID: "uuid-a", providers: [accountA])
        let macB = makeSnapshot(deviceName: "Mac Mini", deviceID: "uuid-b", providers: [accountB])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 2)

        let emails = Set(merged.providers.compactMap(\.accountEmail))
        #expect(emails == ["personal@a.com", "work@b.com"])
    }

    // MARK: - Different providers from different devices

    @Test("Different providers from different Macs are combined")
    func differentProviders() throws {
        let claude = makeProvider(id: "claude", name: "Claude", lastUpdated: olderDate)
        let cursor = makeProvider(id: "cursor", name: "Cursor", lastUpdated: olderDate)
        let codex = makeProvider(id: "codex", name: "Codex", lastUpdated: newerDate)

        let macA = makeSnapshot(deviceName: "MacBook Air", deviceID: "uuid-a", providers: [claude, cursor])
        let macB = makeSnapshot(deviceName: "Mac Mini", deviceID: "uuid-b", providers: [codex])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 3)

        let ids = Set(merged.providers.map(\.providerID))
        #expect(ids == ["claude", "cursor", "codex"])
    }

    // MARK: - Combined device name

    @Test("Merged snapshot combines device names")
    func combinedDeviceName() throws {
        let macA = makeSnapshot(
            deviceName: "MacBook Air", deviceID: "uuid-a",
            providers: [makeProvider(id: "claude", name: "Claude", lastUpdated: olderDate)])
        let macB = makeSnapshot(
            deviceName: "Mac Mini", deviceID: "uuid-b",
            providers: [makeProvider(id: "codex", name: "Codex", lastUpdated: newerDate)])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.deviceName.contains("MacBook Air"))
        #expect(merged.deviceName.contains("Mac Mini"))
    }

    // MARK: - Empty input

    @Test("Empty snapshot list returns nil")
    func emptyInput() {
        let result = CloudSyncReader.mergeSnapshots([])
        #expect(result == nil)
    }

    // MARK: - Provider with nil email vs non-nil email

    @Test("Provider with nil email is treated as separate from one with email")
    func nilVsNonNilEmail() throws {
        let noEmail = makeProvider(id: "claude", name: "Claude", email: nil, lastUpdated: olderDate)
        let withEmail = makeProvider(id: "claude", name: "Claude", email: "a@b.com", lastUpdated: newerDate)

        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [noEmail])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [withEmail])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 2) // Different keys: "claude|" vs "claude|a@b.com"
    }

    // MARK: - Providers sorted by name

    @Test("Merged providers are sorted alphabetically by name")
    func sortedByName() throws {
        let zProvider = makeProvider(id: "z-tool", name: "Z Tool", lastUpdated: olderDate)
        let aProvider = makeProvider(id: "a-tool", name: "A Tool", lastUpdated: newerDate)

        let snapshot = makeSnapshot(
            deviceName: "Mac", deviceID: "uuid-1",
            providers: [zProvider, aProvider])

        let merged = try #require(CloudSyncReader.mergeSnapshots([snapshot]))
        #expect(merged.providers[0].providerName == "A Tool")
        #expect(merged.providers[1].providerName == "Z Tool")
    }

    // MARK: - Uses latest sync timestamp

    @Test("Merged snapshot uses the most recent syncTimestamp across devices")
    func latestTimestamp() throws {
        let macA = makeSnapshot(
            deviceName: "Mac A", deviceID: "uuid-a",
            providers: [makeProvider(id: "claude", name: "Claude", lastUpdated: olderDate)],
            timestamp: olderDate)
        let macB = makeSnapshot(
            deviceName: "Mac B", deviceID: "uuid-b",
            providers: [makeProvider(id: "codex", name: "Codex", lastUpdated: newerDate)],
            timestamp: newerDate)

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.syncTimestamp == newerDate)
    }

    // MARK: - Cost aggregation for local-cost providers

    private func makeProviderWithCost(
        id: String,
        name: String,
        email: String? = nil,
        lastUpdated: Date,
        sessionCost: Double,
        daily: [SyncDailyPoint]
    ) -> ProviderUsageSnapshot {
        let totalCost = daily.reduce(0) { $0 + $1.costUSD }
        let totalTokens = daily.reduce(0) { $0 + $1.totalTokens }
        return ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: email,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated,
            costSummary: SyncCostSummary(
                sessionCostUSD: sessionCost,
                sessionTokens: nil,
                last30DaysCostUSD: totalCost,
                last30DaysTokens: totalTokens,
                daily: daily))
    }

    @Test("Claude cost data is summed across devices (local-cost provider)")
    func claudeCostSummed() throws {
        let dailyA = [
            SyncDailyPoint(dayKey: "2024-01-15", costUSD: 1.50, totalTokens: 10000),
            SyncDailyPoint(dayKey: "2024-01-16", costUSD: 2.00, totalTokens: 15000),
        ]
        let dailyB = [
            SyncDailyPoint(dayKey: "2024-01-15", costUSD: 0.80, totalTokens: 5000),
            SyncDailyPoint(dayKey: "2024-01-17", costUSD: 3.00, totalTokens: 20000),
        ]

        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            makeProviderWithCost(id: "claude", name: "Claude", email: "user@a.com",
                                 lastUpdated: olderDate, sessionCost: 0.50, daily: dailyA),
        ])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            makeProviderWithCost(id: "claude", name: "Claude", email: "user@a.com",
                                 lastUpdated: newerDate, sessionCost: 0.30, daily: dailyB),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 1)

        let cost = try #require(merged.providers[0].costSummary)

        // Session costs should be summed
        #expect(cost.sessionCostUSD == 0.80) // 0.50 + 0.30

        // Daily points: Jan 15 summed, Jan 16 from A only, Jan 17 from B only
        #expect(cost.daily.count == 3)

        let jan15 = try #require(cost.daily.first { $0.dayKey == "2024-01-15" })
        #expect(jan15.costUSD == 2.30) // 1.50 + 0.80
        #expect(jan15.totalTokens == 15000) // 10000 + 5000

        let jan16 = try #require(cost.daily.first { $0.dayKey == "2024-01-16" })
        #expect(jan16.costUSD == 2.00) // Only from Mac A

        let jan17 = try #require(cost.daily.first { $0.dayKey == "2024-01-17" })
        #expect(jan17.costUSD == 3.00) // Only from Mac B

        // 30-day total recalculated from merged daily
        #expect(cost.last30DaysCostUSD == 7.30) // 2.30 + 2.00 + 3.00
    }

    @Test("Account-level provider cost is NOT summed (takes newest)")
    func accountCostDeduped() throws {
        let daily = [SyncDailyPoint(dayKey: "2024-01-15", costUSD: 5.00, totalTokens: 50000)]

        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            makeProviderWithCost(id: "augment", name: "Augment", email: "user@a.com",
                                 lastUpdated: olderDate, sessionCost: 1.00, daily: daily),
        ])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            makeProviderWithCost(id: "augment", name: "Augment", email: "user@a.com",
                                 lastUpdated: newerDate, sessionCost: 2.00, daily: daily),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let cost = try #require(merged.providers[0].costSummary)

        // Should NOT be summed — account-level data, take newest
        #expect(cost.sessionCostUSD == 2.00) // From Mac B (newer), not 3.00
        #expect(cost.last30DaysCostUSD == 5.00) // Not doubled
    }

    @Test("Model breakdowns are merged by label with summed costs")
    func modelBreakdownsMerged() throws {
        let dailyA = [SyncDailyPoint(
            dayKey: "2024-01-15", costUSD: 2.00, totalTokens: 10000,
            modelBreakdowns: [
                SyncCostBreakdown(label: "claude-4-sonnet", costUSD: 1.50),
                SyncCostBreakdown(label: "claude-4-opus", costUSD: 0.50),
            ])]
        let dailyB = [SyncDailyPoint(
            dayKey: "2024-01-15", costUSD: 1.00, totalTokens: 5000,
            modelBreakdowns: [
                SyncCostBreakdown(label: "claude-4-sonnet", costUSD: 0.80),
                SyncCostBreakdown(label: "claude-4-haiku", costUSD: 0.20),
            ])]

        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            makeProviderWithCost(id: "claude", name: "Claude", lastUpdated: olderDate,
                                 sessionCost: 0, daily: dailyA),
        ])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            makeProviderWithCost(id: "claude", name: "Claude", lastUpdated: newerDate,
                                 sessionCost: 0, daily: dailyB),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let jan15 = try #require(merged.providers[0].costSummary?.daily.first)

        #expect(jan15.modelBreakdowns.count == 3)

        let sonnet = try #require(jan15.modelBreakdowns.first { $0.label == "claude-4-sonnet" })
        #expect(sonnet.costUSD == 2.30) // 1.50 + 0.80

        let opus = try #require(jan15.modelBreakdowns.first { $0.label == "claude-4-opus" })
        #expect(opus.costUSD == 0.50) // Only from Mac A

        let haiku = try #require(jan15.modelBreakdowns.first { $0.label == "claude-4-haiku" })
        #expect(haiku.costUSD == 0.20) // Only from Mac B
    }

    @Test("Provider without cost data is unaffected by merge")
    func noCostDataUnaffected() throws {
        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            makeProvider(id: "copilot", name: "Copilot", email: "user@a.com",
                         lastUpdated: olderDate, usedPercent: 40),
        ])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            makeProvider(id: "copilot", name: "Copilot", email: "user@a.com",
                         lastUpdated: newerDate, usedPercent: 60),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 1)
        #expect(merged.providers[0].primary?.usedPercent == 60) // Newer wins
        #expect(merged.providers[0].costSummary == nil) // No cost data
    }

    // MARK: - Perplexity credits passthrough (T3 · Build 71 / Mac 0.20.3)
    //
    // Regression guard: `mergeProviderEntries` rebuilds
    // `ProviderUsageSnapshot` for multi-device scenarios. Build 71's new
    // `perplexityCredits` field was added with a default-nil initializer
    // parameter, which would compile cleanly even if the merger forgot
    // to forward it — silently regressing the iOS Perplexity detail page
    // to the legacy 3-bar fallback whenever the user had >1 Mac signed in.
    // Codex-reviewer caught this in the initial T3 review; this test pins
    // the fix.

    private func makePerplexitySnapshot(
        email: String? = "user@example.com",
        lastUpdated: Date,
        credits: SyncPerplexityCreditSummary?
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "perplexity",
            providerName: "Perplexity",
            primary: nil,
            secondary: nil,
            accountEmail: email,
            loginMethod: credits?.planName,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated,
            perplexityCredits: credits)
    }

    @Test("Merged Perplexity snapshot preserves perplexityCredits from latest device")
    func perplexityCreditsPreservedInMultiDeviceMerge() throws {
        // Mac A (older) has no structured credits (e.g. still on 0.20.2);
        // Mac B (newer) has the full 3-pool breakdown. Merger must pick
        // Mac B's data (lastUpdated wins for identity fields) AND preserve
        // the credits field, not drop it to nil.
        let credits = SyncPerplexityCreditSummary(
            recurringTotalCents: 5000,
            recurringUsedCents: 2500,
            promoTotalCents: 1000,
            promoUsedCents: 500,
            promoExpiresAt: nil,
            purchasedTotalCents: nil,
            purchasedUsedCents: nil,
            renewalAt: Date(timeIntervalSince1970: 1_700_500_000),
            planName: "Pro",
            balanceCents: 3000)
        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            makePerplexitySnapshot(lastUpdated: olderDate, credits: nil),
        ])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            makePerplexitySnapshot(lastUpdated: newerDate, credits: credits),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 1)
        let perplexity = try #require(merged.providers.first)
        #expect(perplexity.perplexityCredits?.planName == "Pro")
        #expect(perplexity.perplexityCredits?.recurringTotalCents == 5000)
        #expect(perplexity.perplexityCredits?.recurringUsedCents == 2500)
    }

    // MARK: - Cross-version data-loss regression (Build 76)
    //
    // The scenario: user has 2 Macs on different CodexBar versions. The
    // older Mac (e.g. 0.20.2) doesn't know about `perplexityCredits` /
    // account-level `budget` and pushes nil. The newer Mac (0.20.3) pushes
    // the real data. Critically: the OLDER Mac may refresh **later** in
    // wall-clock time (e.g. it's the one the user is actively using today).
    // Naive take-latest-by-lastUpdated would silently drop the real data
    // whenever the older Mac happened to push last — the iPhone detail
    // view would flicker between the new rendering (when newer Mac is
    // authoritative) and the legacy fallback (when older Mac is). Not a
    // temporary transition issue; a real steady-state scenario for any
    // user with mixed Mac versions — which IS the default until they
    // manually update both (could be months apart).
    //
    // These tests pin the `latestNonNil` semantics: if ANY device has the
    // structured data, the merged snapshot uses it, regardless of which
    // device was most recently refreshed.

    @Test("perplexityCredits: older Mac with credits + newer Mac with nil → merged has credits")
    func perplexityCreditsInvertedFreshnessKeepsData() throws {
        let credits = SyncPerplexityCreditSummary(
            recurringTotalCents: 5000,
            recurringUsedCents: 2500,
            renewalAt: Date(timeIntervalSince1970: 1_700_500_000),
            planName: "Pro")
        // Key twist: Mac A (with data) is OLDER; Mac B (without) is NEWER.
        // Naive take-latest would return Mac B's nil credits.
        let macAWithCreditsOlder = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            makePerplexitySnapshot(lastUpdated: olderDate, credits: credits),
        ])
        let macBNoCreditsNewer = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            makePerplexitySnapshot(lastUpdated: newerDate, credits: nil),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots(
            [macAWithCreditsOlder, macBNoCreditsNewer]))
        let perplexity = try #require(merged.providers.first)
        #expect(perplexity.perplexityCredits?.planName == "Pro")
        #expect(perplexity.perplexityCredits?.recurringTotalCents == 5000)
    }

    @Test("budget: older Mac with budget + newer Mac with nil → merged keeps budget")
    func budgetInvertedFreshnessKeepsData() throws {
        // Same class of bug as perplexityCredits but on the `budget` field.
        // Pre-Build-76 merger took `base.budget` (latest-lastUpdated's value)
        // which dropped the budget if the newer Mac hadn't fetched it yet.
        let budget = SyncBudgetSnapshot(
            usedAmount: 12.34,
            limitAmount: 100,
            currencyCode: "USD",
            period: "monthly",
            resetsAt: nil)
        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            ProviderUsageSnapshot(
                providerID: "claude",
                providerName: "Claude",
                primary: nil,
                secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: olderDate,
                budget: budget),
        ])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            ProviderUsageSnapshot(
                providerID: "claude",
                providerName: "Claude",
                primary: nil,
                secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: newerDate,
                budget: nil),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let claude = try #require(merged.providers.first)
        #expect(claude.budget?.usedAmount == 12.34)
        #expect(claude.budget?.limitAmount == 100)
    }

    @Test("non-local-cost costSummary: older Mac with data + newer Mac with nil → merged keeps data")
    func nonLocalCostInvertedFreshnessKeepsData() throws {
        // Cost for account-level providers (Cursor, Perplexity, OpenCode Go,
        // etc. — anything NOT in localCostProviders) should follow
        // latestNonNil semantics, not take-latest. Test with `cursor`
        // (account-level via API, not per-Mac CLI).
        let cost = SyncCostSummary(
            sessionCostUSD: 1.23,
            sessionTokens: 0,
            last30DaysCostUSD: 45.67,
            last30DaysTokens: 0,
            daily: [])
        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            ProviderUsageSnapshot(
                providerID: "cursor",
                providerName: "Cursor",
                primary: nil,
                secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: olderDate,
                costSummary: cost),
        ])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            ProviderUsageSnapshot(
                providerID: "cursor",
                providerName: "Cursor",
                primary: nil,
                secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: newerDate,
                costSummary: nil),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let cursor = try #require(merged.providers.first)
        #expect(cursor.costSummary?.sessionCostUSD == 1.23)
    }

    @Test("local-cost costSummary STILL sums (not overridden by the new latestNonNil path)")
    func localCostStillSumsAfterRefactor() throws {
        // Guard against accidentally regressing the claude / codex / vertexai
        // SUMMING semantic when we added latestNonNil for non-local. Two
        // Macs both report $10 session cost for claude (a local-cost
        // provider) — merged should be $20 (sum), not $10 (latest).
        let costA = SyncCostSummary(
            sessionCostUSD: 10,
            sessionTokens: 0,
            last30DaysCostUSD: 100,
            last30DaysTokens: 0,
            daily: [])
        let costB = SyncCostSummary(
            sessionCostUSD: 10,
            sessionTokens: 0,
            last30DaysCostUSD: 100,
            last30DaysTokens: 0,
            daily: [])
        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            ProviderUsageSnapshot(
                providerID: "claude", providerName: "Claude",
                primary: nil, secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil, statusMessage: nil,
                isError: false, lastUpdated: olderDate,
                costSummary: costA),
        ])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            ProviderUsageSnapshot(
                providerID: "claude", providerName: "Claude",
                primary: nil, secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil, statusMessage: nil,
                isError: false, lastUpdated: newerDate,
                costSummary: costB),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let claude = try #require(merged.providers.first)
        #expect(claude.costSummary?.sessionCostUSD == 20) // SUMMED, not 10
    }

    @Test("loginMethod: older Mac with plan + newer Mac with nil → merged keeps plan")
    func loginMethodInvertedFreshnessKeepsData() throws {
        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: "Pro",
                statusMessage: nil, isError: false,
                lastUpdated: olderDate),
        ])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil,
                statusMessage: nil, isError: false,
                lastUpdated: newerDate),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.first?.loginMethod == "Pro")
    }

    @Test("Single-device Perplexity snapshot preserves perplexityCredits through merge no-op")
    func perplexityCreditsPreservedSingleDevice() throws {
        // Degenerate single-device path: mergeProviderEntries still runs
        // (merger doesn't special-case count == 1 at the provider level),
        // so this verifies the field survives even the trivial passthrough.
        let credits = SyncPerplexityCreditSummary(
            recurringTotalCents: 7500, renewalAt: Date(timeIntervalSince1970: 1_700_600_000), planName: "Max")
        let mac = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            makePerplexitySnapshot(lastUpdated: olderDate, credits: credits),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([mac]))
        #expect(merged.providers.first?.perplexityCredits?.planName == "Max")
        #expect(merged.providers.first?.perplexityCredits?.recurringTotalCents == 7500)
    }

    // MARK: - App/mobile version: take highest across devices (Build 77)
    //
    // Reported scenario: user has two Macs on different CodexBar versions
    // (e.g. 0.19.0 and 0.20.3). The "Mac App" field in iOS Settings used
    // `snapshots.first?.appVersion`, which is whichever snapshot CloudKit
    // iterated first — flipped non-deterministically run to run. Users saw
    // the older version "randomly" even though the newer Mac was fully
    // synced. Fix: take highest semver across devices.

    @Test("Mac App version merged to highest semver across two Macs")
    func appVersionTakesHighest() throws {
        let macOld = SyncedUsageSnapshot(
            providers: [makeProvider(id: "claude", name: "Claude", lastUpdated: olderDate)],
            syncTimestamp: olderDate,
            deviceName: "Old Mac", deviceID: "uuid-old",
            appVersion: "0.19.0", mobileVersion: "1.2.0")
        let macNew = SyncedUsageSnapshot(
            providers: [makeProvider(id: "codex", name: "Codex", lastUpdated: newerDate)],
            syncTimestamp: newerDate,
            deviceName: "New Mac", deviceID: "uuid-new",
            appVersion: "0.20.3", mobileVersion: "1.3.0")

        let merged = try #require(CloudSyncReader.mergeSnapshots([macOld, macNew]))
        #expect(merged.appVersion == "0.20.3")
        #expect(merged.mobileVersion == "1.3.0")
    }

    @Test("Mac App version merge is order-independent")
    func appVersionOrderIndependent() throws {
        // Same two snapshots, flipped iteration order — the result must not
        // change. The pre-fix bug was: `snapshots.first?.appVersion` returned
        // 0.19.0 here but 0.20.3 in the previous test, purely based on order.
        let macNew = SyncedUsageSnapshot(
            providers: [makeProvider(id: "codex", name: "Codex", lastUpdated: newerDate)],
            syncTimestamp: newerDate,
            deviceName: "New Mac", deviceID: "uuid-new",
            appVersion: "0.20.3", mobileVersion: "1.3.0")
        let macOld = SyncedUsageSnapshot(
            providers: [makeProvider(id: "claude", name: "Claude", lastUpdated: olderDate)],
            syncTimestamp: olderDate,
            deviceName: "Old Mac", deviceID: "uuid-old",
            appVersion: "0.19.0", mobileVersion: "1.2.0")

        let merged = try #require(CloudSyncReader.mergeSnapshots([macNew, macOld]))
        #expect(merged.appVersion == "0.20.3")
        #expect(merged.mobileVersion == "1.3.0")
    }

    @Test("Semver comparison handles 2-segment, 3-segment, and non-numeric segments")
    func semverComparison() {
        // Numeric-segment ordering
        #expect(CloudSyncReader.semverLessThan("0.19.0", "0.20.0"))
        #expect(CloudSyncReader.semverLessThan("0.20.0", "0.20.3"))
        #expect(!CloudSyncReader.semverLessThan("0.20.3", "0.20.0"))
        #expect(!CloudSyncReader.semverLessThan("0.20.3", "0.20.3"))

        // Mixed segment counts (treat missing as 0)
        #expect(CloudSyncReader.semverLessThan("0.20", "0.20.1"))
        #expect(!CloudSyncReader.semverLessThan("0.20.0", "0.20"))

        // Non-numeric suffix falls back to string comparison
        #expect(CloudSyncReader.semverLessThan("0.20.0-beta", "0.20.0-rc"))
    }

    // MARK: - Utilization history: cross-version series merge (Build 77)
    //
    // Reported scenario: iPhone Cost tab's "Subscription Utilization"
    // section showed Codex at 0% even though the Codex detail page rendered
    // clear session bars and "16% used". Root cause was two-fold:
    //   (a) aggregate view averaged raw entries instead of daily peaks
    //       (bursty providers look like zeros in raw avg) — fixed in
    //       UtilizationAggregateView.buildModel;
    //   (b) `mergeUtilizationHistories` grouped by (name, windowMinutes),
    //       so if two Macs disagreed on `windowMinutes` for the same series,
    //       two "session" entries landed in the merged history and
    //       downstream pickers hit the stale one non-deterministically.
    // These tests pin (b): same-name series must union, and the freshest
    // device's windowMinutes wins.

    private func makeCodexWithSession(
        email: String = "user@example.com",
        lastUpdated: Date,
        windowMinutes: Int = 300,
        entries: [SyncUtilizationEntry]
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil, secondary: nil,
            accountEmail: email,
            loginMethod: nil, statusMessage: nil,
            isError: false, lastUpdated: lastUpdated,
            utilizationHistory: [SyncUtilizationSeries(
                name: "session", windowMinutes: windowMinutes, entries: entries)])
    }

    @Test("Two Macs reporting session with mismatched windowMinutes merge into ONE session series")
    func utilizationMismatchedWindowMinutesUnion() throws {
        let hourAgo = Date().addingTimeInterval(-3600)
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        let macA = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            makeCodexWithSession(
                lastUpdated: olderDate,
                windowMinutes: 300,
                entries: [SyncUtilizationEntry(
                    capturedAt: twoHoursAgo, usedPercent: 25, resetsAt: nil)]),
        ])
        let macB = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            makeCodexWithSession(
                lastUpdated: newerDate,
                // Different windowMinutes — pre-fix, this created a SECOND
                // "session" series that downstream code could pick instead.
                windowMinutes: 180,
                entries: [SyncUtilizationEntry(
                    capturedAt: hourAgo, usedPercent: 40, resetsAt: nil)]),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let codex = try #require(merged.providers.first { $0.providerID == "codex" })
        let sessions = codex.utilizationHistory?.filter { $0.name == "session" } ?? []
        #expect(sessions.count == 1)  // Unioned, not split
        // The newer Mac's windowMinutes wins (180), because its entry was
        // captured more recently.
        #expect(sessions.first?.windowMinutes == 180)
        // Both devices' entries survive the union.
        let entryCount = sessions.first?.entries.count ?? 0
        #expect(entryCount == 2)
    }

    @Test("Mac B reports empty session; Mac A's real entries survive the union")
    func utilizationEmptySeriesFromOneDeviceDoesNotMaskOther() throws {
        // Degenerate but common: one Mac opens, samples Codex once, then gets
        // put to sleep. Its "session" series may be empty until the next
        // refresh. That empty series must not shadow the other Mac's real
        // data when picking windowMinutes or when downstream views filter
        // for `!entries.isEmpty`.
        let now = Date()
        let macARealData = makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            makeCodexWithSession(
                lastUpdated: newerDate,
                entries: [
                    SyncUtilizationEntry(capturedAt: now.addingTimeInterval(-3600),
                                         usedPercent: 30, resetsAt: nil),
                    SyncUtilizationEntry(capturedAt: now.addingTimeInterval(-7200),
                                         usedPercent: 50, resetsAt: nil),
                ]),
        ])
        let macBEmpty = makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            makeCodexWithSession(
                lastUpdated: olderDate,
                entries: []),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([macARealData, macBEmpty]))
        let codex = try #require(merged.providers.first { $0.providerID == "codex" })
        let sessions = codex.utilizationHistory?.filter { $0.name == "session" } ?? []
        #expect(sessions.count == 1)
        #expect((sessions.first?.entries.count ?? 0) >= 2)
    }
}
