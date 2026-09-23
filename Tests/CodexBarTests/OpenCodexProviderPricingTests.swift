import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct OpenCodexProviderPricingTests {
    private static let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test
    func `same model uses the recorded provider across every breakdown`() {
        let catalog = Self.catalog()
        let direct = Self.snapshot(Self.entry(provider: "openai", model: "gpt-5.4"), catalog: catalog)
        let router = Self.snapshot(
            Self.entry(provider: "openrouter", model: "openai/gpt-5.4"), catalog: catalog)

        #expect(abs((direct.last30DaysCostUSD ?? 0) - 0.000244) < 1e-10)
        #expect(abs((router.last30DaysCostUSD ?? 0) - 0.00142) < 1e-10)
        #expect(router.daily.first?.costUSD == router.last30DaysCostUSD)
        #expect(router.daily.first?.modelBreakdowns?.first?.costUSD == router.last30DaysCostUSD)
        #expect(router.sessions.first?.costUSD == router.last30DaysCostUSD)
        #expect(router.hourly.first?.costUSD == router.last30DaysCostUSD)
        #expect(router.costProvenance == .listPriceEstimate)
    }

    @Test
    func `legacy OpenAI model route still selects the routed provider`() {
        let catalog = Self.catalog()
        let direct = Self.snapshot(Self.entry(provider: "opencode-go", model: "gpt-5.4"), catalog: catalog)
        let legacy = Self.snapshot(
            Self.entry(provider: "openai", model: "opencode-go/gpt-5.4"), catalog: catalog)
        #expect(abs((direct.last30DaysCostUSD ?? 0) - 0.00284) < 1e-10)
        #expect(direct.last30DaysCostUSD == legacy.last30DaysCostUSD)
    }

    @Test
    func `unknown provider cannot borrow model namespace prices`() {
        let entry = Self.entry(provider: "private-router", model: "openai/gpt-5.4")
        let snapshot = Self.snapshot(entry, catalog: Self.catalog())
        #expect(snapshot.last30DaysCostUSD == nil)
        #expect(snapshot.sessionCostUSD == nil)
        #expect(snapshot.daily.first?.unpricedRequestCount == 1)
        #expect(OpenCodexUsageFanOut.snapshotsBySubscription(
            entries: [entry], now: Self.now, historyDays: 7, calendar: Self.calendar).isEmpty)
    }

    @Test
    func `provider lookup does not strip another provider namespace`() {
        let catalog = Self.catalog(openRouterModel: "gpt-5.4")
        let entry = Self.entry(provider: "openrouter", model: "openai/gpt-5.4")
        #expect(Self.snapshot(entry, catalog: catalog).last30DaysCostUSD == nil)
        #expect(ModelsDevPricingTargetResolver.targets(
            providerID: "openrouter", modelID: "openai/gpt-5.4").first?.modelID == "openai/gpt-5.4")
    }

    @Test
    func `missing provider keeps the legacy OpenAI fallback`() throws {
        let entry = Self.entry(provider: " ", model: "gpt-5.4")
        #expect(OpenCodexUsagePricing.providerID(for: entry) == "openai")
        let snapshot = Self.snapshot(entry, catalog: ModelsDevCatalog(providers: [:]))
        let expected = try #require(CostUsagePricing.codexCostUSD(
            model: "gpt-5.4",
            inputTokens: 100,
            cachedInputTokens: 20,
            outputTokens: 10,
            pricingDate: Self.now,
            modelsDevCatalog: ModelsDevCatalog(providers: [:]),
            customPricing: .empty))
        #expect(snapshot.last30DaysCostUSD == expected)
    }

    @Test
    func `missing input or output counts keep reported usage cost unknown`() {
        let entry = OpenCodexUsageEntry(
            requestID: "partial",
            timestamp: Self.now,
            provider: "openai",
            model: "gpt-5.4",
            usageStatus: .reported,
            usage: OpenCodexTokenUsage(totalTokens: 500))
        let snapshot = Self.snapshot(entry, catalog: Self.catalog())
        #expect(snapshot.last30DaysTokens == 500)
        #expect(snapshot.last30DaysCostUSD == nil)
        #expect(snapshot.sessionCostUSD == nil)
        #expect(snapshot.daily.first?.unpricedRequestCount == 1)
    }

    @Test
    func `malformed input count cannot become a priced zero`() throws {
        let entry = try #require(OpenCodexUsageParser.parseLine("""
        {"requestId":"malformed-input","timestamp":2000000000,"provider":"openrouter",\
        "model":"openai/gpt-5.4","usageStatus":"reported",\
        "usage":{"inputTokens":"not-a-count","outputTokens":10,"totalTokens":110}}
        """))
        #expect(entry.usage?.inputTokens == nil)
        #expect(entry.usage?.outputTokens == 10)

        let snapshot = Self.snapshot(entry, catalog: Self.catalog())
        #expect(snapshot.last30DaysTokens == 110)
        #expect(snapshot.last30DaysCostUSD == nil)
        #expect(snapshot.sessionCostUSD == nil)
        #expect(snapshot.daily.first?.unpricedRequestCount == 1)
    }

    @Test
    func `generic provider cache classes are counted once and require their rates`() {
        let entry = Self.entry(
            provider: "openrouter",
            model: "openai/gpt-5.4",
            input: 100,
            output: 10,
            cacheRead: 20,
            cacheWrite: 30,
            total: 160)
        let catalog = Self.catalog(cacheWrite: 5)
        let snapshot = Self.snapshot(entry, catalog: catalog)
        #expect(abs((snapshot.last30DaysCostUSD ?? 0) - 0.00157) < 1e-10)
        #expect(snapshot.sessions.first?.costUSD == snapshot.last30DaysCostUSD)

        let missingWriteRate = Self.snapshot(entry, catalog: Self.catalog())
        #expect(missingWriteRate.last30DaysCostUSD == nil)
        #expect(missingWriteRate.daily.first?.unpricedRequestCount == 1)
    }

    @Test
    func `cache conversion overflow is left unpriced`() {
        let entry = Self.entry(
            provider: "openrouter",
            model: "openai/gpt-5.4",
            input: Int.max,
            output: 0,
            cacheRead: 1,
            total: nil)
        let snapshot = Self.snapshot(entry, catalog: Self.catalog())
        #expect(snapshot.last30DaysCostUSD == nil)
        #expect(snapshot.sessionCostUSD == nil)
        #expect(snapshot.daily.first?.unpricedRequestCount == 1)
    }

    @Test
    func `partial caller override blocks provider pricing fallback`() {
        let entry = Self.entry(provider: "openrouter", model: "openai/gpt-5.4")
        let partial = CostUsageCustomPricing(entries: [
            "openrouter/openai/gpt-5.4": .init(input: 1),
        ], fingerprint: "partial")
        let snapshot = OpenCodexUsageAggregator.snapshot(
            entries: [entry],
            now: Self.now,
            historyDays: 7,
            calendar: Self.calendar,
            customPricing: partial,
            modelsDevCatalog: Self.catalog(),
            customPricingOverlay: .empty)
        #expect(snapshot.last30DaysCostUSD == nil)
        #expect(snapshot.daily.first?.unpricedRequestCount == 1)
    }

    @Test
    func `legacy recorded application override wins before routed provider pricing`() {
        let entry = Self.entry(provider: "openai", model: "opencode-go/gpt-5.4")
        let application = CostUsageCustomPricing(entries: [
            "openai/opencode-go/gpt-5.4": .init(input: 1, output: 2, cacheRead: 0.1),
        ], fingerprint: "legacy")
        let snapshot = OpenCodexUsageAggregator.snapshot(
            entries: [entry],
            now: Self.now,
            historyDays: 7,
            calendar: Self.calendar,
            modelsDevCatalog: Self.catalog(),
            customPricingOverlay: application)
        #expect(abs((snapshot.last30DaysCostUSD ?? 0) - 0.000102) < 1e-10)
    }

    @Test
    func `fresh exact provider miss refreshes the shared pricing cache`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = Self.catalog(openRouterModel: "gpt-5.4")
        #expect(ModelsDevCache.save(catalog: before, fetchedAt: Self.now.addingTimeInterval(-901), cacheRoot: root))
        let transport = try PricingTransport(catalog: Self.catalog())
        let entries = [Self.entry(provider: "openrouter", model: "openai/gpt-5.4")]

        await OpenCodexUsageStore.refreshPricingIfNeeded(
            entries: entries,
            now: Self.now,
            cacheRoot: root,
            client: ModelsDevClient(transport: transport))

        let refreshed = try #require(ModelsDevCache.load(now: Self.now, cacheRoot: root).artifact?.catalog)
        #expect(abs((Self.snapshot(entries[0], catalog: refreshed).last30DaysCostUSD ?? 0) - 0.00142) < 1e-10)
        #expect(await transport.calls == 1)
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func entry(
        provider: String,
        model: String,
        input: Int = 100,
        output: Int = 10,
        cacheRead: Int = 20,
        cacheWrite: Int = 0,
        total: Int? = 110) -> OpenCodexUsageEntry
    {
        OpenCodexUsageEntry(
            requestID: "request",
            timestamp: self.now,
            provider: provider,
            model: model,
            usageStatus: .reported,
            usage: OpenCodexTokenUsage(
                inputTokens: input,
                outputTokens: output,
                cachedInputTokens: cacheRead,
                cacheCreationInputTokens: cacheWrite,
                totalTokens: total))
    }

    private static func snapshot(_ entry: OpenCodexUsageEntry, catalog: ModelsDevCatalog) -> CostUsageTokenSnapshot {
        OpenCodexUsageAggregator.snapshot(
            entries: [entry],
            now: self.now,
            historyDays: 7,
            calendar: self.calendar,
            modelsDevCatalog: catalog,
            customPricingOverlay: .empty)
    }

    private static func catalog(
        openRouterModel: String = "openai/gpt-5.4",
        cacheWrite: Double? = nil) -> ModelsDevCatalog
    {
        func model(
            _ id: String,
            input: Double,
            output: Double,
            cacheRead: Double? = nil,
            cacheWrite: Double? = nil) -> ModelsDevModel
        {
            ModelsDevModel(
                id: id,
                name: nil,
                cost: ModelsDevCost(
                    input: input,
                    output: output,
                    cacheRead: cacheRead,
                    cacheWrite: cacheWrite,
                    contextOver200K: nil),
                limit: nil)
        }
        return ModelsDevCatalog(providers: [
            "openai": ModelsDevProvider(id: "openai", name: "OpenAI", models: [
                "gpt-5.4": model("gpt-5.4", input: 2, output: 8, cacheRead: 0.2),
            ]),
            "anthropic": ModelsDevProvider(id: "anthropic", name: "Anthropic", models: [
                "fixture": model("fixture", input: 1, output: 2),
            ]),
            "opencode-go": ModelsDevProvider(id: "opencode-go", name: "OpenCode Go", models: [
                "gpt-5.4": model("gpt-5.4", input: 20, output: 80, cacheRead: 2),
            ]),
            "openrouter": ModelsDevProvider(id: "openrouter", name: "OpenRouter", models: [
                openRouterModel: model(
                    openRouterModel,
                    input: 10,
                    output: 40,
                    cacheRead: 1,
                    cacheWrite: cacheWrite),
            ]),
        ])
    }
}

private actor PricingTransport: ModelsDevHTTPTransport {
    private let data: Data
    private(set) var calls = 0

    init(catalog: ModelsDevCatalog) throws {
        self.data = try JSONEncoder().encode(catalog)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.calls += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (self.data, response)
    }
}
