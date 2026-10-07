import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Sync Model Codable Tests")
struct SyncModelTests {
    @Test
    func `today totals preserve an explicit zero as reported`() {
        let now = Date(timeIntervalSince1970: 1_745_500_000)
        let summary = SyncCostSummary(
            sessionCostUSD: 42,
            sessionTokens: 900,
            last30DaysCostUSD: 42,
            last30DaysTokens: 900,
            daily: [
                SyncDailyPoint(
                    dayKey: SyncCostSummary.iso8601DayKey(for: now),
                    costUSD: 0,
                    totalTokens: 0),
            ],
            costUpdatedAt: now)

        let today = summary.todayTotals(now: now)
        #expect(today.availability == .reported)
        #expect(today.source == .daily)
        #expect(today.costUSD == 0)
        #expect(today.tokens == 0)
    }

    @Test
    func `today totals keep partial positive subtotals and hide unknown zero`() {
        let now = Date(timeIntervalSince1970: 1_745_500_000)
        let todayKey = SyncCostSummary.iso8601DayKey(for: now)
        let partial = SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: 2.5,
            last30DaysTokens: 250,
            daily: [SyncDailyPoint(
                dayKey: todayKey,
                costUSD: 2.5,
                totalTokens: 250,
                costIsKnown: false)],
            costIsKnown: false)
        let unknownZero = SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: 0,
            last30DaysTokens: 250,
            daily: [SyncDailyPoint(
                dayKey: todayKey,
                costUSD: 0,
                totalTokens: 250,
                costIsKnown: false)],
            costIsKnown: false)

        let partialToday = partial.todayTotals(now: now)
        let unknownToday = unknownZero.todayTotals(now: now)

        #expect(partialToday.availability == .reported)
        #expect(partialToday.costUSD == 2.5)
        #expect(partialToday.tokens == 250)
        #expect(partialToday.isPartial)
        #expect(unknownToday.availability == .unavailable)
        #expect(unknownToday.costUSD == nil)
        #expect(unknownToday.tokens == 250)
        #expect(unknownToday.isPartial)
    }

    @Test
    func `today session fallback inherits the summary unknown marker`() {
        let now = Date(timeIntervalSince1970: 1_745_500_000)
        let positive = SyncCostSummary(
            sessionCostUSD: 1.25,
            sessionTokens: 100,
            last30DaysCostUSD: 1.25,
            last30DaysTokens: 100,
            daily: [],
            costIsKnown: false,
            costUpdatedAt: now)
        let zero = SyncCostSummary(
            sessionCostUSD: 0,
            sessionTokens: 100,
            last30DaysCostUSD: 0,
            last30DaysTokens: 100,
            daily: [],
            costIsKnown: false,
            costUpdatedAt: now)

        let positiveToday = positive.todayTotals(now: now)
        let zeroToday = zero.todayTotals(now: now)

        #expect(positiveToday.costUSD == 1.25)
        #expect(positiveToday.isPartial)
        #expect(zeroToday.availability == .unavailable)
        #expect(zeroToday.costUSD == nil)
        #expect(zeroToday.isPartial)
    }

    @Test
    func `explicit known day overrides a partial aggregate summary`() {
        let now = Date(timeIntervalSince1970: 1_745_500_000)
        let summary = SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: 9,
            last30DaysTokens: 900,
            daily: [SyncDailyPoint(
                dayKey: SyncCostSummary.iso8601DayKey(for: now),
                costUSD: 3,
                totalTokens: 300,
                costIsKnown: true)],
            costIsKnown: false)

        let today = summary.todayTotals(now: now)

        #expect(today.costUSD == 3)
        #expect(!today.isPartial)
    }

    @Test
    func `daily subtotal follows the configured horizon and ignores older partial days`() throws {
        let calendar = Calendar.current
        let now = Date(timeIntervalSince1970: 1_782_816_000)
        let todayKey = SyncCostSummary.iso8601DayKey(for: now)
        let olderDate = try #require(calendar.date(byAdding: .day, value: -31, to: now))
        let olderKey = SyncCostSummary.iso8601DayKey(for: olderDate)
        let summary = SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: nil,
            last30DaysTokens: nil,
            daily: [
                SyncDailyPoint(dayKey: olderKey, costUSD: 8, totalTokens: 800, costIsKnown: false),
                SyncDailyPoint(dayKey: todayKey, costUSD: 2, totalTokens: 200, costIsKnown: true),
            ],
            costIsKnown: false,
            historyDays: 365)

        let thirtyDays = summary.dailyTotals(windowDays: 30, asOf: now)
        let configured = summary.dailyTotals(asOf: now)

        #expect(thirtyDays.costUSD == 2)
        #expect(thirtyDays.totalTokens == 200)
        #expect(!thirtyDays.isPartial)
        #expect(configured.costUSD == 10)
        #expect(configured.totalTokens == 1000)
        #expect(configured.isPartial)
    }

    @Test
    func `raw dashboard projects configured histories onto its thirty day window`() throws {
        let now = Date()
        let todayKey = SyncCostSummary.iso8601DayKey(for: now)
        let olderDate = try #require(Calendar.current.date(byAdding: .day, value: -31, to: now))
        let olderKey = SyncCostSummary.iso8601DayKey(for: olderDate)
        let summary = SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: 10,
            last30DaysTokens: 1000,
            daily: [
                SyncDailyPoint(
                    dayKey: todayKey,
                    costUSD: 2,
                    totalTokens: 200,
                    modelBreakdowns: [SyncCostBreakdown(label: "Current", costUSD: 2)],
                    serviceBreakdowns: [SyncCostBreakdown(label: "Current Service", costUSD: 2)],
                    costIsKnown: true),
                SyncDailyPoint(
                    dayKey: olderKey,
                    costUSD: 8,
                    totalTokens: 800,
                    modelBreakdowns: [SyncCostBreakdown(label: "Older", costUSD: 8)],
                    serviceBreakdowns: [SyncCostBreakdown(label: "Older Service", costUSD: 8)],
                    costIsKnown: false),
            ],
            costIsKnown: false,
            historyDays: 365,
            historyCoverageIsEstablished: true)
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: summary)
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Mac",
            deviceID: "mac-a")

        let insights = CostDashboardInsights(snapshot: snapshot)
        let row = try #require(insights.providerRows.first)

        #expect(row.thirtyDayCost == 2)
        #expect(row.thirtyDayTokens == 200)
        #expect(!row.thirtyDayCostIsPartial)
        #expect(insights.total30DayCost == 2)
        #expect(insights.dailyPoints.map(\.dayKey) == [todayKey])
        #expect(insights.modelRows.map(\.label) == ["Current"])
        #expect(insights.serviceRows.map(\.label) == ["Current Service"])
    }

    @Test
    func `raw dashboard marks histories shorter than thirty days as partial`() throws {
        let now = Date()
        let todayKey = SyncCostSummary.iso8601DayKey(for: now)
        let summary = SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: 5,
            last30DaysTokens: 500,
            daily: [SyncDailyPoint(dayKey: todayKey, costUSD: 2, totalTokens: 200, costIsKnown: true)],
            costIsKnown: true,
            historyDays: 7)
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: summary)
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Mac",
            deviceID: "mac-a")

        let insights = CostDashboardInsights(snapshot: snapshot)
        let row = try #require(insights.providerRows.first)

        #expect(row.thirtyDayCost == 2)
        #expect(row.thirtyDayTokens == 200)
        #expect(row.thirtyDayCostIsPartial)
    }

    @Test
    func `raw dashboard keeps incomplete scan coverage partial despite a known day`() throws {
        let now = Date()
        let todayKey = SyncCostSummary.iso8601DayKey(for: now)
        let summary = SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: 5,
            last30DaysTokens: 500,
            daily: [SyncDailyPoint(dayKey: todayKey, costUSD: 2, totalTokens: 200, costIsKnown: true)],
            costIsKnown: false,
            historyDays: 365,
            historyCoverageIsEstablished: false)
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: summary)
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Mac",
            deviceID: "mac-a")

        let insights = CostDashboardInsights(snapshot: snapshot)
        let row = try #require(insights.providerRows.first)

        #expect(row.thirtyDayCost == 2)
        #expect(row.thirtyDayCostIsPartial)
    }

    @Test
    func `today totals only use a session fallback when freshness is today`() {
        let now = Date(timeIntervalSince1970: 1_745_500_000)
        let summary = SyncCostSummary(
            sessionCostUSD: 1.23,
            sessionTokens: 1000,
            last30DaysCostUSD: 50,
            last30DaysTokens: 30000,
            daily: [
                SyncDailyPoint(dayKey: "2020-01-01", costUSD: 99, totalTokens: 9999),
            ])

        let today = summary.todayTotals(now: now, providerLastUpdated: now)
        #expect(today.availability == .reported)
        #expect(today.source == .session)
        #expect(today.costUSD == 1.23)

        let yesterday = summary.todayTotals(now: now, providerLastUpdated: now.addingTimeInterval(-86400))
        #expect(yesterday.availability == .unavailable)
        #expect(yesterday.costUSD == nil)
    }

    @Test
    func `today totals report unavailable when session freshness is not today`() {
        let now = Date(timeIntervalSince1970: 1_745_500_000)
        let summary = SyncCostSummary(
            sessionCostUSD: 1.23,
            sessionTokens: 1000,
            last30DaysCostUSD: 50,
            last30DaysTokens: 30000,
            daily: [
                SyncDailyPoint(dayKey: "2020-01-01", costUSD: 99, totalTokens: 9999),
            ])

        let today = summary.todayTotals(now: now, providerLastUpdated: now.addingTimeInterval(-86400))
        #expect(today.availability == .unavailable)
        #expect(today.costUSD == nil)
        #expect(today.source == .none)
    }

    @Test
    func `today totals retain a stale reported value instead of hiding it`() {
        let now = Date(timeIntervalSince1970: 1_745_500_000)
        let summary = SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: 20,
            last30DaysTokens: 200,
            daily: [
                SyncDailyPoint(
                    dayKey: SyncCostSummary.iso8601DayKey(for: now),
                    costUSD: 4.56,
                    totalTokens: 400),
            ],
            costUpdatedAt: now.addingTimeInterval(-2 * 60 * 60))

        let today = summary.todayTotals(now: now)
        #expect(today.availability == .reported)
        #expect(today.costUSD == 4.56)
        #expect(today.isStale)
    }

    @Test
    func `ProviderUsageSnapshot round-trips through JSON`() throws {
        let snapshot = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: SyncRateWindow(
                usedPercent: 42.5,
                windowMinutes: 300,
                resetsAt: Date(timeIntervalSince1970: 1_700_000_000),
                resetDescription: "Resets in 2h 30m"),
            secondary: SyncRateWindow(
                usedPercent: 15.0,
                windowMinutes: 10080,
                resetsAt: nil,
                resetDescription: "Resets Monday"),
            accountEmail: "user@example.com",
            loginMethod: "Pro",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let data = try encoder.encode(snapshot)

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(ProviderUsageSnapshot.self, from: data)

        #expect(decoded.providerID == "claude")
        #expect(decoded.providerName == "Claude")
        #expect(decoded.primary?.usedPercent == 42.5)
        #expect(decoded.primary?.windowMinutes == 300)
        #expect(decoded.primary?.remainingPercent == 57.5)
        #expect(decoded.secondary?.usedPercent == 15.0)
        #expect(decoded.accountEmail == "user@example.com")
        #expect(decoded.loginMethod == "Pro")
        #expect(decoded.isError == false)
        #expect(decoded.costSummary == nil)
        #expect(decoded.budget == nil)
    }

    @Test
    func `SyncedUsageSnapshot round-trips through JSON`() throws {
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: SyncRateWindow(
                usedPercent: 80.0,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: "Rate limited",
            isError: true,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))

        let synced = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test Mac",
            deviceID: "test-uuid-123")

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let data = try encoder.encode(synced)

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncedUsageSnapshot.self, from: data)

        #expect(decoded.providers.count == 1)
        #expect(decoded.providers[0].providerID == "codex")
        #expect(decoded.providers[0].isError == true)
        #expect(decoded.deviceName == "Test Mac")
        #expect(decoded.deviceID == "test-uuid-123")
    }

    @Test
    func `SyncedUsageSnapshot without deviceID decodes with nil (backward compat)`() throws {
        let oldJSON = """
        {
            "providers": [],
            "syncTimestamp": "2023-11-14T22:13:20Z",
            "deviceName": "Old Mac"
        }
        """

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncedUsageSnapshot.self, from: Data(oldJSON.utf8))

        #expect(decoded.deviceName == "Old Mac")
        #expect(decoded.deviceID == nil)
    }

    @Test
    func `SyncRateWindow remainingPercent clamps to zero`() {
        let window = SyncRateWindow(
            usedPercent: 150.0,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil)
        #expect(window.remainingPercent == 0)
    }

    @Test
    func `Codex reset details filter unavailable rows and sort known expirations first`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let resetCredits = SyncCodexResetCredits(
            credits: [
                SyncCodexResetCredit(
                    id: "no-expiry",
                    resetType: "codex_rate_limits",
                    status: "available",
                    grantedAt: now),
                SyncCodexResetCredit(
                    id: "later",
                    resetType: "codex_rate_limits",
                    status: "available",
                    grantedAt: now,
                    expiresAt: now.addingTimeInterval(200)),
                SyncCodexResetCredit(
                    id: "redeemed",
                    resetType: "codex_rate_limits",
                    status: "redeemed",
                    grantedAt: now,
                    expiresAt: now.addingTimeInterval(50)),
                SyncCodexResetCredit(
                    id: "expired",
                    resetType: "codex_rate_limits",
                    status: "available",
                    grantedAt: now,
                    expiresAt: now.addingTimeInterval(-1)),
                SyncCodexResetCredit(
                    id: "earlier",
                    resetType: "codex_rate_limits",
                    status: "available",
                    grantedAt: now,
                    expiresAt: now.addingTimeInterval(100)),
            ],
            availableCount: 4,
            updatedAt: now)

        #expect(resetCredits.authoritativeAvailableCount == 4)
        #expect(resetCredits.availableCredits(at: now).map(\.id) == [
            "earlier",
            "later",
            "no-expiry",
        ])
        #expect(resetCredits.hasAvailableInventory)
    }

    @Test
    func `Codex credit limit becomes display fallback when no rate windows exist`() {
        let creditLimit = SyncCodexCreditLimit(
            title: "Monthly credit limit",
            used: 99000,
            limit: 100_000,
            remaining: 1000,
            remainingPercent: 1,
            resetsAt: Date(timeIntervalSince1970: 1_700_086_400),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let codex = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            codexCreditLimit: creditLimit)
        let claude = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            codexCreditLimit: creditLimit)

        #expect(codex.displayRateWindows.count == 1)
        #expect(codex.displayRateWindows.first?.label == "Monthly credit limit")
        #expect(codex.displayRateWindows.first?.usedPercent == 99)
        #expect(codex.displayRateWindows.first?.remainingPercent == 1)
        #expect(claude.displayRateWindows.isEmpty)
    }

    @Test
    func `SyncRateWindow decodes old payloads with nil pace`() throws {
        let json = """
        {
            "label": "Weekly",
            "usedPercent": 42,
            "windowMinutes": 10080,
            "resetsAt": "2023-11-14T22:13:20Z"
        }
        """

        let window = try CloudSyncConstants.makeJSONDecoder()
            .decode(SyncRateWindow.self, from: Data(json.utf8))

        #expect(window.pace == nil)
        #expect(window.identity == nil)
        #expect(window.usedPercent == 42)
    }

    @Test
    func `SyncRateWindow round-trips typed identity`() throws {
        let window = SyncRateWindow(
            label: "Session",
            usedPercent: 50,
            windowMinutes: 300,
            resetsAt: Date(timeIntervalSince1970: 1_700_000_000),
            resetDescription: nil,
            identity: .session)

        let data = try CloudSyncConstants.makeJSONEncoder().encode(window)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(SyncRateWindow.self, from: data)

        #expect(decoded.identity == .session)
    }

    @Test
    func `SyncRateWindow decodes unknown identity as nil`() throws {
        let json = """
        {
            "label": "Monthly",
            "usedPercent": 37,
            "windowMinutes": 43200,
            "resetsAt": "2023-11-14T22:13:20Z",
            "identity": "monthly"
        }
        """

        let window = try CloudSyncConstants.makeJSONDecoder()
            .decode(SyncRateWindow.self, from: Data(json.utf8))

        #expect(window.identity == nil)
        #expect(window.usedPercent == 37)
        #expect(window.windowMinutes == 43200)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test
    func `SyncRateWindow round-trips populated pace`() throws {
        let pace = SyncUsagePace(
            stage: .ahead,
            deltaPercent: 7,
            expectedUsedPercent: 43,
            actualUsedPercent: 50,
            leftLabel: "7% in deficit",
            rightLabel: "Runs out in 3d")
        let window = SyncRateWindow(
            label: "Weekly",
            usedPercent: 50,
            windowMinutes: 10080,
            resetsAt: Date(timeIntervalSince1970: 1_700_000_000),
            resetDescription: nil,
            pace: pace)

        let data = try CloudSyncConstants.makeJSONEncoder().encode(window)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(SyncRateWindow.self, from: data)

        #expect(decoded.pace == pace)
        #expect(decoded.pace?.leftLabel == "7% in deficit")
    }

    @Test
    func `Empty provider list encodes correctly`() throws {
        let synced = SyncedUsageSnapshot(
            providers: [],
            syncTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Empty Mac")

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let data = try encoder.encode(synced)
        #expect(data.count < CloudSyncConstants.maxPayloadBytes)

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncedUsageSnapshot.self, from: data)
        #expect(decoded.providers.isEmpty)
    }

    // MARK: - Backward Compatibility

    @Test
    func `Old JSON without cost fields decodes correctly`() throws {
        // Simulate a payload from an older Mac app that doesn't include costSummary/budget
        let oldJSON = """
        {
            "providerID": "claude",
            "providerName": "Claude",
            "primary": {
                "usedPercent": 42.5,
                "windowMinutes": 300
            },
            "accountEmail": "user@example.com",
            "loginMethod": "Pro",
            "isError": false,
            "lastUpdated": "2023-11-14T22:13:20Z"
        }
        """

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(ProviderUsageSnapshot.self, from: Data(oldJSON.utf8))

        #expect(decoded.providerID == "claude")
        #expect(decoded.primary?.usedPercent == 42.5)
        #expect(decoded.costSummary == nil)
        #expect(decoded.budget == nil)
        #expect(decoded.secondary == nil)
        #expect(decoded.statusMessage == nil)
    }

    // MARK: - Cost Data Round-Trip

    @Test
    func `Cost summary and budget round-trip through JSON`() throws {
        let daily = [
            SyncDailyPoint(
                dayKey: "2024-01-15",
                costUSD: 1.42,
                totalTokens: 12340,
                modelBreakdowns: [
                    SyncCostBreakdown(label: "gpt-5.4", costUSD: 1.10),
                    SyncCostBreakdown(label: "gpt-5.3-codex", costUSD: 0.32),
                ],
                serviceBreakdowns: [SyncCostBreakdown(label: "Codex Run", costUSD: 1.42)]),
            SyncDailyPoint(dayKey: "2024-01-16", costUSD: 2.10, totalTokens: 18500),
        ]

        let snapshot = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            costSummary: SyncCostSummary(
                sessionCostUSD: 1.42,
                sessionTokens: 12340,
                last30DaysCostUSD: 28.90,
                last30DaysTokens: 1_245_000,
                daily: daily),
            budget: SyncBudgetSnapshot(
                usedAmount: 42.50,
                limitAmount: 100.0,
                currencyCode: "USD",
                period: "Monthly",
                resetsAt: Date(timeIntervalSince1970: 1_701_000_000)))

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let data = try encoder.encode(snapshot)

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(ProviderUsageSnapshot.self, from: data)

        #expect(decoded.costSummary?.sessionCostUSD == 1.42)
        #expect(decoded.costSummary?.sessionTokens == 12340)
        #expect(decoded.costSummary?.last30DaysCostUSD == 28.90)
        #expect(decoded.costSummary?.last30DaysTokens == 1_245_000)
        #expect(decoded.costSummary?.daily.count == 2)
        #expect(decoded.costSummary?.daily[0].dayKey == "2024-01-15")
        #expect(decoded.costSummary?.daily[0].costUSD == 1.42)
        #expect(decoded.costSummary?.daily[0].totalTokens == 12340)
        #expect(decoded.costSummary?.daily[0].modelBreakdowns == [
            SyncCostBreakdown(label: "gpt-5.4", costUSD: 1.10),
            SyncCostBreakdown(label: "gpt-5.3-codex", costUSD: 0.32),
        ])
        #expect(decoded.costSummary?.daily[0].serviceBreakdowns == [
            SyncCostBreakdown(label: "Codex Run", costUSD: 1.42),
        ])

        #expect(decoded.budget?.usedAmount == 42.50)
        #expect(decoded.budget?.limitAmount == 100.0)
        #expect(decoded.budget?.currencyCode == "USD")
        #expect(decoded.budget?.period == "Monthly")
        #expect(decoded.budget?.resetsAt != nil)
    }

    // MARK: - Payload Size

    // MARK: - Version Fields

    @Test
    func `SyncedUsageSnapshot includes appVersion and mobileVersion`() throws {
        let synced = SyncedUsageSnapshot(
            providers: [],
            syncTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test Mac",
            appVersion: "0.18.0-beta.3",
            mobileVersion: "1.0.0")

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let data = try encoder.encode(synced)

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncedUsageSnapshot.self, from: data)

        #expect(decoded.appVersion == "0.18.0-beta.3")
        #expect(decoded.mobileVersion == "1.0.0")
    }

    @Test
    func `Legacy syncVersion key decodes into mobileVersion`() throws {
        let legacyJSON = """
        {
            "providers": [],
            "syncTimestamp": "2023-11-14T22:13:20Z",
            "deviceName": "Old Mac",
            "appVersion": "0.17.0",
            "syncVersion": "0.1.0"
        }
        """

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncedUsageSnapshot.self, from: Data(legacyJSON.utf8))

        #expect(decoded.mobileVersion == "0.1.0")
    }

    @Test
    func `Old payload without version fields decodes with nil`() throws {
        let oldJSON = """
        {
            "providers": [],
            "syncTimestamp": "2023-11-14T22:13:20Z",
            "deviceName": "Old Mac"
        }
        """

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncedUsageSnapshot.self, from: Data(oldJSON.utf8))

        #expect(decoded.deviceName == "Old Mac")
        #expect(decoded.appVersion == nil)
        #expect(decoded.mobileVersion == nil)
    }

    // MARK: - Payload Size

    @Test
    func `10 providers x 30 days stays under 1MB KVS limit`() throws {
        let daily = (0..<30).map { day in
            SyncDailyPoint(
                dayKey: "2024-01-\(String(format: "%02d", day + 1))",
                costUSD: Double.random(in: 0.10...5.00),
                totalTokens: Int.random(in: 1000...100_000),
                modelBreakdowns: [
                    SyncCostBreakdown(label: "Model A", costUSD: 0.7),
                    SyncCostBreakdown(label: "Model B", costUSD: 0.3),
                ])
        }

        let costSummary = SyncCostSummary(
            sessionCostUSD: 2.50,
            sessionTokens: 25000,
            last30DaysCostUSD: 45.00,
            last30DaysTokens: 2_000_000,
            daily: daily)

        let budget = SyncBudgetSnapshot(
            usedAmount: 60.0,
            limitAmount: 100.0,
            currencyCode: "USD",
            period: "Monthly",
            resetsAt: Date(timeIntervalSince1970: 1_701_000_000))

        let providers = (0..<10).map { i in
            ProviderUsageSnapshot(
                providerID: "provider-\(i)",
                providerName: "Provider \(i)",
                primary: SyncRateWindow(
                    usedPercent: Double(i * 15),
                    windowMinutes: 300,
                    resetsAt: Date(timeIntervalSince1970: 1_700_000_000),
                    resetDescription: nil),
                secondary: SyncRateWindow(
                    usedPercent: Double(i * 10),
                    windowMinutes: 10080,
                    resetsAt: nil,
                    resetDescription: nil),
                accountEmail: "user\(i)@example.com",
                loginMethod: "Pro",
                statusMessage: nil,
                isError: false,
                lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
                costSummary: costSummary,
                budget: budget)
        }

        let synced = SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test Mac")

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let data = try encoder.encode(synced)

        // iCloud KVS limit is 1MB per key
        #expect(data.count < CloudSyncConstants.maxPayloadBytes)
    }

    @Test
    func `Cost dashboard insights aggregate ten providers`() {
        var providers: [ProviderUsageSnapshot] = []
        var expectedTotal30DayCost = 0.0
        let now = Date()
        let calendar = Calendar.current

        for index in 0..<10 {
            let dayCost = Double(index + 1) * 0.9
            let last30DayCost = Double(index + 1) * 3.5
            let dayDate = calendar.date(byAdding: .day, value: -index, to: now)!
            let daily = [
                SyncDailyPoint(
                    dayKey: SyncCostSummary.iso8601DayKey(for: dayDate),
                    costUSD: dayCost,
                    totalTokens: (index + 1) * 1500,
                    modelBreakdowns: [
                        SyncCostBreakdown(label: "Model \(index % 3)", costUSD: Double(index + 1) * 0.5),
                    ],
                    serviceBreakdowns: index == 0
                        ? [SyncCostBreakdown(label: "Codex Run", costUSD: 0.9)]
                        : []),
            ]
            let costSummary = SyncCostSummary(
                sessionCostUSD: Double(index + 1) * 0.4,
                sessionTokens: (index + 1) * 1000,
                last30DaysCostUSD: last30DayCost,
                last30DaysTokens: (index + 1) * 10000,
                daily: daily)
            let budget = SyncBudgetSnapshot(
                usedAmount: Double(index + 1) * 5,
                limitAmount: 100,
                currencyCode: "USD",
                period: "Monthly",
                resetsAt: nil)

            providers.append(
                ProviderUsageSnapshot(
                    providerID: "provider-\(index)",
                    providerName: "Provider \(index)",
                    primary: nil,
                    secondary: nil,
                    accountEmail: "user\(index)@example.com",
                    loginMethod: index.isMultiple(of: 2) ? "API" : "Plan",
                    statusMessage: nil,
                    isError: false,
                    lastUpdated: now,
                    costSummary: costSummary,
                    budget: budget))
            expectedTotal30DayCost += last30DayCost
        }

        let snapshot = SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: now,
            deviceName: "Test Mac")
        let insights = CostDashboardInsights(snapshot: snapshot)

        #expect(insights.providerRows.count == 10)
        #expect(insights.budgetRows.count == 10)
        #expect(insights.dailyPoints.count == 10)
        #expect(insights.total30DayCost == expectedTotal30DayCost)
        #expect(insights.serviceRows.first?.label == "Codex Run")
        #expect(insights.hasDisplayData == true)
    }

    @Test
    func `Cost dashboard model mix retains and derives model token totals`() {
        let daily = SyncDailyPoint(
            dayKey: SyncCostSummary.iso8601DayKey(for: Date()),
            costUSD: 6.0,
            totalTokens: 1200,
            modelBreakdowns: [
                SyncCostBreakdown(label: "Sol", costUSD: 1.0, totalTokens: 600),
                SyncCostBreakdown(
                    label: "Terra",
                    costUSD: 2.0,
                    standardTokens: 200,
                    priorityTokens: 100),
                SyncCostBreakdown(label: "Luna", costUSD: 3.0),
            ])
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "Pro",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: nil,
                last30DaysTokens: nil,
                daily: [daily]))

        let insights = CostDashboardInsights(snapshot: SyncedUsageSnapshot(
            providers: [provider], syncTimestamp: Date(), deviceName: "Test Mac"))
        let modelTokens = Dictionary(
            uniqueKeysWithValues: insights.modelRows.map { ($0.label, $0.totalTokens) })

        #expect(modelTokens["Sol"] == 600)
        #expect(modelTokens["Terra"] == 300)
        #expect(insights.modelRows.first(where: { $0.label == "Luna" })?.totalTokens == nil)
    }

    @Test
    func `Cost dashboard keeps partial aggregates and daily points marked`() throws {
        let now = Date()
        let todayKey = CostDashboardInsights.todayDayKey(now: now)
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "API",
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 2.5,
                sessionTokens: 250,
                last30DaysCostUSD: 8.75,
                last30DaysTokens: 875,
                daily: [SyncDailyPoint(
                    dayKey: todayKey,
                    costUSD: 2.5,
                    totalTokens: 250,
                    modelBreakdowns: [SyncCostBreakdown(
                        label: "gpt-4o",
                        costUSD: 2.5,
                        totalTokens: 250)],
                    costIsKnown: false)],
                costIsKnown: false,
                costUpdatedAt: now))
        let insights = CostDashboardInsights(snapshot: SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Test Mac"))
        let row = try #require(insights.providerRows.first)
        let daily = try #require(insights.dailyPoints.first)

        #expect(insights.total30DayCost == 8.75)
        #expect(insights.total30DayCostIsPartial)
        #expect(row.thirtyDayCostIsPartial)
        #expect(insights.totalTodayCost == 2.5)
        #expect(insights.todayHasPartialCost)
        #expect(row.today.isPartial)
        #expect(insights.modelRows.first?.isPartial == true)
        #expect(daily.costUSD == 2.5)
        #expect(daily.isPartial)
    }

    // MARK: - Future-field resilience (Build 78 · Fix C)

    //
    // Scenario: Mac 0.21 (hypothetical future version) adds a new field to
    // `ProviderUsageSnapshot` or `SyncedUsageSnapshot` that iOS 1.3.0 doesn't
    // know about. Mac pushes a CKRecord whose JSON payload includes the new
    // key. iOS 1.3.0's decoder must **silently ignore** the unknown key and
    // preserve all known fields — any `throws` would cascade through
    // `CloudSyncManager.decodeEnvelope(from:)` → `return nil`, and that one
    // Mac's data would vanish from the iPhone view until the user upgraded iOS.
    //
    // These tests synthesize the scenario by encoding a real snapshot, injecting
    // unknown keys at the JSON-dict level, re-encoding, and asserting round-trip.
    // Swift's synthesized + custom `init(from:)` behavior both SHOULD tolerate
    // unknown keys (keyed containers don't fail on unknown keys unless you
    // explicitly enumerate them), but without a pinned test, a future refactor
    // to a strict decoder would silently break all iOS-reading-newer-Mac paths.

    private static func injectFutureFields(
        into data: Data,
        extras: [String: Any]) throws -> Data
    {
        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FutureFieldTestError.notATopLevelDictionary
        }
        for (key, value) in extras {
            dict[key] = value
        }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private enum FutureFieldTestError: Error {
        case notATopLevelDictionary
    }

    @Test
    func `ProviderUsageSnapshot tolerates unknown future fields at the JSON top level`() throws {
        let original = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: SyncRateWindow(
                usedPercent: 42.5, windowMinutes: 300,
                resetsAt: Date(timeIntervalSince1970: 1_700_000_000),
                resetDescription: nil),
            secondary: nil,
            accountEmail: "user@example.com",
            loginMethod: "Pro", statusMessage: nil, isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let baseline = try encoder.encode(original)
        let augmented = try Self.injectFutureFields(into: baseline, extras: [
            "futureFieldFromMac021": "hello world",
            "someInt": 42,
            "someNested": ["a": 1, "b": 2],
        ])

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(ProviderUsageSnapshot.self, from: augmented)

        // All known fields survived; unknown fields were silently dropped.
        #expect(decoded.providerID == "claude")
        #expect(decoded.providerName == "Claude")
        #expect(decoded.primary?.usedPercent == 42.5)
        #expect(decoded.accountEmail == "user@example.com")
        #expect(decoded.loginMethod == "Pro")
    }

    @Test
    func `SyncedUsageSnapshot tolerates unknown future fields at the JSON top level`() throws {
        let original = SyncedUsageSnapshot(
            providers: [],
            syncTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Mac A",
            deviceID: "uuid-a",
            appVersion: "0.20.3",
            mobileVersion: "1.3.0",
            notificationPushEnabled: true)

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let baseline = try encoder.encode(original)
        let augmented = try Self.injectFutureFields(into: baseline, extras: [
            "hypotheticalHardwareBadge": "AppleSilicon",
            "hypotheticalBatteryLevel": 0.87,
        ])

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncedUsageSnapshot.self, from: augmented)
        #expect(decoded.deviceName == "Mac A")
        #expect(decoded.deviceID == "uuid-a")
        #expect(decoded.appVersion == "0.20.3")
        #expect(decoded.mobileVersion == "1.3.0")
        #expect(decoded.notificationPushEnabled == true)
    }

    @Test
    func `SyncCostSummary tolerates unknown future fields at the JSON top level`() throws {
        let original = SyncCostSummary(
            sessionCostUSD: 1.23,
            sessionTokens: 1000,
            last30DaysCostUSD: 100,
            last30DaysTokens: 50000,
            daily: [
                SyncDailyPoint(dayKey: "2026-04-23", costUSD: 4.56, totalTokens: 4000),
            ])

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let baseline = try encoder.encode(original)
        let augmented = try Self.injectFutureFields(into: baseline, extras: [
            "hypothetical90DayTotal": 789.0,
            "hypotheticalBucket": "premium",
        ])

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncCostSummary.self, from: augmented)
        #expect(decoded.sessionCostUSD == 1.23)
        #expect(decoded.last30DaysCostUSD == 100)
        #expect(decoded.daily.count == 1)
        #expect(decoded.daily.first?.costUSD == 4.56)
    }

    @Test
    func `SyncPerplexityCreditSummary tolerates unknown future fields`() throws {
        let original = SyncPerplexityCreditSummary(
            recurringTotalCents: 5000,
            recurringUsedCents: 2500,
            renewalAt: Date(timeIntervalSince1970: 1_700_000_000),
            planName: "Pro")

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let baseline = try encoder.encode(original)
        let augmented = try Self.injectFutureFields(into: baseline, extras: [
            "hypotheticalReferralCredits": 500,
            "hypotheticalTeamSharedPool": true,
        ])

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncPerplexityCreditSummary.self, from: augmented)
        #expect(decoded.recurringTotalCents == 5000)
        #expect(decoded.recurringUsedCents == 2500)
        #expect(decoded.planName == "Pro")
    }
}
