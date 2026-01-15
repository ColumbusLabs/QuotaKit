import Foundation
import Testing
@testable import CodexBarCore

@Suite
struct ZaiSettingsReaderTests {
    @Test
    func apiTokenReadsFromEnvironment() {
        let token = ZaiSettingsReader.apiToken(environment: ["Z_AI_API_KEY": "abc123"])
        #expect(token == "abc123")
    }

    @Test
    func apiTokenStripsQuotes() {
        let token = ZaiSettingsReader.apiToken(environment: ["Z_AI_API_KEY": "\"token-xyz\""])
        #expect(token == "token-xyz")
    }
}

@Suite
struct ZaiUsageSnapshotTests {
    @Test
    func mapsUsageSnapshotWindows() {
        let reset = Date(timeIntervalSince1970: 123)
        let tokenLimit = ZaiLimitEntry(
            type: .tokensLimit,
            unit: .hours,
            number: 5,
            usage: 100,
            currentValue: 20,
            remaining: 80,
            percentage: 25,
            usageDetails: [],
            nextResetTime: reset)
        let timeLimit = ZaiLimitEntry(
            type: .timeLimit,
            unit: .days,
            number: 30,
            usage: 200,
            currentValue: 40,
            remaining: 160,
            percentage: 50,
            usageDetails: [],
            nextResetTime: nil)
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: tokenLimit,
            timeLimit: timeLimit,
            planName: nil,
            updatedAt: reset)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 20)
        #expect(usage.primary?.windowMinutes == 300)
        #expect(usage.primary?.resetsAt == reset)
        #expect(usage.primary?.resetDescription == "5 hours window")
        #expect(usage.secondary?.usedPercent == 20)
        #expect(usage.secondary?.resetDescription == "30 days window")
        #expect(usage.zaiUsage?.tokenLimit?.usage == 100)
    }
}

@Suite
struct ZaiUsageParsingTests {
    @Test
    func parsesUsageResponse() throws {
        let json = """
        {
          "code": 200,
          "msg": "Operation successful",
          "data": {
            "limits": [
              {
                "type": "TIME_LIMIT",
                "unit": 5,
                "number": 1,
                "usage": 100,
                "currentValue": 102,
                "remaining": 0,
                "percentage": 100,
                "usageDetails": [
                  { "modelCode": "search-prime", "usage": 95 }
                ]
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "usage": 40000000,
                "currentValue": 13628365,
                "remaining": 26371635,
                "percentage": 34,
                "nextResetTime": 1768507567547
              }
            ],
            "planName": "Pro"
          },
          "success": true
        }
        """

        let snapshot = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))

        #expect(snapshot.planName == "Pro")
        #expect(snapshot.tokenLimit?.usage == 40_000_000)
        #expect(snapshot.timeLimit?.usageDetails.first?.modelCode == "search-prime")
    }

    @Test
    func missingDataReturnsApiError() {
        let json = """
        { "code": 1001, "msg": "Authorization Token Missing", "success": false }
        """

        #expect {
            _ = try ZaiUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))
        } throws: { error in
            guard case let ZaiUsageError.apiError(message) = error else { return false }
            return message == "Authorization Token Missing"
        }
    }
}
