import Foundation
import LiteCore
import Testing

struct ClaudeCredentialsTests {
    @Test
    func `parses the full credentials shape`() throws {
        // The fixture from the full app's `ClaudeOAuthTests.swift` (`parses O auth credentials`).
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "test-token",
            "refreshToken": "test-refresh",
            "expiresAt": 4102444800000,
            "scopes": ["usage:read"],
            "rateLimitTier": "default_claude_max_20x",
            "subscriptionType": "pro"
          }
        }
        """
        let credentials = try ClaudeCredentials.parse(Data(json.utf8))

        #expect(credentials.accessToken == "test-token")
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 4_102_444_800))
        #expect(credentials.scopes == ["usage:read"])
        #expect(credentials.rateLimitTier == "default_claude_max_20x")
        #expect(credentials.subscriptionType == "pro")
        #expect(credentials.isExpired(at: ClaudeFixtures.now) == false)
    }

    @Test
    func `optional fields may be missing and the token is trimmed`() throws {
        let json = #"{ "claudeAiOauth": { "accessToken": "  token-with-space \n" } }"#
        let credentials = try ClaudeCredentials.parse(Data(json.utf8))

        #expect(credentials.accessToken == "token-with-space")
        #expect(credentials.expiresAt == nil)
        #expect(credentials.scopes.isEmpty)
        #expect(credentials.subscriptionType == nil)
        #expect(credentials.rateLimitTier == nil)
        #expect(credentials.plan == nil)
        // Lite can't refresh, so a missing expiry lets the server decide rather than reporting "expired".
        #expect(credentials.isExpired(at: ClaudeFixtures.now) == false)
    }

    @Test
    func `missing or blank access token is rejected`() {
        let blank = #"{ "claudeAiOauth": { "accessToken": "", "expiresAt": 1735689600000 } }"#
        let missing = #"{ "claudeAiOauth": { "expiresAt": 1735689600000 } }"#

        #expect(throws: ClaudeCredentialsError.missingAccessToken) { try ClaudeCredentials.parse(Data(blank.utf8)) }
        #expect(throws: ClaudeCredentialsError.missingAccessToken) {
            try ClaudeCredentials.parse(Data(missing.utf8))
        }
    }

    @Test
    func `missing OAuth block is rejected, including MCP only payloads`() {
        let other = #"{ "other": { "accessToken": "nope" } }"#
        // The MCP-only shape from the full app's `ClaudeOAuthTests.swift` (`mcp O auth only keychain payload throws`).
        let mcpOnly = #"{ "mcpOAuth": { "plugin:slack:slack": { "accessToken": "" } } }"#

        #expect(throws: ClaudeCredentialsError.missingOAuth) { try ClaudeCredentials.parse(Data(other.utf8)) }
        #expect(throws: ClaudeCredentialsError.missingOAuth) { try ClaudeCredentials.parse(Data(mcpOnly.utf8)) }
    }

    @Test
    func `garbage and wrongly typed fields are invalid JSON`() {
        let wrongType = #"{ "claudeAiOauth": { "accessToken": "t", "expiresAt": "soon" } }"#

        #expect(throws: ClaudeCredentialsError.invalidJSON) { try ClaudeCredentials.parse(Data("not json".utf8)) }
        #expect(throws: ClaudeCredentialsError.invalidJSON) { try ClaudeCredentials.parse(Data("[1, 2]".utf8)) }
        #expect(throws: ClaudeCredentialsError.invalidJSON) { try ClaudeCredentials.parse(Data()) }
        #expect(throws: ClaudeCredentialsError.invalidJSON) { try ClaudeCredentials.parse(Data(wrongType.utf8)) }
    }

    @Test
    func `expiry is reached at exactly expiresAt`() {
        let credentials = ClaudeCredentials(accessToken: "t", expiresAt: ClaudeFixtures.now)

        #expect(credentials.isExpired(at: ClaudeFixtures.now.addingTimeInterval(-1)) == false)
        #expect(credentials.isExpired(at: ClaudeFixtures.now))
    }

    @Test
    func `descriptions never include the token`() {
        let credentials = ClaudeCredentials(accessToken: "sk-ant-oat01-secret", expiresAt: nil)

        #expect(!String(describing: credentials).contains("secret"))
        #expect(!String(reflecting: credentials).contains("secret"))
    }

    /// Expected values from the full app's `ClaudePlanResolverTests.swift`.
    @Test(arguments: [
        (nil, "claude_pro", "Claude Pro"),
        (nil, "claude_team", "Claude Team"),
        (nil, "claude_enterprise", "Claude Enterprise"),
        (nil, "default_claude_max_5x", "Claude Max 5x"),
        (nil, "default_claude_max_20x", "Claude Max 20x"),
        (nil, "v2_default_claude_max_20x", "Claude Max 20x"),
        (nil, "claude_max", "Claude Max"),
        (nil, "default_claude_team_5x", "Claude Team"),
        ("team", "default_claude_max_5x", "Claude Team"),
        ("pro", "default_claude_ai", "Claude Pro"),
        ("max", "default_claude_max_20x", "Claude Max 20x"),
        (nil, "default_claude_ai", nil),
        (nil, nil, nil),
    ] as [(String?, String?, String?)])
    func `plan matches the full app's OAuth login method`(
        subscriptionType: String?,
        rateLimitTier: String?,
        expected: String?)
    {
        let credentials = ClaudeCredentials(
            accessToken: "t",
            expiresAt: nil,
            subscriptionType: subscriptionType,
            rateLimitTier: rateLimitTier)

        #expect(credentials.plan == expected)
    }

    @Test
    func `credentials file honours CLAUDE_CONFIG_DIR`() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

        #expect(
            ClaudeCredentialsFile.url(environment: [:], homeDirectory: home).path
                == "/Users/someone/.claude/.credentials.json")
        #expect(
            ClaudeCredentialsFile.url(environment: ["CLAUDE_CONFIG_DIR": ""], homeDirectory: home).path
                == "/Users/someone/.claude/.credentials.json")
        #expect(
            ClaudeCredentialsFile.url(environment: ["CLAUDE_CONFIG_DIR": "/tmp/profile"], homeDirectory: home).path
                == "/tmp/profile/.credentials.json")
    }

    @Test
    func `credentials file reads from a temporary home`() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCredentialsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = ClaudeCredentialsFile(environment: [:], homeDirectory: home)
        #expect(file.readCredentialsFile() == nil)

        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let contents = ClaudeFixtures.credentialsJSON(token: "file-token")
        try contents.write(to: file.url)

        #expect(file.readCredentialsFile() == contents)
    }
}
