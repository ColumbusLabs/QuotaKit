import CodexBarCore
import Testing

struct LogRedactorTests {
    @Test
    func `email is redacted`() {
        let redacted = LogRedactor.redact("Contact: user@example.com")

        #expect(redacted == "Contact: <redacted-email>")
    }

    @Test
    func `cookie header is redacted`() {
        let redacted = LogRedactor.redact("Cookie: session=secret; preference=value")

        #expect(redacted == "Cookie: <redacted>")
    }

    @Test
    func `authorization header is redacted`() {
        let redacted = LogRedactor.redact("Authorization: Bearer secret-token")

        #expect(redacted == "Authorization: <redacted>")
    }

    @Test
    func `standalone bearer credential is redacted`() {
        let redacted = LogRedactor.redact("request failed for bearer secret-token")

        #expect(redacted == "request failed for Bearer <redacted>")
    }

    @Test
    func `ordinary text is unchanged`() {
        let input = "Provider refresh completed"

        #expect(LogRedactor.redact(input) == input)
    }
}
