import AppKit
import CodexBarCore

struct MenuBarLayoutLaneLabels: Hashable {
    private enum Label: Hashable {
        case localized(String)
        case supplied(String)

        var value: String {
            switch self {
            case let .localized(key): L(key)
            case let .supplied(text): text
            }
        }
    }

    let isPlugin: Bool
    private let primaryLabel: Label
    private let secondaryLabel: Label
    private let tertiaryLabel: Label

    var primary: String {
        self.primaryLabel.value
    }

    var secondary: String {
        self.secondaryLabel.value
    }

    var tertiary: String {
        self.tertiaryLabel.value
    }

    init(provider: UsageProvider, snapshot: UsageSnapshot?) {
        self.isPlugin = false
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        let labels = snapshot.map {
            descriptor.presentation.rateWindowLabels(metadata: descriptor.metadata, snapshot: $0)
        }
        self.primaryLabel = .localized(labels?.primary ?? descriptor.metadata.sessionLabel)
        self.secondaryLabel = .localized(labels?.secondary ?? descriptor.metadata.weeklyLabel)
        self.tertiaryLabel = .localized(labels?.tertiary ?? descriptor.metadata.opusLabel ?? "Tertiary")
    }

    init(pluginSnapshot: UsageSnapshot?) {
        self.isPlugin = true
        self.primaryLabel = (pluginSnapshot?.primary?.title).map(Label.supplied) ?? .localized("Primary")
        self.secondaryLabel = (pluginSnapshot?.secondary?.title).map(Label.supplied) ?? .localized("Secondary")
        self.tertiaryLabel = (pluginSnapshot?.tertiary?.title).map(Label.supplied) ?? .localized("Tertiary")
    }

    func label(for lane: MenuBarLayoutLane) -> String {
        switch lane {
        case .primary: self.primary
        case .secondary: self.secondary
        case .tertiary: self.tertiary
        }
    }
}

extension MenuBarLayoutRenderData {
    static func plugin(
        instanceID: ProviderInstanceID,
        name: String,
        snapshot: UsageSnapshot?,
        iconKey: String,
        hidePersonalInfo: Bool) -> Self
    {
        let primary = MenuBarLayoutRenderWindow(snapshot?.primary)
        let secondary = MenuBarLayoutRenderWindow(snapshot?.secondary)
        return Self(
            iconKey: iconKey,
            providerName: name,
            accountLabel: hidePersonalInfo || snapshot?.identity?.providerID != instanceID
                ? nil : snapshot?.identity?.accountEmail,
            laneLabels: MenuBarLayoutLaneLabels(pluginSnapshot: snapshot),
            primary: primary,
            secondary: secondary,
            tertiary: MenuBarLayoutRenderWindow(snapshot?.tertiary),
            quotaIsEstimated: snapshot?.dataConfidence == .estimated,
            extraRateWindows: (snapshot?.extraRateWindows ?? []).map(MenuBarLayoutRenderExtra.init),
            session: primary,
            weekly: secondary,
            scopedWeekly: nil,
            scopedWeeklyTitle: nil,
            automatic: MenuBarLayoutRenderWindow(StatusItemController.pluginMetricWindow(snapshot: snapshot)),
            automaticText: nil,
            sessionPace: nil,
            weeklyPace: nil,
            automaticPace: nil,
            runsOut: nil,
            balance: nil,
            tokensPerMinute: snapshot?.throughput?.latestTokensPerMinute,
            tokensSparkline: snapshot?.throughput.map { MenuBarTokensSparkline(minutes: $0.minutes) },
            costToday: nil,
            cost30d: nil,
            metrics: .unavailable)
    }
}

extension StatusItemController {
    func renderedMenuBarLayoutResolution(forInstanceID instanceID: ProviderInstanceID) -> MenuBarLayoutResolution {
        if let provider = instanceID.firstPartyProvider {
            return self.renderedMenuBarLayoutResolution(for: provider)
        }
        return .stored(self.settings.menuBarLayout(forPlugin: instanceID))
    }

    func menuBarLayoutRenderData(for instanceID: ProviderInstanceID, now: Date) -> MenuBarLayoutRenderData {
        if let provider = instanceID.firstPartyProvider {
            return self.menuBarLayoutRenderData(
                provider: provider,
                snapshot: self.menuBarUsageSource(for: provider).snapshot,
                warningFlash: self.quotaWarningFlashActive(provider: provider),
                now: now)
        }
        let plugin = UserProviderPluginRegistry.plugin(for: instanceID)
        let snapshot = self.store.menuBarSnapshot(for: instanceID)
        return .plugin(
            instanceID: instanceID,
            name: plugin?.manifest.name ?? instanceID.rawValue,
            snapshot: snapshot,
            iconKey: "\(plugin?.sourceHash ?? instanceID.rawValue):\(snapshot?.iconProvider?.rawValue ?? "")",
            hidePersonalInfo: self.settings.hidePersonalInfo)
    }

    func applyPluginMenuBarLayout(instanceID: ProviderInstanceID, icon: NSImage, now: Date = .init()) -> Bool? {
        guard self.settings.menuBarIconStyle == .iconAndPercent, let button = self.statusItem.button else { return nil }
        let data = self.menuBarLayoutRenderData(for: instanceID, now: now)
        let rendered = self.menuBarLayoutRenderer.render(
            layout: self.renderedMenuBarLayoutResolution(forInstanceID: instanceID).layout,
            data: data,
            icon: icon,
            options: self.menuBarLayoutRenderOptions(forInstanceID: instanceID, button: button, now: now))
        self.lastAppliedMergedIconRenderSignature = nil
        self.statusItem.length = Self.applyMenuBarLayoutContent(
            rendered,
            for: button,
            gap: self.settings.menuBarLayoutGap)
        return false
    }
}
