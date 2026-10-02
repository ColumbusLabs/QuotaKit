import Foundation
import Testing
@testable import CodexBarCore

struct AntigravityPricingAliasTests {
    private typealias Fixture = AntigravityLocalFixture

    @Test
    func `routing variants price from their base model without widening shared Claude pricing`() async throws {
        let fixture = try Fixture()
        let catalog = try JSONDecoder().decode(ModelsDevCatalog.self, from: Data(#"""
        {
            "google": {
                "id": "google",
                "name": "Google",
                "models": {
                    "gemini-fixture-a": {
                        "id": "gemini-fixture-a",
                        "cost": {"input": 1, "output": 2, "cache_read": 0.2}
                    }
                }
            }
        }
        """#.utf8))
        let cacheRoot = fixture.root.appendingPathComponent("scanner-cache")
        #expect(ModelsDevCache.save(catalog: catalog, fetchedAt: Fixture.now, cacheRoot: cacheRoot))
        try fixture.database(blobs: [Fixture.blob(model: "gemini-fixture-a-tiered")])

        let snapshot = try await fixture.snapshot()
        let expected = 100e-6 + 50 * 0.2e-6 + 37 * 2e-6
        #expect(abs((snapshot.last30DaysCostUSD ?? .nan) - expected) < 1e-12)
        // The recorded variant keeps its own identity in the breakdown; only pricing falls back.
        #expect(snapshot.daily.first?.modelBreakdowns?.first?.modelName == "gemini-fixture-a-tiered")

        #expect(AntigravityLocalReader.pricingBaseModelID(for: "gemini-3.8-flash-tiered")
            == "gemini-3.8-flash")
        #expect(AntigravityLocalReader.pricingBaseModelID(for: "claude-opus-4-6-thinking")
            == "claude-opus-4-6")
        #expect(AntigravityLocalReader.pricingBaseModelID(for: "gemini-3.8-flash") == nil)
        #expect(AntigravityLocalReader.pricingBaseModelID(for: "-low") == nil)

        let claudeTargets = CostUsagePricing.claudeModelsDevPricingTargets(for: "claude-fixture-9-thinking")
        #expect(claudeTargets.isEmpty == false)
        #expect(claudeTargets.contains { $0.modelID == "claude-fixture-9" } == false)
    }

    @Test
    func `Gemini product aliases use exact model pricing before preview fallback`() throws {
        let fixture = try Fixture()
        let catalog = try JSONDecoder().decode(ModelsDevCatalog.self, from: Data(#"""
        {
            "google": {
                "id": "google",
                "models": {
                    "gemini-pro-default": {
                        "id": "gemini-pro-default",
                        "cost": {"input": 5, "output": 7, "cache_read": 0.5}
                    },
                    "gemini-3.1-pro-preview": {
                        "id": "gemini-3.1-pro-preview",
                        "cost": {"input": 2, "output": 8, "cache_read": 0.2}
                    }
                }
            }
        }
        """#.utf8))
        let cacheRoot = fixture.root.appendingPathComponent("pricing")
        #expect(ModelsDevCache.save(catalog: catalog, fetchedAt: Fixture.now, cacheRoot: cacheRoot))
        try fixture.database(blobs: [
            Fixture.blob(model: "gemini-pro-default"),
            Fixture.blob(model: "gemini-pro-agent"),
            Fixture.blob(model: "gemini-3.1-pro"),
            Fixture.blob(model: "gemini-3.1-pro-high"),
            Fixture.blob(model: "gemini-3.1-pro-low"),
        ])

        let result = try AntigravityLocalReader.makeDailyReportWithStatus(
            context: fixture.context,
            calendar: Fixture.calendar,
            estimateCost: true,
            pricingCacheRoot: cacheRoot)
        let exactCost = 100 * 5e-6 + 50 * 0.5e-6 + 37 * 7e-6
        let previewCost = 100 * 2e-6 + 50 * 0.2e-6 + 37 * 8e-6
        let actualCost = try #require(result.report.data.first?.costUSD)

        #expect(result.coverage == .complete)
        #expect(abs(actualCost - (exactCost + 4 * previewCost)) < 1e-12)
        #expect(result.report.data.first?.unpricedRequestCount == 0)
        #expect(result.report.data.first?.estimatedRequestCount == 5)
        #expect(Set(result.report.data.first?.modelBreakdowns?.map(\.modelName) ?? []) == Set([
            "gemini-pro-default",
            "gemini-pro-agent",
            "gemini-3.1-pro",
            "gemini-3.1-pro-high",
            "gemini-3.1-pro-low",
        ]))
        #expect(AntigravityLocalReader.pricingBaseModelID(for: "gemini-pro-default")
            == "gemini-3.1-pro-preview")
        #expect(AntigravityLocalReader.pricingBaseModelID(for: "gemini-pro-agent")
            == "gemini-3.1-pro-preview")
        #expect(AntigravityLocalReader.pricingBaseModelID(for: "gemini-3.1-pro-high")
            == "gemini-3.1-pro-preview")
        #expect(AntigravityLocalReader.pricingBaseModelID(for: "gemini-3.1-pro-low")
            == "gemini-3.1-pro-preview")
    }
}
