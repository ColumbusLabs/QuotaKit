import Foundation
import Testing
@testable import CodexBarCore

struct MiniMaxWebResponseTests {
    @Test
    func `next data accepts JSON whitespace and preserves fallback for an empty script`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {"modelRemains":[{"current_interval_total_count":100,"current_interval_usage_count":75}],
         "currentSubscribeTitle":"Max"}
        """
        let html = "<script id=\"__NEXT_DATA__\"> \t\r\n\(json)\r\n\t </script>"
        #expect(try MiniMaxUsageParser.parse(html: html, now: now).planName == "Max")
        let empty = "<script id=\"__NEXT_DATA__\"> \t\r\n </script><div>Coding Plan Pro</div>"
        #expect(try MiniMaxUsageParser.parse(html: empty, now: now).planName == "Pro")
    }

    @Test
    func `next data aliases preserve snake case precedence and nested payloads`() throws {
        let payload = try MiniMaxUsageParser.decodePayload(json: ["data": [
            "modelRemains": [],
            "currentSubscribeTitle": "Current",
            "plan_name": "Original",
            "planName": "Alias",
            "comboTitle": "Combo",
            "currentPlanTitle": "Plan",
            "currentComboCard": ["title": "Card"],
            "baseResp": ["status_code": 0],
            "pointsBalance": 12.5,
            "creditsBalance": 25,
        ]])
        #expect(payload.data.modelRemains.isEmpty)
        #expect(payload.data.currentSubscribeTitle == "Current")
        #expect(payload.data.planName == "Original")
        #expect(payload.data.comboTitle == "Combo")
        #expect(payload.data.currentPlanTitle == "Plan")
        #expect(payload.data.currentComboCard?.title == "Card")
        #expect(payload.data.baseResp?.statusCode == 0)
        #expect(payload.data.pointsBalance == 12.5)
    }
}
