import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct MetricTextUpdateLayoutTests {
    @Test
    func `longer live pace text renders like a reopened card without changing height`() throws {
        let initial = Self.model(text: "On pace · Lasts until reset")
        let updated = Self.model(text: "32% in deficit · Runs out in 1d 11m")
        #expect(initial.hasCompatibleTrackedLayout(with: updated))

        let before = try Self.render(model: initial, layoutModel: initial)
        let live = try Self.render(model: updated, layoutModel: initial)
        let reopened = try Self.render(model: updated, layoutModel: updated)

        #expect(live.size == before.size)
        #expect(live.size == reopened.size)
        #expect(before.pixels != reopened.pixels, "The fixture must visibly update its text.")
        #expect(live.pixels == reopened.pixels, "Frozen layout must not clip text that fits the card width.")
    }

    private static func model(text: String) -> UsageMenuCardView.Model {
        UsageMenuCardView.Model(
            provider: .kimi,
            providerName: "Kimi Code",
            email: "synthetic@example.test",
            subtitleText: "Updated just now",
            subtitleStyle: .info,
            planText: nil,
            metrics: [.init(
                id: "primary",
                title: "7-day usage",
                percent: 68,
                percentStyle: .left,
                resetText: "Resets in 3d 2h",
                detailText: nil,
                detailLeftText: text,
                detailRightText: nil,
                pacePercent: 36,
                detailIsPaceDerived: true,
                paceOnTop: false)],
            usageNotes: [],
            openAIAPIUsage: nil,
            inlineUsageDashboard: nil,
            creditsText: nil,
            creditsRemaining: nil,
            creditsHintText: nil,
            creditsHintCopyText: nil,
            providerCost: nil,
            tokenUsage: nil,
            placeholder: nil,
            progressColor: .blue)
    }

    private static func render(
        model: UsageMenuCardView.Model,
        layoutModel: UsageMenuCardView.Model) throws -> (size: CGSize, pixels: Data)
    {
        let view = UsageMenuCardUsageSectionView(
            model: model,
            layoutModel: layoutModel,
            showBottomDivider: false,
            bottomPadding: 6,
            width: 320)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.colorScheme, .light)
            .environment(\.displayScale, 2)
            .background(Color.white)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        let size = hosting.fittingSize
        #expect(size.width == 320)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        let pixelWidth = Int(ceil(size.width * scale))
        let pixelHeight = Int(ceil(size.height * scale))
        let representation = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelWidth * 4,
            bitsPerPixel: 32))
        representation.size = size
        let pixels = try #require(representation.bitmapData)
        let byteCount = representation.bytesPerRow * pixelHeight
        pixels.initialize(repeating: 0, count: byteCount)
        let context = try #require(NSGraphicsContext(bitmapImageRep: representation))
        hosting.displayIgnoringOpacity(hosting.bounds, in: context)
        return (size, Data(bytes: pixels, count: byteCount))
    }
}
