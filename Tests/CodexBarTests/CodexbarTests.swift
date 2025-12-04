import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite
struct CodexBarTests {
    @Test
    func iconRendererProducesTemplateImage() {
        let image = IconRenderer.makeIcon(
            primaryRemaining: 50,
            weeklyRemaining: 75,
            creditsRemaining: 500,
            stale: false,
            style: .codex)
        #expect(image.isTemplate)
        #expect(image.size.width > 0)
    }

    @Test
    func accountInfoParsesAuthToken() throws {
        let tmp = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
            create: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let token = Self.fakeJWT(email: "user@example.com", plan: "pro")
        let auth = ["tokens": ["idToken": token]]
        let data = try JSONSerialization.data(withJSONObject: auth)
        let authURL = tmp.appendingPathComponent("auth.json")
        try data.write(to: authURL)

        let fetcher = UsageFetcher(environment: ["CODEX_HOME": tmp.path])
        let account = fetcher.loadAccountInfo()
        #expect(account.email == "user@example.com")
        #expect(account.plan == "pro")
    }

    private static func fakeJWT(email: String, plan: String) -> String {
        let header = (try? JSONSerialization.data(withJSONObject: ["alg": "none"])) ?? Data()
        let payload = (try? JSONSerialization.data(withJSONObject: [
            "email": email,
            "chatgpt_plan_type": plan,
        ])) ?? Data()
        func b64(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }
        return "\(b64(header)).\(b64(payload))."
    }
}
