import CodexBarSync
import Foundation
import SwiftUI
import Testing
@testable import CodexBarMobile

@Suite("Codex reset credits card")
struct CodexResetCreditsCardTests {
    @Test
    func `Expiration formatting includes year time and time zone`() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let value = CodexResetCreditsCard.formattedExpiration(
            Date(timeIntervalSince1970: 1_700_000_000),
            locale: Locale(identifier: "en_US"),
            timeZone: timeZone)

        #expect(value.contains("2023"))
        #expect(value.contains("10:13:20"))
        #expect(value.contains("GMT"))
    }

    @Test @MainActor
    func `Card renders authoritative count with partial and no-expiry details`() {
        let now = Date()
        let card = CodexResetCreditsCard(
            credits: SyncCodexResetCredits(
                credits: [
                    SyncCodexResetCredit(
                        id: "no-expiry",
                        resetType: "codex_rate_limits",
                        status: "available",
                        grantedAt: now,
                        expiresAt: nil),
                ],
                availableCount: 3,
                updatedAt: now),
            tintColor: .blue)
            .frame(width: 360)
            .padding()

        let renderer = ImageRenderer(content: card)
        renderer.scale = 1

        #expect(renderer.uiImage != nil)
    }

    @Test
    func `Displayed rows never exceed the authoritative count`() {
        let now = Date()
        let credits = SyncCodexResetCredits(
            credits: [
                SyncCodexResetCredit(
                    id: "first",
                    resetType: "codex_rate_limits",
                    status: "available",
                    grantedAt: now,
                    expiresAt: now.addingTimeInterval(60)),
                SyncCodexResetCredit(
                    id: "second",
                    resetType: "codex_rate_limits",
                    status: "available",
                    grantedAt: now,
                    expiresAt: now.addingTimeInterval(120)),
            ],
            availableCount: 1,
            updatedAt: now)

        let displayed = CodexResetCreditsCard.displayedCredits(credits, at: now)

        #expect(displayed.map(\.id) == ["first"])
    }
}
