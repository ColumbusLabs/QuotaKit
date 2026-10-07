import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct MenuBarLayoutProviderBalanceTests {
    private let now = Date(timeIntervalSince1970: 1_752_768_000)

    @Test(arguments: ["$2.57", "$0.00", "-$1.25", "Less than $0.01"])
    func `LithosAI prepaid balance reaches automatic and explicit layout tokens`(amount: String) throws {
        let snapshot = try UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [ProviderDetailSection(title: "Billing", rows: [.init(label: "Balance", value: amount)])],
            updatedAt: self.now,
            identity: ProviderIdentitySnapshot(
                providerID: .lithosai,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: "Browser session"))
        let data = self.data(provider: .lithosai, snapshot: snapshot)
        #expect(data.balance == amount)
        #expect(data.automaticText == amount)
        for token: MenuBarLayoutToken in [.balance, .percent(window: .automatic)] {
            #expect(self.render(layout: MenuBarLayout(lines: [[token]]), data: data).attributedTitle.string == amount)
        }
        #expect(MenuBarLayoutBalanceResolver.balance(provider: .claude, snapshot: snapshot) == nil)
        #expect(MenuBarLayoutBalanceResolver.balance(provider: .poe, snapshot: snapshot) == nil)
    }

    @Test(arguments: [UsageProvider.mimo, .hyper, .atlascloud, .vercel, .devpass, .lithosai])
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

    @Test(arguments: [UsageProvider.mimo, .hyper, .atlascloud, .vercel, .devpass, .doubao, .lithosai, .nous, .openrouter])
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

    @Test
    func `provider descriptors select the intended balance detail labels`() throws {
        let cases: [(UsageProvider, String, String)] = [
            (.openrouter, "Remaining", "$1.25"),
            (.atlascloud, "Available balance", "$2.50"),
            (.devpass, "Cycle remaining", "$3.75"),
            (.vercel, "Available balance", "$5.00"),
            (.nous, "Total usable", "900 credits"),
        ]
        for (provider, label, value) in cases {
            let snapshot = try UsageSnapshot(
                primary: nil,
                secondary: nil,
                details: [ProviderDetailSection(title: "Credits", rows: [.init(label: label, value: value)])],
                updatedAt: self.now)
            #expect(MenuBarLayoutBalanceResolver.balance(provider: provider, snapshot: snapshot) == value)
        }

        let nousTopUp = try UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [ProviderDetailSection(title: "Credits", rows: [.init(label: "Top-up credits", value: "80")])],
            updatedAt: self.now)
        #expect(MenuBarLayoutBalanceResolver.balance(provider: .nous, snapshot: nousTopUp) == "80")
    }

    @Test
    func `descriptor balance details reject snapshots from another provider`() throws {
        let snapshot = try UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [ProviderDetailSection(title: "Credits", rows: [
                .init(label: "Available balance", value: "$2.50"),
            ])],
            updatedAt: self.now,
            identity: ProviderIdentitySnapshot(
                providerID: UsageProvider.vercel.instanceID,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: nil))
        #expect(MenuBarLayoutBalanceResolver.balance(provider: .vercel, snapshot: snapshot) == "$2.50")
        #expect(MenuBarLayoutBalanceResolver.balance(provider: .atlascloud, snapshot: snapshot) == nil)
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
        let label = provider == .devpass ? "Cycle remaining"
            : [.hyper, .lithosai].contains(provider) ? "Balance" : "Available balance"
        let value = provider == .hyper ? "42.5 HC" : provider == .lithosai ? "$2.57" : "$25.00"
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
