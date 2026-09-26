import Foundation
import Testing
@testable import CodexBarCore

struct DeepSeekModelCostTests {
    private let now = Date(timeIntervalSince1970: 1_779_796_800)

    private func parse(_ models: [(String?, [Any]?)]) throws -> DeepSeekUsageSummary {
        let records: [[String: Any]] = models.map { entry in
            let (name, items) = entry
            var record: [String: Any] = [:]
            if let name { record["model"] = name }
            record["usage"] = items?.map { ["type": "RESPONSE_TOKEN", "amount": $0] }
            return record
        }
        let amount = Data(#"{"code":0,"data":{"biz_data":{"total":[],"days":[]}}}"#.utf8)
        let cost = try JSONSerialization.data(withJSONObject: ["code": 0, "data": ["biz_data": [
            ["currency": "USD", "total": records, "days": []],
        ]]])
        return try DeepSeekUsageFetcher._parseUsageSummaryForTesting(
            amountData: amount,
            costData: cost,
            now: self.now)
    }

    @Test
    func `model spend combines repeated names and keeps reported zero`() throws {
        let summary = try self.parse([
            ("example-beta", ["2"]), (" example-alpha ", ["1", "2"]),
            ("example-beta", ["1"]), ("example-zero", ["0"]),
            (nil, ["9"]), ("  ", ["8"]),
        ])
        #expect(summary.modelCosts == [
            DeepSeekModelCost(model: "example-alpha", cost: 3),
            DeepSeekModelCost(model: "example-beta", cost: 3),
            DeepSeekModelCost(model: "example-zero", cost: 0),
        ])
        #expect(summary.currency == "USD")
    }

    @Test(arguments: ["invalid", "-1", "NaN", "Infinity", "null", "overflow"])
    func `invalid components withhold only the affected model`(invalid: String) throws {
        let amounts: [Any] = switch invalid {
        case "null": ["1", NSNull(), "2"]
        case "overflow": ["1e308", "1e308"]
        default: ["1", invalid, "2"]
        }
        let summary = try self.parse([
            ("example-invalid", amounts), ("example-invalid", ["4"]),
            ("example-zero", ["0"]),
        ])
        #expect(summary.modelCosts == [DeepSeekModelCost(model: "example-zero", cost: 0)])
    }

    @Test
    func `missing cost collections invalidate repeated model totals`() throws {
        let summary = try self.parse([
            ("example-incomplete", ["1"]), ("example-incomplete", nil),
            ("example-incomplete", ["2"]), ("example-complete", ["3"]),
            ("example-complete", []),
        ])
        #expect(summary.modelCosts == [DeepSeekModelCost(model: "example-complete", cost: 3)])
    }
}
