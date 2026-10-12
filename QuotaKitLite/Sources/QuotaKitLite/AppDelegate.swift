import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let icon = LiteResources.templateIcon(named: "ProviderIcon-claude") {
            item.button?.image = icon
        } else {
            // Running outside the `.app` bundle (for example `swift run`), so there are no resources.
            item.button?.title = "QK"
        }
        item.button?.setAccessibilityLabel("QuotaKit Lite")
        item.menu = self.makeMenu()
        self.statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit QuotaKit Lite",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        return menu
    }
}
