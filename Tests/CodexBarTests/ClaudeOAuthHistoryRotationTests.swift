import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct ClaudeOAuthHistoryRotationTests {
    @Test
    func `two external refresh token rotations retain the account history`() async {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let identity = UsageStore._activeClaudeAccountIdentityForTesting("account-a")
        for (index, character) in ["a", "b", "c"].enumerated() {
            let owner = String(repeating: character, count: 64)
            await self.record(store, owner: owner, identity: identity, hour: index * 2)
            await self.record(store, owner: owner, identity: identity, hour: index * 2 + 1)
        }

        let selection = store.planUtilizationHistorySelection(for: .claude)
        #expect(selection.accountKey == self.key(identity))
        #expect(findSeries(selection.histories, name: .session, windowMinutes: 300)?
            .entries.map(\.usedPercent) == [10, 20, 30, 40, 50, 60])
        #expect(store.planUtilizationHistory[.claude]?.accounts.count == 1)
    }

    @Test
    func `saved bound fragments migrate without adopting another account or unbound history`() async throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let identity = UsageStore._activeClaudeAccountIdentityForTesting("account-a")
        let owners = ["a", "b", "c", "d"].map { String(repeating: $0, count: 64) }
        store.persistClaudeOAuthAccountUuidMap([
            owners[0]: identity,
            owners[1]: identity,
            owners[2]: UsageStore._activeClaudeAccountIdentityForTesting("account-b"),
        ])
        let buckets = PlanUtilizationHistoryBuckets(
            preferredAccountKey: self.key(owners[1]),
            accounts: Dictionary(uniqueKeysWithValues: owners.enumerated().map { index, owner in
                (self.key(owner), [planSeries(name: .session, windowMinutes: 300, entries: [
                    planEntry(at: self.date(index), usedPercent: Double((index + 1) * 10)),
                ])])
            }))
        store.planUtilizationHistoryStore.save([.claude: buckets])
        store.planUtilizationHistory = store.planUtilizationHistoryStore.load()

        await self.record(store, owner: owners[1], identity: identity, hour: 4)

        let migrated = try #require(store.planUtilizationHistory[.claude])
        #expect(migrated.preferredAccountKey == self.key(identity))
        #expect(findSeries(migrated.accounts[self.key(identity)] ?? [], name: .session, windowMinutes: 300)?
            .entries.map(\.usedPercent) == [10, 20, 50])
        #expect(migrated.accounts[self.key(owners[0])] == nil)
        #expect(migrated.accounts[self.key(owners[1])] == nil)
        #expect(migrated.accounts[self.key(owners[2])] == buckets.accounts[self.key(owners[2])])
        #expect(migrated.accounts[self.key(owners[3])] == buckets.accounts[self.key(owners[3])])
        store.planUtilizationHistoryStore.save([.claude: migrated])
        #expect(store.planUtilizationHistoryStore.load()[.claude] == migrated)
    }

    @Test
    func `new credential must be corroborated before joining an established account`() async throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let identity = UsageStore._activeClaudeAccountIdentityForTesting("account-a")
        let first = String(repeating: "a", count: 64)
        let replacement = String(repeating: "b", count: 64)
        await self.record(store, owner: first, identity: identity, hour: 0)
        await self.record(store, owner: first, identity: identity, hour: 1)
        await self.record(store, owner: replacement, identity: identity, hour: 2)
        let buckets = try #require(store.planUtilizationHistory[.claude])
        #expect(findSeries(buckets.accounts[self.key(identity)] ?? [], name: .session, windowMinutes: 300)?
            .entries.map(\.usedPercent) == [10, 20])
        #expect(findSeries(buckets.accounts[self.key(replacement)] ?? [], name: .session, windowMinutes: 300)?
            .entries.map(\.usedPercent) == [30])
        #expect(UsageStore.loadClaudeOAuthAccountUuidMap(from: store.settings.userDefaults)[replacement] == nil)
    }

    @Test(arguments: [false, true])
    func `different accounts and profiles keep independent histories`(sameAccountDifferentProfile: Bool) async throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let (firstIdentity, secondIdentity) = ClaudeOAuthCredentialsStore.withEnvironmentCredentialsURLForTesting {
            (
                UsageStore._activeClaudeAccountIdentityForTesting(
                    "account-a", environment: ["CLAUDE_CONFIG_DIR": root.appendingPathComponent("first").path]),
                UsageStore._activeClaudeAccountIdentityForTesting(
                    sameAccountDifferentProfile ? "account-a" : "account-b",
                    environment: ["CLAUDE_CONFIG_DIR": root.appendingPathComponent(
                        sameAccountDifferentProfile ? "second" : "first").path]))
        }
        #expect(firstIdentity != secondIdentity)
        let first = String(repeating: "a", count: 64)
        let second = String(repeating: "b", count: 64)
        await self.record(store, owner: first, identity: firstIdentity, hour: 0)
        await self.record(store, owner: first, identity: firstIdentity, hour: 1)
        await self.record(store, owner: second, identity: secondIdentity, hour: 2)
        await self.record(store, owner: second, identity: secondIdentity, hour: 3)

        let buckets = try #require(store.planUtilizationHistory[.claude])
        #expect(buckets.accounts.count == 2)
        #expect(findSeries(buckets.accounts[self.key(firstIdentity)] ?? [], name: .session, windowMinutes: 300)?
            .entries.map(\.usedPercent) == [10, 20])
        #expect(findSeries(buckets.accounts[self.key(secondIdentity)] ?? [], name: .session, windowMinutes: 300)?
            .entries.map(\.usedPercent) == [30, 40])
    }

    @Test(arguments: [false, true])
    func `corrected binding preserves ambiguous history across restart`(emptyConfirmation: Bool) async throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let owner = String(repeating: "a", count: 64)
        let identity = UsageStore._activeClaudeAccountIdentityForTesting("account-b")
        let legacy = planSeries(name: .session, windowMinutes: 300, entries: [
            planEntry(at: self.date(0), usedPercent: 10),
        ])
        store.planUtilizationHistory[.claude] = PlanUtilizationHistoryBuckets(
            preferredAccountKey: self.key(owner), accounts: [self.key(owner): [legacy]])
        store.persistClaudeOAuthAccountUuidMap([
            owner: UsageStore._activeClaudeAccountIdentityForTesting("account-a"),
        ])

        await self.record(store, owner: owner, identity: identity, hour: 1)
        #expect(store.planUtilizationHistory[.claude]?.accounts == [self.key(owner): [legacy]])
        await self.record(store, owner: owner, identity: identity, hour: 2, hasQuota: !emptyConfirmation)
        let reloaded = self.reloadedStore(store)
        await self.record(reloaded, owner: owner, identity: identity, hour: 3)

        let buckets = try #require(reloaded.planUtilizationHistory[.claude])
        #expect(buckets.preferredAccountKey == self.key(identity))
        #expect(findSeries(buckets.accounts[self.key(identity)] ?? [], name: .session, windowMinutes: 300)?
            .entries.map(\.usedPercent) == (emptyConfirmation ? [40] : [30, 40]))
        #expect(buckets.accounts[self.key(owner)] == [legacy])
        #expect(Array(buckets.accounts.filter { $0.key != self.key(identity) }.values) == [[legacy]])
    }

    @Test
    func `bound history stays continuous when account metadata temporarily disappears`() async {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let identity = UsageStore._activeClaudeAccountIdentityForTesting("account-a")
        let owner = String(repeating: "a", count: 64)
        await self.record(store, owner: owner, identity: identity, hour: 0)
        await self.record(store, owner: owner, identity: identity, hour: 1)
        await self.record(store, owner: owner, identity: nil, hour: 2)
        let selection = store.planUtilizationHistorySelection(for: .claude)
        #expect(selection.accountKey == self.key(identity))
        #expect(findSeries(selection.histories, name: .session, windowMinutes: 300)?
            .entries.map(\.usedPercent) == [10, 20, 30])
    }

    @Test
    func `canonical history fallback requires a persisted verified credential binding`() async {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let identity = UsageStore._activeClaudeAccountIdentityForTesting("account-a")
        let owner = String(repeating: "a", count: 64)
        await self.record(store, owner: owner, identity: identity, hour: 0)
        await self.record(store, owner: owner, identity: identity, hour: 1)
        #expect(!store.claudeHistoryFallbackSelection(
            activeAccountObservation: .stable(identity: identity)).histories.isEmpty)
        store.persistClaudeOAuthAccountUuidMap([:])
        #expect(store.claudeHistoryFallbackSelection(
            activeAccountObservation: .stable(identity: identity)).histories.isEmpty)
    }

    @Test(arguments: [false, true])
    func `repair retires already merged ambiguous history across restart`(emptyConfirmation: Bool) async throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let identityA = UsageStore._activeClaudeAccountIdentityForTesting("account-a")
        let identityB = UsageStore._activeClaudeAccountIdentityForTesting("account-b")
        let ownerA = String(repeating: "a", count: 64)
        let ownerB = String(repeating: "b", count: 64)
        for hour in 0..<4 {
            await self.record(store, owner: hour < 2 ? ownerA : ownerB, identity: identityA, hour: hour)
        }
        await self.record(store, owner: ownerB, identity: identityB, hour: 4)
        await self.record(store, owner: ownerB, identity: identityB, hour: 5, hasQuota: !emptyConfirmation)
        if emptyConfirmation {
            #expect(store.planUtilizationHistorySelection(for: .claude).histories.isEmpty)
        }
        let reloaded = self.reloadedStore(store)
        if emptyConfirmation {
            #expect(reloaded.planUtilizationHistorySelection(for: .claude).histories.isEmpty)
        }

        await self.record(reloaded, owner: ownerA, identity: identityA, hour: 6)
        let rotatedOwner = String(repeating: "c", count: 64)
        await self.record(reloaded, owner: rotatedOwner, identity: identityA, hour: 7)
        await self.record(reloaded, owner: rotatedOwner, identity: identityA, hour: 8)
        let selection = reloaded.planUtilizationHistorySelection(for: .claude)
        #expect(selection.accountKey != self.key(identityA))
        #expect(findSeries(selection.histories, name: .session, windowMinutes: 300)?
            .entries.map(\.usedPercent) == [70, 80, 90])
        let buckets = try #require(reloaded.planUtilizationHistory[.claude])
        #expect(findSeries(buckets.accounts[self.key(identityA)] ?? [], name: .session, windowMinutes: 300)?
            .entries.map(\.usedPercent) == [10, 20, 30, 40])
    }

    private func reloadedStore(_ store: UsageStore) -> UsageStore {
        let reloaded = UsageStorePlanUtilizationTests.makeStore()
        // The original store's queued writer must not overwrite the restart fixture with an older snapshot.
        reloaded.planUtilizationHistoryStore.save(store.planUtilizationHistory)
        reloaded.planUtilizationHistory = reloaded.planUtilizationHistoryStore.load()
        reloaded.persistClaudeOAuthAccountUuidMap(
            UsageStore.loadClaudeOAuthAccountUuidMap(from: store.settings.userDefaults))
        return reloaded
    }

    private func key(_ owner: String) -> String {
        UsageStore._claudeOAuthPlanUtilizationAccountKeyForTesting(historyOwnerIdentifier: owner)!
    }

    private func date(_ hour: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(hour * 3600))
    }

    private func record(
        _ store: UsageStore,
        owner: String,
        identity: String?,
        hour: Int,
        hasQuota: Bool = true) async
    {
        await store.recordPlanUtilizationHistorySample(
            provider: .claude,
            snapshot: UsageSnapshot(
                primary: hasQuota ? RateWindow(
                    usedPercent: Double((hour + 1) * 10),
                    windowMinutes: 300,
                    resetsAt: nil,
                    resetDescription: nil) : nil,
                secondary: nil,
                updatedAt: self.date(hour)),
            claudeOAuthPersistentRefHash: "same-keychain-row",
            claudeOAuthHistoryOwnerIdentifier: owner,
            claudeOAuthActiveAccountObservation: .stable(identity: identity),
            isClaudeOAuthSample: true,
            now: self.date(hour))
    }
}
