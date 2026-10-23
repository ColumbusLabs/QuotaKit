import SwiftUI

/// Share the saved width with the legacy sidebar while letting the native divider handle dragging.
struct SettingsSidebarSizing: ViewModifier {
    @Binding var width: Double
    @State private var initialIdealWidth: CGFloat

    init(width: Binding<Double>) {
        self._width = width
        // Seed each new sidebar from the saved content width, then let the native divider own its live size.
        // Keep persistence updates from changing the column's preferred width while it is attached.
        self._initialIdealWidth = State(initialValue: min(
            max(CGFloat(width.wrappedValue), SettingsPane.sidebarMinWidth),
            SettingsPane.sidebarMaxWidth))
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { newWidth in
                // Ignore transient zero/undersized measurements while the split view is being attached.
                guard newWidth >= SettingsPane.sidebarMinWidth,
                      newWidth <= SettingsPane.sidebarMaxWidth,
                      abs(self.width - newWidth) > 0.5 else { return }
                self.width = newWidth
            }
            // Keep this last so the column preference reaches NavigationSplitView.
            .navigationSplitViewColumnWidth(
                min: SettingsPane.sidebarMinWidth,
                ideal: self.initialIdealWidth,
                max: SettingsPane.sidebarMaxWidth)
    }
}
