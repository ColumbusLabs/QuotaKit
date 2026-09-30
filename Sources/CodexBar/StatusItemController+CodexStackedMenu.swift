import AppKit
import CodexBarCore
import SwiftUI

extension StatusItemController {
    func addStackedCodexMenuCards(
        _ display: CodexAccountMenuDisplay,
        to menu: NSMenu,
        context: MenuCardContext)
    {
        let snapshotsByAccountID = Dictionary(uniqueKeysWithValues: display.snapshots.map {
            ($0.account.id, $0)
        })
        var cardIndex = 0
        let sections = display.showsWorkspaceGroups ? display.workspaceSections : [
            CodexAccountWorkspaceSection(title: "", accounts: display.accounts),
        ]
        let workspaceTitles = CodexWorkspaceHeaderPrivacy.titles(
            for: sections,
            hidePersonalInfo: self.settings.hidePersonalInfo)

        for (sectionIndex, section) in sections.enumerated() {
            if display.showsWorkspaceGroups {
                self.addCodexWorkspaceHeader(workspaceTitles[sectionIndex], index: sectionIndex, to: menu)
            }

            for account in section.accounts {
                let accountSnapshot = snapshotsByAccountID[account.id]
                let health = CodexAccountHealth.status(for: account, error: accountSnapshot?.error)
                let model = self.menuCardModel(
                    for: .codex,
                    snapshotOverride: accountSnapshot?.snapshot,
                    errorOverride: health.label,
                    forceOverrideCard: accountSnapshot == nil,
                    accountOverride: self.accountInfo(for: account),
                    historySelectionOverride: self.store.codexPlanUtilizationHistorySelection(
                        forVisibleAccount: account),
                    creditsOverride: accountSnapshot?.credits)
                guard let model else { continue }
                menu.addItem(self.makeMenuCardItem(
                    UsageMenuCardView(model: model, width: context.menuWidth),
                    id: "menuCard-\(cardIndex)",
                    width: context.menuWidth,
                    heightCacheScope: account.id,
                    heightCacheFingerprint: model.heightFingerprint(section: "card"),
                    containsInteractiveControls: true))
                cardIndex += 1
                if account.id != section.accounts.last?.id {
                    menu.addItem(.separator())
                }
            }

            if sectionIndex < sections.count - 1 {
                menu.addItem(.separator())
            }
        }

        if cardIndex == 0, let model = self.menuCardModel(for: context.selectedProvider) {
            menu.addItem(self.makeMenuCardItem(
                UsageMenuCardView(model: model, width: context.menuWidth),
                id: "menuCard",
                width: context.menuWidth,
                heightCacheScope: context.currentProvider.rawValue,
                heightCacheFingerprint: model.heightFingerprint(section: "card"),
                containsInteractiveControls: true))
        }
        menu.addItem(.separator())
        if self.addStorageMenuCardSection(to: menu, provider: context.currentProvider, width: context.menuWidth) {
            menu.addItem(.separator())
        }
    }

    func addCodexAccountMenuCards(
        _ display: CodexAccountMenuDisplay,
        to menu: NSMenu,
        captureMenu: NSMenu,
        context: MenuCardContext)
    {
        if !self.addCompactCodexAccountMenuIfPlanned(
            display: display, to: menu, captureMenu: captureMenu, context: context)
        {
            self.addStackedCodexMenuCards(display, to: menu, context: context)
        }
        self.addAccountAgnosticCostMenuSection(to: menu, context: context)
    }

    func addAccountAgnosticCostMenuSection(to menu: NSMenu, context: MenuCardContext) {
        let provider = context.currentProvider
        guard self.store.tokenCostIsAccountAgnostic(for: provider),
              let model = self.menuCardModel(for: provider),
              model.inlineUsageDashboard != nil || model.tokenUsage != nil
        else { return }
        if menu.items.last?.isSeparatorItem != true {
            menu.addItem(.separator())
        }
        let scope = NSMenuItem(title: L("This Mac"), action: nil, keyEquivalent: "")
        scope.isEnabled = false
        scope.representedObject = "sharedCodexCostScope"
        menu.addItem(scope)
        if let dashboard = model.inlineUsageDashboard {
            menu.addItem(self.makeMenuCardItem(
                InlineUsageDashboardContent(model: dashboard)
                    .padding(.horizontal, UsageMenuCardLayout.horizontalPadding)
                    .padding(.vertical, 6)
                    .frame(width: context.menuWidth),
                id: "sharedCodexInlineCost",
                width: context.menuWidth,
                heightCacheScope: provider.rawValue,
                heightCacheFingerprint: model.heightFingerprint(section: "usage")))
        }
        if model.tokenUsage != nil {
            menu.addItem(self.makeCostMenuCardItem(
                model: model,
                submenu: self.makeCostHistorySubmenu(provider: provider, width: context.menuWidth),
                width: context.menuWidth))
        }
        menu.addItem(.separator())
    }

    private func addCodexWorkspaceHeader(_ title: String, index: Int, to menu: NSMenu) {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.representedObject = "codexWorkspace-\(index)"
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        header.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        menu.addItem(header)
    }
}

enum CodexWorkspaceHeaderPrivacy {
    static func titles(
        for sections: [CodexAccountWorkspaceSection],
        hidePersonalInfo: Bool) -> [String]
    {
        guard hidePersonalInfo else { return sections.map(\.title) }
        let orderedKeys = Set(sections.map(self.stableKey)).sorted()
        let ordinalByKey = Dictionary(uniqueKeysWithValues: orderedKeys.enumerated().map { index, key in
            (key, index + 1)
        })
        return sections.map { section in
            let ordinal = ordinalByKey[self.stableKey(section)] ?? 1
            return "\(L("Workspace")) \(ordinal)"
        }
    }

    private static func stableKey(_ section: CodexAccountWorkspaceSection) -> String {
        let accountKeys = section.accounts.map { account in
            account.storedAccountID?.uuidString ?? account.id
        }.sorted()
        let workspaceIDs = section.accounts.compactMap {
            ManagedCodexAccount.normalizeWorkspaceAccountID($0.workspaceAccountID)
        }.sorted()
        let stableIdentity = workspaceIDs.isEmpty ? accountKeys : workspaceIDs
        return stableIdentity.joined(separator: "\0")
    }
}
