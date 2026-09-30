import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct AntigravityCLIProjectionTests {
    @Test
    func `text and card projections use quota summary lanes and mark unknown usage unavailable`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 95, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 90, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: RateWindow(usedPercent: 80, windowMinutes: 43200, resetsAt: nil, resetDescription: nil),
            extraRateWindows: [
                NamedRateWindow(
                    id: "antigravity-quota-summary-gemini-5h",
                    title: "Gemini 5-hour",
                    window: RateWindow(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: nil)),
                NamedRateWindow(
                    id: "antigravity-quota-summary-3p-weekly",
                    title: "Claude/GPT weekly",
                    window: RateWindow(usedPercent: 88, windowMinutes: 10080, resetsAt: nil, resetDescription: nil)),
                NamedRateWindow(
                    id: "antigravity-quota-summary-future-window",
                    title: "Future quota",
                    window: RateWindow(usedPercent: 0, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                    usageKnown: false),
            ],
            updatedAt: now)
        let context = RenderContext(
            header: "Antigravity",
            status: nil,
            useColor: false,
            resetStyle: .absolute)

        let text = CLIRenderer.renderText(
            provider: .antigravity,
            snapshot: snapshot,
            credits: nil,
            context: context,
            now: now)
        let metrics = CLIRenderer.collectCardMetrics(
            provider: .antigravity,
            snapshot: snapshot,
            resetStyle: .absolute,
            now: now)
        let extraLines = CLIRenderer.collectCardExtraLines(
            provider: .antigravity,
            snapshot: snapshot,
            credits: nil,
            context: context,
            now: now)

        #expect(text.contains("Gemini 5-hour: 88% left"))
        #expect(text.contains("Claude/GPT weekly: 12% left"))
        #expect(text.contains("Future quota: Unavailable"))
        #expect(!text.contains("Gemini Models:"))
        #expect(!text.contains("Weekly:"))
        #expect(!text.contains("Future quota: 100% left"))
        #expect(metrics.map(\.label) == ["Gemini 5-hour", "Claude/GPT weekly"])
        #expect(metrics.map(\.remainingPercent) == [88, 12])
        #expect(extraLines.contains { $0.contains("Future quota: Unavailable") })
        #expect(!extraLines.contains { $0.contains("Future quota: 100% left") })
    }

    @Test
    func `auto fallback summary reports ordered safe outcomes only for Antigravity Auto`() throws {
        let attempts = [
            ProviderFetchAttempt(
                strategyID: "antigravity.app-local",
                kind: .localProbe,
                wasAvailable: true,
                errorDescription: "Network timeout for token=fixture-secret"),
            ProviderFetchAttempt(
                strategyID: "antigravity.cli-https",
                kind: .cli,
                wasAvailable: false,
                errorDescription: nil),
            ProviderFetchAttempt(
                strategyID: "antigravity.oauth",
                kind: .oauth,
                wasAvailable: true,
                errorDescription: nil),
        ]

        let summary = try #require(CodexBarCLI.antigravityAutoFallbackSummary(
            provider: .antigravity,
            sourceMode: .auto,
            attempts: attempts))

        #expect(summary == "Antigravity Auto source outcomes: antigravity.app-local: failed (network) -> " +
            "antigravity.cli-https: skipped -> antigravity.oauth: succeeded")
        #expect(!summary.contains("fixture-secret"))
        #expect(CodexBarCLI.antigravityAutoFallbackSummary(
            provider: .antigravity,
            sourceMode: .cli,
            attempts: attempts) == nil)
        #expect(CodexBarCLI.antigravityAutoFallbackSummary(
            provider: .codex,
            sourceMode: .auto,
            attempts: attempts) == nil)
    }

    @Test
    func `legacy quota snapshots retain the generic CLI projection`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 20, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000))

        let antigravityMetrics = CLIRenderer.collectCardMetrics(
            provider: .antigravity,
            snapshot: snapshot,
            resetStyle: .absolute)
        let codexMetrics = CLIRenderer.collectCardMetrics(
            provider: .codex,
            snapshot: snapshot,
            resetStyle: .absolute)
        let antigravityText = CLIRenderer.renderText(
            provider: .antigravity,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(
                header: "Antigravity",
                status: nil,
                useColor: false,
                resetStyle: .absolute))

        #expect(antigravityMetrics.count == 2)
        #expect(codexMetrics.count == 2)
        #expect(antigravityMetrics.map(\.remainingPercent) == [90, 80])
        #expect(antigravityText.contains("Gemini Models: 90% left"))
        #expect(antigravityText.contains("Claude and GPT: 80% left"))
    }
}
