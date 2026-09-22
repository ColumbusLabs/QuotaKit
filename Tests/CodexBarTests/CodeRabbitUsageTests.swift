import Foundation
import Testing
@testable import CodexBarCore

struct CodeRabbitUsageTests {
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
    func `cli probe invokes usage and combines stdout with stderr`() async throws {
        let script = """
        [ "$1" = "usage" ] || exit 2
        [ "$NO_COLOR" = "1" ] || exit 3
        printf 'Your reviews: 23\\n'
        printf 'Usage billing: included\\n' >&2
        """

        let snapshot = try await CodeRabbitCLIProbe(usageArguments: ["-c", script, "coderabbit", "usage"])
            .fetch(environment: ["CODERABBIT_CLI_PATH": "/bin/sh"])

        #expect(snapshot.reviewsCount == 23)
        #expect(snapshot.usageBilling == "included")
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
