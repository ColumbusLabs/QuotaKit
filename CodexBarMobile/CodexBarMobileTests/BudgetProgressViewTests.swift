import CodexBarSync
import Testing
@testable import CodexBarMobile

@Suite("Budget progress presentation")
struct BudgetProgressViewTests {
    @Test
    @MainActor
    func `zero allowance keeps spend visible without showing a false budget`() {
        let view = BudgetProgressView(
            budget: SyncBudgetSnapshot(
                usedAmount: 8.32,
                limitAmount: 0,
                currencyCode: "USD",
                period: "Monthly",
                resetsAt: nil))

        #expect(!view.showsAllowance)
    }

    @Test
    @MainActor
    func `positive allowance retains budget progress presentation`() {
        let view = BudgetProgressView(
            budget: SyncBudgetSnapshot(
                usedAmount: 8.32,
                limitAmount: 20,
                currencyCode: "USD",
                period: "Monthly",
                resetsAt: nil))

        #expect(view.showsAllowance)
    }
}
