import CodexBarSync
import Foundation
import Testing

/// iOS mirror of the Mac `AccountIdentityComputerTests.normalizeMatchesSharedContract`
/// test (0.23.3 P1-3). Both files must assert the same expected outputs
/// for the same inputs — that's how we guarantee Mac-written
/// `codex:email:...` identifiers byte-equal what iOS synthesizes from
/// the legacy `accountEmail` fallback.
///
/// If you change either implementation, change the other AND update
/// both tests in the same commit.
@Suite("AccountIdentityNormalize contract pin")
struct AccountIdentityNormalizeContractTests {
    @Test
    func `normalize byte-equals Mac AccountIdentityComputer contract`() {
        let cases: [(String?, String?)] = [
            ("ABC", "abc"),
            ("Café@Example.com", "caf%C3%A9@example.com"),
            (" trailing  ", "trailing"),
            ("cafe\u{0301}@example.com", "caf%C3%A9@example.com"),
            ("a:b|c/d", "a%3Ab%7Cc%2Fd"),
            ("", nil),
            ("   ", nil),
            (nil, nil),
        ]
        for (input, expected) in cases {
            #expect(
                AccountIdentityNormalize.normalize(input) == expected,
                "normalize(\(input ?? "<nil>")) — expected \(expected ?? "<nil>")")
        }
    }

    @Test
    func `maxAccountIdentifierLength matches Mac maxIdentifierLength`() {
        // Mac side has `AccountIdentityComputer.maxIdentifierLength = 256`
        // documented as "must equal AccountIdentityNormalize.maxAccountIdentifierLength".
        #expect(AccountIdentityNormalize.maxAccountIdentifierLength == 256)
    }

    @Test
    func `boundary-length values stay unchanged`() throws {
        let exact = String(repeating: "a", count: AccountIdentityNormalize.maxAccountIdentifierLength)
        let value = try #require(AccountIdentityNormalize.normalize(exact))

        #expect(value == exact)
        #expect(!value.contains("#sha256#"))
    }

    @Test
    func `normalize caps to maxAccountIdentifierLength with digest`() throws {
        let huge = String(repeating: "a", count: AccountIdentityNormalize.maxAccountIdentifierLength + 100)
        let result = AccountIdentityNormalize.normalize(huge)
        let value = try #require(result)
        #expect(value.count == AccountIdentityNormalize.maxAccountIdentifierLength)
        #expect(value.hasSuffix("#sha256#9bad493076a15c3d04cb2e1f41607ef0f47270f8a79ebf1620bbb9d3e31e191e"))
    }

    @Test
    func `over-limit values with the same prefix do not collide`() throws {
        let sharedPrefix = String(repeating: "a", count: AccountIdentityNormalize.maxAccountIdentifierLength + 20)
        let first = AccountIdentityNormalize.normalize(sharedPrefix + "1")
        let second = AccountIdentityNormalize.normalize(sharedPrefix + "2")

        let firstValue = try #require(first)
        let secondValue = try #require(second)
        #expect(firstValue.count == AccountIdentityNormalize.maxAccountIdentifierLength)
        #expect(secondValue.count == AccountIdentityNormalize.maxAccountIdentifierLength)
        #expect(firstValue != secondValue)
    }
}
