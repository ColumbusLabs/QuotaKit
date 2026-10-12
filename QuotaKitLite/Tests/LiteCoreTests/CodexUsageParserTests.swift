import Foundation
import LiteCore
import Testing

/// Fixtures are copied from `Tests/CodexBarTests/CodexOAuthTests.swift` (the `wham/usage` bodies the full app's
/// tests use). The test target has no resources, so they are Swift string literals.
struct CodexUsageParserTests {
    /// CodexOAuthTests.swift, `maps usage windows from O auth`.
    private static let sessionAndWeekly = """
    {
      "rate_limit": {
        "primary_window": {
          "used_percent": 22,
          "reset_at": 1766948068,
          "limit_window_seconds": 18000
        },
        "secondary_window": {
          "used_percent": 43,
          "reset_at": 1767407914,
          "limit_window_seconds": 604800
        }
      }
    }
    """

    /// CodexOAuthTests.swift, `decodes prolite plan type without failing usage mapping`.
    private static let prolite = """
    {
      "plan_type": "prolite",
      "rate_limit": {
        "primary_window": {
          "used_percent": 12,
          "reset_at": 1766948068,
          "limit_window_seconds": 18000
        }
      }
    }
    """

    /// CodexOAuthTests.swift, `decodes credits balance string`: plan_type "pro" plus a credits block Lite ignores.
    private static let proWithCredits = """
    {
      "plan_type": "pro",
      "rate_limit": {
        "primary_window": {
          "used_percent": 12,
          "reset_at": 1766948068,
          "limit_window_seconds": 18000
        }
      },
      "credits": { "has_credits": false, "unlimited": false, "balance": "0" }
    }
    """

    /// CodexOAuthTests.swift, `maps free weekly only window into secondary`.
    private static let freeWeeklyOnly = """
    {
      "plan_type": "free",
      "rate_limit": {
        "primary_window": {
          "used_percent": 0,
          "reset_at": 1775468693,
          "limit_window_seconds": 604800
        },
        "secondary_window": null
      }
    }
    """

    /// CodexOAuthTests.swift, `preserves unknown secondary only window as primary`.
    private static let unknownSecondaryOnly = """
    {
      "rate_limit": {
        "primary_window": null,
        "secondary_window": {
          "used_percent": 17,
          "reset_at": 1766948068,
          "limit_window_seconds": 32400
        }
      }
    }
    """

    /// CodexOAuthTests.swift, `swaps reversed weekly and unknown windows`.
    private static let weeklyThenUnknown = """
    {
      "rate_limit": {
        "primary_window": {
          "used_percent": 43,
          "reset_at": 1767407914,
          "limit_window_seconds": 604800
        },
        "secondary_window": {
          "used_percent": 17,
          "reset_at": 1766948068,
          "limit_window_seconds": 32400
        }
      }
    }
    """

    /// CodexOAuthTests.swift, `returns nil when O auth usage has no windows`.
    private static let noWindows = """
    { "rate_limit": { "primary_window": null, "secondary_window": null } }
    """

    /// CodexOAuthTests.swift, `keeps valid window when secondary window is malformed`.
    private static let malformedSecondary = """
    {
      "rate_limit": {
        "primary_window": {
          "used_percent": 18,
          "reset_at": 1766948068,
          "limit_window_seconds": 18000
        },
        "secondary_window": {
          "used_percent": "bad",
          "reset_at": 1767407914,
          "limit_window_seconds": 604800
        }
      }
    }
    """

    private static let auth = CodexAuth(
        accessToken: "token",
        accountID: "account-123",
        email: "Person@Example.com")

    private static func parse(_ json: String, auth: CodexAuth = auth) -> Result<ProbeResult, ProbeFailure> {
        CodexUsageParser.parse(Data(json.utf8), auth: auth)
    }

    private static func result(_ json: String) throws -> ProbeResult {
        try self.parse(json).get()
    }

    // MARK: - Window mapping

    @Test
    func `18000 and 604800 second windows map to the session and weekly lanes`() throws {
        let result = try Self.result(Self.sessionAndWeekly)

        #expect(result.windows == [
            QuotaWindow(
                label: "Session",
                lane: .session,
                usedPercent: 22,
                windowMinutes: 300,
                resetsAt: Date(timeIntervalSince1970: 1_766_948_068)),
            QuotaWindow(
                label: "Weekly",
                lane: .weekly,
                usedPercent: 43,
                windowMinutes: 10080,
                resetsAt: Date(timeIntervalSince1970: 1_767_407_914)),
        ])
    }

    @Test
    func `a weekly only window fills the weekly lane even when it arrives as the primary window`() throws {
        let result = try Self.result(Self.freeWeeklyOnly)

        #expect(result.windows.map(\.lane) == [.weekly])
        #expect(result.windows.first?.label == "Weekly")
        #expect(result.windows.first?.windowMinutes == 10080)
        #expect(result.windows.first?.usedPercent == 0)
    }

    @Test
    func `a single session window stays in the session lane`() throws {
        let result = try Self.result(Self.prolite)

        #expect(result.windows.map(\.lane) == [.session])
        #expect(result.windows.first?.usedPercent == 12)
    }

    @Test
    func `an unknown length window keeps its real length and takes the slot its position implies`() throws {
        // The full app keeps an unknown lone window as the primary (session) slot, with its real minutes.
        let secondaryOnly = try Self.result(Self.unknownSecondaryOnly)
        #expect(secondaryOnly.windows.map(\.lane) == [.session])
        #expect(secondaryOnly.windows.first?.label == "Session")
        #expect(secondaryOnly.windows.first?.windowMinutes == 540)
        #expect(secondaryOnly.windows.first?.usedPercent == 17)
    }

    @Test
    func `a weekly primary beside an unknown secondary is swapped like the full app does`() throws {
        let result = try Self.result(Self.weeklyThenUnknown)

        #expect(result.windows.map(\.lane) == [.session, .weekly])
        #expect(result.windows[0].usedPercent == 17)
        #expect(result.windows[0].windowMinutes == 540)
        #expect(result.windows[1].usedPercent == 43)
        #expect(result.windows[1].windowMinutes == 10080)
    }

    @Test
    func `reversed session and weekly windows are put back in lane order`() throws {
        let json = """
        {
          "rate_limit": {
            "primary_window": { "used_percent": 43, "reset_at": 1767407914, "limit_window_seconds": 604800 },
            "secondary_window": { "used_percent": 22, "reset_at": 1766948068, "limit_window_seconds": 18000 }
          }
        }
        """
        let result = try Self.result(json)

        #expect(result.windows.map(\.lane) == [.session, .weekly])
        #expect(result.windows.map(\.usedPercent) == [22, 43])
    }

    @Test
    func `two weekly windows produce one weekly lane`() throws {
        let json = """
        {
          "rate_limit": {
            "primary_window": { "used_percent": 10, "reset_at": 1767407914, "limit_window_seconds": 604800 },
            "secondary_window": { "used_percent": 20, "reset_at": 1767407914, "limit_window_seconds": 604800 }
          }
        }
        """
        let result = try Self.result(json)

        #expect(result.windows.map(\.lane) == [.weekly])
        #expect(result.windows.first?.usedPercent == 10)
    }

    @Test
    func `a malformed window is dropped and the valid one survives`() throws {
        let result = try Self.result(Self.malformedSecondary)

        #expect(result.windows.map(\.lane) == [.session])
        #expect(result.windows.first?.usedPercent == 18)
    }

    @Test
    func `numbers sent as strings or fractions are accepted`() throws {
        let json = """
        {
          "rate_limit": {
            "primary_window": { "used_percent": "37.5", "reset_at": "1766948068", "limit_window_seconds": 18000.0 }
          }
        }
        """
        let window = try #require(try Self.result(json).windows.first)

        #expect(window.usedPercent == 37.5)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_766_948_068))
        #expect(window.windowMinutes == 300)
    }

    @Test
    func `a window without a reset time still shows its percentage`() throws {
        let json = """
        { "rate_limit": { "primary_window": { "used_percent": 5, "limit_window_seconds": 18000 } } }
        """
        let window = try #require(try Self.result(json).windows.first)

        #expect(window.usedPercent == 5)
        #expect(window.resetsAt == nil)
    }

    // MARK: - Unrecognised shapes

    @Test
    func `a body with no usable window is an unrecognized response`() {
        let bodies = [
            Self.noWindows,
            "{}",
            #"{ "plan_type": "pro" }"#,
            #"{ "rate_limit": {} }"#,
            #"{ "rate_limit": null }"#,
            #"{ "rate_limit": "oops" }"#,
            // Missing used_percent, missing length, non-positive length, and a sub-minute length.
            #"{ "rate_limit": { "primary_window": { "reset_at": 1, "limit_window_seconds": 18000 } } }"#,
            #"{ "rate_limit": { "primary_window": { "used_percent": 1, "reset_at": 1 } } }"#,
            #"{ "rate_limit": { "primary_window": { "used_percent": 1, "limit_window_seconds": 0 } } }"#,
            #"{ "rate_limit": { "primary_window": { "used_percent": 1, "limit_window_seconds": 30 } } }"#,
            #"{ "rate_limit": { "primary_window": "oops" } }"#,
        ]
        for body in bodies {
            #expect(Self.parse(body) == .failure(.unrecognizedResponse), "\(body)")
        }
    }

    @Test
    func `garbage and non object JSON are an unrecognized response`() {
        let bodies = ["", "not json", "<html>Just a moment...</html>", "[]", "null", "42", #""text""#]
        for body in bodies {
            #expect(Self.parse(body) == .failure(.unrecognizedResponse), "\(body)")
        }
    }

    @Test
    func `unknown extra fields are ignored`() throws {
        let json = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "allowed": true,
            "limit_reached": false,
            "primary_window": {
              "used_percent": 1, "reset_at": 1766948068, "limit_window_seconds": 18000, "future_field": [1, 2]
            }
          },
          "additional_rate_limits": "not even an array",
          "credits": 7
        }
        """
        let result = try Self.result(json)

        #expect(result.windows.count == 1)
        #expect(result.plan == "Plus")
    }

    // MARK: - Plan, email and identities

    @Test
    func `plan type maps through the full app display names`() throws {
        #expect(try Self.result(Self.proWithCredits).plan == "Pro 20x")
        #expect(try Self.result(Self.prolite).plan == "Pro 5x")
        #expect(try Self.result(Self.freeWeeklyOnly).plan == "Free")
        #expect(try Self.result(Self.sessionAndWeekly).plan == nil)
    }

    @Test
    func `plan display names match CodexPlanFormatting`() {
        // Cases from `CodexPlanFormatting.displayName` and the plan types in `CodexUsageResponse.PlanType`.
        let cases: [(String?, String?)] = [
            ("pro", "Pro 20x"),
            ("PRO", "Pro 20x"),
            ("prolite", "Pro 5x"),
            ("pro_lite", "Pro 5x"),
            ("pro-lite", "Pro 5x"),
            ("pro lite", "Pro 5x"),
            ("plus", "Plus"),
            ("team", "Team"),
            ("business", "Business"),
            ("enterprise", "Enterprise"),
            ("free_workspace", "Free Workspace"),
            ("k12", "K12"),
            ("edu", "Edu"),
            ("  go  ", "Go"),
            ("", nil),
            ("   ", nil),
            (nil, nil),
        ]
        for (raw, expected) in cases {
            #expect(CodexPlanName.displayName(raw) == expected, "\(raw ?? "nil")")
        }
    }

    @Test
    func `email and identities come from the auth file, not the response`() throws {
        let result = try Self.result(Self.sessionAndWeekly)

        #expect(result.accountEmail == "Person@Example.com")
        #expect(result.accountIdentities == ["codex:account:account-123", "codex:email:person@example.com"])
    }

    @Test
    func `identities are empty when the auth file has neither an account nor an email`() throws {
        let result = try Self.parse(Self.sessionAndWeekly, auth: CodexAuth(accessToken: "token")).get()

        #expect(result.accountEmail == nil)
        #expect(result.accountIdentities.isEmpty)
    }
}
