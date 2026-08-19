import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

extension SpendDashboardModelTests {
    @Test
    func `model metric changes value ordering ranks and formatting`() {
        let rows = [
            SpendDashboardModel.ModelRow(
                rank: 1,
                provider: .codex,
                providerName: "Codex",
                modelName: "example-cost-heavy-model",
                totalTokens: 1000,
                totalCost: 4),
            SpendDashboardModel.ModelRow(
                rank: 2,
                provider: .codex,
                providerName: "Codex",
                modelName: "example-token-heavy-model",
                totalTokens: 9000,
                totalCost: 2),
            SpendDashboardModel.ModelRow(
                rank: 3,
                provider: .codex,
                providerName: "Codex",
                modelName: "example-unavailable-model",
                totalTokens: nil,
                totalCost: nil),
        ]

        let costRows = spendDashboardModelRows(rows, metric: .cost)
        #expect(costRows.map(\.modelName) == [
            "example-cost-heavy-model",
            "example-token-heavy-model",
            "example-unavailable-model",
        ])
        #expect(costRows.map(\.rank) == [1, 2, 3])

        let tokenRows = spendDashboardModelRows(rows, metric: .tokens)
        #expect(tokenRows.map(\.modelName) == [
            "example-token-heavy-model",
            "example-cost-heavy-model",
            "example-unavailable-model",
        ])
        #expect(tokenRows.map(\.rank) == [1, 2, 3])
        #expect(spendDashboardModelValueText(tokenRows[0], metric: .tokens, currencyCode: "USD") == "9K")
        #expect(spendDashboardModelValueText(tokenRows[2], metric: .tokens, currencyCode: "USD") == "—")
        #expect(
            spendDashboardModelValueText(costRows[0], metric: .cost, currencyCode: "USD")
                == UsageFormatter.currencyString(4, currencyCode: "USD"))
    }

    @Test
    func `token metric reports partial and unavailable model coverage`() throws {
        let complete = Self.input(id: "complete", provider: .codex, currency: "USD", cost: 4)
        let missing = SpendDashboardModel.ProviderInput(
            id: "missing",
            provider: .claude,
            displayName: "Claude",
            snapshot: Self.snapshot(
                currency: "USD",
                entries: [Self.entry(day: "2026-07-16", cost: 2, tokens: nil, model: "claude-model")]))
        let partial = try #require(SpendDashboardModel.build(
            inputs: [complete, missing],
            requestedDays: 30,
            now: Self.now,
            calendar: Self.calendar).groups.first)

        #expect(spendDashboardModelHistoryPresentation(partial, metric: .cost) == .complete)
        #expect(spendDashboardModelHistoryPresentation(partial, metric: .tokens) == .partial)

        let unavailable = try #require(SpendDashboardModel.build(
            inputs: [missing],
            requestedDays: 30,
            now: Self.now,
            calendar: Self.calendar).groups.first)
        #expect(spendDashboardModelHistoryPresentation(unavailable, metric: .tokens) == .unavailable)
    }

    @Test
    func `partially attributed Codex history retains its priced model rows`() throws {
        let codex = SpendDashboardModel.ProviderInput(
            provider: .codex,
            displayName: "Codex",
            snapshot: Self.snapshot(
                currency: "USD",
                entries: [
                    Self.entry(day: "2026-07-15", cost: 2, model: "gpt-5.2-codex"),
                    Self.entry(day: "2026-07-16", cost: 3, model: nil),
                ]))
        let group = try #require(SpendDashboardModel.build(
            inputs: [codex],
            requestedDays: 7,
            now: Self.now,
            calendar: Self.calendar).groups.first)

        #expect(group.totalCost == 5)
        #expect(group.modelHistoryCompleteness == .incomplete)
        #expect(group.models.map(\.modelName) == ["gpt-5.2-codex"])
        #expect(group.models.map(\.totalCost) == [2])
        #expect(spendDashboardModelHistoryPresentation(group) == .partial)
    }

    @Test
    func `unpriced Codex routing row retains priced model rows as partial`() throws {
        let codex = SpendDashboardModel.ProviderInput(
            provider: .codex,
            displayName: "Codex",
            snapshot: Self.snapshot(
                currency: "USD",
                entries: [
                    Self.entryWithBreakdowns(
                        day: "2026-07-15",
                        totalCost: 2,
                        totalTokens: 100,
                        breakdowns: [
                            .init(modelName: "example-priced-codex-model", costUSD: 2, totalTokens: 40),
                            .init(modelName: "example-unpriced-routing-model", costUSD: nil, totalTokens: 60),
                        ]),
                ]))
        let group = try #require(SpendDashboardModel.build(
            inputs: [codex],
            requestedDays: 7,
            now: Self.now,
            calendar: Self.calendar).groups.first)

        #expect(group.totalCost == 2)
        #expect(group.modelHistoryCompleteness == .incomplete)
        #expect(group.models.first(where: { $0.modelName == "example-priced-codex-model" })?.totalCost == 2)
        #expect(group.models.first(where: { $0.modelName == "example-unpriced-routing-model" })?.totalCost == nil)
        #expect(spendDashboardModelHistoryPresentation(group) == .partial)
    }

    @Test
    func `Codex history with only unpriced routing rows stays unavailable`() throws {
        let codex = SpendDashboardModel.ProviderInput(
            provider: .codex,
            displayName: "Codex",
            snapshot: Self.snapshot(
                currency: "USD",
                entries: [
                    Self.entryWithBreakdowns(
                        day: "2026-07-15",
                        totalCost: 2,
                        totalTokens: 100,
                        breakdowns: [
                            .init(modelName: "example-unpriced-routing-model", costUSD: nil, totalTokens: 100),
                        ]),
                ]))
        let group = try #require(SpendDashboardModel.build(
            inputs: [codex],
            requestedDays: 7,
            now: Self.now,
            calendar: Self.calendar).groups.first)

        #expect(group.totalCost == 2)
        #expect(group.modelHistoryCompleteness == .incomplete)
        #expect(group.models.isEmpty)
        #expect(spendDashboardModelHistoryPresentation(group) == .unavailable)
    }

    @Test
    func `partial Codex model history rejects a malformed named cost`() throws {
        let codex = SpendDashboardModel.ProviderInput(
            provider: .codex,
            displayName: "Codex",
            snapshot: Self.snapshot(
                currency: "USD",
                entries: [
                    Self.entryWithBreakdowns(
                        day: "2026-07-15",
                        totalCost: 2,
                        totalTokens: 100,
                        breakdowns: [
                            .init(modelName: "example-priced-codex-model", costUSD: 2, totalTokens: 40),
                            .init(modelName: "example-invalid-codex-model", costUSD: -1, totalTokens: 60),
                        ]),
                ]))
        let group = try #require(SpendDashboardModel.build(
            inputs: [codex],
            requestedDays: 7,
            now: Self.now,
            calendar: Self.calendar).groups.first)

        #expect(group.totalCost == 2)
        #expect(group.modelHistoryCompleteness == .incomplete)
        #expect(group.models.isEmpty)
    }

    @Test
    func `full 30 day coverage keeps unpriced spend unavailable instead of zero`() throws {
        let snapshot = Self.snapshot(
            currency: "USD",
            entries: [
                Self.entry(day: "2026-07-16", cost: nil, tokens: 12, model: nil),
                Self.entry(day: "2026-07-15", cost: nil, tokens: 8, model: nil),
            ])
        let group = try #require(SpendDashboardModel.build(
            inputs: [.init(provider: .claude, displayName: "Claude", snapshot: snapshot)],
            requestedDays: 30,
            now: Self.now,
            calendar: Self.calendar).groups.first)

        #expect(group.coveredDayCount == 30)
        #expect(group.totalCost == nil)
        #expect(group.totalTokens == 20)
        #expect(group.modelHistoryCompleteness == .incomplete)
        #expect(group.models.isEmpty)
        #expect(spendDashboardModelHistoryPresentation(group) == .unavailable)
    }

    @Test
    func `full 30 day coverage keeps empty and known zero spend distinct from unavailable`() throws {
        let unpriced = SpendDashboardModel.build(
            inputs: [.init(provider: .claude, displayName: "Claude", snapshot: Self.snapshot(
                currency: "USD",
                entries: [Self.entry(day: "2026-07-16", cost: nil, tokens: 12, model: nil)]))],
            requestedDays: 30,
            now: Self.now,
            calendar: Self.calendar)
        let empty = SpendDashboardModel.build(
            inputs: [.init(provider: .claude, displayName: "Claude", snapshot: CostUsageTokenSnapshot(
                sessionTokens: nil,
                sessionCostUSD: nil,
                last30DaysTokens: 0,
                last30DaysCostUSD: 0,
                currencyCode: "USD",
                historyDays: 30,
                daily: [],
                updatedAt: Self.now))],
            requestedDays: 30,
            now: Self.now,
            calendar: Self.calendar)
        let knownZero = SpendDashboardModel.build(
            inputs: [.init(provider: .claude, displayName: "Claude", snapshot: Self.snapshot(
                currency: "USD",
                entries: [
                    Self.entry(day: "2026-07-16", cost: 0, tokens: 0, model: nil),
                    Self.entry(day: "2026-07-15", cost: 0, tokens: 0, model: nil),
                ]))],
            requestedDays: 30,
            now: Self.now,
            calendar: Self.calendar)

        for model in [unpriced, empty, knownZero] {
            let group = try #require(model.groups.first)
            #expect(group.coveredDayCount == 30)
        }

        let unpricedGroup = try #require(unpriced.groups.first)
        #expect(unpricedGroup.totalCost == nil)
        #expect(unpricedGroup.modelHistoryCompleteness == .incomplete)
        #expect(unpricedGroup.models.isEmpty)
        #expect(spendDashboardModelHistoryPresentation(unpricedGroup) == .unavailable)

        let emptyGroup = try #require(empty.groups.first)
        #expect(emptyGroup.totalCost == 0)
        #expect(emptyGroup.totalTokens == 0)
        #expect(emptyGroup.modelHistoryCompleteness == .complete)
        #expect(emptyGroup.models.isEmpty)
        #expect(spendDashboardModelHistoryPresentation(emptyGroup) == .empty)

        let knownZeroGroup = try #require(knownZero.groups.first)
        #expect(knownZeroGroup.totalCost == 0)
        #expect(knownZeroGroup.totalTokens == 0)
        #expect(knownZeroGroup.modelHistoryCompleteness == .complete)
        #expect(knownZeroGroup.models.isEmpty)
        #expect(spendDashboardModelHistoryPresentation(knownZeroGroup) == .empty)
    }

    @Test
    func `token mix keeps missing classes unset and supports a 90 day window`() throws {
        let now = Date(timeIntervalSince1970: 1_784_179_200)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let input = SpendDashboardModel.ProviderInput(
            id: "codex",
            provider: .codex,
            displayName: "Codex",
            snapshot: CostUsageTokenSnapshot(
                sessionTokens: nil,
                sessionCostUSD: nil,
                last30DaysTokens: 12,
                last30DaysCostUSD: 1,
                currencyCode: "USD",
                historyDays: 90,
                daily: [
                    CostUsageDailyReport.Entry(
                        date: "2026-07-16",
                        inputTokens: 10,
                        outputTokens: 2,
                        cacheReadTokens: nil,
                        reasoningTokens: 3,
                        totalTokens: 12,
                        costUSD: 1,
                        modelsUsed: ["gpt-5.4"],
                        modelBreakdowns: [
                            .init(modelName: "gpt-5.4", costUSD: 1, totalTokens: 12, reasoningTokens: 3),
                        ]),
                ],
                sessions: [
                    CostUsageSessionBreakdown(
                        sessionID: "s1",
                        lastActivity: now,
                        inputTokens: 10,
                        cachedInputTokens: nil,
                        outputTokens: 2,
                        reasoningTokens: 3,
                        totalTokens: 12,
                        requestCount: 1,
                        costUSD: 1,
                        modelBreakdowns: []),
                ],
                updatedAt: now))
        let model = SpendDashboardModel.build(
            inputs: [input],
            requestedDays: 90,
            now: now,
            calendar: calendar)
        #expect(model.requestedDays == 90)
        let group = model.groups[0]
        #expect(group.tokenMix.inputTokens == 10)
        #expect(group.tokenMix.outputTokens == 2)
        #expect(group.tokenMix.cacheReadTokens == nil)
        #expect(group.tokenMix.reasoningTokens == 3)
        #expect(group.displayedModels.count == 1)
        #expect(group.sessions.count == 1)
        #expect(group.provenance == .listPriceEstimate)
    }

    @Test
    func `stored day keys stay put when the display timezone changes`() throws {
        let now = Date(timeIntervalSince1970: 1_784_222_400) // 2026-07-16 12:00:00 UTC
        let input = SpendDashboardModel.ProviderInput(
            id: "codex",
            provider: .codex,
            displayName: "Codex",
            snapshot: Self.snapshot(
                currency: "USD",
                entries: [Self.entry(day: "2026-07-16", cost: 4, tokens: 12)],
                updatedAt: now))
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let west = SpendDashboardModel.build(
            inputs: [input],
            requestedDays: 7,
            now: now,
            calendar: losAngeles)
        let east = SpendDashboardModel.build(
            inputs: [input],
            requestedDays: 7,
            now: now,
            calendar: shanghai)
        let westDays = west.groups[0].dailyPoints.map {
            CostUsageLocalDay.key(from: $0.day, calendar: losAngeles)
        }
        let eastDays = east.groups[0].dailyPoints.map {
            CostUsageLocalDay.key(from: $0.day, calendar: shanghai)
        }
        #expect(westDays == ["2026-07-16"])
        #expect(eastDays == ["2026-07-16"])
        #expect(west.groups[0].totalCost == east.groups[0].totalCost)
    }

    @Test
    func `openCodex stays on a separate ledger from native Codex`() {
        let now = Date(timeIntervalSince1970: 1_784_179_200)
        let native = SpendDashboardModel.ProviderInput(
            id: "codex:main",
            provider: .codex,
            displayName: "Codex",
            snapshot: Self.snapshot(currency: "USD", entries: [Self.entry(day: "2026-07-16", cost: 4)]),
            sourceKind: .native)
        let openCodex = SpendDashboardModel.ProviderInput(
            id: SpendDashboardModel.openCodexSourceID,
            provider: .codex,
            displayName: "OpenCodex",
            snapshot: Self.snapshot(currency: "USD", entries: [Self.entry(day: "2026-07-16", cost: 9)]),
            sourceKind: .openCodex)
        let sideBySide = SpendDashboardModel.build(
            inputs: [native, openCodex],
            requestedDays: 7,
            now: now)
        #expect(Set(sideBySide.groups[0].providers.map(\.id)) == ["opencodex", "codex:main"])
        #expect(sideBySide.groups[0].providers.count == 2)

        let hiddenNative = SpendDashboardModel.build(
            inputs: [native, openCodex],
            requestedDays: 7,
            now: now,
            hideNativeCodexWhenOpenCodexPresent: true)
        #expect(hiddenNative.groups[0].providers.map(\.id) == [SpendDashboardModel.openCodexSourceID])

        let filtered = SpendDashboardModel.build(
            inputs: [native, openCodex],
            requestedDays: 7,
            now: now,
            hiddenSourceIDs: [SpendDashboardModel.openCodexSourceID])
        #expect(filtered.groups[0].providers.map(\.id) == ["codex:main"])
        #expect(Set(filtered.availableSources.map(\.id)) == ["codex:main", SpendDashboardModel.openCodexSourceID])
    }

    @Test
    func `metered spend stays on the snapshot window instead of a shorter range`() {
        let now = Date(timeIntervalSince1970: 1_784_179_200)
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: 10,
            sessionCostUSD: 1,
            last30DaysTokens: 100,
            last30DaysCostUSD: 10,
            historyDays: 30,
            meteredCostUSD: 4.5,
            costProvenance: .mixed,
            daily: [Self.entry(day: "2026-07-16", cost: 1)],
            updatedAt: now)
        let input = SpendDashboardModel.ProviderInput(
            id: "cursor",
            provider: .cursor,
            displayName: "Cursor",
            snapshot: snapshot)
        let week = SpendDashboardModel.build(inputs: [input], requestedDays: 7, now: now)
        let month = SpendDashboardModel.build(inputs: [input], requestedDays: 30, now: now)
        #expect(week.groups[0].meteredCost == nil)
        #expect(month.groups[0].meteredCost == 4.5)
    }

    @Test
    func `vendor reported daily spend keeps vendor metered provenance`() throws {
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 10,
            last30DaysCostUSD: 3.5,
            costProvenance: .vendorMetered,
            daily: [Self.entry(day: "2026-07-16", cost: 3.5)],
            updatedAt: Self.now)
        let input = SpendDashboardModel.ProviderInput(
            provider: .openrouter,
            displayName: "OpenRouter",
            snapshot: snapshot)

        let model = SpendDashboardModel.build(inputs: [input], requestedDays: 30, now: Self.now)
        let group = try #require(model.groups.first)

        #expect(group.totalCost == 3.5)
        #expect(group.provenance == .vendorMetered)
        #expect(group.meteredCost == nil)
    }

    @Test
    func `hourly points come from request buckets instead of session last activity`() {
        let now = Date(timeIntervalSince1970: 1_784_179_200)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let firstHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let secondHour = calendar.date(byAdding: .hour, value: 1, to: firstHour) ?? firstHour
        let openCodex = SpendDashboardModel.ProviderInput(
            id: SpendDashboardModel.openCodexSourceID,
            provider: .codex,
            displayName: "OpenCodex",
            snapshot: CostUsageTokenSnapshot(
                sessionTokens: 17,
                sessionCostUSD: 2,
                last30DaysTokens: 17,
                last30DaysCostUSD: 2,
                historyDays: 7,
                costProvenance: .listPriceEstimate,
                daily: [Self.entry(day: "2026-07-16", cost: 2, tokens: 17)],
                sessions: [
                    CostUsageSessionBreakdown(
                        sessionID: "chat-1",
                        lastActivity: secondHour,
                        inputTokens: 14,
                        cachedInputTokens: nil,
                        outputTokens: 3,
                        totalTokens: 17,
                        requestCount: 2,
                        costUSD: 2,
                        modelBreakdowns: []),
                ],
                hourly: [
                    CostUsageHourlyEntry(hour: firstHour, totalTokens: 12, costUSD: 1.2),
                    CostUsageHourlyEntry(hour: secondHour, totalTokens: 5, costUSD: 0.8),
                ],
                updatedAt: now),
            sourceKind: .openCodex)
        let native = SpendDashboardModel.ProviderInput(
            id: "codex",
            provider: .codex,
            displayName: "Codex",
            snapshot: CostUsageTokenSnapshot(
                sessionTokens: 40,
                sessionCostUSD: 3,
                last30DaysTokens: 40,
                last30DaysCostUSD: 3,
                historyDays: 7,
                costProvenance: .listPriceEstimate,
                daily: [Self.entry(day: "2026-07-16", cost: 3, tokens: 40)],
                sessions: [
                    CostUsageSessionBreakdown(
                        sessionID: "native-1",
                        lastActivity: secondHour,
                        inputTokens: 30,
                        cachedInputTokens: nil,
                        outputTokens: 10,
                        totalTokens: 40,
                        requestCount: 1,
                        costUSD: 3,
                        modelBreakdowns: []),
                ],
                updatedAt: now))
        let combined = SpendDashboardModel.build(
            inputs: [openCodex, native],
            requestedDays: 7,
            now: now,
            calendar: calendar)
        #expect(combined.groups[0].hourlyPoints.map(\.hour) == [firstHour, secondHour])
        #expect(combined.groups[0].hourlyPoints.map(\.cost) == [1.2, 0.8])
        #expect(Set(combined.groups[0].hourlyPoints.map(\.sourceID)) == [SpendDashboardModel.openCodexSourceID])

        let selected = SpendDashboardModel.build(
            inputs: [openCodex],
            requestedDays: 7,
            now: now,
            calendar: calendar,
            selectedDay: calendar.startOfDay(for: now))
        #expect(selected.groups[0].hourlyPoints.count == 2)
        #expect(selected.groups[0].hourlyChartDomain?.lowerBound == calendar.startOfDay(for: now))
        #expect(combined.groups[0].timeZone == calendar.timeZone)
    }
}
