import AppKit
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct SettingsSidebarSizingTests {
    private static let nativeColumnChromeWidth: CGFloat = 8

    @Test
    func `native sidebar saves divider changes and restores them in a new view`() async throws {
        let width = SidebarWidth(value: 320)
        let firstWindow = self.makeWindow(width: width)
        try await self.settle(firstWindow)
        let initialSplit = try #require(self.attachedSplitView(in: firstWindow))
        let initialController = try #require(initialSplit.delegate as? NSSplitViewController)
        let initialSidebar = try #require(initialController.splitViewItems.first)
        // The saved value tracks hosted content like the legacy frame; native split columns add 8pt of chrome.
        #expect(initialSidebar.viewController.view.frame.width == CGFloat(width.value))
        #expect(initialSplit.subviews[0].frame.width == CGFloat(width.value) + Self.nativeColumnChromeWidth)

        let dividerPosition: CGFloat = 300
        initialSplit.setPosition(dividerPosition, ofDividerAt: 0)
        try await self.settle(firstWindow)
        // Updating the bound width can rebuild NavigationSplitView. Resolve the current attached split after layout.
        let resizedSplit = try #require(self.attachedSplitView(in: firstWindow))
        let resizedController = try #require(resizedSplit.delegate as? NSSplitViewController)
        let resizedSidebar = try #require(resizedController.splitViewItems.first)
        #expect(resizedSplit.subviews[0].frame.width == dividerPosition)
        #expect(width.value == Double(dividerPosition - Self.nativeColumnChromeWidth))
        #expect(resizedSidebar.viewController.view.frame.width == CGFloat(width.value))

        let secondWindow = self.makeWindow(width: width)
        try await self.settle(secondWindow)
        let secondSplit = try #require(self.attachedSplitView(in: secondWindow))
        let secondController = try #require(secondSplit.delegate as? NSSplitViewController)
        let secondSidebar = try #require(secondController.splitViewItems.first)
        #expect(secondSidebar.viewController.view.frame.width == CGFloat(width.value))
        #expect(secondSplit.subviews[0].frame.width == dividerPosition)
        #expect(
            secondSplit.subviews[0].frame.width == secondSidebar.viewController.view.frame.width +
                Self.nativeColumnChromeWidth)

        #expect(resizedSidebar.canCollapse)
        resizedSidebar.isCollapsed = true
        try await self.settle(firstWindow)
        let collapsedSplit = try #require(self.attachedSplitView(in: firstWindow))
        let collapsedController = try #require(collapsedSplit.delegate as? NSSplitViewController)
        let collapsedSidebar = try #require(collapsedController.splitViewItems.first)
        #expect(collapsedSidebar.isCollapsed)
        #expect(width.value == Double(dividerPosition - Self.nativeColumnChromeWidth))
        collapsedSidebar.isCollapsed = false
        try await self.settle(firstWindow)
        let expandedSplit = try #require(self.attachedSplitView(in: firstWindow))
        let expandedController = try #require(expandedSplit.delegate as? NSSplitViewController)
        let expandedSidebar = try #require(expandedController.splitViewItems.first)
        #expect(width.value == Double(dividerPosition - Self.nativeColumnChromeWidth))
        #expect(expandedSidebar.viewController.view.frame.width == CGFloat(width.value))
        #expect(expandedSplit.subviews[0].frame.width == dividerPosition)
    }

    @Test
    func `native sidebar keeps the existing saved minimum width`() async throws {
        let width = SidebarWidth(value: 200)
        let window = self.makeWindow(width: width)
        try await self.settle(window)
        let content = try #require(window.contentView)
        let split = try #require(self.splitView(in: content))
        let controller = try #require(split.delegate as? NSSplitViewController)
        let sidebar = try #require(controller.splitViewItems.first)
        #expect(sidebar.viewController.view.frame.width == 200)
        #expect(width.value == 200)
        #expect(sidebar.canCollapse)
        #expect(sidebar.minimumThickness == SettingsPane.sidebarMinWidth)
        #expect(sidebar.maximumThickness == SettingsPane.sidebarMaxWidth)
    }

    private func makeWindow(width: SidebarWidth) -> NSWindow {
        _ = NSApplication.shared
        // Wide enough that the detail column's minimum width never limits sidebar resizing.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: SettingsPane.windowHeight),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.contentViewController = NSHostingController(rootView: SidebarHarness(width: width))
        return window
    }

    private func splitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        return view.subviews.lazy.compactMap { self.splitView(in: $0) }.first
    }

    private func attachedSplitView(in window: NSWindow) -> NSSplitView? {
        guard let contentView = window.contentView,
              let splitView = self.splitView(in: contentView), splitView.window === window
        else {
            return nil
        }
        return splitView
    }

    private func settle(_ window: NSWindow) async throws {
        // Allow the hosting view's deferred layout and geometry callbacks to finish without showing a window.
        for _ in 0..<5 {
            window.contentView?.layoutSubtreeIfNeeded()
            self.attachedSplitView(in: window)?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
@Observable
private final class SidebarWidth {
    var value: Double

    init(value: Double) {
        self.value = value
    }
}

@MainActor
private struct SidebarHarness: View {
    @Bindable var width: SidebarWidth

    var body: some View {
        NavigationSplitView {
            Color.clear
                .modifier(SettingsSidebarSizing(width: self.$width.value))
        } detail: {
            Color.clear
        }
    }
}
