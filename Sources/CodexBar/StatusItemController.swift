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
        for provider in UsageProvider.allCases {
            let item = bar.statusItem(withLength: NSStatusItem.variableLength)
            // Ensure the icon is rendered at 1:1 without resampling (crisper edges for template images).
            item.button?.imageScaling = .scaleNone
            self.statusItems[provider] = item
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
        UsageProvider.allCases.forEach { self.applyIcon(for: $0, phase: nil) }
        self.attachMenus(fallback: self.fallbackProvider)
        self.updateAnimationState()
        self.updateBlinkingState()
    }

    private func updateVisibility() {
        let fallback = self.fallbackProvider
        for provider in UsageProvider.allCases {
            let item = self.statusItems[provider]
            let isEnabled = self.isEnabled(provider)
            let force = self.store.debugForceAnimation
            item?.isVisible = isEnabled || fallback == provider || force
        }
        self.attachMenus(fallback: fallback)
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
        self.attachMenus(fallback: self.fallbackProvider)
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

    func switchAccountSubtitle(for target: UsageProvider) -> String? {
        guard self.loginTask != nil, let provider = self.activeLoginProvider, provider == target else { return nil }
        let base: String
        switch self.loginPhase {
        case .idle: return nil
        case .requesting: base = "Requesting login…"
        case .waitingBrowser: base = "Waiting in browser…"
        }
        return provider == .claude ? "Claude: \(base)" : "Codex: \(base)"
    }

    deinit {
        self.blinkTask?.cancel()
        self.loginTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}
