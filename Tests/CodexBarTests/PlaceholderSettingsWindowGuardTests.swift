import AppKit
import Testing
@testable import CodexBar

@MainActor
struct PlaceholderSettingsWindowGuardTests {
    @Test
    func `closes the empty SwiftUI Settings placeholder window`() {
        _ = NSApplication.shared
        let placeholder = self.makeWindow(
            identifier: "com_apple_SwiftUI_Settings_window",
            frameAutosaveName: "com_apple_SwiftUI_Settings_window")
        placeholder.isRestorable = true
        var closed: [NSWindow] = []
        let guardian = PlaceholderSettingsWindowGuard(
            windows: { [placeholder] },
            isKnownSettingsWindow: { _ in false },
            closeWindow: { closed.append($0) })

        #expect(guardian.sweep() == 1)
        #expect(closed.count == 1)
        #expect(closed.first === placeholder)
        #expect(!placeholder.isRestorable)
    }

    @Test
    func `closes a retained placeholder only once across repeated sweeps`() {
        _ = NSApplication.shared
        let placeholder = self.makeWindow(identifier: "com_apple_SwiftUI_Settings_window")
        var closed: [NSWindow] = []
        let guardian = PlaceholderSettingsWindowGuard(
            windows: { [placeholder] },
            closeWindow: { closed.append($0) })

        #expect(guardian.sweep() == 1)
        for _ in 0..<3 {
            #expect(guardian.sweep() == 0)
        }
        #expect(closed.count == 1)
        #expect(closed.first === placeholder)
    }

    @Test
    func `contains a synchronous reentrant window update while closing`() {
        _ = NSApplication.shared
        let placeholder = self.makeWindow(identifier: "com_apple_SwiftUI_Settings_window")
        var closed: [NSWindow] = []
        let guardian = PlaceholderSettingsWindowGuard(
            windows: { [placeholder] },
            isVisible: { _ in true },
            closeWindow: {
                closed.append($0)
                NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: $0)
            })

        guardian.start()

        #expect(closed.count == 1)
        #expect(closed.first === placeholder)
    }

    @Test
    func `closes the same retained placeholder after it is presented again`() {
        _ = NSApplication.shared
        let placeholder = self.makeWindow(identifier: "com_apple_SwiftUI_Settings_window")
        var isVisible = true
        var closed: [NSWindow] = []
        let guardian = PlaceholderSettingsWindowGuard(
            windows: { [placeholder] },
            isVisible: { _ in isVisible },
            closeWindow: {
                closed.append($0)
                isVisible = false
            })

        #expect(guardian.sweep() == 1)
        #expect(guardian.sweep() == 0)
        isVisible = true
        #expect(guardian.sweep() == 1)
        #expect(closed.count == 2)
        #expect(closed.allSatisfy { $0 === placeholder })
        #expect(guardian.sweep() == 0)
    }

    @Test
    func `closes new placeholders and windows that become placeholders later`() {
        _ = NSApplication.shared
        let placeholder = self.makeWindow(identifier: "com_apple_SwiftUI_Settings_window")
        let laterPlaceholder = self.makeWindow(identifier: "unrelated")
        let state = PlaceholderWindowCollection([placeholder, laterPlaceholder])
        var closed: [NSWindow] = []
        let guardian = PlaceholderSettingsWindowGuard(
            windows: { state.windows },
            closeWindow: { closed.append($0) })

        #expect(guardian.sweep() == 1)
        let newPlaceholder = self.makeWindow(identifier: "com_apple_SwiftUI_Settings_window")
        state.windows.append(newPlaceholder)
        laterPlaceholder.identifier = placeholder.identifier

        #expect(guardian.sweep() == 2)
        #expect(closed.count == 3)
        #expect(closed.contains { $0 === laterPlaceholder })
        #expect(closed.contains { $0 === newPlaceholder })
        #expect(guardian.sweep() == 0)
    }

    @Test
    func `keeps the AppKit Settings window and unrelated windows onscreen`() {
        _ = NSApplication.shared
        let settingsWindow = self.makeWindow(identifier: SettingsWindowIdentity.identifier)
        let updateWindow = self.makeWindow(identifier: "SUUpdateAlert")
        var closed: [NSWindow] = []
        let guardian = PlaceholderSettingsWindowGuard(
            windows: { [settingsWindow, updateWindow] },
            isKnownSettingsWindow: { $0 === settingsWindow },
            closeWindow: { closed.append($0) })

        #expect(guardian.sweep() == 0)
        #expect(closed.isEmpty)
    }

    @Test
    func `recognizes the placeholder by frame autosave name when the identifier is missing`() {
        #expect(PlaceholderSettingsWindowDecision.shouldClose(
            identifier: nil,
            frameAutosaveName: "com_apple_SwiftUI_Settings_window",
            isKnownSettingsWindow: false))
    }

    @Test
    func `never closes the registered Settings window`() {
        #expect(!PlaceholderSettingsWindowDecision.shouldClose(
            identifier: "com_apple_SwiftUI_Settings_window",
            frameAutosaveName: "com_apple_SwiftUI_Settings_window",
            isKnownSettingsWindow: true))
        #expect(!PlaceholderSettingsWindowDecision.shouldClose(
            identifier: SettingsWindowIdentity.identifier,
            frameAutosaveName: SettingsWindowIdentity.frameAutosaveName,
            isKnownSettingsWindow: false))
    }

    @Test
    func `leaves windows without SwiftUI Settings naming alone`() {
        #expect(!PlaceholderSettingsWindowDecision.shouldClose(
            identifier: nil,
            frameAutosaveName: "",
            isKnownSettingsWindow: false))
    }

    private func makeWindow(identifier: String, frameAutosaveName: String = "") -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        if !frameAutosaveName.isEmpty {
            window.setFrameAutosaveName(frameAutosaveName)
        }
        window.isReleasedWhenClosed = false
        return window
    }
}

@MainActor
private final class PlaceholderWindowCollection {
    var windows: [NSWindow]

    init(_ windows: [NSWindow]) {
        self.windows = windows
    }
}
