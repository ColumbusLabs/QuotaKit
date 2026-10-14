import Foundation
import Testing
@testable import CodexBar

struct MenuInlineCodeTextTests {
    @Test
    func `single inline code span removes delimiters and marks code`() {
        let text = MenuInlineCodeText.attributed("Run `claude` to authenticate.")
        #expect(String(text.characters) == "Run claude to authenticate.")
        #expect(self.codeRuns(text) == ["claude"])
    }

    @Test
    func `multiple inline code spans preserve surrounding text`() {
        let text = MenuInlineCodeText.attributed("Run `claude` then `status`.")
        #expect(String(text.characters) == "Run claude then status.")
        #expect(self.codeRuns(text) == ["claude", "status"])
    }

    @Test(arguments: ["Run `claude", "Run claude`", "Empty `` stays", "``claude`` stays", "```code``` stays"])
    func `unbalanced empty and multiple backticks stay literal`(raw: String) {
        let text = MenuInlineCodeText.attributed(raw)
        #expect(String(text.characters) == raw)
        #expect(self.codeRuns(text).isEmpty)
    }

    @Test
    func `other markup and unicode stay literal`() {
        let raw = "*bold* _path_ [x](y) https://example.com/a_b `命令` /tmp/a*b"
        let text = MenuInlineCodeText.attributed(raw)
        #expect(String(text.characters) == "*bold* _path_ [x](y) https://example.com/a_b 命令 /tmp/a*b")
        #expect(self.codeRuns(text) == ["命令"])
        #expect(text.runs.allSatisfy { $0.link == nil && $0.presentationIntent == nil })
    }

    private func codeRuns(_ text: AttributedString) -> [String] {
        text.runs.compactMap { run in
            run.inlinePresentationIntent == .code ? String(text[run.range].characters) : nil
        }
    }
}
