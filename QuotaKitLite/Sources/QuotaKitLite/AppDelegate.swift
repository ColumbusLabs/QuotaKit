import AppKit
import LiteCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Antigravity joins in S11 (068 §13).
    private static let enabledProviders: [LiteProvider] = [.claude, .codex]

    private var statusItem: NSStatusItem?
    private let store = LiteStateStore(fileURL: LiteStateStore.defaultFileURL())
    private var states: [LiteProvider: ProviderState] = [:]
    private var scheduler: RefreshScheduler?
    private var systemObservers: SystemObservers?
    private var activityWatcher: ActivityWatcher?
    private let statusRenderer = StatusItemRenderer()

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
            enabledProviders: Set(Self.enabledProviders),
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

        self.scheduler = scheduler
        self.systemObservers = observers
        self.activityWatcher = watcher
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

    /// Each provider's logo and remaining percent, like the full app's brand icon with percent mode.
    private func updateStatusItem() {
        let now = Date()
        let segments = Self.enabledProviders.map { provider in
            StatusItemRenderer.Segment(
                iconName: "ProviderIcon-\(provider.rawValue)",
                text: self.states[provider].flatMap { MenuBarText.percent(for: $0, now: now) })
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
        for provider in Self.enabledProviders {
            let state = self.states[provider] ?? ProviderState(provider: provider)
            let card = ProviderCardView(card: CardPresentation(state: state, now: now), tint: provider.brandColor)
            let host = NSHostingView(rootView: card)
            host.frame = NSRect(origin: .zero, size: NSSize(width: ProviderCardView.width, height: 1))
            host.frame.size.height = host.fittingSize.height
            let item = NSMenuItem()
            item.view = host
            menu.addItem(item)
            menu.addItem(.separator())
        }
        menu.addItem(
            withTitle: "Quit QuotaKit Lite",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
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
