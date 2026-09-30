import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct MenuBarLayoutProviderBalanceTests {
    private let now = Date(timeIntervalSince1970: 1_752_768_000)

    @Test(arguments: [UsageProvider.mimo, .hyper, .atlascloud, .vercel, .devpass])
    func `stored balance and automatic tokens resolve provider amounts`(provider: UsageProvider) throws {
        let (snapshot, expected) = try self.fixture(provider: provider)
        let data = self.data(provider: provider, snapshot: snapshot)
        let layout = try JSONDecoder().decode(MenuBarLayout.self, from: Data(
            #"{"lines":[[{"balance":{}}],[{"percent":{"window":"automatic"}}]]}"#.utf8))
        #expect(data.balance == expected)
        #expect(data.automaticText == expected)
        let output = self.render(layout: layout, data: data)
        #expect(output.attributedTitle.string == "\(expected)\n\(expected)")
    }

    @Test(arguments: [UsageProvider.mimo, .devpass, .opencodego])
    func `explicit balance coexists with real quota percentages`(provider: UsageProvider) throws {
        let snapshot: UsageSnapshot
        let expected: String
        if provider == .mimo {
            snapshot = MiMoUsageSnapshot(
                balance: 4.84,
                currency: "USD",
                planCode: "standard",
                tokenUsed: 25,
                tokenLimit: 100,
                tokenPercent: 0.25,
                updatedAt: self.now).toUsageSnapshot()
            expected = "$4.84"
        } else {
            snapshot = try UsageSnapshot(
                primary: RateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                providerCost: provider == .opencodego
                    ? ProviderCostSnapshot(
                        used: 25,
                        limit: 0,
                        currencyCode: "USD",
                        period: "Zen balance",
                        updatedAt: self.now) : nil,
                details: [ProviderDetailSection(title: "DevPass credits", rows: [
                    .init(label: "Cycle remaining", value: "$25.00"),
                ])],
                updatedAt: self.now)
            expected = "$25.00"
        }
        let data = self.data(provider: provider, snapshot: snapshot)
        #expect(data.balance == expected)
        #expect(data.automaticText == nil)
        #expect(self.render(layout: MenuBarLayout(lines: [[.percent(window: .automatic)]]), data: data)
            .attributedTitle.string == "25%")
    }

    @Test(arguments: [UsageProvider.mimo, .hyper, .atlascloud, .vercel, .devpass, .doubao])
    func `absent balances never borrow unrelated spend`(provider: UsageProvider) throws {
        let snapshot = try UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [ProviderDetailSection(title: "API key (all time)", rows: [
                .init(label: "All-time key usage", value: "$31.42"),
            ])],
            updatedAt: self.now)
        #expect(MenuBarLayoutBalanceResolver.balance(provider: provider, snapshot: nil) == nil)
        #expect(MenuBarLayoutBalanceResolver.balance(provider: provider, snapshot: snapshot) == nil)
    }

    @Test(arguments: ["$0.00", "-$4.25"])
    func `zero and negative balances remain visible`(amount: String) throws {
        let snapshot = try UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [ProviderDetailSection(title: "Account balance", rows: [
                .init(label: "Available balance", value: amount),
            ])],
            updatedAt: self.now)
        #expect(MenuBarLayoutBalanceResolver.balance(provider: .atlascloud, snapshot: snapshot) == amount)
    }

    @Test(arguments: [0.0, 0.6, 42.5])
    func `Codex balance tokens retain reported fractional credits`(amount: Double) {
        let credits = CreditsSnapshot(remaining: amount, events: [], updatedAt: self.now)
        #expect(MenuBarLayoutBalanceResolver.balance(provider: .codex, snapshot: nil, codexCredits: credits)
            == UsageFormatter.creditsNumberString(from: amount))
        let unread = CreditsSnapshot(
            remaining: amount, events: [], updatedAt: self.now, balanceReadSucceeded: false)
        #expect(MenuBarLayoutBalanceResolver.balance(provider: .codex, snapshot: nil, codexCredits: unread) == nil)
    }

    private func fixture(provider: UsageProvider) throws -> (UsageSnapshot, String) {
        if provider == .mimo {
            return (MiMoUsageSnapshot(
                balance: 4.84,
                currency: "USD",
                cashBalance: 4.84,
                giftBalance: 0,
                updatedAt: self.now).toUsageSnapshot(), "$4.84")
        }
        let label = provider == .devpass ? "Cycle remaining" : provider == .hyper ? "Balance" : "Available balance"
        let value = provider == .hyper ? "42.5 HC" : "$25.00"
        return try (UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [ProviderDetailSection(title: "Synthetic credits", rows: [.init(label: label, value: value)])],
            updatedAt: self.now), value)
    }

    private func data(provider: UsageProvider, snapshot: UsageSnapshot) -> MenuBarLayoutRenderData {
        let automatic = MenuBarLayoutRenderWindow(MenuBarMetricWindowResolver.rateWindow(
            preference: .automatic,
            provider: provider,
            snapshot: snapshot,
            supportsAverage: false,
            now: self.now))
        return MenuBarLayoutRenderData(
            iconKey: provider.rawValue,
            providerName: provider.rawValue,
            accountLabel: nil,
            laneLabels: MenuBarLayoutLaneLabels(provider: provider, snapshot: snapshot),
            primary: MenuBarLayoutRenderWindow(snapshot.primary),
            secondary: nil,
            tertiary: nil,
            provider: provider,
            session: nil,
            weekly: nil,
            scopedWeekly: nil,
            scopedWeeklyTitle: nil,
            automatic: automatic,
            automaticText: StatusItemController.menuBarLayoutAutomaticText(
                provider: provider, snapshot: snapshot, automatic: automatic),
            sessionPace: nil,
            weeklyPace: nil,
            automaticPace: nil,
            runsOut: nil,
            balance: MenuBarLayoutBalanceResolver.balance(provider: provider, snapshot: snapshot),
            costToday: nil,
            cost30d: nil,
            metrics: .unavailable)
    }

    private func render(layout: MenuBarLayout, data: MenuBarLayoutRenderData) -> MenuBarLayoutRenderedTitle {
        MenuBarLayoutRenderer().render(layout: layout, data: data, icon: nil, options: MenuBarLayoutRenderOptions(
            size: .regular,
            highContrast: false,
            showUsed: true,
            conditionals: [],
            appearanceName: "aqua",
            isDebugApp: false,
            now: self.now))
    }
}
