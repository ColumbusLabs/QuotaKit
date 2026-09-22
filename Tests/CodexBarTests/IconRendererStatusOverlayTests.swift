import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct IconRendererStatusOverlayTests {
    @Test
    func `minor status badges attach to a prominent single quota meter`() throws {
        for secondaryOnly in [false, true] {
            for indicator in [ProviderStatusIndicator.minor, .maintenance] {
                let plain = try self.render(secondaryOnly: secondaryOnly, indicator: .none)
                let marked = try self.render(secondaryOnly: secondaryOnly, indicator: indicator)
                var cutoutPixels = 0
                var glyphPixels = 0

                for y in 0..<marked.pixelsHigh {
                    for x in 0..<marked.pixelsWide {
                        let plainAlpha = (plain.colorAt(x: x, y: y) ?? .clear).alphaComponent
                        let markedAlpha = (marked.colorAt(x: x, y: y) ?? .clear).alphaComponent
                        if plainAlpha > 0.5, markedAlpha < 0.05 {
                            cutoutPixels += 1
                        }
                        if plainAlpha < 0.05, markedAlpha > 0.5 {
                            glyphPixels += 1
                        }
                    }
                }

                #expect(cutoutPixels >= 8, "Expected the badge halo to overlap the single meter")
                #expect(glyphPixels >= 4, "Expected the status badge glyph to remain visible")
            }
        }
    }

    @Test
    func `zero and positive secondary quotas keep cached badge placement distinct in either order`() throws {
        for indicator in [ProviderStatusIndicator.minor, .maintenance] {
            let zeroFirst = try self.render(
                primaryRemaining: nil,
                weeklyRemaining: 0,
                indicator: indicator,
                style: .combined)
            let positiveAfterZero = try self.render(
                primaryRemaining: nil,
                weeklyRemaining: 0.01,
                indicator: indicator,
                style: .combined)
            #expect(try self.pixels(zeroFirst) != self.pixels(positiveAfterZero))

            let positiveFirst = try self.render(
                primaryRemaining: nil,
                weeklyRemaining: 0.01,
                indicator: indicator,
                style: .codex)
            let zeroAfterPositive = try self.render(
                primaryRemaining: nil,
                weeklyRemaining: 0,
                indicator: indicator,
                style: .codex)
            #expect(try self.pixels(positiveFirst) != self.pixels(zeroAfterPositive))
        }
    }

    private func render(
        secondaryOnly: Bool,
        indicator: ProviderStatusIndicator) throws -> NSBitmapImageRep
    {
        try self.render(
            primaryRemaining: secondaryOnly ? nil : 100,
            weeklyRemaining: secondaryOnly ? 100 : nil,
            indicator: indicator,
            style: .combined)
    }

    private func render(
        primaryRemaining: Double?,
        weeklyRemaining: Double?,
        indicator: ProviderStatusIndicator,
        style: IconStyle) throws -> NSBitmapImageRep
    {
        let image = IconRenderer.makeIcon(
            primaryRemaining: primaryRemaining,
            weeklyRemaining: weeklyRemaining,
            creditsRemaining: nil,
            stale: false,
            style: style,
            statusIndicator: indicator,
            hideCritters: true,
            quotaLayoutPolicy: .provider(.codex))
        return try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.first {
            $0.pixelsWide == 36 && $0.pixelsHigh == 36
        })
    }

    private func pixels(_ rep: NSBitmapImageRep) throws -> Data {
        try Data(bytes: #require(rep.bitmapData), count: rep.bytesPerRow * rep.pixelsHigh)
    }
}
