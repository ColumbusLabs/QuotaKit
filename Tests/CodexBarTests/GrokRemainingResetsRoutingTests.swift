import Foundation
import Testing
@testable import CodexBarCore

struct GrokRemainingResetsRoutingTests {
    @Test
    func `the winning web cookie alone routes the supplemental inventory`() async throws {
        let selectedCookie = LockIsolated<String?>(nil)
        let selectedCredentialsPresent = LockIsolated(false)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let result = try await GrokWebFetchStrategy().fetchResolved(
            Self.context(includeOptionalUsage: true),
            webBilling: { _ in
                GrokWebBillingResult(
                    snapshot: GrokWebBillingSnapshot(
                        usedPercent: 29,
                        resetsAt: now.addingTimeInterval(86400)),
                    sourceLabel: "Chrome Profile 2",
                    authContext: .cookie("sso=winning-session"))
            },
            settingsTier: { _ in nil },
            remainingResets: { credentials, cookieHeader, _ in
                selectedCredentialsPresent.setValue(credentials != nil)
                selectedCookie.setValue(cookieHeader)
                return GrokRemainingResetsLookupResult(
                    tokens: [GrokRemainingReset(
                        tokenID: "redemption-token",
                        grantedAt: nil,
                        expiresAt: now.addingTimeInterval(172_800))],
                    snapshotTask: nil)
            })

        #expect(!selectedCredentialsPresent.value)
        #expect(selectedCookie.value == "sso=winning-session")
        #expect(result.usage.grokResetCredits?.expirations.count == 1)
        let encoded = try JSONEncoder().encode(result.usage)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("redemption-token"))
        #expect(!String(decoding: encoded, as: UTF8.self).contains("grokResetCredits"))
    }

    @Test
    func `completion-required fetch awaits reset inventory without publishing a later task`() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let credits = GrokRateLimitResetCreditsSnapshot(
            expirations: [now.addingTimeInterval(172_800)], updatedAt: now)
        let result = try await GrokWebFetchStrategy().fetchResolved(
            Self.context(includeOptionalUsage: true, requiresCompleteness: true),
            webBilling: { _ in
                GrokWebBillingResult(
                    snapshot: GrokWebBillingSnapshot(usedPercent: 29, resetsAt: nil),
                    sourceLabel: "manual-cookie",
                    authContext: .cookie("sso=winning-session"))
            },
            settingsTier: { _ in nil },
            remainingResets: { _, _, _ in
                GrokRemainingResetsLookupResult(tokens: [], snapshotTask: Task { credits })
            })

        #expect(result.usage.grokResetCredits == credits)
        #expect(result.supplementalUsageTask == nil)
    }

    private static func context(
        includeOptionalUsage: Bool,
        requiresCompleteness: Bool = false) -> ProviderFetchContext
    {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaKit-GrokRouting-\(UUID().uuidString)", isDirectory: true)
        let browserDetection = BrowserDetection(cacheTTL: 0)
        return ProviderFetchContext(
            runtime: .cli,
            sourceMode: .web,
            includeCredits: true,
            includeOptionalUsage: includeOptionalUsage,
            requiresOptionalUsageCompleteness: requiresCompleteness,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: ["GROK_HOME": home.path, "GROK_CLI_PATH": home.appendingPathComponent("missing-grok").path,
                  "PATH": home.path],
            settings: nil,
            fetcher: UsageFetcher(),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
    }
}
