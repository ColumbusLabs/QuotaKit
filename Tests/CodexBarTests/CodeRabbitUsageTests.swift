import Foundation
import Testing
@testable import CodexBarCore

struct CodeRabbitUsageTests {
    private struct StubCLI {
        let directory: URL
        let executable: URL
        let invocations: URL

        func environment(authStatus: String, exitCode: Int32 = 0) -> [String: String] {
            [
                "CODERABBIT_CLI_PATH": self.executable.path,
                "CODERABBIT_TEST_AUTH_STATUS": authStatus,
                "CODERABBIT_TEST_AUTH_EXIT_CODE": String(exitCode),
                "CODERABBIT_TEST_INVOCATIONS": self.invocations.path,
            ]
        }
    }

    private func makeStubCLI() throws -> StubCLI {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeRabbitCLIProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("coderabbit")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$CODERABBIT_TEST_INVOCATIONS"
        if [ "$1" = "auth" ] && [ "$2" = "status" ] && [ "$3" = "--agent" ]; then
            printf '%s\\n' "$CODERABBIT_TEST_AUTH_STATUS"
            exit "${CODERABBIT_TEST_AUTH_EXIT_CODE:-0}"
        fi
        if [ "$1" = "usage" ]; then
            [ "$NO_COLOR" = "1" ] || exit 3
            printf 'Your reviews: 23\\n'
            printf 'Usage billing: included\\n' >&2
            exit 0
        fi
        exit 2
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return StubCLI(
            directory: directory,
            executable: executable,
            invocations: directory.appendingPathComponent("invocations.txt"))
    }

    private func expectAuthFailure(
        _ expected: CodeRabbitUsageError,
        stub: StubCLI,
        authStatus: String,
        exitCode: Int32 = 0) async throws
    {
        do {
            _ = try await CodeRabbitCLIProbe().fetch(
                environment: stub.environment(authStatus: authStatus, exitCode: exitCode))
            Issue.record("Expected the authentication preflight to stop the usage command")
        } catch let error as CodeRabbitUsageError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected authentication preflight error: \(error)")
        }

        let invocations = try String(contentsOf: stub.invocations, encoding: .utf8)
        #expect(invocations == "auth status --agent\n")
    }

    @Test
    func `parses cli report into bounded generic detail rows`() throws {
        let now = Date(timeIntervalSince1970: 1_789_700_000)
        let report = """
        \u{1B}[2mOrganization : Example Team\u{1B}[0m
        User : reviewer
        Plan : Pro
        Your reviews : 17
        Usage billing : $42.00: monthly cap
        Period resets : 2026-09-30
        """

        let parsed = try CodeRabbitUsageParser.parse(usageText: report, now: now)
        let usage = parsed.toUsageSnapshot()

        #expect(parsed.organization == "Example Team")
        #expect(parsed.user == "reviewer")
        #expect(parsed.plan == "Pro")
        #expect(parsed.reviewsCount == 17)
        #expect(parsed.usageBilling == "$42.00: monthly cap")
        #expect(parsed.periodResets == "2026-09-30")
        #expect(parsed.updatedAt == now)
        #expect(usage.primary == nil)
        #expect(usage.secondary == nil)
        #expect(usage.tertiary == nil)
        #expect(!usage.hasRateLimitWindows)
        #expect(usage.detailRow(label: "Reviews")?.value == "17")
        #expect(usage.detailRow(label: "Usage billing")?.value == "$42.00: monthly cap")
        #expect(usage.detailRow(label: "Period resets")?.value == "2026-09-30")
        #expect(usage.identity?.providerID == .coderabbit)
        #expect(usage.accountOrganization(for: .coderabbit) == "Example Team")
        #expect(usage.loginMethod(for: .coderabbit) == "Pro")
        #expect(usage.identity(for: .coderabbit)?.accountID == "reviewer")
        #expect(usage.subscriptionRenewsAt == nil)
    }

    @Test
    func `parses partial reports without treating negative review counts as usage`() throws {
        let billingOnly = try CodeRabbitUsageParser.parse(usageText: "Usage billing: inactive")
        #expect(billingOnly.reviewsCount == nil)
        #expect(billingOnly.usageBilling == "inactive")

        let negative = try CodeRabbitUsageParser.parse(usageText: "Your reviews: -1\nUsage billing: inactive")
        #expect(negative.reviewsCount == nil)
        #expect(negative.usageBilling == "inactive")
    }

    @Test
    func `distinguishes signed out and unrecognized cli output`() {
        #expect(throws: CodeRabbitUsageError.notLoggedIn) {
            try CodeRabbitUsageParser.parse(usageText: "Please log in with coderabbit auth login")
        }
        #expect(throws: CodeRabbitUsageError.parseFailed) {
            try CodeRabbitUsageParser.parse(usageText: "CodeRabbit CLI 1.2.3")
        }
    }

    @Test
    func `cli probe checks auth before usage and combines usage output streams`() async throws {
        let stub = try self.makeStubCLI()
        defer { try? FileManager.default.removeItem(at: stub.directory) }

        let snapshot = try await CodeRabbitCLIProbe().fetch(
            environment: stub.environment(authStatus: #"{"authenticated":true}"#))

        #expect(snapshot.reviewsCount == 23)
        #expect(snapshot.usageBilling == "included")
        let invocations = try String(contentsOf: stub.invocations, encoding: .utf8)
        #expect(invocations == "auth status --agent\nusage\n")
    }

    @Test
    func `cli probe rejects a signed out auth status before usage`() async throws {
        let stub = try self.makeStubCLI()
        defer { try? FileManager.default.removeItem(at: stub.directory) }

        try await self.expectAuthFailure(
            .notLoggedIn,
            stub: stub,
            authStatus: #"{"authenticated":false}"#)
    }

    @Test(arguments: ["not JSON", #"{}"#, #"{"authenticated":"true"}"#])
    func `cli probe rejects ambiguous auth status before usage`(authStatus: String) async throws {
        let stub = try self.makeStubCLI()
        defer { try? FileManager.default.removeItem(at: stub.directory) }

        try await self.expectAuthFailure(.parseFailed, stub: stub, authStatus: authStatus)
    }

    @Test
    func `cli probe rejects an auth status command failure before usage`() async throws {
        let stub = try self.makeStubCLI()
        defer { try? FileManager.default.removeItem(at: stub.directory) }

        try await self.expectAuthFailure(
            .parseFailed,
            stub: stub,
            authStatus: #"{"authenticated":true}"#,
            exitCode: 17)
    }

    @Test
    func `invalid explicit cli override does not fall through to path lookup`() {
        let executable = CodeRabbitCLIProbe.executable(
            environment: ["CODERABBIT_CLI_PATH": "/missing/coderabbit"],
            loginPATH: ["/bin", "/usr/bin"])
        #expect(executable == nil)
    }

    @Test
    func `descriptor is disabled by default and uses only cli sources`() {
        let descriptor = CodeRabbitProviderDescriptor.descriptor
        #expect(descriptor.id == .coderabbit)
        #expect(descriptor.metadata.displayName == "CodeRabbit")
        #expect(!descriptor.metadata.defaultEnabled)
        #expect(descriptor.metadata.widgetSelectable == false)
        #expect(descriptor.fetchPlan.sourceModes == [.auto, .cli])
        #expect(descriptor.tokenCost.supportsTokenCost == false)
        #expect(descriptor.branding.color.hexString == "#FF5C35")
    }
}
