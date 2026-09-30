import AppKit
import CodexBarCore
import SwiftUI
import XCTest
@testable import CodexBar

@MainActor
final class HooksPaneNativeProofTests: XCTestCase {
    func test_emptyInputsExposeAccessiblePromptsWithoutWritingExamples() throws {
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let box = RuleBox()
            let binding = Binding(get: { box.rule }, set: { box.rule = $0 })
            let hosting = NSHostingView(rootView: HookRuleRow(rule: binding, onDelete: {})
                .environment(\.accessibilityEnabled, true))
            hosting.frame = NSRect(x: 0, y: 0, width: 640, height: 320)
            let window = NSWindow(
                contentRect: hosting.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            defer { window.contentView = nil; window.close() }
            _ = hosting.fittingSize
            window.layoutIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            let fields = Self.textFields(in: hosting)
            for prompt in ["/usr/local/bin/my-command", "Argument", "90"] {
                let input = try XCTUnwrap(fields.first { $0.placeholderString == prompt })
                XCTAssertTrue(input.isEditable)
                XCTAssertTrue(input.stringValue.isEmpty)
                let element = try XCTUnwrap(NSAccessibility.unignoredDescendant(of: input) as? NSObject)
                XCTAssertEqual(
                    Self.attribute("accessibilityRole", of: element) as? String,
                    NSAccessibility.Role.textField.rawValue)
                XCTAssertEqual(Self.attribute("accessibilityPlaceholderValue", of: element) as? String, prompt)
            }
            XCTAssertTrue(box.rule.executable.isEmpty)
            XCTAssertEqual(box.rule.arguments, [""])
            XCTAssertNil(box.rule.threshold)
        }
    }

    private static func textFields(in view: NSView) -> [NSTextField] {
        ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap { self.textFields(in: $0) }
    }

    private static func attribute(_ name: String, of element: NSObject) -> Any? {
        let selector = NSSelectorFromString(name)
        guard element.responds(to: selector) else { return nil }
        return element.perform(selector)?.takeUnretainedValue()
    }

    @MainActor
    private final class RuleBox {
        var rule = HookRule(enabled: false, event: .quotaLow, executable: "", arguments: [""])
    }
}
