import Foundation
import Testing
@testable import CodexBarCore

struct ZaiProviderRecoveryTests {
    @Test(arguments: BundledPluginTestSupport.engines)
    func `unknown quota types stay unavailable while recognized limits remain visible`(
        engine: ProviderPluginEngineKind) async throws
    {
        let withOnlyUnknown = #"""
        {"code":200,"success":true,"data":{"limits":[
          {"type":"FUTURE_POINTS_POOL","pointsRemaining":800}
        ]}}
        """#
        let unavailable = try await Self.pluginSnapshot(quotaFixture: withOnlyUnknown, engine: engine)
        #expect(unavailable.primary == nil)
        #expect(unavailable.detailRow(label: "Coding Plan usage")?.value == "Unavailable")

        let withRecognizedAndUnknown = #"""
        {"code":200,"success":true,"data":{"limits":[
          {"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":25},
          {"type":"FUTURE_POINTS_POOL","pointsRemaining":800}
        ]}}
        """#
        let recognized = try await Self.pluginSnapshot(quotaFixture: withRecognizedAndUnknown, engine: engine)
        #expect(recognized.primary?.usedPercent == 25)
        #expect(recognized.detailRow(label: "Coding Plan usage") == nil)
        #expect(recognized.detailRow(label: "Additional quota")?.value == "Unavailable")

        let withMCPAndUnknown = #"""
        {"code":200,"success":true,"data":{"limits":[
          {"type":"FUTURE_POINTS_POOL","pointsRemaining":800},
          {"type":"TIME_LIMIT","unit":5,"number":1,"percentage":25}
        ]}}
        """#
        let mcp = try await Self.pluginSnapshot(quotaFixture: withMCPAndUnknown, engine: engine)
        #expect(mcp.primary?.resetDescription == "MCP")
        #expect(mcp.primary?.usedPercent == 25)
        #expect(mcp.detailRow(label: "Coding Plan usage")?.value == "Unavailable")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `unsupported quota envelopes direct users to the usage dashboard`(engine: ProviderPluginEngineKind) async {
        let unsupported = #"{"code":200,"success":true,"data":{"pointsPool":{"remaining":800}}}"#
        do {
            _ = try await Self.pluginSnapshot(quotaFixture: unsupported, engine: engine)
            Issue.record("An unsupported quota envelope must not invent usage")
        } catch {
            #expect(error.localizedDescription.contains("Usage Dashboard"))
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `invalid optional model analytics do not discard required quota`(
        engine: ProviderPluginEngineKind) async throws
    {
        for (count, name, label) in [
            (121, "Example", "hour"),
            (1, String(repeating: "x", count: 121), "hour"),
            (1, "Example", String(repeating: "x", count: 121)),
            (1, "  ", "hour"),
            (1, "Example", "  "),
            (1, "\u{0085}\u{200B}", "hour"),
            (1, "Example", "\u{0085}\u{200B}"),
        ] {
            let analytics: [String: Any] = [
                "code": 200, "success": true,
                "data": [
                    "x_time": Array(repeating: label, count: count),
                    "modelDataList": [["modelName": name, "tokensUsage": Array(repeating: 1, count: count)]],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: analytics)
            let snapshot = try await Self.pluginSnapshot(
                quotaFixture: Self.quotaFixture,
                modelUsageFixture: #require(String(data: data, encoding: .utf8)),
                engine: engine)
            #expect(snapshot.primary?.usedPercent == 25)
            #expect(snapshot.secondary?.usedPercent == 9)
            #expect(snapshot.identity?.loginMethod == "Pro")
            #expect(snapshot.details.map(\.title) == ["Quota details"])
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `overflowing optional model aggregates do not discard required quota`(
        engine: ProviderPluginEngineKind) async throws
    {
        let analytics = #"""
        {"code":200,"success":true,"data":{"x_time":["hour"],"modelDataList":[
          {"modelName":"Example A","tokensUsage":[1e308]},
          {"modelName":"Example B","tokensUsage":[1e308]}
        ]}}
        """#
        let snapshot = try await Self.pluginSnapshot(
            quotaFixture: Self.quotaFixture, modelUsageFixture: analytics, engine: engine)
        #expect(snapshot.primary?.usedPercent == 25)
        #expect(snapshot.secondary?.usedPercent == 9)
        #expect(snapshot.details.map(\.title) == ["Quota details"])
    }

    @Test(arguments: BundledPluginTestSupport.engines, [
        String(repeating: "x", count: 120),
        String(repeating: "e\u{0301}", count: 120),
        String(repeating: "👩‍👩‍👧‍👦", count: 120),
    ])
    func `optional chart and detail label bounds remain complete`(
        engine: ProviderPluginEngineKind,
        name: String) async throws
    {
        let analytics: [String: Any] = [
            "code": 200, "success": true,
            "data": [
                "x_time": (0..<120).map { "hour-\($0)" },
                "modelDataList": [["modelName": name, "tokensUsage": Array(repeating: 1, count: 120)]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: analytics)
        let snapshot = try await Self.pluginSnapshot(
            quotaFixture: Self.quotaFixture,
            modelUsageFixture: #require(String(data: data, encoding: .utf8)),
            engine: engine)
        for title in ["Hourly tokens", "Daily tokens"] {
            let section = try #require(snapshot.details.first { $0.title == title })
            #expect(section.rows.first?.label == name)
            #expect(section.rows.first?.value == "120")
            #expect(section.chart?.points.count == 120)
        }
    }

    private static func pluginSnapshot(
        quotaFixture: String,
        modelUsageFixture: String = Self.emptyModelUsageFixture,
        engine: ProviderPluginEngineKind) async throws -> UsageSnapshot
    {
        let transport = ProviderHTTPTransportHandler { request in
            let body = request.url?.path.hasSuffix("/quota/limit") == true
                ? quotaFixture
                : modelUsageFixture
            return try CookiePluginFixtures.response(request, body: body)
        }
        return try await BundledPluginTestSupport.runtime("zai", engine: engine, transport: transport).fetchUsage(
            settings: ["Z_AI_REGION": "global", "Z_AI_USAGE_SCOPE": "personal"],
            secrets: ["Z_AI_API_KEY": "fixture-key"],
            now: Date(timeIntervalSince1970: 1_785_816_000))
    }

    private static let quotaFixture = #"""
    {"code":200,"success":true,"data":{"planName":"Pro","limits":[
      {"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":25},
      {"type":"TOKENS_LIMIT","unit":6,"number":1,"percentage":9}
    ]}}
    """#

    private static let emptyModelUsageFixture = #"{"code":200,"success":true,"data":{"x_time":[],"modelDataList":[]}}"#
}
