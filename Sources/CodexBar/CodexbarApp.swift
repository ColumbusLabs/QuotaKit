import AppKit
import CodexBarCore
import Combine
import OSLog
import QuartzCore
import Security
import SwiftUI

@main
struct CodexBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsStore
    @StateObject private var store: UsageStore
    private let preferencesSelection: PreferencesSelection
    private let account: AccountInfo

    init() {
        let preferencesSelection = PreferencesSelection()
        let settings = SettingsStore()
        let fetcher = UsageFetcher()
        let account = fetcher.loadAccountInfo()
        let store = UsageStore(fetcher: fetcher, settings: settings)
        self.preferencesSelection = preferencesSelection
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: store)
        self.account = account
        self.appDelegate.configure(
            store: store,
            settings: settings,
            account: account,
            selection: preferencesSelection)
    }

    @SceneBuilder
    var body: some Scene {
        // Hidden 1×1 window to keep SwiftUI's lifecycle alive so `Settings` scene
        // shows the native toolbar tabs even though the UI is AppKit-based.
        WindowGroup("CodexBarLifecycleKeepalive") {
            HiddenWindowView()
        }
        .defaultSize(width: 20, height: 20)
        .windowStyle(.hiddenTitleBar)

        Settings {
            PreferencesView(
                settings: self.settings,
                store: self.store,
                updater: self.appDelegate.updaterController,
                selection: self.preferencesSelection)
        }
        .defaultSize(width: PreferencesTab.windowWidth, height: PreferencesTab.general.preferredHeight)
        .windowResizability(.contentSize)
    }

    private func openSettings(tab: PreferencesTab) {
        self.preferencesSelection.tab = tab
        NSApp.activate(ignoringOtherApps: true)
        _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}

// MARK: - Updater abstraction

@MainActor
protocol UpdaterProviding: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    func checkForUpdates(_ sender: Any?)
}

// No-op updater used for debug builds and non-bundled runs to suppress Sparkle dialogs.
final class DisabledUpdaterController: UpdaterProviding {
    var automaticallyChecksForUpdates: Bool = false
    let isAvailable: Bool = false
    let unavailableReason: String?

    init(unavailableReason: String? = nil) {
        self.unavailableReason = unavailableReason
    }

    func checkForUpdates(_ sender: Any?) {}
}

#if canImport(Sparkle) && ENABLE_SPARKLE
import Sparkle

extension SPUStandardUpdaterController: UpdaterProviding {
    var automaticallyChecksForUpdates: Bool {
        get { self.updater.automaticallyChecksForUpdates }
        set { self.updater.automaticallyChecksForUpdates = newValue }
    }

    var isAvailable: Bool { true }
    var unavailableReason: String? { nil }
}

private func isDeveloperIDSigned(bundleURL: URL) -> Bool {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
          let code = staticCode else { return false }

    var infoCF: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
          let info = infoCF as? [String: Any],
          let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
          let leaf = certs.first else { return false }

    if let summary = SecCertificateCopySubjectSummary(leaf) as String? {
        return summary.hasPrefix("Developer ID Application:")
    }
    return false
}

@MainActor
private func makeUpdaterController() -> UpdaterProviding {
    let bundleURL = Bundle.main.bundleURL
    let isBundledApp = bundleURL.pathExtension == "app"
    guard isBundledApp else {
        return DisabledUpdaterController(unavailableReason: "Updates unavailable in this build.")
    }

    if InstallOrigin.isHomebrewCask(appBundleURL: bundleURL) {
        return DisabledUpdaterController(
            unavailableReason: "Updates managed by Homebrew. Run: brew upgrade --cask steipete/tap/codexbar")
    }

    guard isDeveloperIDSigned(bundleURL: bundleURL) else {
        return DisabledUpdaterController(unavailableReason: "Updates unavailable in this build.")
    }

    let defaults = UserDefaults.standard
    let autoUpdateKey = "autoUpdateEnabled"
    // Default to true for first launch; fall back to saved preference thereafter.
    let savedAutoUpdate = (defaults.object(forKey: autoUpdateKey) as? Bool) ?? true

    let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil)
    controller.updater.automaticallyChecksForUpdates = savedAutoUpdate
    controller.startUpdater()
    return controller
}
#else
private func makeUpdaterController() -> UpdaterProviding {
    DisabledUpdaterController()
}
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController: UpdaterProviding = makeUpdaterController()
    private var statusController: StatusItemControlling?
    private var store: UsageStore?
    private var settings: SettingsStore?
    private var account: AccountInfo?
    private var preferencesSelection: PreferencesSelection?

    func configure(store: UsageStore, settings: SettingsStore, account: AccountInfo, selection: PreferencesSelection) {
        self.store = store
        self.settings = settings
        self.account = account
        self.preferencesSelection = selection
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppNotifications.shared.requestAuthorizationOnStartup()
        self.ensureStatusController()
    }

    private func ensureStatusController() {
        if self.statusController != nil { return }

        if let store, let settings, let account, let selection = self.preferencesSelection {
            self.statusController = StatusItemController.factory(
                store,
                settings,
                account,
                self.updaterController,
                selection)
            return
        }

        // Defensive fallback: this should not be hit in normal app lifecycle.
        let fallbackSettings = SettingsStore()
        let fetcher = UsageFetcher()
        let fallbackAccount = fetcher.loadAccountInfo()
        let fallbackStore = UsageStore(fetcher: fetcher, settings: fallbackSettings)
        self.statusController = StatusItemController.factory(
            fallbackStore,
            fallbackSettings,
            fallbackAccount,
            self.updaterController,
            PreferencesSelection())
    }
}
