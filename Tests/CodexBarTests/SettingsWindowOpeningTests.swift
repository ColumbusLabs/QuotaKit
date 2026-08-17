import AppKit
import Testing
@testable import CodexBar

@MainActor
struct SettingsWindowOpeningTests {
    @Test
    func `recreated keepalive shell is configured and missing relay invokes settings fallback`() {
        let keepaliveShell = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        let configuratorView = KeepaliveWindowConfiguratorView(windowProvider: { _ in keepaliveShell })
        configuratorView.viewDidMoveToWindow()

        #expect(keepaliveShell.identifier?.rawValue == "CodexBarLifecycleKeepalive")
        #expect(keepaliveShell.styleMask == [.borderless])
        #expect(keepaliveShell.alphaValue == 0)
        #expect(keepaliveShell.frame.size == NSSize(width: 1, height: 1))

        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        var presentedWindow: NSWindow?
        var prepareCount = 0
        let opener = SettingsWindowOpener(
            prepare: { prepareCount += 1 },
            sendAction: { selector in
                selectors.append(NSStringFromSelector(selector))
                return true
            })

        let outcome = opener.open()

        #expect(outcome == .settingsSelector)
        #expect(prepareCount == 1)
        #expect(selectors == ["showSettingsWindow:"])
    }

    @Test
    func `legacy Preferences action is the fallback`() {
        var selectors: [String] = []
        let opener = SettingsWindowOpener(sendAction: { selector in
            let name = NSStringFromSelector(selector)
            selectors.append(name)
            return name == "showPreferencesWindow:"
        })

        let outcome = opener.open()

        #expect(outcome == .preferencesSelector)
        #expect(selectors == ["showSettingsWindow:", "showPreferencesWindow:"])
    }

    @Test
    func `unhandled Settings actions report failure`() {
        var selectors: [String] = []
        let opener = SettingsWindowOpener(sendAction: { selector in
            selectors.append(NSStringFromSelector(selector))
            return false
        })

        let outcome = opener.open()

        #expect(outcome == .failed)
        #expect(selectors == ["showSettingsWindow:", "showPreferencesWindow:"])
    }
}
