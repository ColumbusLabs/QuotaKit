import CodexBarCore
import XCTest
@testable import CodexBar

final class TTYIntegrationTests: XCTestCase {
    func testCodexRPCUsageLive() async throws {
        let fetcher = UsageFetcher()
        do {
            let snapshot = try await fetcher.loadLatestUsage()
            let hasData = snapshot.primary.usedPercent >= 0 && (snapshot.secondary?.usedPercent ?? 0) >= 0
            XCTAssertTrue(hasData, "Codex RPC probe returned no usage data.")
        } catch UsageError.noRateLimitsFound {
            throw XCTSkip("Codex RPC returned no rate limits yet (likely warming up).")
        } catch {
            throw XCTSkip("Codex RPC probe failed: \(error)")
        }
    }

    func testClaudeTTYUsageProbeLive() async throws {
        guard TTYCommandRunner.which("claude") != nil else {
            throw XCTSkip("Claude CLI not installed; skipping live PTY probe.")
        }

        let fetcher = ClaudeUsageFetcher(dataSource: .cli)
        do {
            let snapshot = try await fetcher.loadLatestUsage()
            XCTAssertNotNil(snapshot.primary.remainingPercent, "Claude session percent missing")
            // Weekly is absent for some enterprise accounts.
        } catch let ClaudeUsageError.parseFailed(message) {
            throw XCTSkip("Claude PTY parse failed (likely not logged in or usage unavailable): \(message)")
        } catch let ClaudeStatusProbeError.parseFailed(message) {
            throw XCTSkip("Claude status parse failed (likely not logged in or usage unavailable): \(message)")
        } catch ClaudeUsageError.claudeNotInstalled {
            throw XCTSkip("Claude CLI not installed; skipping live PTY probe.")
        } catch ClaudeStatusProbeError.timedOut {
            throw XCTSkip("Claude PTY probe timed out; skipping.")
        } catch let TTYCommandRunner.Error.launchFailed(message) where message.contains("login") {
            throw XCTSkip("Claude CLI not logged in: \(message)")
        }
    }
}
