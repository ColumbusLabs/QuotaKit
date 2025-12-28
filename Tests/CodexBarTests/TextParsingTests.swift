import CodexBarCore
import Testing

@Suite
struct TextParsingTests {
    @Test
    func stripANSICodesRemovesCursorVisibilityCSI() {
        let input = "\u{001B}[?25hhello\u{001B}[0m"
        let stripped = TextParsing.stripANSICodes(input)
        #expect(stripped == "hello")
    }
}
