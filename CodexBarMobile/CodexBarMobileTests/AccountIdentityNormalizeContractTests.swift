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
    @Test("normalize byte-equals Mac AccountIdentityComputer contract")
    func normalizeMatchesMacContract() {
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

    @Test("maxAccountIdentifierLength matches Mac maxIdentifierLength")
    func maxLengthMatches() {
        // Mac side has `AccountIdentityComputer.maxIdentifierLength = 256`
        // documented as "must equal AccountIdentityNormalize.maxAccountIdentifierLength".
        #expect(AccountIdentityNormalize.maxAccountIdentifierLength == 256)
    }

    @Test("normalize truncates to maxAccountIdentifierLength")
    func truncatesAtCap() {
        let huge = String(repeating: "a", count: AccountIdentityNormalize.maxAccountIdentifierLength + 100)
        let result = AccountIdentityNormalize.normalize(huge)
        #expect(result?.count == AccountIdentityNormalize.maxAccountIdentifierLength)
    }
}
