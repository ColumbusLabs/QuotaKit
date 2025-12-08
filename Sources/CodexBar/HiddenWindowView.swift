import SwiftUI

struct HiddenWindowView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 20, height: 20)
            .onReceive(NotificationCenter.default.publisher(for: .codexbarOpenSettings)) { _ in
                Task { @MainActor in
                    self.openSettings()
                }
            }
            .onAppear {
                if let window = NSApp.windows.first(where: { $0.title == "CodexBarLifecycleKeepalive" }) {
                    window.collectionBehavior = [.auxiliary, .ignoresCycle, .transient]
                    window.isExcludedFromWindowsMenu = true
                    window.level = .floating
                    window.isOpaque = false
                    window.backgroundColor = .clear
                    window.hasShadow = false
                    window.ignoresMouseEvents = true
                    window.canHide = false
                    window.setContentSize(NSSize(width: 20, height: 20))
                }
            }
    }
}
