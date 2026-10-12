import AppKit
import LiteCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let store = LiteStateStore(fileURL: LiteStateStore.defaultFileURL())
    private var states: [LiteProvider: ProviderState] = [:]
    private var scheduler: RefreshScheduler?
    private var systemObservers: SystemObservers?
    private var activityWatcher: ActivityWatcher?
    private var fullAppMonitor: FullAppMonitor?
    private let statusRenderer = StatusItemRenderer()
    private let preferences = LitePreferences()

    private var enabledProviders: [LiteProvider] {
        self.preferences.enabledProviders
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.statusItem = item

        for state in self.store.load() {
            self.states[state.provider] = state
        }
        self.updateStatusItem()
        self.startScheduling()
    }

    // MARK: - Refresh

    private func startScheduling() {
        let transport = URLSessionTransport()
        let codex = CodexProbe(transport: transport)
        let claude = ClaudeProbe(
            transport: transport,
            credentialsFile: ClaudeCredentialsFile(),
            keychainMetadata: ClaudeKeychainMetadataReader(),
            keychainSecret: ClaudeSecurityCLISecretReader(),
            tokenCache: LiteKeychainTokenCache())

        let scheduler = RefreshScheduler(
            enabledProviders: Set(self.enabledProviders),
            refresh: { [weak self] provider in
                let now = Date()
                let result: Result<ProbeResult, ProbeFailure> = switch provider {
                case .claude: await claude.fetch(now: now)
                case .codex: await codex.fetch(now: now)
                case .antigravity: .failure(.notRunning)
                }
                await self?.apply(result, for: provider, at: now)
                return result
            })
        for state in self.states.values {
            scheduler.restore(state.provider, windows: state.windows, lastSuccess: state.lastFetched)
        }

        let observers = SystemObservers(scheduler: scheduler)
        observers.start()
        let watcher = ActivityWatcher { [weak scheduler] provider in
            scheduler?.activity(provider)
        }
        watcher.start()

        // Before `start()`, so nothing is fetched at launch if the full app is already running (§5.4).
        let fullApp = FullAppMonitor { [weak scheduler] running in
            // Ending the pause fetches every enabled provider once.
            scheduler?.setPaused(running)
        }
        fullApp.start()
        scheduler.setPaused(fullApp.isRunning)

        self.scheduler = scheduler
        self.systemObservers = observers
        self.activityWatcher = watcher
        self.fullAppMonitor = fullApp
        scheduler.start()
    }

    /// Folds a fetch into the provider's state and persists it. A failure keeps the last data and only changes
    /// the status, so the menu can still show projected numbers (068 §5.3).
    private func apply(_ result: Result<ProbeResult, ProbeFailure>, for provider: LiteProvider, at now: Date) {
        var state = self.states[provider] ?? ProviderState(provider: provider)
        switch result {
        case let .success(probe):
            state.windows = probe.windows
            state.plan = probe.plan
            state.accountEmail = probe.accountEmail
            state.accountIdentities = probe.accountIdentities
            state.lastFetched = now
            state.status = .ok
        case let .failure(failure):
            state.status = failure.status
        }
        self.states[provider] = state
        _ = try? self.store.save(LiteProvider.allCases.compactMap { self.states[$0] })
        self.updateStatusItem()
    }

    /// The status item in the chosen §7.3 style. Percentages is the full app's brand icon with percent mode.
    private func updateStatusItem() {
        let now = Date()
        let enabled = self.enabledProviders
        func percent(_ provider: LiteProvider) -> StatusItemRenderer.Segment {
            StatusItemRenderer.Segment(
                provider: provider,
                content: .percent(self.states[provider].flatMap { MenuBarText.percent(for: $0, now: now) }))
        }
        let segments: [StatusItemRenderer.Segment] = switch self.preferences.menuBarStyle {
        case .percentages:
            enabled.map(percent)
        case .mostConstrained:
            [percent(MenuBarText.mostConstrained(enabled.compactMap { self.states[$0] }, now: now)?.provider
                    ?? enabled[0])]
        case .logosAndBars:
            enabled.map { provider in
                StatusItemRenderer.Segment(
                    provider: provider,
                    content: .bars(self.states[provider].flatMap { MenuBarText.bars(for: $0, now: now) }))
            }
        }
        self.statusRenderer.render(segments, into: self.statusItem?.button)
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) {
        self.activityWatcher?.rescan()
        self.scheduler?.menuOpened()
    }

    /// Card views exist only while the menu is open (068 §7.1): built here, released in `menuDidClose`.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date()
        let isPaused = self.fullAppMonitor?.isRunning ?? false
        for provider in self.enabledProviders {
            var state = self.states[provider] ?? ProviderState(provider: provider)
            // Display only: the stored status stays the last fetch's, so it shows again when the pause ends.
            if isPaused { state.status = .paused }
            let card = ProviderCardView(card: CardPresentation(state: state, now: now), tint: provider.brandColor)
            let host = NSHostingView(rootView: card)
            host.frame = NSRect(origin: .zero, size: NSSize(width: ProviderCardView.width, height: 1))
            host.frame.size.height = host.fittingSize.height
            let item = NSMenuItem()
            item.view = host
            menu.addItem(item)
            menu.addItem(.separator())
        }
        self.addActionItems(to: menu)
    }

    /// Refresh now, Providers ▸, Menu bar style ▸, Launch at login and Quit (068 §7.4).
    private func addActionItems(to menu: NSMenu) {
        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(self.refreshNow), keyEquivalent: "r")
        refresh.target = self
        // Nothing is fetched while the full app runs.
        if self.fullAppMonitor?.isRunning == true {
            refresh.action = nil
        }
        menu.addItem(refresh)

        let providers = NSMenu()
        let enabled = self.enabledProviders
        for provider in LitePreferences.availableProviders {
            let item = NSMenuItem(
                title: provider.displayName,
                action: #selector(self.toggleProvider(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = provider.rawValue
            item.state = enabled.contains(provider) ? .on : .off
            providers.addItem(item)
        }
        self.addSubmenu(providers, titled: "Providers", to: menu)

        let styles = NSMenu()
        let current = self.preferences.menuBarStyle
        for style in MenuBarStyle.allCases {
            let item = NSMenuItem(title: style.displayName, action: #selector(self.chooseStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = style == current ? .on : .off
            styles.addItem(item)
        }
        self.addSubmenu(styles, titled: "Menu Bar Style", to: menu)

        let login = NSMenuItem(
            title: "Launch at Login",
            action: #selector(self.toggleLaunchAtLogin),
            keyEquivalent: "")
        login.target = self
        login.state = switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .mixed
        default: .off
        }
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit QuotaKit Lite",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
    }

    private func addSubmenu(_ submenu: NSMenu, titled title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    @objc private func refreshNow() {
        self.scheduler?.refreshNow()
    }

    @objc private func toggleProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let provider = LiteProvider(rawValue: raw) else { return }
        self.preferences.toggle(provider)
        self.scheduler?.setEnabledProviders(Set(self.enabledProviders))
        self.updateStatusItem()
    }

    @objc private func chooseStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = MenuBarStyle(rawValue: raw) else { return }
        self.preferences.menuBarStyle = style
        self.updateStatusItem()
    }

    /// `SMAppService.mainApp`, with no helper bundle (068 §3.2). If macOS wants approval, open Login Items.
    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("QuotaKit Lite: launch at login change failed: %@", String(describing: error))
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        // After the current event, so AppKit can still deliver the chosen item's action (for example Quit).
        DispatchQueue.main.async {
            menu.removeAllItems()
            // Hand the cards' SwiftUI allocations back to the system (068 §9), as the full app's heap trimmer does.
            malloc_zone_pressure_relief(nil, 0)
        }
    }
}
