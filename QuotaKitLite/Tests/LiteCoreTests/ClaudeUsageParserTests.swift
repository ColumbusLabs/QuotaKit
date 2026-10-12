import CodexBarSync
import Foundation
import LiteCore
import Testing

/// Usage fixtures are copied from the full app's tests, named per case (068 §8).
struct ClaudeUsageParserTests {
    private static func parse(_ json: String) -> [QuotaWindow]? {
        ClaudeUsageAPI.parseUsage(Data(json.utf8))
    }

    private static func date(_ iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)
    }

    @Test
    func `session weekly and Sonnet windows map to lanes`() throws {
        // `ClaudeOAuthTests.swift` (`maps O auth usage to snapshot`).
        let json = """
        {
          "five_hour": { "utilization": 12.5, "resets_at": "2025-12-25T12:00:00.000Z" },
          "seven_day": { "utilization": 30, "resets_at": "2025-12-31T00:00:00.000Z" },
          "seven_day_sonnet": { "utilization": 5 }
        }
        """
        let windows = try #require(Self.parse(json))

        #expect(windows == [
            QuotaWindow(
                label: "Session",
                lane: .session,
                usedPercent: 12.5,
                windowMinutes: 300,
                resetsAt: Self.date("2025-12-25T12:00:00Z")),
            QuotaWindow(
                label: "Weekly",
                lane: .weekly,
                usedPercent: 30,
                windowMinutes: 10080,
                resetsAt: Self.date("2025-12-31T00:00:00Z")),
            QuotaWindow(label: "Sonnet", lane: .weekly, usedPercent: 5, windowMinutes: 10080, resetsAt: nil),
        ])
    }

    @Test
    func `Opus is used when Sonnet is missing`() throws {
        // `ClaudeOAuthTests.swift` (`prefers opus when sonnet missing`).
        let json = """
        {
          "five_hour": { "utilization": 10, "resets_at": "2025-12-25T12:00:00.000Z" },
          "seven_day_opus": { "utilization": 42 }
        }
        """
        let windows = try #require(Self.parse(json))

        #expect(windows.map(\.label) == ["Session", "Opus"])
        #expect(windows.last?.usedPercent == 42)
        #expect(windows.last?.lane == .weekly)
    }

    @Test
    func `Sonnet wins over Opus even without utilization, like the full app`() throws {
        // `usage.sevenDaySonnet ?? usage.sevenDayOpus` picks the decoded Sonnet window, which then has no value.
        let json = """
        {
          "five_hour": { "utilization": 10 },
          "seven_day_sonnet": { "resets_at": "2025-12-31T00:00:00.000Z" },
          "seven_day_opus": { "utilization": 42 }
        }
        """
        #expect(try #require(Self.parse(json)).map(\.label) == ["Session"])
    }

    @Test
    func `null model windows and other fields are ignored`() throws {
        // `ClaudeOAuthTests.swift` (`surfaces Fable scoped weekly limit from limits array`), shortened.
        let json = """
        {
          "five_hour": { "utilization": 11.0, "resets_at": "2026-07-03T00:30:00.282668+00:00" },
          "seven_day": { "utilization": 9.0, "resets_at": "2026-07-08T09:00:00.282694+00:00" },
          "seven_day_opus": null,
          "seven_day_sonnet": null,
          "extra_usage": { "is_enabled": true, "monthly_limit": 1000, "used_credits": 300 },
          "cedar_ember": { "eligible": true, "grants": [] },
          "limits": [
            {
              "kind": "weekly_scoped", "group": "weekly", "percent": 5,
              "resets_at": "2026-07-08T09:00:00.283070+00:00",
              "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
              "is_active": false
            }
          ]
        }
        """
        let windows = try #require(Self.parse(json))

        #expect(windows.map(\.label) == ["Session", "Weekly"])
        #expect(windows.map(\.usedPercent) == [11, 9])
        // Microsecond fractions parse, as in the full app.
        #expect(windows.allSatisfy { $0.resetsAt != nil })
    }

    @Test
    func `windows without utilization are dropped`() throws {
        // `ClaudeUsageTests.swift` (`oauth usage falls back when five hour has no utilization`).
        let json = """
        {
          "five_hour": { "resets_at": "2025-12-23T16:00:00.000Z" },
          "seven_day": { "utilization": 9, "resets_at": "2025-12-29T23:00:00.000Z" }
        }
        """
        let windows = try #require(Self.parse(json))

        #expect(windows.map(\.label) == ["Weekly"])
    }

    @Test
    func `a malformed window is skipped without failing the others`() throws {
        let json = """
        {
          "five_hour": { "utilization": "lots" },
          "seven_day": { "utilization": 21, "resets_at": "not a date" }
        }
        """
        let windows = try #require(Self.parse(json))

        #expect(windows == [
            QuotaWindow(label: "Weekly", lane: .weekly, usedPercent: 21, windowMinutes: 10080, resetsAt: nil),
        ])
    }

    @Test
    func `unknown shapes give no windows`() {
        // `ClaudeUsageTests.swift` (`oauth usage throws when no usable windows are present`) uses `{}`.
        #expect(Self.parse("{}") == [])
        #expect(Self.parse("[]") == nil)
        #expect(Self.parse("not json") == nil)
    }

    @Test
    func `identities are the email in AccountIdentityComputer's Claude format`() {
        // Format and normalisation from the full app's `AccountIdentityComputerTests.swift`:
        // `Claude follows the same shape as Codex` and `normalize byte-equals iOS shared contract`.
        #expect(
            ClaudeUsageAPI.accountIdentities(email: "claude-user@example.com")
                == ["claude:email:claude-user@example.com"])
        #expect(
            ClaudeUsageAPI.accountIdentities(email: " Café@Example.com ")
                == ["claude:email:caf%C3%A9@example.com"])
        #expect(
            ClaudeUsageAPI.accountIdentities(email: "cafe\u{0301}@example.com")
                == ["claude:email:caf%C3%A9@example.com"])
        #expect(ClaudeUsageAPI.accountIdentities(email: "") == [])
        #expect(ClaudeUsageAPI.accountIdentities(email: nil) == [])
    }

    @Test
    func `identities use the shared normaliser byte for byte`() {
        let email = "Person.Name+tag@Example.COM"

        #expect(ClaudeUsageAPI.accountIdentities(email: email) == [
            "claude:email:" + (AccountIdentityNormalize.normalize(email) ?? ""),
        ])
    }
}
