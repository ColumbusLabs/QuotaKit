import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CodexBarTests {
    @Test
    func `icon renderer produces template image`() {
        let image = IconRenderer.makeIcon(
            primaryRemaining: 50,
            weeklyRemaining: 75,
            creditsRemaining: 500,
            stale: false,
            style: .codex)

        #expect(image.isTemplate)
        #expect(image.size.width > 0)
    }

    @Test
    func `icon renderer renders at pixel aligned size`() {
        let image = IconRenderer.makeIcon(
            primaryRemaining: 50,
            weeklyRemaining: 75,
            creditsRemaining: 500,
            stale: false,
            style: .claude)
        let bitmapReps = image.representations.compactMap { $0 as? NSBitmapImageRep }

        #expect(bitmapReps.contains { rep in
            rep.pixelsWide == 36 && rep.pixelsHigh == 36
        })
    }

    @Test
    func `icon renderer caches static icons`() {
        let first = IconRenderer.makeIcon(
            primaryRemaining: 42,
            weeklyRemaining: 17,
            creditsRemaining: 250,
            stale: false,
            style: .codex)
        let second = IconRenderer.makeIcon(
            primaryRemaining: 42,
            weeklyRemaining: 17,
            creditsRemaining: 250,
            stale: false,
            style: .codex)

        #expect(first === second)
    }

    @Test
    func `icon renderer caches Codex credits by explicit remaining percent`() throws {
        let legacyFull = IconRenderer.makeIcon(
            primaryRemaining: nil,
            weeklyRemaining: nil,
            creditsRemaining: 1000,
            stale: false,
            style: .codex)
        let explicitLow = IconRenderer.makeIcon(
            primaryRemaining: nil,
            weeklyRemaining: nil,
            creditsRemaining: 1000,
            creditsRemainingPercent: 1,
            stale: false,
            style: .codex)
        let explicitLowAgain = IconRenderer.makeIcon(
            primaryRemaining: nil,
            weeklyRemaining: nil,
            creditsRemaining: 1000,
            creditsRemainingPercent: 1,
            stale: false,
            style: .codex)

        #expect(explicitLow === explicitLowAgain)
        #expect(legacyFull !== explicitLow)

        func averageAlpha(_ image: NSImage, xRange: ClosedRange<Int>, yRange: ClosedRange<Int>) throws -> CGFloat {
            let rep = try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.first { rep in
                rep.pixelsWide == 36 && rep.pixelsHigh == 36
            })
            var total: CGFloat = 0
            var count: CGFloat = 0
            for y in yRange {
                for x in xRange {
                    total += (rep.colorAt(x: x, y: y) ?? .clear).alphaComponent
                    count += 1
                }
            }
            return total / count
        }

        let fullRightEdge = try averageAlpha(legacyFull, xRange: 24...30, yRange: 8...24)
        let lowRightEdge = try averageAlpha(explicitLow, xRange: 24...30, yRange: 8...24)

        #expect(fullRightEdge > lowRightEdge + 0.2)
    }

    @Test
    func `copying rate windows preserves generic snapshot details`() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let identity = ProviderIdentitySnapshot(
            providerID: .grok,
            accountEmail: "test@example.com",
            accountOrganization: "Example",
            loginMethod: "OAuth")
        let snapshot = try UsageSnapshot(
            primary: nil,
            secondary: nil,
            tertiary: RateWindow(usedPercent: 30, windowMinutes: 60, resetsAt: nil, resetDescription: nil),
            details: [ProviderDetailSection(rows: [
                ProviderDetailSection.Row(label: "Balance", value: "$12.50"),
            ])],
            subscriptionExpiresAt: updatedAt.addingTimeInterval(100),
            subscriptionRenewsAt: updatedAt.addingTimeInterval(200),
            updatedAt: updatedAt,
            identity: identity)

        let copied = snapshot.with(
            primary: RateWindow(usedPercent: 40, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 50, windowMinutes: 10080, resetsAt: nil, resetDescription: nil))

        #expect(copied.primary?.usedPercent == 40)
        #expect(copied.secondary?.usedPercent == 50)
        #expect(copied.tertiary?.usedPercent == 30)
        #expect(copied.detailRow(label: "Balance")?.value == "$12.50")
        #expect(copied.subscriptionExpiresAt == updatedAt.addingTimeInterval(100))
        #expect(copied.subscriptionRenewsAt == updatedAt.addingTimeInterval(200))
        #expect(copied.identity?.providerID == .grok)
    }

    @Test
    func `status icon accessibility uses percentage scale`() {
        #expect(
            StatusIconView.accessibilityPercentRemaining(50) ==
                String(format: L("%d percent remaining"), 50))
    }

    @Test
    func `codex icon promotes weekly only window into primary display lane`() {
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: RateWindow(usedPercent: 25, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            updatedAt: Date())

        let remaining = IconRemainingResolver.resolvedRemaining(snapshot: snapshot, style: .codex)

        #expect(remaining.primary == 75)
        #expect(remaining.secondary == nil)
    }

    @Test
    func `codex icon caps session until exhausted weekly lane resets`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let weeklyReset = now.addingTimeInterval(3600)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 1,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(1800),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 100,
                windowMinutes: 10080,
                resetsAt: weeklyReset,
                resetDescription: nil),
            updatedAt: now.addingTimeInterval(-7200))

        let capped = IconRemainingResolver.resolvedRemaining(snapshot: snapshot, style: .codex, now: now)
        let reset = IconRemainingResolver.resolvedRemaining(snapshot: snapshot, style: .codex, now: weeklyReset)

        #expect(capped.primary == 0)
        #expect(capped.secondary == 0)
        #expect(reset.primary == 99)
        #expect(reset.secondary == nil)
    }
}
