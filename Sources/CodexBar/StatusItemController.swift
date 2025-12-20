import AppKit
import CodexBarCore
import Combine
import OSLog
import QuartzCore
import SwiftUI

// MARK: - Status item controller (AppKit-hosted icons, SwiftUI popovers)

protocol StatusItemControlling: AnyObject {}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate, StatusItemControlling {
    typealias Factory = (UsageStore, SettingsStore, AccountInfo, UpdaterProviding, PreferencesSelection)
        -> StatusItemControlling
    static let defaultFactory: Factory = { store, settings, account, updater, selection in
        StatusItemController(
            store: store,
            settings: settings,
            account: account,
            updater: updater,
            preferencesSelection: selection)
    }

    static var factory: Factory = StatusItemController.defaultFactory

    let store: UsageStore
    let settings: SettingsStore
    let account: AccountInfo
    let updater: UpdaterProviding
    var statusItem: NSStatusItem
    var statusItems: [UsageProvider: NSStatusItem] = [:]
    var lastMenuProvider: UsageProvider?
    var menuProviders: [ObjectIdentifier: UsageProvider] = [:]
    var blinkTask: Task<Void, Never>?
    var loginTask: Task<Void, Never>? {
        didSet { self.refreshMenusForLoginStateChange() }
    }

    var activeLoginProvider: UsageProvider? {
        didSet {
            if oldValue != self.activeLoginProvider {
                self.refreshMenusForLoginStateChange()
            }
        }
    }

    var blinkStates: [UsageProvider: BlinkState] = [:]
    var blinkAmounts: [UsageProvider: CGFloat] = [:]
    var wiggleAmounts: [UsageProvider: CGFloat] = [:]
    var tiltAmounts: [UsageProvider: CGFloat] = [:]
    var blinkForceUntil: Date?
    private var cancellables = Set<AnyCancellable>()
    var loginPhase: LoginPhase = .idle {
        didSet {
            if oldValue != self.loginPhase {
                self.refreshMenusForLoginStateChange()
            }
        }
    }

    let preferencesSelection: PreferencesSelection
    var animationDisplayLink: CADisplayLink?
    var animationPhase: Double = 0
    var animationPattern: LoadingPattern = .knightRider
    let loginLogger = Logger(subsystem: "com.steipete.codexbar", category: "login")
    var selectedMenuProvider: UsageProvider? {
        get { self.settings.selectedMenuProvider }
        set { self.settings.selectedMenuProvider = newValue }
    }

    struct BlinkState {
        var nextBlink: Date
        var blinkStart: Date?
        var pendingSecondStart: Date?
        var effect: MotionEffect = .blink

        static func randomDelay() -> TimeInterval {
            Double.random(in: 3...12)
        }
    }

    enum MotionEffect {
        case blink
        case wiggle
        case tilt
    }

    enum LoginPhase {
        case idle
        case requesting
        case waitingBrowser
    }

    init(
        store: UsageStore,
        settings: SettingsStore,
        account: AccountInfo,
        updater: UpdaterProviding,
        preferencesSelection: PreferencesSelection)
    {
        self.store = store
        self.settings = settings
        self.account = account
        self.updater = updater
        self.preferencesSelection = preferencesSelection
        let bar = NSStatusBar.system
        let item = bar.statusItem(withLength: NSStatusItem.variableLength)
        // Ensure the icon is rendered at 1:1 without resampling (crisper edges for template images).
        item.button?.imageScaling = .scaleNone
        self.statusItem = item
        for provider in UsageProvider.allCases {
            let providerItem = bar.statusItem(withLength: NSStatusItem.variableLength)
            // Ensure the icon is rendered at 1:1 without resampling (crisper edges for template images).
            providerItem.button?.imageScaling = .scaleNone
            self.statusItems[provider] = providerItem
        }
        super.init()
        self.wireBindings()
        self.updateIcons()
        self.updateVisibility()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleDebugReplayNotification(_:)),
            name: .codexbarDebugReplayAllAnimations,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleDebugBlinkNotification),
            name: .codexbarDebugBlinkNow,
            object: nil)
    }

    private func wireBindings() {
        self.store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIcons()
                self?.updateBlinkingState()
            }
            .store(in: &self.cancellables)

        self.store.$debugForceAnimation
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateVisibility()
                self?.updateBlinkingState()
            }
            .store(in: &self.cancellables)

        self.settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateVisibility()
                self?.updateIcons()
            }
            .store(in: &self.cancellables)
    }

    private func updateIcons() {
        if self.shouldMergeIcons {
            self.applyIcon(phase: nil)
            self.attachMenus()
        } else {
            UsageProvider.allCases.forEach { self.applyIcon(for: $0, phase: nil) }
            self.attachMenus(fallback: self.fallbackProvider)
        }
        self.updateAnimationState()
        self.updateBlinkingState()
    }

    private func updateVisibility() {
        let anyEnabled = !self.store.enabledProviders().isEmpty
        let force = self.store.debugForceAnimation
        if self.shouldMergeIcons {
            self.statusItem.isVisible = anyEnabled || force
            for item in self.statusItems.values {
                item.isVisible = false
            }
            self.attachMenus()
        } else {
            self.statusItem.isVisible = false
            let fallback = self.fallbackProvider
            for provider in UsageProvider.allCases {
                let item = self.statusItems[provider]
                let isEnabled = self.isEnabled(provider)
                item?.isVisible = isEnabled || fallback == provider || force
            }
            self.attachMenus(fallback: fallback)
        }
        self.updateAnimationState()
        self.updateBlinkingState()
    }

    var fallbackProvider: UsageProvider? {
        self.store.enabledProviders().isEmpty ? .codex : nil
    }

    func isEnabled(_ provider: UsageProvider) -> Bool {
        self.store.isEnabled(provider)
    }

    private func refreshMenusForLoginStateChange() {
        if self.shouldMergeIcons {
            self.attachMenus()
        } else {
            self.attachMenus(fallback: self.fallbackProvider)
        }
    }

    private func attachMenus() {
        self.statusItem.menu = self.makeMenu()
    }

    private func attachMenus(fallback: UsageProvider? = nil) {
        self.menuProviders.removeAll()
        for provider in UsageProvider.allCases {
            guard let item = self.statusItems[provider] else { continue }
            if self.isEnabled(provider) {
                item.menu = self.makeMenu(for: provider)
            } else if fallback == provider {
                item.menu = self.makeMenu(for: nil)
            } else {
                item.menu = nil
            }
        }
    }

    func isVisible(_ provider: UsageProvider) -> Bool {
        self.store.debugForceAnimation || self.isEnabled(provider) || self.fallbackProvider == provider
    }

    var shouldMergeIcons: Bool {
        self.settings.mergeIcons && self.store.enabledProviders().count > 1
    }

    func switchAccountSubtitle(for target: UsageProvider) -> String? {
        guard self.loginTask != nil, let provider = self.activeLoginProvider, provider == target else { return nil }
        let base: String
        switch self.loginPhase {
        case .idle: return nil
        case .requesting: base = "Requesting login…"
        case .waitingBrowser: base = "Waiting in browser…"
        }
        let prefix = switch provider {
        case .codex: "Codex"
        case .claude: "Claude"
        case .gemini: "Gemini"
        }
        return "\(prefix): \(base)"
    }

    deinit {
        self.blinkTask?.cancel()
        self.loginTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}
