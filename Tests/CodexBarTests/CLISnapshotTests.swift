import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLISnapshotTests {
    @Test
    func `renders text snapshot for Codex`() {
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "user@example.com",
            accountOrganization: nil,
            loginMethod: "pro")
        let snapshot = UsageSnapshot(
            primary: .init(
                usedPercent: 12,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: "today at 3:00 PM"),
            secondary: .init(
                usedPercent: 25,
                windowMinutes: 10080,
                resetsAt: nil,
                resetDescription: "Friday at 9:00 AM"),
            updatedAt: Date(timeIntervalSince1970: 0),
            identity: identity)

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snapshot,
            credits: CreditsSnapshot(remaining: 42, events: [], updatedAt: Date()),
            context: RenderContext(
                header: "Codex 1.2.3 (codex-cli)",
                status: ProviderStatusPayload(
                    indicator: .minor,
                    description: "Degraded performance",
                    updatedAt: Date(timeIntervalSince1970: 0),
                    url: "https://status.example.com"),
                useColor: false,
                resetStyle: .absolute))

        #expect(output.contains("== Codex 1.2.3 (codex-cli) =="))
        #expect(output.contains("Session: 88% left"))
        #expect(output.contains("Weekly: 75% left"))
        #expect(output.contains("Credits: 42"))
        #expect(output.contains("Account: user@example.com"))
        #expect(output.contains("Plan: Pro 20x"))
        #expect(output.contains("Status: Partial outage – Degraded performance"))
    }

    @Test
    func `renders Codex reset credits`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let resetCredits = CodexRateLimitResetCreditsSnapshot(
            credits: [
                CodexRateLimitResetCredit(
                    id: "available",
                    resetType: "codex_rate_limits",
                    status: .available,
                    grantedAt: Date(timeIntervalSince1970: 0),
                    expiresAt: now.addingTimeInterval(7200),
                    redeemStartedAt: nil,
                    redeemedAt: nil,
                    title: nil,
                    description: nil),
                CodexRateLimitResetCredit(
                    id: "expired",
                    resetType: "codex_rate_limits",
                    status: .available,
                    grantedAt: Date(timeIntervalSince1970: 0),
                    expiresAt: now,
                    redeemStartedAt: nil,
                    redeemedAt: nil,
                    title: nil,
                    description: nil),
            ],
            availableCount: 2,
            updatedAt: now)
        let snapshot = UsageSnapshot(
            primary: .init(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            codexResetCredits: resetCredits,
            updatedAt: now)

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snapshot,
            credits: nil,
            context: Self.context(header: "Codex"),
            now: now)

        #expect(output.contains("Limit Reset Credits: 1 available"))
        #expect(output.contains("Next reset credit expires"))
    }

    @Test
    func `renders Claude session and preserves Max multiplier casing`() {
        let identity = ProviderIdentitySnapshot(
            providerID: .claude,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "Claude Max 5x")
        let snapshot = UsageSnapshot(
            primary: .init(usedPercent: 2, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            identity: identity)

        let output = CLIRenderer.renderText(
            provider: .claude,
            snapshot: snapshot,
            credits: nil,
            context: Self.context(header: "Claude"))

        #expect(output.contains("Session: 98% left"))
        #expect(!output.contains("Weekly:"))
        #expect(output.contains("Plan: Claude Max 5x"))
        #expect(!output.contains("Plan: Claude Max 5X"))
    }

    @Test
    func `renders Cursor rate window labels`() {
        let snapshot = UsageSnapshot(
            primary: .init(usedPercent: 10, windowMinutes: 1440, resetsAt: nil, resetDescription: nil),
            secondary: .init(usedPercent: 20, windowMinutes: 1440, resetsAt: nil, resetDescription: nil),
            tertiary: .init(usedPercent: 30, windowMinutes: 1440, resetsAt: nil, resetDescription: nil),
            updatedAt: Date(timeIntervalSince1970: 0))

        let output = CLIRenderer.renderText(
            provider: .cursor,
            snapshot: snapshot,
            credits: nil,
            context: Self.context(header: "Cursor"))

        #expect(output.contains("Total: 90% left"))
        #expect(output.contains("Auto: 80% left"))
        #expect(output.contains("API: 70% left"))
    }

    @Test
    func `renders Grok weekly usage`() {
        let snapshot = UsageSnapshot(
            primary: .init(usedPercent: 30, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 0))

        let output = CLIRenderer.renderText(
            provider: .grok,
            snapshot: snapshot,
            credits: nil,
            context: Self.context(header: "Grok"))

        #expect(output.contains("Weekly: 70% left"))
    }

    @Test
    func `renders Codex session and weekly pace with distinct wording`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = UsageSnapshot(
            primary: .init(
                usedPercent: 50,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(4 * 60 * 60),
                resetDescription: nil),
            secondary: .init(
                usedPercent: 90,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(2 * 24 * 60 * 60),
                resetDescription: nil),
            updatedAt: now)

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snapshot,
            credits: nil,
            context: Self.context(header: "Codex", resetStyle: .countdown),
            now: now)
        let pace = try #require(CLIRenderer.providerPacePayload(provider: .codex, snapshot: snapshot, now: now))

        #expect(output.contains("Projected empty"))
        #expect(output.contains("Runs out"))
        #expect(pace.primary?.expectedUsedPercent == 20)
        #expect(pace.secondary?.expectedUsedPercent == 71)
    }

    @Test
    func `configured work days affect weekly text and JSON pace`() throws {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let resetsAt = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 14)))
        let now = resetsAt.addingTimeInterval(-72 * 60 * 60)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: .init(
                usedPercent: 60,
                windowMinutes: 10080,
                resetsAt: resetsAt,
                resetDescription: nil),
            updatedAt: now)

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(
                header: "Codex",
                status: nil,
                useColor: false,
                resetStyle: .countdown,
                weeklyWorkDays: 5),
            now: now)
        let pace = try #require(CLIRenderer.providerPacePayload(
            provider: .codex,
            snapshot: snapshot,
            weeklyWorkDays: 5,
            now: now)?.secondary)

        #expect(output.contains("Pace: On pace | Expected 60% used | Lasts until reset"))
        #expect(pace.expectedUsedPercent == 60)
    }

    @Test
    func `Grok duration enables pace`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = UsageSnapshot(
            primary: .init(
                usedPercent: 30,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                resetDescription: nil),
            secondary: nil,
            updatedAt: now)

        let pace = try #require(CLIRenderer.providerPacePayload(provider: .grok, snapshot: snapshot, now: now))
        let primary = try #require(pace.primary)

        #expect(primary.expectedUsedPercent == 43)
        #expect(primary.summary == "13% in reserve | Expected 43% used | Lasts until reset")
    }

    @Test
    func `JSON payload supports every retained provider`() throws {
        let payloads = UsageProvider.allCases.map { provider in
            ProviderPayload(
                provider: provider,
                account: nil,
                version: nil,
                source: "fixture",
                status: nil,
                usage: nil,
                credits: nil,
                openaiDashboard: nil,
                error: nil)
        }

        let data = try JSONEncoder().encode(payloads)
        let objects = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let providers = objects.compactMap { $0["provider"] as? String }

        #expect(providers == ["codex", "claude", "cursor", "grok"])
    }

    @Test
    func `JSON pace rounds derived values`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = UsageSnapshot(
            primary: .init(
                usedPercent: 79,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(5000),
                resetDescription: nil),
            secondary: nil,
            updatedAt: now)
        let payload = ProviderPayload(
            provider: .codex,
            account: nil,
            version: nil,
            source: "codex-cli",
            status: nil,
            usage: snapshot,
            credits: nil,
            openaiDashboard: nil,
            error: nil,
            pace: CLIRenderer.providerPacePayload(provider: .codex, snapshot: snapshot, now: now))

        let data = try JSONEncoder().encode(payload)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let primary = try #require((root["pace"] as? [String: Any])?["primary"] as? [String: Any])

        #expect(primary["expectedUsedPercent"] as? Double == 72)
        #expect(primary["deltaPercent"] as? Double == 7)
        #expect(primary["etaSeconds"] as? Double == 3456)
    }

    @Test
    func `usage JSON preserves missing secondary as null`() throws {
        let snapshot = UsageSnapshot(
            primary: .init(usedPercent: 0, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try JSONEncoder().encode(snapshot)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"secondary\":null"))
    }

    @Test
    func `parses output format`() {
        #expect(OutputFormat(argument: "json") == .json)
        #expect(OutputFormat(argument: "TEXT") == .text)
        #expect(OutputFormat(argument: "invalid") == nil)
    }

    @Test
    func `defaults to usage when no command provided`() {
        #expect(CodexBarCLI.effectiveArgv([]) == ["usage"])
        #expect(CodexBarCLI.effectiveArgv(["--format", "json"]).first == "usage")
        #expect(CodexBarCLI.effectiveArgv(["usage", "--format", "json"]).first == "usage")
    }

    @Test
    func `status line is last and colored for TTY output`() {
        let snapshot = UsageSnapshot(
            primary: .init(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 0))
        let output = CLIRenderer.renderText(
            provider: .claude,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(
                header: "Claude",
                status: ProviderStatusPayload(
                    indicator: .critical,
                    description: "Major outage",
                    updatedAt: nil,
                    url: "https://status.example.com"),
                useColor: true,
                resetStyle: .absolute))

        let lines = output.split(separator: "\n")
        #expect(lines.last?.contains("Status: Critical issue – Major outage") == true)
        #expect(output.contains("\u{001B}[31mStatus"))
    }

    private static func context(
        header: String,
        resetStyle: ResetTimeDisplayStyle = .absolute) -> RenderContext
    {
        RenderContext(
            header: header,
            status: nil,
            useColor: false,
            resetStyle: resetStyle)
    }
}
