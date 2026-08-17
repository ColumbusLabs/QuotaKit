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
        let redacted = try CodexBarCLI.serveOperationKey(
            kind: "dashboard-\(DashboardIdentityMode.redacted.rawValue)",
            provider: nil)
        let full = try CodexBarCLI.serveOperationKey(
            kind: "dashboard-\(DashboardIdentityMode.full.rawValue)",
            provider: nil)

        #expect(redacted != full)
    }
}
