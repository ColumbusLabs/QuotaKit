import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct AntigravityOfflineStoreTests {
    @Test
    func `offline snapshot is deliberately unowned`() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = AntigravityOfflineFetchStrategy.usageSnapshot(
            conversationCount: 3,
            updatedAt: updatedAt)

        #expect(snapshot.identity == nil)
        #expect(snapshot.updatedAt == updatedAt)
        #expect(snapshot.extraRateWindows?.first?.usageKnown == false)
    }

    @Test
    func `unowned offline snapshot is suppressed from mobile sync`() {
        let offline = AntigravityOfflineFetchStrategy.usageSnapshot(conversationCount: 3)
        #expect(SyncCoordinator.shouldSuppressUnownedAntigravityOfflineSnapshot(
            provider: .antigravity,
            snapshot: offline))

        let authoritative = UsageSnapshot(
            primary: offline.primary,
            secondary: offline.secondary,
            tertiary: offline.tertiary,
            extraRateWindows: offline.extraRateWindows,
            updatedAt: offline.updatedAt,
            identity: ProviderIdentitySnapshot(
                providerID: .antigravity,
                accountEmail: "owner@example.com",
                accountOrganization: nil,
                loginMethod: "oauth"))
        #expect(!SyncCoordinator.shouldSuppressUnownedAntigravityOfflineSnapshot(
            provider: .antigravity,
            snapshot: authoritative))
        #expect(!SyncCoordinator.shouldSuppressUnownedAntigravityOfflineSnapshot(
            provider: .gemini,
            snapshot: offline))
    }

    @Test
    func `offline result preserves an existing authoritative quota snapshot`() {
        let offline = ProviderFetchResult(
            usage: AntigravityOfflineFetchStrategy.usageSnapshot(conversationCount: 3),
            credits: nil,
            dashboard: nil,
            sourceLabel: "offline",
            strategyID: "antigravity.offline",
            strategyKind: .localProbe)
        let priorReset = Date(timeIntervalSince1970: 1_700_100_000)
        let prior = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 42,
                windowMinutes: 300,
                resetsAt: priorReset,
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            identity: ProviderIdentitySnapshot(
                providerID: .antigravity,
                accountEmail: "owner@example.com",
                accountOrganization: nil,
                loginMethod: "oauth"))

        #expect(UsageStore.shouldPreserveAntigravityQuotaSnapshot(
            provider: .antigravity,
            result: offline,
            priorSnapshot: prior))
        #expect(!UsageStore.shouldPreserveAntigravityQuotaSnapshot(
            provider: .antigravity,
            result: offline,
            priorSnapshot: nil))
        #expect(!UsageStore.shouldPreserveAntigravityQuotaSnapshot(
            provider: .antigravity,
            result: offline,
            priorSnapshot: offline.usage))
        #expect(UsageStore.isUnownedAntigravityOfflineResult(provider: .antigravity, result: offline))
    }

    @Test
    func `resolves gemini home from env override`() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let envOverride = "/tmp/custom-gemini"
        let resolved = AntigravityOfflineStore.geminiHomeDirectory(
            home: home,
            env: ["GEMINI_CLI_HOME": envOverride])
        #expect(resolved.path == envOverride)
        let fallback = AntigravityOfflineStore.geminiHomeDirectory(home: home, env: [:])
        #expect(fallback.path == "/Users/test/.gemini")
    }

    @Test
    func `counts db files in conversations directory`() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let conv = AntigravityOfflineStore.conversationsDirectory(home: tmp, env: [:])
        try FileManager.default.createDirectory(at: conv, withIntermediateDirectories: true)
        #expect(AntigravityOfflineStore.countConversations(home: tmp) == 0)
        #expect(!AntigravityOfflineStore.hasOfflineData(home: tmp))
        FileManager.default.createFile(atPath: conv.appendingPathComponent("a.db").path, contents: Data())
        FileManager.default.createFile(atPath: conv.appendingPathComponent("b.DB").path, contents: Data())
        FileManager.default.createFile(atPath: conv.appendingPathComponent("c.txt").path, contents: Data())
        #expect(AntigravityOfflineStore.countConversations(home: tmp) == 2)
        #expect(AntigravityOfflineStore.hasOfflineData(home: tmp))
    }

    @Test
    func `counts desktop app databases from both supported app data locations`() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let appData = AntigravityOfflineStore.appDataDirectory(home: tmp)
        let conversations = appData.appendingPathComponent("conversations", isDirectory: true)
        try FileManager.default.createDirectory(at: conversations, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: appData.appendingPathComponent("desktop.db").path, contents: Data())
        FileManager.default.createFile(
            atPath: conversations.appendingPathComponent("conversation.db").path,
            contents: Data())

        #expect(AntigravityOfflineStore.countConversations(home: tmp) == 2)
        #expect(AntigravityOfflineStore.hasOfflineData(home: tmp))
    }

    @Test
    func `falls back to tokscale cache when no db`() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cache = AntigravityOfflineStore.tokscaleCacheDirectory(home: tmp)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cache.appendingPathComponent("x.jsonl").path, contents: Data())
        FileManager.default.createFile(atPath: cache.appendingPathComponent("y.jsonl").path, contents: Data())
        #expect(AntigravityOfflineStore.countConversations(home: tmp) == 2)
    }

    @Test
    func `prefers db count over cache`() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let conv = AntigravityOfflineStore.conversationsDirectory(home: tmp, env: [:])
        let cache = AntigravityOfflineStore.tokscaleCacheDirectory(home: tmp)
        try FileManager.default.createDirectory(at: conv, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: conv.appendingPathComponent("a.db").path, contents: Data())
        FileManager.default.createFile(atPath: cache.appendingPathComponent("x.jsonl").path, contents: Data())
        FileManager.default.createFile(atPath: cache.appendingPathComponent("y.jsonl").path, contents: Data())
        #expect(AntigravityOfflineStore.countConversations(home: tmp) == 1)
    }
}
