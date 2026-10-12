import Foundation
import LiteCore
import Testing

/// Cases mirror `Tests/CodexBarTests/CodexOAuthTests.swift` (auth.json variants) and
/// `CodexNativeJWTExpiryTests.swift` (expiry), against the same logic in `CodexAuthReader`.
struct CodexAuthTests {
    private typealias Support = CodexTestSupport

    private static func parse(_ json: String) -> Result<CodexAuth, CodexAuthError> {
        CodexAuthReader.parse(Data(json.utf8))
    }

    private static func auth(_ json: String) throws -> CodexAuth {
        try self.parse(json).get()
    }

    // MARK: - auth.json variants

    @Test
    func `snake case tokens are read`() throws {
        // CodexOAuthTests.swift, `parses O auth credentials`.
        let auth = try Self.auth("""
        {
          "OPENAI_API_KEY": null,
          "tokens": {
            "access_token": "access-token",
            "refresh_token": "refresh-token",
            "id_token": "id-token",
            "account_id": "account-123"
          },
          "last_refresh": "2025-12-20T12:34:56Z"
        }
        """)

        #expect(auth.accessToken == "access-token")
        #expect(auth.accountID == "account-123")
        #expect(auth.lastRefresh == Date(timeIntervalSince1970: 1_766_234_096))
    }

    @Test
    func `camel case tokens are read`() throws {
        // CodexOAuthTests.swift, `parses legacy camel case O auth credentials`.
        let auth = try Self.auth("""
        {
          "tokens": {
            "accessToken": "access-token",
            "refreshToken": "refresh-token",
            "idToken": "id-token",
            "accountId": "account-123"
          },
          "last_refresh": "2025-12-20T12:34:56.789Z"
        }
        """)

        #expect(auth.accessToken == "access-token")
        #expect(auth.accountID == "account-123")
        #expect(auth.lastRefresh != nil)
    }

    @Test
    func `an API key beside OAuth tokens is ignored`() throws {
        let auth = try Self.auth("""
        {
          "OPENAI_API_KEY": "sk-test",
          "tokens": { "access_token": "oauth-access-token", "refresh_token": "r", "account_id": "account-123" }
        }
        """)

        #expect(auth.accessToken == "oauth-access-token")
    }

    @Test
    func `an API key only login has no rate limit to show`() {
        // CodexOAuthTests.swift, `parses API key credentials`.
        #expect(Self.parse(#"{ "OPENAI_API_KEY": "sk-test" }"#) == .failure(.noOAuthTokens))
    }

    @Test
    func `files without a usable access token are rejected`() {
        let bodies = [
            "{}",
            #"{ "tokens": null }"#,
            #"{ "tokens": {} }"#,
            #"{ "tokens": { "access_token": "" } }"#,
            #"{ "tokens": { "access_token": 7 } }"#,
            #"{ "tokens": "oops" }"#,
        ]
        for body in bodies {
            #expect(Self.parse(body) == .failure(.noOAuthTokens), "\(body)")
        }
    }

    @Test
    func `files that are not JSON objects are unreadable`() {
        for body in ["", "not json", "[]", #"{ "tokens": "#, "null"] {
            #expect(Self.parse(body) == .failure(.unreadable), "\(body)")
        }
    }

    // MARK: - JWT claims

    @Test
    func `account ID falls back to the chatgpt_account_id claim in the https auth namespace`() throws {
        let idToken = Support.jwt(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"claim-account"}}"#)
        let json = Support.authJSON(accessToken: Support.accessToken(), accountID: nil, idToken: idToken)

        #expect(try Self.auth(json).accountID == "claim-account")
    }

    @Test
    func `account ID fallback checks the ID token before the access token`() throws {
        let idToken = Support.jwt(#"{"chatgpt_account_id":"from-id-token"}"#)
        let access = Support.accessToken(extraClaims: #","chatgpt_account_id":"from-access-token""#)

        let both = Support.authJSON(accessToken: access, accountID: nil, idToken: idToken)
        let accessOnly = Support.authJSON(accessToken: access, accountID: nil)

        #expect(try Self.auth(both).accountID == "from-id-token")
        #expect(try Self.auth(accessOnly).accountID == "from-access-token")
    }

    @Test
    func `account ID fallback reads the first organization when no account claim exists`() throws {
        let idToken = Support.jwt(#"{"organizations":[{"id":""},{"id":"org-1"},{"id":"org-2"}]}"#)
        let json = Support.authJSON(accessToken: Support.accessToken(), accountID: nil, idToken: idToken)

        #expect(try Self.auth(json).accountID == "org-1")
    }

    @Test
    func `an explicit account ID wins over the claims`() throws {
        let idToken = Support.jwt(#"{"chatgpt_account_id":"from-claim"}"#)
        let json = Support.authJSON(accessToken: Support.accessToken(), accountID: "explicit", idToken: idToken)

        #expect(try Self.auth(json).accountID == "explicit")
    }

    @Test
    func `a blank account ID falls back to the claim`() throws {
        let idToken = Support.jwt(#"{"chatgpt_account_id":"from-claim"}"#)
        let json = Support.authJSON(accessToken: Support.accessToken(), accountID: "   ", idToken: idToken)

        #expect(try Self.auth(json).accountID == "from-claim")
    }

    @Test
    func `no account ID anywhere leaves it nil`() throws {
        let json = Support.authJSON(accessToken: "opaque-token", accountID: nil, idToken: "also-opaque")

        #expect(try Self.auth(json).accountID == nil)
    }

    @Test
    func `email comes from the ID token claims`() throws {
        let top = Support.jwt(#"{"email":"  Top@Example.com "}"#)
        let profile = Support.jwt(#"{"https://api.openai.com/profile":{"email":"profile@example.com"}}"#)
        let neither = Support.jwt(#"{"sub":"x"}"#)

        #expect(try Self.auth(Support.authJSON(accessToken: "t", idToken: top)).email == "Top@Example.com")
        #expect(try Self.auth(Support.authJSON(accessToken: "t", idToken: profile)).email == "profile@example.com")
        #expect(try Self.auth(Support.authJSON(accessToken: "t", idToken: neither)).email == nil)
        #expect(try Self.auth(Support.authJSON(accessToken: "t", idToken: nil)).email == nil)
    }

    @Test
    func `an email in the access token is not used`() throws {
        let access = Support.accessToken(extraClaims: #","email":"access@example.com""#)

        #expect(try Self.auth(Support.authJSON(accessToken: access)).email == nil)
    }

    @Test
    func `expiry comes from the access token exp claim`() throws {
        let json = Support.authJSON(accessToken: Support.accessToken(exp: 1_800_000_000))

        #expect(try Self.auth(json).expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test
    func `an ID token exp is not an access token expiry`() throws {
        let idToken = Support.jwt(#"{"exp":4102444800}"#)
        let json = Support.authJSON(accessToken: "opaque", idToken: idToken)

        #expect(try Self.auth(json).expiresAt == nil)
    }

    @Test
    func `exp claims that are not integers in range are ignored`() throws {
        let payloads = [
            #"{}"#, #"{"exp":null}"#, #"{"exp":true}"#, #"{"exp":"4102444800"}"#, #"{"exp":1.5}"#,
            #"{"exp":[4102444800]}"#, #"{"nested":{"exp":4102444800}}"#, #"{"exp":8210266876800}"#,
            #"{"exp":-8334601228801}"#, "not-json", "[]",
        ]
        for payload in payloads {
            let json = Support.authJSON(accessToken: Support.jwt(payload))
            #expect(try Self.auth(json).expiresAt == nil, "\(payload)")
        }
    }

    @Test
    func `malformed access tokens have no expiry`() throws {
        let payload = Data(#"{"exp":4102444800}"#.utf8).base64EncodedString()
        for token in ["opaque", "a.\(payload)", "a.\(payload).c.extra", ".\(payload).sig", "hdr.\(payload)."] {
            #expect(try Self.auth(Support.authJSON(accessToken: token)).expiresAt == nil, "\(token)")
        }
    }

    // MARK: - Expiry decision

    @Test
    func `a token is expired at and after its exp and valid before`() {
        let exp = Support.now.addingTimeInterval(60)
        let auth = CodexAuth(accessToken: "t", expiresAt: exp)

        #expect(!auth.isExpired(now: Support.now))
        #expect(auth.isExpired(now: exp))
        #expect(auth.isExpired(now: exp.addingTimeInterval(1)))
    }

    @Test
    func `exp wins over last_refresh in both directions`() {
        let old = Support.now.addingTimeInterval(-30 * 86400)
        let future = CodexAuth(accessToken: "t", expiresAt: Support.now.addingTimeInterval(3600), lastRefresh: old)
        let past = CodexAuth(accessToken: "t", expiresAt: Support.now.addingTimeInterval(-1), lastRefresh: Support.now)

        #expect(!future.isExpired(now: Support.now))
        #expect(past.isExpired(now: Support.now))
    }

    @Test
    func `without exp a token expires 8 days after last_refresh`() {
        let fresh = CodexAuth(accessToken: "t", lastRefresh: Support.now.addingTimeInterval(-7 * 86400))
        let stale = CodexAuth(accessToken: "t", lastRefresh: Support.now.addingTimeInterval(-8 * 86400 - 1))
        let unknown = CodexAuth(accessToken: "t")

        #expect(!fresh.isExpired(now: Support.now))
        #expect(stale.isExpired(now: Support.now))
        #expect(unknown.isExpired(now: Support.now))
    }

    // MARK: - Identities

    /// The full app's ambient OAuth path leaves `accountOrganization` nil, so `AccountIdentityComputer.codex` emits
    /// only the email (`Codex with only email returns email-only set`). The ChatGPT account ID is never an identity.
    @Test
    func `identities are only the email even with an account ID`() {
        let auth = CodexAuth(accessToken: "t", accountID: "org-abc123", email: "user@example.com")

        #expect(auth.accountIdentities == ["codex:email:user@example.com"])
    }

    @Test
    func `an email only auth produces the email identity`() {
        // AccountIdentityComputerTests.swift, `Codex with only email returns email-only set`.
        let auth = CodexAuth(accessToken: "t", email: "user@example.com")

        #expect(auth.accountIdentities == ["codex:email:user@example.com"])
    }

    @Test
    func `an account only auth produces no identity`() {
        let auth = CodexAuth(accessToken: "t", accountID: "org-abc")

        #expect(auth.accountIdentities.isEmpty)
    }

    @Test
    func `identity values are normalised exactly like AccountIdentityNormalize`() {
        // AccountIdentityComputerTests.swift, `normalize byte-equals iOS shared contract`.
        let accented = CodexAuth(accessToken: "t", email: "Café@Example.com")
        let decomposed = CodexAuth(accessToken: "t", email: "cafe\u{0301}@example.com")
        let separators = CodexAuth(accessToken: "t", email: " A:b|c/d@example.com ")
        let blank = CodexAuth(accessToken: "t", accountID: "   ", email: "")

        #expect(accented.accountIdentities == ["codex:email:caf%C3%A9@example.com"])
        #expect(decomposed.accountIdentities == ["codex:email:caf%C3%A9@example.com"])
        #expect(separators.accountIdentities == ["codex:email:a%3Ab%7Cc%2Fd@example.com"])
        #expect(blank.accountIdentities.isEmpty)
    }

    @Test
    func `very long identity values are capped with a digest suffix`() throws {
        // AccountIdentityComputerTests.swift, `Over-limit value cap uses stable SHA-256 suffix`.
        let auth = CodexAuth(accessToken: "t", email: String(repeating: "a", count: 356))
        let identity = try #require(auth.accountIdentities.first)
        let value = identity.dropFirst("codex:email:".count)

        #expect(value.count == 256)
        #expect(value.hasSuffix("#sha256#9bad493076a15c3d04cb2e1f41607ef0f47270f8a79ebf1620bbb9d3e31e191e"))
    }

    // MARK: - Reader and file location

    @Test
    func `the auth file defaults to dot codex in the home directory`() throws {
        let home = try Support.Home()
        defer { home.remove() }

        #expect(home.reader().authFileURL.standardizedFileURL == home.defaultCodexHome
            .appendingPathComponent("auth.json").standardizedFileURL)
    }

    @Test
    func `CODEX_HOME overrides the default and blank values are ignored`() throws {
        let home = try Support.Home()
        defer { home.remove() }
        let custom = home.root.appendingPathComponent("custom-codex", isDirectory: true)

        #expect(home.reader(codexHome: custom).authFileURL.standardizedFileURL == custom
            .appendingPathComponent("auth.json").standardizedFileURL)

        for blank in ["", "   "] {
            let reader = CodexAuthReader(environment: ["CODEX_HOME": blank], homeDirectory: home.root)
            #expect(reader.authFileURL.standardizedFileURL == home.defaultCodexHome
                .appendingPathComponent("auth.json").standardizedFileURL)
        }
    }

    @Test
    func `the reader reads the file under CODEX_HOME and not the default one`() throws {
        let home = try Support.Home()
        defer { home.remove() }
        let custom = home.root.appendingPathComponent("custom-codex", isDirectory: true)
        try home.writeAuth(Support.authJSON(accessToken: "default-token"))
        try home.writeAuth(Support.authJSON(accessToken: "custom-token"), in: custom)

        #expect(try home.reader().read().get().accessToken == "default-token")
        #expect(try home.reader(codexHome: custom).read().get().accessToken == "custom-token")
    }

    @Test
    func `a missing file is notFound and an unreadable one is unreadable`() throws {
        let home = try Support.Home()
        defer { home.remove() }

        #expect(home.reader().read() == .failure(.notFound))

        try home.writeAuth("{ truncated")
        #expect(home.reader().read() == .failure(.unreadable))
    }

    @Test
    func `auth descriptions never include the token`() {
        let auth = CodexAuth(accessToken: "super-secret-token", accountID: "account-123", email: "a@b.c")

        #expect(!String(describing: auth).contains("super-secret-token"))
        #expect(!String(reflecting: auth).contains("super-secret-token"))
    }
}
