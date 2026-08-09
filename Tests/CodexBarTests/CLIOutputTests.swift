import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct CLIOutputTests {
    @Test
    func `output preferences JSON only forces JSON`() {
        let output = CLIOutputPreferences.from(argv: ["--json-only"])
        #expect(output.jsonOnly)
        #expect(output.format == .json)
    }

    @Test
    func `CLI error payload is a JSON array`() throws {
        let payload = CodexBarCLI.makeCLIErrorPayload(
            message: "Nope",
            code: .failure,
            kind: .args,
            pretty: false)
        let data = try #require(payload?.data(using: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [Any])
        let first = try #require(json.first as? [String: Any])
        let error = try #require(first["error"] as? [String: Any])

        #expect(first["provider"] as? String == "cli")
        #expect(error["message"] as? String == "Nope")
    }

    @Test
    func `exit omits generic error when a command already emitted its payload`() {
        #expect(!CodexBarCLI.shouldPrintExitError(code: .success, message: nil))
        #expect(!CodexBarCLI.shouldPrintExitError(code: .failure, message: nil))
        #expect(CodexBarCLI.shouldPrintExitError(code: .failure, message: "Nope"))
    }

    @Test
    func `text renderer includes generic provider detail rows`() {
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [.makeSection(title: "Usage summary", rows: [
                .makeRow(label: "Requests", value: "42"),
                .makeRow(label: "Tokens", value: "150", secondaryValue: "cached 20"),
            ])],
            updatedAt: Date(timeIntervalSince1970: 0))
        let text = CLIRenderer.renderText(
            provider: .cursor,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(
                header: "Cursor (web)",
                status: nil,
                useColor: false,
                resetStyle: .countdown))

        #expect(text.contains("Requests: 42"))
        #expect(text.contains("Tokens: 150 · cached 20"))
    }

    @Test
    func `text renderer includes Claude extra usage balance`() {
        let now = Date(timeIntervalSince1970: 0)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 5,
                limit: 20,
                currencyCode: "USD",
                period: "Monthly cap",
                balance: 100,
                updatedAt: now),
            updatedAt: now)
        let text = CLIRenderer.renderText(
            provider: .claude,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(
                header: "Claude (web)",
                status: nil,
                useColor: false,
                resetStyle: .countdown))

        #expect(text.contains("Extra usage balance: $100.00"))
    }

    @Test
    func `text renderer does not show zero cost for Claude balance only snapshot`() {
        let now = Date(timeIntervalSince1970: 0)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 0,
                limit: 0,
                currencyCode: "USD",
                period: "Extra usage",
                balance: 100,
                updatedAt: now),
            updatedAt: now)
        let text = CLIRenderer.renderText(
            provider: .claude,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(
                header: "Claude (web)",
                status: nil,
                useColor: false,
                resetStyle: .countdown))

        #expect(text.contains("Extra usage balance: $100.00"))
        #expect(!text.contains("Cost: 0.0 / 0.0"))
    }
}
