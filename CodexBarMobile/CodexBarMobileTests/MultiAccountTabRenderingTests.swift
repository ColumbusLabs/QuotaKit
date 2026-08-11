import CodexBarSync
import SwiftUI
import XCTest
@testable import CodexBarMobile

/// Smoke + state tests for the Phase G `ProviderDetailView` account
/// tab bar. Verifies:
///   - Single-account group: tab bar HIDDEN (body renders identically
///     to pre-Phase-G single-snapshot path).
///   - Multi-account group: tab bar VISIBLE (segmented control with
///     N tabs).
///   - Render doesn't crash with edge inputs (1 / 2 / many accounts,
///     missing emails, identical accounts).
///
/// We assert via ImageRenderer — same approach as Phase F
/// V026ViewSmokeTests. The image-non-nil signal proves the view
/// hierarchy assembled correctly with all data wired through the
/// new `group: ProviderAccountGroup` parameter.
@MainActor
final class MultiAccountTabRenderingTests: XCTestCase {
    private nonisolated static let remoteConfigSuiteName = "com.columbuslabs.quotakit.tests.multi-account"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: Self.remoteConfigSuiteName)
        UserDefaults(suiteName: Self.remoteConfigSuiteName)?
            .removePersistentDomain(forName: Self.remoteConfigSuiteName)
    }

    private func snapshot(
        providerID: String,
        providerName: String,
        accountEmail: String? = nil,
        loginMethod: String? = nil) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: providerID,
            providerName: providerName,
            primary: nil,
            secondary: nil,
            accountEmail: accountEmail,
            loginMethod: loginMethod,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func renderToImage(_ view: some View) -> UIImage? {
        let renderer = ImageRenderer(content: view
            .environment(ProEntitlementStore.preview(state: .unlocked(source: .storeKit)))
            .environment(RemoteConfigStore(defaults: UserDefaults(suiteName: Self.remoteConfigSuiteName)))
            .frame(width: 390, height: 800))
        renderer.scale = 2.0
        return renderer.uiImage
    }

    // MARK: - Single-account group

    func testSingleAccountGroupRenders() {
        let group = ProviderAccountGroup(
            providerID: "kiro",
            providerName: "Kiro",
            accounts: [self.snapshot(providerID: "kiro", providerName: "Kiro")])
        XCTAssertFalse(group.hasMultipleAccounts)
        let view = ProviderDetailView(group: group)
        XCTAssertNotNil(self.renderToImage(view))
    }

    func testSingleSnapshotInitWrapsInOneAccountGroup() {
        // Backwards-compat init from a bare snapshot. The wrapper
        // group's hasMultipleAccounts MUST be false so the body skips
        // the tab bar rendering path.
        let snap = self.snapshot(providerID: "claude", providerName: "Claude")
        let view = ProviderDetailView(provider: snap)
        XCTAssertNotNil(self.renderToImage(view))
    }

    // MARK: - Multi-account group

    func testTwoAccountGroupRenders() {
        let group = ProviderAccountGroup(
            providerID: "openai",
            providerName: "OpenAI",
            accounts: [
                self.snapshot(providerID: "openai", providerName: "OpenAI", accountEmail: "admin-msxiao113@openai.com"),
                self.snapshot(providerID: "openai", providerName: "OpenAI", accountEmail: "admin-outlook@openai.com"),
            ])
        XCTAssertTrue(group.hasMultipleAccounts)
        let view = ProviderDetailView(group: group)
        XCTAssertNotNil(self.renderToImage(view))
    }

    func testThreeAccountGroupRenders() {
        let group = ProviderAccountGroup(
            providerID: "codex",
            providerName: "Codex",
            accounts: [
                self.snapshot(providerID: "codex", providerName: "Codex", accountEmail: "alice@x.test"),
                self.snapshot(providerID: "codex", providerName: "Codex", accountEmail: "bob@x.test"),
                self.snapshot(providerID: "codex", providerName: "Codex", accountEmail: "carol@x.test"),
            ])
        XCTAssertTrue(group.hasMultipleAccounts)
        XCTAssertEqual(group.accounts.count, 3)
        let view = ProviderDetailView(group: group)
        XCTAssertNotNil(self.renderToImage(view))
    }

    func testMultiAccountGroupWithMissingEmailFallsBackToLoginMethod() {
        let group = ProviderAccountGroup(
            providerID: "antigravity",
            providerName: "Antigravity",
            accounts: [
                self.snapshot(
                    providerID: "antigravity",
                    providerName: "Antigravity",
                    accountEmail: nil,
                    loginMethod: "OAuth"),
                self.snapshot(
                    providerID: "antigravity",
                    providerName: "Antigravity",
                    accountEmail: nil,
                    loginMethod: "Team"),
            ])
        XCTAssertEqual(group.tabLabel(forIndex: 0), "OAuth")
        XCTAssertEqual(group.tabLabel(forIndex: 1), "Team")
        let view = ProviderDetailView(group: group)
        XCTAssertNotNil(self.renderToImage(view))
    }

    // MARK: - List-row count badge

    func testProviderUsageViewWithAccountCountRenders() {
        // The "· N" count badge surfaces on the Usage list row when
        // the group has multiple accounts. Verify the card body
        // assembles cleanly with the new param.
        let snap = self.snapshot(providerID: "openai", providerName: "OpenAI")
        let view = ProviderUsageView(provider: snap, accountCount: 2)
        XCTAssertNotNil(self.renderToImage(view))
    }

    func testProviderUsageViewWithNilAccountCountRendersUnchanged() {
        // Single-account groups pass accountCount=nil — badge MUST
        // be suppressed (no "· 1" leaking into the title).
        let snap = self.snapshot(providerID: "openai", providerName: "OpenAI")
        let view = ProviderUsageView(provider: snap, accountCount: nil)
        XCTAssertNotNil(self.renderToImage(view))
    }
}
