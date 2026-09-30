import Foundation
import Testing
@testable import CodexBarCore

struct MistralBillingDimensionsTests {
    @Test(arguments: [false, true])
    func `prices by event zone and tier regardless of price table order`(reversed: Bool) throws {
        var prices = [
            Self.price(event: "api_tokens", zone: "global", tier: "standard", amount: "0.25"),
            Self.price(event: "api_tokens", zone: "eu", tier: "priority", amount: "0.5"),
            Self.price(event: "api_tokens", zone: "eu", tier: "standard", amount: "50"),
            Self.price(event: "api_tokens", zone: "global", tier: "priority", amount: "60"),
            Self.price(event: "api_audio_seconds", zone: "global", tier: "standard", amount: "10"),
        ]
        if reversed { prices.reverse() }

        let entries = [
            Self.entry(4, paid: 2, event: "api_tokens", zone: "global", tier: "standard"),
            Self.entry(5, paid: 3, event: "api_tokens", zone: "eu", tier: "priority"),
            Self.entry(7, paid: 7, event: "api_audio_seconds", zone: "global", tier: "standard"),
        ]
        let snapshot = try Self.parse([
            "completion": ["models": ["fixture": ["input": entries]]],
            "prices": prices,
        ])

        #expect(snapshot.totalInputTokens == 16)
        #expect(snapshot.totalCost == 72)
        #expect(snapshot.daily.first?.cost == 72)
    }

    @Test(arguments: ["legacy", "zone", "tier"])
    func `legacy fallback needs both zone and tier to be absent`(priceKind: String) throws {
        let qualifiers = switch priceKind {
        case "zone": #", "api_zone":"eu", "service_tier":"standard""#
        case "tier": #", "api_zone":"global", "service_tier":"priority""#
        default: ""
        }
        let priceJSON = """
        {"event_type":"api_tokens","billing_metric":"fixture","billing_group":"input","price":"0.25"\(qualifiers)}
        """
        let json = """
        {"completion":{"models":{"fixture":{"input":[{
          "event_type":"api_tokens","billing_metric":"fixture","billing_group":"input",
          "timestamp":"2026-09-16","value":100,"value_paid":40,
          "api_zone":"global","service_tier":"standard"
        }]}}},"prices":[\(priceJSON)]}
        """
        let snapshot = try Self.parse(json)

        #expect(snapshot.totalInputTokens == 100)
        #expect(snapshot.totalCost == (priceKind == "legacy" ? 10 : 0))
        #expect(snapshot.daily.first?.cost == snapshot.totalCost)
    }

    @Test
    func `nil and blank billing dimensions remain distinct`() throws {
        let snapshot = try Self.parse([
            "completion": ["models": ["fixture": ["input": [
                Self.entry(2, paid: 2),
                Self.entry(3, paid: 3, zone: "", tier: ""),
            ]]]],
            "prices": [
                Self.price(amount: "0.5"),
                Self.price(zone: "", tier: "", amount: "0.75"),
            ],
        ])

        #expect(snapshot.totalInputTokens == 5)
        #expect(snapshot.totalCost == 3.25)
        #expect(snapshot.daily.first?.cost == 3.25)
    }

    @Test
    func `qualified prices do not guess a different zone or tier`() throws {
        let snapshot = try Self.parse([
            "completion": ["models": ["fixture": ["input": [
                Self.entry(100, paid: 40, event: "api_tokens", zone: "global", tier: "standard"),
            ]]]],
            "prices": [
                Self.price(event: "api_tokens", zone: "eu", tier: "standard", amount: "0.25"),
                Self.price(event: "api_tokens", zone: "global", tier: "priority", amount: "0.5"),
            ],
        ])

        #expect(snapshot.totalInputTokens == 100)
        #expect(snapshot.totalCost == 0)
        #expect(snapshot.daily.first?.cost == 0)
    }

    @Test
    func `month and daily tokens follow category-specific policies`() throws {
        let snapshot = try Self.parse([
            "completion": ["models": ["completion": Self.model(1)]],
            "chat": ["models": ["chat": Self.model(2)]],
            "vibe_code": ["completion": ["models": ["vibe": Self.model(3)]]],
            "ocr": ["models": ["ocr": Self.model(4)]],
            "connectors": ["models": ["connector": Self.model(5)]],
            "audio": ["models": ["audio": Self.model(6)]],
            "libraries_api": [
                "pages": ["models": ["page": Self.model(7)]],
                "tokens": ["models": ["library-token": Self.model(8)]],
            ],
            "fine_tuning": [
                "training": ["training": Self.model(9)],
                "storage": ["storage": Self.model(10)],
            ],
            "prices": [Self.price(amount: "1")],
        ])

        #expect(snapshot.totalInputTokens == 6)
        #expect(snapshot.modelCount == 3)
        #expect(snapshot.totalCost == 55)
        #expect(snapshot.daily.first?.totalTokens == 14)
        #expect(snapshot.daily.first?.cost == 55)
    }

    private static func entry(
        _ value: Int,
        paid: Int,
        event: String? = "api_tokens",
        zone: String? = nil,
        tier: String? = nil) -> [String: Any]
    {
        var entry: [String: Any] = [
            "billing_metric": "fixture",
            "billing_group": "input",
            "timestamp": "2026-09-16",
            "value": value,
            "value_paid": paid,
        ]
        if let event { entry["event_type"] = event }
        if let zone { entry["api_zone"] = zone }
        if let tier { entry["service_tier"] = tier }
        return entry
    }

    private static func price(
        event: String? = "api_tokens",
        zone: String? = nil,
        tier: String? = nil,
        amount: String) -> [String: Any]
    {
        var price: [String: Any] = [
            "billing_metric": "fixture",
            "billing_group": "input",
            "price": amount,
        ]
        if let event { price["event_type"] = event }
        if let zone { price["api_zone"] = zone }
        if let tier { price["service_tier"] = tier }
        return price
    }

    private static func model(_ value: Int) -> [String: Any] {
        ["input": [self.entry(value, paid: value)]]
    }

    private static func parse(_ payload: [String: Any]) throws -> MistralUsageSnapshot {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try MistralUsageFetcher.parseResponse(data: data, updatedAt: Date())
    }

    private static func parse(_ json: String) throws -> MistralUsageSnapshot {
        try MistralUsageFetcher.parseResponse(data: Data(json.utf8), updatedAt: Date())
    }
}
