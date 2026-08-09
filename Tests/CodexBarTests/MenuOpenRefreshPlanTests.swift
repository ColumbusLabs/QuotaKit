import CodexBarCore
import Testing
@testable import CodexBar

struct MenuOpenRefreshPlanTests {
    @Test
    func `refresh all selects every enabled provider concurrently`() {
        let plan = MenuOpenRefreshPlan.resolve(.init(
            refreshAllOnOpen: true,
            enabledProviders: [.codex, .claude, .grok],
            visibleProviders: [.codex],
            refreshingProviders: [],
            staleProviders: [],
            missingProviders: []))

        #expect(plan.providers == [.codex, .claude, .grok])
        #expect(plan.scheduling == .concurrent)
        #expect(plan.refreshCodexDashboard)
    }

    @Test
    func `refresh all skips dashboard refresh when codex is disabled`() {
        let plan = MenuOpenRefreshPlan.resolve(.init(
            refreshAllOnOpen: true,
            enabledProviders: [.claude, .grok],
            visibleProviders: [.claude],
            refreshingProviders: [],
            staleProviders: [],
            missingProviders: []))

        #expect(plan.providers == [.claude, .grok])
        #expect(!plan.refreshCodexDashboard)
    }

    @Test
    func `ordinary refresh selects only visible enabled retries sequentially`() {
        let plan = MenuOpenRefreshPlan.resolve(.init(
            refreshAllOnOpen: false,
            enabledProviders: [.codex, .claude, .grok],
            visibleProviders: [.grok, .codex, .claude, .cursor],
            refreshingProviders: [.grok],
            staleProviders: [.codex],
            missingProviders: [.claude, .cursor]))

        #expect(plan.providers == [.grok, .codex, .claude])
        #expect(plan.scheduling == .sequential)
        #expect(!plan.refreshCodexDashboard)
    }

    @Test
    func `ordinary refresh skips fresh providers`() {
        let plan = MenuOpenRefreshPlan.resolve(.init(
            refreshAllOnOpen: false,
            enabledProviders: [.codex],
            visibleProviders: [.codex],
            refreshingProviders: [],
            staleProviders: [],
            missingProviders: []))

        #expect(plan.providers.isEmpty)
    }
}
