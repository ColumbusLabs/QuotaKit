import AppKit
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct CostHistoryMenuScrollViewTests {
    @Test(arguments: [200.0, 1400.0])
    func `menu row is bounded while chart document retains its full height`(height: Double) {
        let expectedHeight = CGFloat(height)
        let hosting = MenuHostingView(rootView: Color.clear.frame(width: 400, height: expectedHeight))
        let viewport = CostHistoryMenuScrollView(hosting: hosting, width: 400, maximumHeight: 620)

        #expect(viewport.intrinsicContentSize.height == min(expectedHeight, 620))
        #expect(viewport.fittingSize.height == min(expectedHeight, 620))
        #expect(hosting.frame.height == expectedHeight)
        #expect(viewport.scrollerStyle == .overlay)
        #expect(viewport.contentSize.width == 400)
    }

    @Test
    func `repeated sizing preserves the chart document and scroll position`() {
        let hosting = MenuHostingView(rootView: Color.clear.frame(width: 400, height: 1400))
        let viewport = CostHistoryMenuScrollView(hosting: hosting, width: 400, maximumHeight: 620)
        viewport.contentView.scroll(to: NSPoint(x: 0, y: 100))
        viewport.reflectScrolledClipView(viewport.contentView)
        let origin = viewport.contentView.bounds.origin

        viewport.updateSize(width: 400, maximumHeight: 620)
        #expect(viewport.documentView === hosting)
        #expect(viewport.contentView.bounds.origin == origin)
        #expect(viewport.fittingHeight(width: 400) == 620)
        #expect(viewport.contentView.bounds.origin == origin)
        viewport.updateSize(width: 400, maximumHeight: 400)
        #expect(viewport.documentView === hosting)
        #expect(viewport.intrinsicContentSize.height == 400)
        #expect(hosting.frame.height == 1400)
        #expect(viewport.contentView.bounds.origin == origin)
    }

    @Test(arguments: [100.0, 800.0, 2000.0])
    func `maximum height stays within the screen cap and visible fraction`(visibleFrameHeight: Double) {
        let expected = min(620, max(1, CGFloat(visibleFrameHeight) * 0.72))
        #expect(CostHistoryMenuScrollView.maximumHeight(for: CGFloat(visibleFrameHeight)) == expected)
    }
}
