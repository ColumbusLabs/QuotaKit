import Foundation
import Testing
@testable import CodexBarCore

@Suite
struct MiniMaxCookieHeaderTests {
    @Test
    func normalizesRawCookieHeader() {
        let raw = "foo=bar; session=abc123"
        let normalized = MiniMaxCookieHeader.normalized(from: raw)
        #expect(normalized == "foo=bar; session=abc123")
    }

    @Test
    func extractsFromCookieHeaderLine() {
        let raw = "Cookie: foo=bar; session=abc123"
        let normalized = MiniMaxCookieHeader.normalized(from: raw)
        #expect(normalized == "foo=bar; session=abc123")
    }

    @Test
    func extractsFromCurlHeader() {
        let raw = "curl https://platform.minimax.io -H 'Cookie: foo=bar; session=abc123' -H 'accept: */*'"
        let normalized = MiniMaxCookieHeader.normalized(from: raw)
        #expect(normalized == "foo=bar; session=abc123")
    }

    @Test
    func extractsAuthAndGroupIDFromCurl() {
        let raw = """
        curl 'https://platform.minimax.io/v1/api/openplatform/coding_plan/remains?GroupId=123456' \
          -H 'authorization: Bearer token123' \
          -H 'Cookie: foo=bar; session=abc123'
        """
        let override = MiniMaxCookieHeader.override(from: raw)
        #expect(override?.cookieHeader == "foo=bar; session=abc123")
        #expect(override?.authorizationToken == "token123")
        #expect(override?.groupID == "123456")
    }
}

@Suite
struct MiniMaxUsageParserTests {
    @Test
    func parsesCodingPlanSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let html = """
        <div>Coding Plan</div>
        <div>Max</div>
        <div>Available usage: 1,000 prompts / 5 hours</div>
        <div>Current Usage</div>
        <div>0% Used</div>
        <div>Resets in 4 min</div>
        """

        let snapshot = try MiniMaxUsageParser.parse(html: html, now: now)

        #expect(snapshot.planName == "Max")
        #expect(snapshot.availablePrompts == 1000)
        #expect(snapshot.windowMinutes == 300)
        #expect(snapshot.usedPercent == 0)
        #expect(snapshot.resetsAt == now.addingTimeInterval(240))

        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary.resetDescription == "1000 prompts / 5 hours")
    }

    @Test
    func parsesCodingPlanRemainsResponse() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = 1_700_000_000_000
        let end = start + 5 * 60 * 60 * 1000
        let json = """
        {
          "base_resp": { "status_code": 0 },
          "current_subscribe_title": "Max",
          "model_remains": [
            {
              "current_interval_total_count": 1000,
              "current_interval_usage_count": 250,
              "start_time": \(start),
              "end_time": \(end),
              "remains_time": 240000
            }
          ]
        }
        """

        let snapshot = try MiniMaxUsageParser.parseCodingPlanRemains(data: Data(json.utf8), now: now)

        #expect(snapshot.planName == "Max")
        #expect(snapshot.availablePrompts == 1000)
        #expect(snapshot.windowMinutes == 300)
        #expect(snapshot.usedPercent == 75)
        #expect(snapshot.resetsAt == now.addingTimeInterval(240))
    }

    @Test
    func parsesCodingPlanFromNextData() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = 1_700_000_000_000
        let end = start + 5 * 60 * 60 * 1000
        let json = """
        {
          "props": {
            "pageProps": {
              "data": {
                "base_resp": { "status_code": 0 },
                "current_subscribe_title": "Max",
                "model_remains": [
                  {
                    "current_interval_total_count": 1000,
                    "current_interval_usage_count": 250,
                    "start_time": \(start),
                    "end_time": \(end),
                    "remains_time": 240000
                  }
                ]
              }
            }
          }
        }
        """
        let html = """
        <html>
          <script id="__NEXT_DATA__" type="application/json">\(json)</script>
        </html>
        """

        let snapshot = try MiniMaxUsageParser.parse(html: html, now: now)

        #expect(snapshot.planName == "Max")
        #expect(snapshot.availablePrompts == 1000)
        #expect(snapshot.windowMinutes == 300)
        #expect(snapshot.usedPercent == 75)
        #expect(snapshot.resetsAt == now.addingTimeInterval(240))
    }

    @Test
    func throwsOnMissingCookieResponse() {
        let json = """
        {
          "base_resp": { "status_code": 1004, "status_msg": "cookie is missing, log in again" }
        }
        """

        #expect(throws: MiniMaxUsageError.invalidCredentials) {
            try MiniMaxUsageParser.parseCodingPlanRemains(data: Data(json.utf8))
        }
    }
}
