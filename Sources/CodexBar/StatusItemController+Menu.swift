import AppKit
import CodexBarCore
import SwiftUI

// MARK: - NSMenu construction

extension StatusItemController {
    private static let menuCardWidth: CGFloat = 300

    func makeMenu(for provider: UsageProvider?) -> NSMenu {
        let targetProvider = provider ?? self.store.enabledProviders().first ?? .codex
        let descriptor = MenuDescriptor.build(
            provider: provider,
            store: self.store,
            settings: self.settings,
            account: self.account)
        let dashboard = self.store.openAIDashboard
        let openAIWebEligible = targetProvider == .codex &&
            self.settings.openAIDashboardEnabled &&
            self.store.openAIDashboardRequiresLogin == false &&
            dashboard != nil
        let hasCreditsHistory = openAIWebEligible && !(dashboard?.creditEvents ?? []).isEmpty
        let hasUsageBreakdown = openAIWebEligible && !(dashboard?.usageBreakdown ?? []).isEmpty
        let hasOpenAIWebMenuItems = hasCreditsHistory || hasUsageBreakdown

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        if let provider {
            self.menuProviders[ObjectIdentifier(menu)] = provider
        }

        if let model = self.menuCardModel(for: provider) {
            let cardView = UsageMenuCardView(model: model)
            let hosting = NSHostingView(rootView: cardView)
            // Important: constrain width before asking SwiftUI for the fitting height, otherwise text wrapping
            // changes the required height and the menu item becomes visually "squeezed".
            hosting.frame = NSRect(origin: .zero, size: NSSize(width: Self.menuCardWidth, height: 1))
            hosting.layoutSubtreeIfNeeded()
            let size = hosting.fittingSize
            hosting.frame = NSRect(origin: .zero, size: NSSize(width: Self.menuCardWidth, height: size.height))
            let item = NSMenuItem()
            item.view = hosting
            item.isEnabled = false
            item.representedObject = "menuCard"
            menu.addItem(item)
            // Keep the menu visually grouped. If we show the credits history submenu, it should sit directly
            // below the Credits line (no separator in between) with a small spacer to read as a "new line".
            if hasCreditsHistory {
                let spacer = NSMenuItem()
                spacer.view = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 1, height: 10)))
                spacer.isEnabled = false
                spacer.representedObject = "menuCardCreditsSpacer"
                menu.addItem(spacer)
            } else if model.subtitleStyle == .info {
                menu.addItem(.separator())
            }
        }

        if hasOpenAIWebMenuItems {
            // Only show these when we actually have OpenAI web-only data.
            if hasCreditsHistory {
                _ = self.addCreditsHistorySubmenu(to: menu)
            }
            if hasUsageBreakdown {
                _ = self.addUsageBreakdownSubmenu(to: menu)
            }
            menu.addItem(.separator())
        }

        let actionableSections = Array(descriptor.sections.suffix(2))
        for (index, section) in actionableSections.enumerated() {
            for entry in section.entries {
                switch entry {
                case let .text(text, style):
                    let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    if style == .headline {
                        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
                        item.attributedTitle = NSAttributedString(string: text, attributes: [.font: font])
                    } else if style == .secondary {
                        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                        item.attributedTitle = NSAttributedString(
                            string: text,
                            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
                    }
                    menu.addItem(item)
                case let .action(title, action):
                    let (selector, represented) = self.selector(for: action)
                    let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
                    item.target = self
                    item.representedObject = represented
                    if let iconName = action.systemImageName,
                       let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
                    {
                        image.isTemplate = true
                        image.size = NSSize(width: 16, height: 16)
                        item.image = image
                    }
                    if case let .switchAccount(targetProvider) = action,
                       let subtitle = self.switchAccountSubtitle(for: targetProvider)
                    {
                        item.subtitle = subtitle
                        item.isEnabled = false
                    }
                    menu.addItem(item)
                case .divider:
                    menu.addItem(.separator())
                }
            }
            if index < actionableSections.count - 1 {
                menu.addItem(.separator())
            }
        }
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Re-measure the menu card height right before display to avoid stale/incorrect sizing when content
        // changes (e.g. dashboard error lines causing wrapping).
        if let item = menu.items.first(where: { ($0.representedObject as? String) == "menuCard" }),
           let view = item.view
        {
            view.frame = NSRect(origin: .zero, size: NSSize(width: Self.menuCardWidth, height: 1))
            view.layoutSubtreeIfNeeded()
            let height = view.fittingSize.height
            view.frame = NSRect(origin: .zero, size: NSSize(width: Self.menuCardWidth, height: height))
        }

        if let provider = self.menuProviders[ObjectIdentifier(menu)] {
            self.lastMenuProvider = provider
        } else {
            self.lastMenuProvider = self.store.enabledProviders().first ?? .codex
        }
    }

    private func selector(for action: MenuDescriptor.MenuAction) -> (Selector, Any?) {
        switch action {
        case .refresh: (#selector(self.refreshNow), nil)
        case .dashboard: (#selector(self.openDashboard), nil)
        case .statusPage: (#selector(self.openStatusPage), nil)
        case let .switchAccount(provider): (#selector(self.runSwitchAccount(_:)), provider.rawValue)
        case .settings: (#selector(self.showSettingsGeneral), nil)
        case .about: (#selector(self.showSettingsAbout), nil)
        case .quit: (#selector(self.quit), nil)
        case let .copyError(message): (#selector(self.copyError(_:)), message)
        }
    }

    @discardableResult
    private func addCreditsHistorySubmenu(to menu: NSMenu) -> Bool {
        let events = self.store.openAIDashboard?.creditEvents ?? []
        guard !events.isEmpty else { return false }

        let item = NSMenuItem(title: "Credits usage history", action: nil, keyEquivalent: "")
        item.isEnabled = true
        let submenu = NSMenu()

        let limit = 20
        for event in events.prefix(limit) {
            let line = UsageFormatter.creditEventCompact(event)
            let row = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            row.isEnabled = false
            submenu.addItem(row)
        }
        if events.count > limit {
            submenu.addItem(.separator())
            let more = NSMenuItem(title: "Showing \(limit) of \(events.count)", action: nil, keyEquivalent: "")
            more.isEnabled = false
            submenu.addItem(more)
        }

        item.submenu = submenu
        menu.addItem(item)
        return true
    }

    @discardableResult
    private func addUsageBreakdownSubmenu(to menu: NSMenu) -> Bool {
        let breakdown = self.store.openAIDashboard?.usageBreakdown ?? []
        guard !breakdown.isEmpty else { return false }

        let item = NSMenuItem(title: "Usage breakdown", action: nil, keyEquivalent: "")
        item.isEnabled = true
        let submenu = NSMenu()
        let chartView = UsageBreakdownChartMenuView(breakdown: breakdown)
        let hosting = NSHostingView(rootView: chartView)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: Self.menuCardWidth, height: 1))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: Self.menuCardWidth, height: size.height))

        let chartItem = NSMenuItem()
        chartItem.view = hosting
        chartItem.isEnabled = false
        chartItem.representedObject = "usageBreakdownChart"
        submenu.addItem(chartItem)

        item.submenu = submenu
        menu.addItem(item)
        return true
    }

    private func menuCardModel(for provider: UsageProvider?) -> UsageMenuCardView.Model? {
        let target = provider ?? self.store.enabledProviders().first ?? .codex
        let metadata = self.store.metadata(for: target)

        let snapshot = self.store.snapshot(for: target)
        let credits: CreditsSnapshot?
        let creditsError: String?
        let dashboard: OpenAIDashboardSnapshot?
        let dashboardError: String?
        if target == .codex {
            credits = self.store.credits
            creditsError = self.store.lastCreditsError
            dashboard = self.store.openAIDashboardRequiresLogin ? nil : self.store.openAIDashboard
            dashboardError = self.store.lastOpenAIDashboardError
        } else {
            credits = nil
            creditsError = nil
            dashboard = nil
            dashboardError = nil
        }

        let input = UsageMenuCardView.Model.Input(
            provider: target,
            metadata: metadata,
            snapshot: snapshot,
            credits: credits,
            creditsError: creditsError,
            dashboard: dashboard,
            dashboardError: dashboardError,
            account: self.account,
            isRefreshing: self.store.isRefreshing,
            lastError: self.store.error(for: target),
            usageBarsShowUsed: self.settings.usageBarsShowUsed)
        return UsageMenuCardView.Model.make(input)
    }
}

extension Notification.Name {
    static let codexbarOpenSettings = Notification.Name("codexbarOpenSettings")
    static let codexbarDebugBlinkNow = Notification.Name("codexbarDebugBlinkNow")
}
