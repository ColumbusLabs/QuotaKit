import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite("Four-provider mock injection", .serialized)
struct MockProviderInjectorTests {
    @Test
    func `Environment variable remains a hard activation gate`() throws {
        let suiteName = "MockProviderInjectorTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: MockProviderInjector.userDefaultsKey)
        #expect(!MockProviderInjector.isEnabled(environment: [:], userDefaults: defaults))
        #expect(MockProviderInjector.isEnabled(
            environment: [MockProviderInjector.environmentVariableName: "1"],
            userDefaults: defaults))
        #expect(MockProviderInjector.isEnabled(
            environment: [MockProviderInjector.environmentVariableName: "false"],
            userDefaults: defaults))

        defaults.set(false, forKey: MockProviderInjector.userDefaultsKey)
        #expect(!MockProviderInjector.isEnabled(
            environment: [MockProviderInjector.environmentVariableName: "false"],
            userDefaults: defaults))
    }

    @Test
    func `Tooling visibility depends only on environment variable presence`() {
        #expect(!MockProviderInjector.isMockToolingVisible(environment: [:]))
        #expect(MockProviderInjector.isMockToolingVisible(
            environment: [MockProviderInjector.environmentVariableName: "0"]))
    }

    @Test
    func `Catalog contains exactly one retained provider fixture`() {
        let snapshots = MockProviderInjector.allMocks()
        let expected = Set(["codex", "claude", "cursor", "grok"])

        #expect(snapshots.count == 4)
        #expect(Set(snapshots.map(\.providerID)) == expected)
        #expect(MockProviderInjector.realProviderIDsBorrowedByMocks == expected)
        #expect(MockProviderInjector.syntheticProviderIDs.isEmpty)
        #expect(MockProviderInjector.allMockProviderIDs == expected)
    }

    @Test
    func `Every fixture has a reserved email and stable account identity`() {
        for snapshot in MockProviderInjector.allMocks() {
            #expect(snapshot.accountEmail?.hasSuffix(MockProviderInjector.mockEmailTLD) == true)
            #expect(snapshot.accountIdentities?.isEmpty == false)
            #expect(snapshot.isError == false)
        }
    }

    @Test
    func `Cursor fixture preserves Total Auto and API lanes`() throws {
        let cursor = try #require(
            MockProviderInjector.allMocks().first { $0.providerID == "cursor" })
        #expect(cursor.rateWindows.compactMap(\.label) == ["Total", "Auto", "API"])
    }

    @Test
    func `Retained provider-specific envelopes are represented`() throws {
        let snapshots = MockProviderInjector.allMocks()
        let codex = try #require(snapshots.first { $0.providerID == "codex" })
        let claude = try #require(snapshots.first { $0.providerID == "claude" })
        let grok = try #require(snapshots.first { $0.providerID == "grok" })

        #expect(codex.codexWorkspace?.workspaceID == "mock-workspace")
        #expect(claude.claudeExtraUsage?.monthlyLimitUSD == 50)
        #expect(grok.grokBilling?.monthlySpendUSD == 9.50)
        #expect(grok.grokBilling?.planTier == "Consumer")
    }

    @Test
    func `Fixtures round-trip through the companion wire envelope`() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for snapshot in MockProviderInjector.allMocks() {
            let data = try encoder.encode(snapshot)
            let decoded = try decoder.decode(ProviderUsageSnapshot.self, from: data)
            #expect(decoded.providerID == snapshot.providerID)
            #expect(decoded.accountIdentities == snapshot.accountIdentities)
            #expect(decoded.rateWindows.map(\.label) == snapshot.rateWindows.map(\.label))
            #expect(decoded.rateWindows.map(\.usedPercent) == snapshot.rateWindows.map(\.usedPercent))
        }
    }
}
