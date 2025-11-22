import AppKit
import SwiftUI

enum PreferencesTab: String, Hashable {
    case general
    case about
    case debug

    static let windowWidth: CGFloat = 424
    static let windowHeight: CGFloat = 570

    var preferredHeight: CGFloat { PreferencesTab.windowHeight }
}

@MainActor
struct PreferencesView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var store: UsageStore
    let updater: UpdaterProviding
    @ObservedObject var selection: PreferencesSelection
    @State private var contentHeight: CGFloat = PreferencesTab.general.preferredHeight

    var body: some View {
        TabView(selection: self.$selection.tab) {
            GeneralPane(settings: self.settings, store: self.store)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(PreferencesTab.general)

            AboutPane(updater: self.updater)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(PreferencesTab.about)

            if self.settings.debugMenuEnabled {
                DebugPane(settings: self.settings, store: self.store)
                    .tabItem { Label("Debug", systemImage: "ladybug") }
                    .tag(PreferencesTab.debug)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(width: PreferencesTab.windowWidth, height: self.contentHeight)
        .onAppear {
            self.updateHeight(for: self.selection.tab, animate: false)
            self.ensureValidTabSelection()
        }
        .onChange(of: self.selection.tab) { _, newValue in
            self.updateHeight(for: newValue, animate: true)
        }
        .onChange(of: self.settings.debugMenuEnabled) { _, _ in
            self.ensureValidTabSelection()
        }
    }

    private func updateHeight(for tab: PreferencesTab, animate: Bool) {
        let change = { self.contentHeight = tab.preferredHeight }
        if animate {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { change() }
        } else {
            change()
        }
    }

    private func ensureValidTabSelection() {
        if !self.settings.debugMenuEnabled, self.selection.tab == .debug {
            self.selection.tab = .general
            self.updateHeight(for: .general, animate: true)
        }
    }
}
