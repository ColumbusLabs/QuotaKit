import CodexBarCore
import Testing
@testable import CodexBar

extension UsageStorePlanUtilizationTests {
    @MainActor
    @Test
    func `global refresh tail does not keep completed provider plan card loading`() {
        let store = Self.makeStore()
        store._setSnapshotForTesting(nil, provider: .claude)
        store.isRefreshing = true
        store.refreshingProviders.insert(.claude)

        #expect(store.shouldShowRefreshingMenuCard(for: .claude))
        #expect(store.shouldShowRefreshingMenuCardIndicator(for: .claude))
        #expect(store.shouldHidePlanUtilizationMenuItem(for: .claude))

        store.refreshingProviders.remove(.claude)

        #expect(store.isRefreshing)
        #expect(store.refreshingProviders.isEmpty)
        #expect(!store.shouldShowRefreshingMenuCard(for: .claude))
        #expect(!store.shouldShowRefreshingMenuCardIndicator(for: .claude))
        #expect(!store.shouldHidePlanUtilizationMenuItem(for: .claude))
    }
}
