import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// Tests for iOS 1.6.0 / Mac 0.25.2 quota warning wire sync.
/// See Research/020-multi-account-comprehensive.md §R7.4.
@Suite("SyncQuotaWarningConfig + ProviderUsageSnapshot plumbing")
struct SyncQuotaWarningConfigTests {
    // MARK: - SyncQuotaWarningConfig basics

    @Test
    func `macDefaults matches Mac's documented [50, 20] threshold`() {
        #expect(SyncQuotaWarningConfig.macDefaults == [50, 20])
    }

    @Test
    func `resolvedSessionThresholds returns Mac defaults when nil`() {
        let config = SyncQuotaWarningConfig()
        #expect(config.resolvedSessionThresholds() == [50, 20])
    }

    @Test
    func `resolvedWeeklyThresholds returns Mac defaults when nil`() {
        let config = SyncQuotaWarningConfig()
        #expect(config.resolvedWeeklyThresholds() == [50, 20])
    }

    @Test
    func `resolvedSessionThresholds returns the override when set`() {
        let config = SyncQuotaWarningConfig(sessionThresholds: [80, 30, 10])
        // Sorted descending defensively.
        #expect(config.resolvedSessionThresholds() == [80, 30, 10])
    }

    @Test
    func `empty array is treated as missing → defaults`() {
        let config = SyncQuotaWarningConfig(sessionThresholds: [], weeklyThresholds: [])
        #expect(config.resolvedSessionThresholds() == [50, 20])
        #expect(config.resolvedWeeklyThresholds() == [50, 20])
    }

    @Test
    func `Out-of-range thresholds are clamped to [0, 99]`() {
        let config = SyncQuotaWarningConfig(sessionThresholds: [150, -5, 50])
        // 150 → 99, -5 → 0, 50 → 50 — then deduped + sorted desc.
        let result = config.resolvedSessionThresholds()
        #expect(result.contains(99))
        #expect(result.contains(50))
        #expect(result.contains(0))
        // Sorted descending.
        #expect(result == result.sorted(by: >))
    }

    @Test
    func `Duplicate thresholds collapse`() {
        let config = SyncQuotaWarningConfig(sessionThresholds: [50, 50, 50, 20, 20])
        #expect(config.resolvedSessionThresholds().count == 2)
    }

    @Test
    func `Enabled flags default to true when missing`() {
        let config = SyncQuotaWarningConfig()
        #expect(config.resolvedSessionEnabled() == true)
        #expect(config.resolvedWeeklyEnabled() == true)
    }

    @Test
    func `Enabled flag honors explicit false`() {
        let config = SyncQuotaWarningConfig(
            sessionEnabled: false,
            weeklyEnabled: false)
        #expect(config.resolvedSessionEnabled() == false)
        #expect(config.resolvedWeeklyEnabled() == false)
    }

    // MARK: - Codable round-trip

    @Test
    func `Codable round-trip preserves all four fields`() throws {
        let original = SyncQuotaWarningConfig(
            sessionThresholds: [80, 50, 20],
            sessionEnabled: true,
            weeklyThresholds: [70, 30],
            weeklyEnabled: false)
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(SyncQuotaWarningConfig.self, from: data)

        #expect(decoded.sessionThresholds == [80, 50, 20])
        #expect(decoded.sessionEnabled == true)
        #expect(decoded.weeklyThresholds == [70, 30])
        #expect(decoded.weeklyEnabled == false)
    }

    @Test
    func `Codable decodes missing fields as nil (backward compat)`() throws {
        // Empty JSON object — simulates an old Mac that wrote
        // a config with all-defaults.
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SyncQuotaWarningConfig.self, from: json)
        #expect(decoded.sessionThresholds == nil)
        #expect(decoded.weeklyThresholds == nil)
        #expect(decoded.sessionEnabled == nil)
        #expect(decoded.weeklyEnabled == nil)
        // Resolution still produces Mac defaults.
        #expect(decoded.resolvedSessionThresholds() == [50, 20])
        #expect(decoded.resolvedWeeklyThresholds() == [50, 20])
        #expect(decoded.resolvedSessionEnabled() == true)
    }

    // MARK: - ProviderUsageSnapshot wire compat

    @Test
    func `Snapshot decodes pre-1.6.0 JSON (no quotaWarnings field)`() throws {
        // Simulate a JSON envelope from Mac pre-0.25.2 — the field
        // doesn't appear at all in the payload.
        let oldJSON = """
        {
            "providerID": "claude",
            "providerName": "Claude",
            "isError": false,
            "lastUpdated": 1700000000
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(ProviderUsageSnapshot.self, from: oldJSON)
        #expect(snapshot.providerID == "claude")
        #expect(snapshot.quotaWarnings == nil)
    }

    @Test
    func `Snapshot round-trip preserves quotaWarnings`() throws {
        let warnings = SyncQuotaWarningConfig(
            sessionThresholds: [60, 25],
            sessionEnabled: true,
            weeklyThresholds: [70, 30],
            weeklyEnabled: true)
        let snapshot = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            quotaWarnings: warnings)

        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        let decoded = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: data)

        #expect(decoded.quotaWarnings?.sessionThresholds == [60, 25])
        #expect(decoded.quotaWarnings?.weeklyEnabled == true)
    }

    @Test
    func `mutable quotaWarnings copy keeps all other fields intact`() {
        let original = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: SyncRateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            accountEmail: "user@example.com",
            loginMethod: "ChatGPT",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))

        var enriched = original
        enriched.quotaWarnings = SyncQuotaWarningConfig(sessionThresholds: [40])

        #expect(enriched.providerID == original.providerID)
        #expect(enriched.providerName == original.providerName)
        #expect(enriched.primary?.usedPercent == 25)
        #expect(enriched.accountEmail == "user@example.com")
        #expect(enriched.loginMethod == "ChatGPT")
        #expect(enriched.quotaWarnings?.sessionThresholds == [40])
    }

    // MARK: - Per-window helper

    @Test
    func `quotaWarning(forWindowIndex:) returns session config at index 0`() {
        let snapshot = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            quotaWarnings: SyncQuotaWarningConfig(
                sessionThresholds: [70, 40],
                weeklyThresholds: [55, 15]))
        let result = snapshot.quotaWarning(forWindowIndex: 0)
        #expect(result.thresholds == [70, 40])
        #expect(result.enabled == true)
    }

    @Test
    func `quotaWarning(forWindowIndex:) returns weekly config at index 1`() {
        let snapshot = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            quotaWarnings: SyncQuotaWarningConfig(
                sessionThresholds: [70, 40],
                weeklyThresholds: [55, 15],
                weeklyEnabled: false))
        let result = snapshot.quotaWarning(forWindowIndex: 1)
        #expect(result.thresholds == [55, 15])
        #expect(result.enabled == false)
    }

    @Test
    func `quotaWarning(forWindowIndex:) returns disabled for extra windows`() {
        let snapshot = ProviderUsageSnapshot(
            providerID: "perplexity",
            providerName: "Perplexity",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            quotaWarnings: SyncQuotaWarningConfig(sessionThresholds: [50]))
        let result = snapshot.quotaWarning(forWindowIndex: 2)
        #expect(result.thresholds == nil)
        #expect(result.enabled == false)
    }

    @Test
    func `nil quotaWarnings falls back to Mac defaults — never empty render`() {
        let snapshot = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            quotaWarnings: nil)
        let session = snapshot.quotaWarning(forWindowIndex: 0)
        let weekly = snapshot.quotaWarning(forWindowIndex: 1)
        #expect(session.thresholds == [50, 20])
        #expect(weekly.thresholds == [50, 20])
        #expect(session.enabled == true)
        #expect(weekly.enabled == true)
    }
}
