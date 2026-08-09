import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIUnificationGoldenTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func `four provider text output golden`() {
        let outputs = Self.fixtures.map { fixture in
            CLIRenderer.renderText(
                provider: fixture.provider,
                snapshot: fixture.snapshot,
                credits: nil,
                context: RenderContext(
                    header: fixture.provider.rawValue,
                    status: nil,
                    useColor: false,
                    resetStyle: .absolute),
                now: Self.now)
        }

        #expect(outputs.count == 4)
        #expect(outputs[0].contains("== codex =="))
        #expect(outputs[0].contains("Session: 90% left"))
        #expect(outputs[0].contains("Weekly: 80% left"))
        #expect(outputs[1].contains("== claude =="))
        #expect(outputs[1].contains("Session: 70% left"))
        #expect(outputs[1].contains("Weekly: 60% left"))
        #expect(outputs[2].contains("== cursor =="))
        #expect(outputs[2].contains("Total: 50% left"))
        #expect(outputs[2].contains("Auto: 40% left"))
        #expect(outputs[2].contains("API: 30% left"))
        #expect(outputs[3].contains("== grok =="))
        #expect(outputs[3].contains("Weekly: 20% left"))
    }

    @Test
    func `four provider cards output golden`() {
        let outputs = Self.fixtures.map { fixture in
            let card = CLICardsRenderer.makeCard(CLICardBuildInput(
                provider: fixture.provider,
                snapshot: fixture.snapshot,
                credits: nil,
                source: "fixture",
                status: nil,
                notes: [],
                useColor: false,
                resetStyle: .absolute,
                weeklyWorkDays: nil,
                now: Self.now))
            return CLICardsRenderer.render(
                cards: [card],
                failures: [],
                terminalWidth: 42,
                useColor: false)
        }

        #expect(outputs.count == 4)
        #expect(outputs[0].contains("Codex [fixture]"))
        #expect(outputs[1].contains("Claude [fixture]"))
        #expect(outputs[2].contains("Cursor [fixture]"))
        #expect(outputs[3].contains("Grok [fixture]"))
        for output in outputs {
            #expect(output.contains("╭"))
            #expect(output.contains("╰"))
        }
    }

    @Test
    func `four provider JSON output golden`() throws {
        let payloads = Self.fixtures.map { fixture in
            ProviderPayload(
                provider: fixture.provider,
                account: nil,
                version: nil,
                source: "fixture",
                status: nil,
                usage: fixture.snapshot,
                credits: nil,
                openaiDashboard: nil,
                error: nil,
                pace: CLIRenderer.providerPacePayload(
                    provider: fixture.provider,
                    snapshot: fixture.snapshot,
                    now: Self.now))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payloads)
        let output = try #require(String(data: data, encoding: .utf8))

        let expectedProviderLines = [
            "    \"provider\" : \"codex\",",
            "    \"provider\" : \"claude\",",
            "    \"provider\" : \"cursor\",",
            "    \"provider\" : \"grok\",",
        ]
        #expect(expectedProviderLines.allSatisfy(output.contains))
        #expect(output.components(separatedBy: "\"source\" : \"fixture\"").count - 1 == 4)
    }

    private struct Fixture {
        let provider: UsageProvider
        let snapshot: UsageSnapshot
    }

    private static let fixtures = [
        Fixture(provider: .codex, snapshot: Self.snapshot(
            primaryUsed: 10,
            secondaryUsed: 20,
            tertiaryUsed: nil)),
        Fixture(provider: .claude, snapshot: Self.snapshot(
            primaryUsed: 30,
            secondaryUsed: 40,
            tertiaryUsed: nil)),
        Fixture(provider: .cursor, snapshot: Self.snapshot(
            primaryUsed: 50,
            secondaryUsed: 60,
            tertiaryUsed: 70)),
        Fixture(provider: .grok, snapshot: Self.snapshot(
            primaryUsed: 80,
            secondaryUsed: nil,
            tertiaryUsed: nil,
            primaryMinutes: 10080)),
    ]

    private static func snapshot(
        primaryUsed: Double,
        secondaryUsed: Double?,
        tertiaryUsed: Double?,
        primaryMinutes: Int = 300) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: self.window(used: primaryUsed, minutes: primaryMinutes),
            secondary: secondaryUsed.map { Self.window(used: $0, minutes: 10080) },
            tertiary: tertiaryUsed.map { Self.window(used: $0, minutes: 1440) },
            updatedAt: self.now)
    }

    private static func window(used: Double, minutes: Int) -> RateWindow {
        RateWindow(
            usedPercent: used,
            windowMinutes: minutes,
            resetsAt: nil,
            resetDescription: nil)
    }
}
