import AppKit
import LiteCore

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let icon = LiteResources.templateIcon(named: "ProviderIcon-claude") {
            item.button?.image = icon
        } else {
            // Running outside the `.app` bundle (for example `swift run`), so there are no resources.
            item.button?.title = "QK"
        }
        item.button?.setAccessibilityLabel("QuotaKit Lite")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.statusItem = item

        for state in self.store.load() {
            self.states[state.provider] = state
        }
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
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) {
        self.activityWatcher?.rescan()
        self.scheduler?.menuOpened()
    }

    /// Plain text rows until the custom-drawn cards land in S6.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date()
        for provider in Self.enabledProviders {
            let state = (self.states[provider] ?? ProviderState(provider: provider)).projected(at: now)
            menu.addItem(Self.disabledItem(MenuText.header(for: state, now: now)))
            if state.windows.isEmpty, state.status == .ok {
                menu.addItem(Self.disabledItem("    Waiting for first refresh…"))
            }
            for window in state.windows {
                menu.addItem(Self.disabledItem("    " + MenuText.line(for: window, provider: provider, now: now)))
            }
            if let footer = MenuText.footer(for: state) {
                menu.addItem(Self.disabledItem("    " + footer))
            }
            menu.addItem(.separator())
        }
        menu.addItem(
            withTitle: "Quit QuotaKit Lite",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
    }

    private static func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

/// Text for the temporary menu rows. Formatted only when the menu opens (068 §5.2).
enum MenuText {
    static func header(for state: ProviderState, now: Date) -> String {
        var parts = [state.provider.displayName]
        if let plan = self.planName(for: state) {
            parts.append(plan)
        }
        if let fetched = state.lastFetched {
            parts.append(self.age(of: fetched, now: now))
        }
        return parts.joined(separator: " · ")
    }

    static func line(for window: QuotaWindow, provider: LiteProvider, now: Date) -> String {
        var parts = ["\(window.label) \(Int(window.usedPercent.rounded()))%"]
        if window.isProjected {
            parts[0] += " (projected)"
        }
        if let resetsAt = window.resetsAt {
            parts.append("resets " + ResetText.countdown(to: resetsAt, now: now))
        }
        if let pace = PaceText.detail(for: window, provider: provider, now: now) {
            parts.append([pace.leftLabel, pace.rightLabel].compactMap(\.self).joined(separator: " · "))
        }
        return parts.joined(separator: " · ")
    }

    static func footer(for state: ProviderState) -> String? {
        let cli = state.provider == .codex ? "codex" : "claude"
        return switch state.status {
        case .ok: nil
        case .tokenExpired: "Token expired — run \(cli) once"
        case .tokenUnavailable: "Claude token unavailable — run claude once"
        case .signInRequired: "Sign in to \(cli) again"
        case .notRunning: "Not running — showing last data"
        case .paused: "Paused — QuotaKit is running"
        case .unrecognizedResponse: "Unrecognized response — update Lite"
        case let .error(message): message
        }
    }

    /// The synced plan is the full app's raw `loginMethod`; the menu shows a friendlier name.
    private static func planName(for state: ProviderState) -> String? {
        guard let plan = state.plan, !plan.isEmpty else { return nil }
        switch state.provider {
        case .codex:
            return CodexPlanName.displayName(plan) ?? plan
        case .claude:
            return plan.hasPrefix("Claude ") ? String(plan.dropFirst("Claude ".count)) : plan
        case .antigravity:
            return plan
        }
    }

    private static func age(of date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if minutes < 24 * 60 { return "\(minutes / 60)h ago" }
        return "\(minutes / (24 * 60))d ago"
    }
}
