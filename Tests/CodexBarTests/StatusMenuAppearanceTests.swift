import AppKit
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct StatusMenuAppearanceTests {
    private final class AppearanceSource: NSObject {
        @objc dynamic var appearance: NSAppearance

        init(_ appearance: NSAppearance) {
            self.appearance = appearance
            super.init()
        }
    }

    private final class AppearanceTrackingMenu: NSMenu {
        var appearanceAssignmentCount = 0

        override var appearance: NSAppearance? {
            didSet {
                self.appearanceAssignmentCount += 1
            }
        }
    }

    @Test
    func `pin uses the exact application effective appearance`() {
        let menu = NSMenu()
        let effectiveAppearance = NSApplication.shared.effectiveAppearance

        StatusMenuAppearance.pin(menu)

        #expect(menu.appearance === effectiveAppearance)
    }

    @Test
    func `pin reassigns an appearance even when its name is unchanged`() throws {
        let menu = AppearanceTrackingMenu()
        let appearance = try #require(NSAppearance(named: .aqua))
        menu.appearance = appearance
        let assignmentsBeforePin = menu.appearanceAssignmentCount

        StatusMenuAppearance.pin(menu, to: appearance)

        #expect(menu.appearance === appearance)
        #expect(menu.appearanceAssignmentCount == assignmentsBeforePin + 1)
    }

    @Test
    func `previously opened nested menus inherit each refreshed root appearance`() throws {
        let menu = NSMenu()
        let submenu = NSMenu()
        let nestedMenu = NSMenu()
        let item = NSMenuItem(title: "Details", action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
        let nestedItem = NSMenuItem(title: "Daily details", action: nil, keyEquivalent: "")
        nestedItem.submenu = nestedMenu
        submenu.addItem(nestedItem)

        let lightAppearance = try #require(NSAppearance(named: .aqua))
        StatusMenuAppearance.pin(menu, to: lightAppearance)
        StatusMenuAppearance.pin(submenu, to: lightAppearance)
        StatusMenuAppearance.pin(nestedMenu, to: lightAppearance)
        #expect(menu.appearance === lightAppearance)
        #expect(submenu.appearance === lightAppearance)
        #expect(nestedMenu.appearance === lightAppearance)

        let darkAppearance = try #require(NSAppearance(named: .darkAqua))
        StatusMenuAppearance.pin(menu, to: darkAppearance)
        #expect(menu.appearance === darkAppearance)
        #expect(submenu.appearance == nil)
        #expect(nestedMenu.appearance == nil)
        #expect(submenu.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        #expect(nestedMenu.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    @Test
    func `appearance observation refreshes cached menus before they open and stops cleanly`() async throws {
        let lightAppearance = try #require(NSAppearance(named: .aqua))
        let darkAppearance = try #require(NSAppearance(named: .darkAqua))
        let source = AppearanceSource(lightAppearance)
        let menu = NSMenu()
        StatusMenuAppearance.pin(menu, to: lightAppearance)
        let observer = StatusMenuAppearanceObserver(source: source, appearance: \.appearance) {
            StatusMenuAppearance.pin(menu, to: $0)
        }
        defer { observer.stop() }

        source.appearance = darkAppearance
        await Self.drainAppearanceQueue()
        #expect(menu.appearance === darkAppearance)

        observer.stop()
        source.appearance = lightAppearance
        await Self.drainAppearanceQueue()
        #expect(menu.appearance === darkAppearance)
    }

    private static func drainAppearanceQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
}
