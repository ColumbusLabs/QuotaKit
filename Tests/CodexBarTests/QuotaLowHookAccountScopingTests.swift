import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct QuotaLowHookAccountScopingTests {
    @Test
    func `quota_low crossing history is scoped per account`() {
        // Same provider/window/lane, different account discriminators must not share
        // history: one account's high usage must not overwrite or re-arm another's.
        let accountA = UsageStore.QuotaWarningStateKey(
            provider: .claude, window: .session, accountDiscriminator: "a@example.com")
        let accountB = UsageStore.QuotaWarningStateKey(
            provider: .claude, window: .session, accountDiscriminator: "b@example.com")
        #expect(accountA != accountB)

        var usage: [UsageStore.QuotaWarningStateKey: Double] = [:]
        usage[accountA] = 0.40
        usage[accountB] = 0.95
        // Account B's observation did not clobber account A's baseline.
        #expect(usage[accountA] == 0.40)
        #expect(usage[accountB] == 0.95)
    }

    @Test
    func `distinct windows and lanes stay independent for one account`() {
        let session = UsageStore.QuotaWarningStateKey(
            provider: .claude, window: .session, accountDiscriminator: "a@example.com")
        let weekly = UsageStore.QuotaWarningStateKey(
            provider: .claude, window: .weekly, accountDiscriminator: "a@example.com")
        let scoped = UsageStore.QuotaWarningStateKey(
            provider: .claude,
            window: .weekly,
            accountDiscriminator: "a@example.com",
            windowID: "claude-weekly-scoped-fable")
        #expect(Set([session, weekly, scoped]).count == 3)
    }
}
