import Commander
import Foundation
import Testing
@testable import CodexBarCLI

/// `quotakit serve` defaults dashboard identity to redacted and only exposes full
/// account identities after an explicit command-line opt-in.
struct CLIServeDashboardIdentityTests {
    @Test
    func `an absent identity flag decodes to redacted`() {
        #expect(CodexBarCLI.decodeDashboardIdentityMode(from: ParsedValues(
            positional: [],
            options: [:],
            flags: [])) == .redacted)
    }

    @Test
    func `dashboard operation key separates identity modes`() throws {
        let redacted = try CodexBarCLI.serveDashboardOperationKey(
            identityMode: .redacted,
            usageBarsShowUsed: false,
            provider: nil)
        let full = try CodexBarCLI.serveDashboardOperationKey(
            identityMode: .full,
            usageBarsShowUsed: false,
            provider: nil)

        #expect(redacted != full)
    }

    @Test
    func `dashboard operation key separates usage bars fill preferences`() throws {
        let used = try CodexBarCLI.serveDashboardOperationKey(
            identityMode: .full,
            usageBarsShowUsed: true,
            provider: nil)
        let remaining = try CodexBarCLI.serveDashboardOperationKey(
            identityMode: .full,
            usageBarsShowUsed: false,
            provider: nil)

        #expect(used != remaining)
    }

    @Test
    func `warm dashboard responses retain the requested fill mode through toggles`() async throws {
        let (_, cache) = makeServeTestCache()
        let counter = DashboardFillBuildCounter()
        for showUsed in [false, true, false, true] {
            let key = try CodexBarCLI.serveDashboardOperationKey(
                identityMode: .redacted,
                usageBarsShowUsed: showUsed,
                provider: "codex")
            let response = await CodexBarCLI.cachedServeResponse(
                key: key, cache: cache, refreshInterval: 60, configFingerprint: "synthetic-config")
            {
                let build = await counter.increment()
                return CLILocalHTTPResponse(
                    status: .ok,
                    body: Data("{\"usageBarsShowUsed\":\(showUsed),\"build\":\(build)}".utf8))
            }
            let payload = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
            #expect(payload["usageBarsShowUsed"] as? Bool == showUsed)
        }
        #expect(await counter.count == 2)
    }
}

private actor DashboardFillBuildCounter {
    private(set) var count = 0

    func increment() -> Int {
        self.count += 1
        return self.count
    }
}
