// swiftlint:disable multiline_arguments
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore
@testable import CodexBarSync

/// Unit tests for the five static mappers added to `SyncCoordinator`
/// in Phase B of the v0.26.1 fold-in. Each mapper extracts a typed
/// envelope payload from the upstream `UsageSnapshot` only when the
/// snapshot's providerID matches AND the relevant upstream data is
/// present. The mapper returning nil for the wrong providerID is
/// load-bearing — the iOS dispatch (`Views/ProviderDetailView.swift`)
/// would otherwise show, e.g., a Bedrock cost card on a Claude page.
///
/// SyncCoordinator is `@MainActor`-isolated, so this entire suite
/// runs on the main actor too.
@MainActor
@Suite("SyncCoordinator v0.26 mappers")
struct SyncCoordinatorV026MapperTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private static func makeIdentity(
        provider: UsageProvider,
        loginMethod: String? = nil) -> ProviderIdentitySnapshot
    {
        ProviderIdentitySnapshot(
            providerID: provider,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: loginMethod)
    }

    // MARK: - mapOpenAIAPIDashboard

    @Test("OpenAI dashboard mapper: returns nil when provider != .openai")
    func openAIDashboardWrongProviderReturnsNil() {
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            openAIAPIUsage: OpenAIAPIUsageSnapshot(daily: [], updatedAt: Self.now),
            updatedAt: Self.now)
        let result = SyncCoordinator.mapOpenAIAPIDashboard(
            provider: .claude, snapshot: snapshot)
        #expect(result == nil)
    }

    @Test("OpenAI dashboard mapper: returns nil when openAIAPIUsage is missing")
    func openAIDashboardMissingUsageReturnsNil() {
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, updatedAt: Self.now)
        let result = SyncCoordinator.mapOpenAIAPIDashboard(
            provider: .openai, snapshot: snapshot)
        #expect(result == nil)
    }

    @Test("OpenAI dashboard mapper: maps daily buckets + summaries faithfully")
    func openAIDashboardMapsDailyBuckets() {
        let bucket = OpenAIAPIUsageSnapshot.DailyBucket(
            day: "2026-05-15",
            startTime: Self.now,
            endTime: Self.now.addingTimeInterval(86400),
            costUSD: 4.20,
            requests: 41,
            inputTokens: 12000,
            cachedInputTokens: 1500,
            outputTokens: 1500,
            totalTokens: 15000,
            lineItems: [.init(name: "Completions", costUSD: 3.10)],
            models: [.init(
                name: "gpt-5",
                requests: 30,
                inputTokens: 8000,
                cachedInputTokens: 1000,
                outputTokens: 1200,
                totalTokens: 10200)])
        let upstream = OpenAIAPIUsageSnapshot(daily: [bucket], updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil,
            openAIAPIUsage: upstream,
            updatedAt: Self.now)
        let result = SyncCoordinator.mapOpenAIAPIDashboard(
            provider: .openai, snapshot: snapshot)
        #expect(result?.dailyBuckets.count == 1)
        #expect(result?.dailyBuckets.first?.dayKey == "2026-05-15")
        #expect(result?.dailyBuckets.first?.costUSD == 4.20)
        #expect(result?.dailyBuckets.first?.totalTokens == 15000)
        #expect(result?.latestDay?.totalCostUSD == 4.20)
        #expect(result?.last30Days.totalCostUSD == 4.20)
    }

    @Test("OpenAI dashboard mapper: returns latestDay=nil when daily buckets are empty")
    func openAIDashboardEmptyBucketsLatestDayNil() {
        let upstream = OpenAIAPIUsageSnapshot(daily: [], updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil,
            openAIAPIUsage: upstream,
            updatedAt: Self.now)
        let result = SyncCoordinator.mapOpenAIAPIDashboard(
            provider: .openai, snapshot: snapshot)
        #expect(result?.latestDay == nil)
        #expect(result?.dailyBuckets.isEmpty == true)
    }

    @Test("OpenAI dashboard mapper: caps top models / line items at 8 entries")
    func openAIDashboardTopListsBounded() {
        let manyModels = (0..<10).map { i in
            OpenAIAPIUsageSnapshot.ModelBreakdown(
                name: "m-\(i)", requests: 100 - i, inputTokens: 0, cachedInputTokens: 0, outputTokens: 0,
                totalTokens: i * 100)
        }
        let bucket = OpenAIAPIUsageSnapshot.DailyBucket(
            day: "2026-05-15",
            startTime: Self.now,
            endTime: Self.now.addingTimeInterval(86400),
            costUSD: 1, requests: 1, inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, totalTokens: 1,
            lineItems: (0..<10).map { i in
                .init(name: "li-\(i)", costUSD: Double(10 - i))
            },
            models: manyModels)
        let upstream = OpenAIAPIUsageSnapshot(daily: [bucket], updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil,
            openAIAPIUsage: upstream,
            updatedAt: Self.now)
        let result = SyncCoordinator.mapOpenAIAPIDashboard(
            provider: .openai, snapshot: snapshot)
        #expect((result?.topModels.count ?? 0) <= 8)
        #expect((result?.topLineItems.count ?? 0) <= 8)
    }

    // MARK: - mapZaiHourlyUsage

    private static func makeZaiSnapshot(modelUsage: ZaiModelUsageData?) -> UsageSnapshot {
        let zai = ZaiUsageSnapshot(
            tokenLimit: nil,
            timeLimit: nil,
            planName: nil,
            modelUsage: modelUsage,
            updatedAt: Self.now)
        return UsageSnapshot(
            primary: nil, secondary: nil,
            zaiUsage: zai,
            updatedAt: Self.now)
    }

    @Test("z.ai mapper: returns nil when provider != .zai")
    func zaiWrongProviderReturnsNil() {
        let snapshot = Self.makeZaiSnapshot(modelUsage: nil)
        let result = SyncCoordinator.mapZaiHourlyUsage(
            provider: .claude, snapshot: snapshot)
        #expect(result == nil)
    }

    @Test("z.ai mapper: returns nil when modelUsage is missing")
    func zaiNoModelUsageReturnsNil() {
        let snapshot = Self.makeZaiSnapshot(modelUsage: nil)
        let result = SyncCoordinator.mapZaiHourlyUsage(
            provider: .zai, snapshot: snapshot)
        #expect(result == nil)
    }

    @Test("z.ai mapper: parses ISO8601 timestamps with fractional seconds")
    func zaiHourlyParsesISO8601() {
        let modelUsage = ZaiModelUsageData(
            xTime: ["2026-05-15T00:00:00.000Z", "2026-05-15T01:00:00.000Z"],
            modelDataList: [
                ZaiModelDataItem(modelName: "glm-4.6", tokensUsage: [1000, 2500]),
            ])
        let snapshot = Self.makeZaiSnapshot(modelUsage: modelUsage)
        let result = SyncCoordinator.mapZaiHourlyUsage(
            provider: .zai, snapshot: snapshot)
        #expect(result?.xTime.count == 2)
        #expect(result?.modelSeries.count == 1)
        #expect(result?.modelSeries.first?.modelName == "glm-4.6")
    }

    @Test("z.ai mapper: drops rows where the upstream model name is nil")
    func zaiHourlyDropsNilModelNames() {
        let modelUsage = ZaiModelUsageData(
            xTime: ["2026-05-15T00:00:00Z"],
            modelDataList: [
                ZaiModelDataItem(modelName: nil, tokensUsage: [42]),
                ZaiModelDataItem(modelName: "glm-4.6", tokensUsage: [1000]),
            ])
        let snapshot = Self.makeZaiSnapshot(modelUsage: modelUsage)
        let result = SyncCoordinator.mapZaiHourlyUsage(
            provider: .zai, snapshot: snapshot)
        #expect(result?.modelSeries.count == 1)
        #expect(result?.modelSeries.first?.modelName == "glm-4.6")
    }

    // MARK: - mapKiroCredits

    private static func makeKiroDetails(
        plan: String = "pro",
        displayPlan: String = "Pro",
        used: Double = 250,
        total: Double = 1000,
        bonusUsed: Double? = nil,
        bonusTotal: Double? = nil,
        bonusExpiryDays: Int? = nil) -> KiroUsageDetails
    {
        KiroUsageDetails(
            planName: plan,
            displayPlanName: displayPlan,
            creditsUsed: used,
            creditsTotal: total,
            creditsRemaining: max(total - used, 0),
            bonusCreditsUsed: bonusUsed,
            bonusCreditsTotal: bonusTotal,
            bonusCreditsRemaining: (bonusTotal ?? 0) - (bonusUsed ?? 0),
            bonusExpiryDays: bonusExpiryDays,
            overagesStatus: nil,
            overageCreditsUsed: nil,
            estimatedOverageCostUSD: nil,
            manageURL: nil,
            contextUsage: nil)
    }

    @Test("Kiro mapper: returns nil when provider != .kiro")
    func kiroWrongProviderReturnsNil() {
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil,
            kiroUsage: Self.makeKiroDetails(),
            updatedAt: Self.now)
        let result = SyncCoordinator.mapKiroCredits(
            provider: .claude, snapshot: snapshot)
        #expect(result == nil)
    }

    @Test("Kiro mapper: derives credits percent when total is positive")
    func kiroMapperDerivesPercent() {
        let kiro = Self.makeKiroDetails(
            used: 250, total: 1000,
            bonusUsed: 20, bonusTotal: 100, bonusExpiryDays: 14)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil,
            kiroUsage: kiro,
            updatedAt: Self.now)
        let result = SyncCoordinator.mapKiroCredits(
            provider: .kiro, snapshot: snapshot)
        #expect(result?.planName == "Pro")
        #expect(result?.creditsPercent == 25.0)
        #expect(result?.creditsTotal == 1000)
        #expect(result?.bonusTotal == 100)
        #expect(result?.bonusExpiryDays == 14)
    }

    @Test("Kiro mapper: omits creditsTotal + percent when upstream total is 0")
    func kiroMapperZeroTotal() {
        let kiro = Self.makeKiroDetails(used: 0, total: 0)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil,
            kiroUsage: kiro,
            updatedAt: Self.now)
        let result = SyncCoordinator.mapKiroCredits(
            provider: .kiro, snapshot: snapshot)
        #expect(result?.creditsTotal == nil)
        #expect(result?.creditsPercent == nil)
    }

    // MARK: - mapBedrockCost

    @Test("Bedrock mapper: returns nil when provider != .bedrock")
    func bedrockWrongProviderReturnsNil() {
        let pc = ProviderCostSnapshot(used: 10, limit: 50, currencyCode: "USD", period: "Monthly", updatedAt: Self.now)
        let result = SyncCoordinator.mapBedrockCost(
            provider: .claude, snapshot: nil, providerCost: pc, region: "us-east-1")
        #expect(result == nil)
    }

    @Test("Bedrock mapper: returns nil when providerCost is nil")
    func bedrockMissingCostReturnsNil() {
        let result = SyncCoordinator.mapBedrockCost(
            provider: .bedrock, snapshot: nil, providerCost: nil, region: nil)
        #expect(result == nil)
    }

    @Test("Bedrock mapper: derives budget percent and uses supplied region")
    func bedrockMapperComputesPercent() {
        let pc = ProviderCostSnapshot(
            used: 19.10,
            limit: 50,
            currencyCode: "USD",
            period: "Monthly",
            updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil,
            updatedAt: Self.now,
            identity: Self.makeIdentity(provider: .bedrock, loginMethod: "Spend: $19.10 - Budget: $50.00"))
        let result = SyncCoordinator.mapBedrockCost(
            provider: .bedrock, snapshot: snapshot, providerCost: pc, region: "us-east-1")
        #expect(result?.monthlySpendUSD == 19.10)
        #expect(result?.monthlyBudgetUSD == 50)
        // Region comes from the caller (SettingsStore.bedrockRegion),
        // NOT from the composite loginMethod display string.
        #expect(result?.region == "us-east-1")
        #expect((result?.budgetUsedPercent ?? 0) > 38.0)
        #expect((result?.budgetUsedPercent ?? 0) < 39.0)
    }

    @Test("Bedrock mapper: region is nil when caller passes nil (no SettingsStore value)")
    func bedrockMapperNoRegion() {
        let pc = ProviderCostSnapshot(used: 1, limit: 50, currencyCode: "USD", period: "Monthly", updatedAt: Self.now)
        let result = SyncCoordinator.mapBedrockCost(
            provider: .bedrock, snapshot: nil, providerCost: pc, region: nil)
        #expect(result?.region == nil)
    }

    @Test("Bedrock mapper: drops budget + percent when upstream limit is 0")
    func bedrockMapperZeroLimit() {
        let pc = ProviderCostSnapshot(used: 5, limit: 0, currencyCode: "USD", period: "Monthly", updatedAt: Self.now)
        let result = SyncCoordinator.mapBedrockCost(
            provider: .bedrock, snapshot: nil, providerCost: pc, region: "ap-southeast-2")
        #expect(result?.monthlyBudgetUSD == nil)
        #expect(result?.budgetUsedPercent == nil)
        #expect(result?.region == "ap-southeast-2")
    }

    @Test("Bedrock mapper: clamps percent to 100 when spend exceeds budget")
    func bedrockMapperOverBudgetClamps() {
        let pc = ProviderCostSnapshot(used: 200, limit: 50, currencyCode: "USD", period: "Monthly", updatedAt: Self.now)
        let result = SyncCoordinator.mapBedrockCost(
            provider: .bedrock, snapshot: nil, providerCost: pc, region: nil)
        #expect(result?.budgetUsedPercent == 100)
    }

    // MARK: - mapMoonshotBalance

    @Test("Moonshot mapper: returns nil when provider != .moonshot")
    func moonshotWrongProviderReturnsNil() {
        let snapshot = UsageSnapshot(primary: nil, secondary: nil, updatedAt: Self.now)
        let result = SyncCoordinator.mapMoonshotBalance(
            provider: .claude, snapshot: snapshot, primaryWindow: nil)
        #expect(result == nil)
    }

    @Test("Moonshot mapper: parses balance from upstream loginMethod string")
    func moonshotMapperParsesLoginMethod() {
        // Simulates the production output of
        // `MoonshotUsageSummary.toUsageSnapshot()`:
        // loginMethod = "Balance: $58.40"
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil,
            updatedAt: Self.now,
            identity: Self.makeIdentity(provider: .moonshot, loginMethod: "Balance: $58.40"))
        let result = SyncCoordinator.mapMoonshotBalance(
            provider: .moonshot, snapshot: snapshot, primaryWindow: nil)
        #expect(result?.balanceAmount == 58.40)
        #expect(result?.balanceCurrency == "USD")
        #expect(result?.region == nil)
    }

    @Test("Moonshot mapper: parses balance when loginMethod also reports a deficit")
    func moonshotMapperParsesLoginMethodWithDeficit() {
        // Production deficit format:
        // loginMethod = "Balance: $58.40 · $5.00 in deficit"
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil,
            updatedAt: Self.now,
            identity: Self.makeIdentity(provider: .moonshot, loginMethod: "Balance: $58.40 · $5.00 in deficit"))
        let result = SyncCoordinator.mapMoonshotBalance(
            provider: .moonshot, snapshot: snapshot, primaryWindow: nil)
        #expect(result?.balanceAmount == 58.40)
    }

    @Test("Moonshot mapper: falls back to providerCost.used when loginMethod is empty")
    func moonshotMapperFromProviderCost() {
        // Future-proofing: if upstream switches Moonshot to publish
        // the balance via providerCost, the fallback path still works.
        let pc = ProviderCostSnapshot(used: 58.40, limit: 0, currencyCode: "CNY", period: nil, updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil,
            providerCost: pc,
            updatedAt: Self.now)
        let result = SyncCoordinator.mapMoonshotBalance(
            provider: .moonshot, snapshot: snapshot, primaryWindow: nil)
        #expect(result?.balanceAmount == 58.40)
        #expect(result?.balanceCurrency == "CNY")
    }

    @Test("Moonshot mapper: returns nil when no signal in any lane")
    func moonshotMapperNoSignal() {
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil,
            updatedAt: Self.now,
            identity: Self.makeIdentity(provider: .moonshot, loginMethod: ""))
        let result = SyncCoordinator.mapMoonshotBalance(
            provider: .moonshot, snapshot: snapshot, primaryWindow: nil)
        #expect(result == nil)
    }

    // MARK: - parseMoonshotBalance (parser)

    @Test("parseMoonshotBalance: handles USD $ prefix")
    func parseMoonshotUSD() {
        let parsed = SyncCoordinator.parseMoonshotBalance(from: "Balance: $58.40")
        #expect(parsed?.amount == 58.40)
        #expect(parsed?.currency == "USD")
    }

    @Test("parseMoonshotBalance: handles CNY ¥ prefix")
    func parseMoonshotCNY() {
        let parsed = SyncCoordinator.parseMoonshotBalance(from: "Balance: ¥412.30 · ¥5 in deficit")
        #expect(parsed?.amount == 412.30)
        #expect(parsed?.currency == "CNY")
    }

    @Test("parseMoonshotBalance: returns nil for malformed input")
    func parseMoonshotMalformed() {
        #expect(SyncCoordinator.parseMoonshotBalance(from: "") == nil)
        #expect(SyncCoordinator.parseMoonshotBalance(from: "Account: $58.40") == nil)
        #expect(SyncCoordinator.parseMoonshotBalance(from: "Balance: abc") == nil)
    }

    @Test("parseMoonshotBalance: handles integer-only amount")
    func parseMoonshotInteger() {
        let parsed = SyncCoordinator.parseMoonshotBalance(from: "Balance: $100")
        #expect(parsed?.amount == 100.0)
    }
}

// swiftlint:enable multiline_arguments
