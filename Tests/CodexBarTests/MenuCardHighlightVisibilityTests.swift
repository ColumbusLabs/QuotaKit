import Testing
@testable import CodexBar

struct MenuCardHighlightVisibilityTests {
    @Test
    func `pointer highlight can be disabled while keyboard selection remains visible`() {
        #expect(!menuCardHighlightShouldRender(
            highlighted: true,
            enabled: true,
            allowsHighlight: true,
            hoverHighlightEnabled: false,
            keyboardSelected: false))
        #expect(menuCardHighlightShouldRender(
            highlighted: true,
            enabled: true,
            allowsHighlight: true,
            hoverHighlightEnabled: false,
            keyboardSelected: true))
        #expect(menuCardHighlightShouldRender(
            highlighted: true,
            enabled: true,
            allowsHighlight: true,
            hoverHighlightEnabled: true,
            keyboardSelected: false))
    }

    @Test
    func `disabled or non-highlightable rows never render custom selection`() {
        #expect(!menuCardHighlightShouldRender(
            highlighted: true,
            enabled: false,
            allowsHighlight: true,
            hoverHighlightEnabled: true,
            keyboardSelected: true))
        #expect(!menuCardHighlightShouldRender(
            highlighted: true,
            enabled: true,
            allowsHighlight: false,
            hoverHighlightEnabled: true,
            keyboardSelected: true))
        #expect(!menuCardHighlightShouldRender(
            highlighted: false,
            enabled: true,
            allowsHighlight: true,
            hoverHighlightEnabled: true,
            keyboardSelected: true))
    }
}
