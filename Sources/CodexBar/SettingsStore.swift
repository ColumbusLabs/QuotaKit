import AppKit
import CodexBarCore
import Combine
import ServiceManagement
import SwiftUI

enum RefreshFrequency: String, CaseIterable, Identifiable {
    case manual
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case fifteenMinutes

    var id: String { self.rawValue }

    var seconds: TimeInterval? {
        switch self {
        case .manual: nil
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        }
    }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .oneMinute: "1 min"
        case .twoMinutes: "2 min"
        case .fiveMinutes: "5 min"
        case .fifteenMinutes: "15 min"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var refreshFrequency: RefreshFrequency {
        didSet { self.userDefaults.set(self.refreshFrequency.rawValue, forKey: "refreshFrequency") }
    }

    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false {
        didSet { LaunchAtLoginManager.setEnabled(self.launchAtLogin) }
    }

    /// Hidden toggle to reveal debug-only menu items (enable via defaults write com.steipete.CodexBar debugMenuEnabled
    /// -bool YES).
    @AppStorage("debugMenuEnabled") var debugMenuEnabled: Bool = false

    @AppStorage("debugLoadingPattern") private var debugLoadingPatternRaw: String?

    @AppStorage("statusChecksEnabled") var statusChecksEnabled: Bool = true {
        didSet { self.objectWillChange.send() }
    }

    @AppStorage("sessionQuotaNotificationsEnabled") var sessionQuotaNotificationsEnabled: Bool = true {
        didSet { self.objectWillChange.send() }
    }

    /// When enabled, progress bars show "percent used" instead of "percent left".
    @AppStorage("usageBarsShowUsed") var usageBarsShowUsed: Bool = false {
        didSet { self.objectWillChange.send() }
    }

    /// Optional: show provider cost summary from ccusage CLIs (offline).
    @AppStorage("tokenCostUsageEnabled") var ccusageCostUsageEnabled: Bool = false {
        didSet { self.objectWillChange.send() }
    }

    @Published private(set) var ccusageAvailability: CCUsageAvailability = .init(claudePath: nil, codexPath: nil)

    @AppStorage("randomBlinkEnabled") var randomBlinkEnabled: Bool = false {
        didSet { self.objectWillChange.send() }
    }

    /// Optional: enable scraping the OpenAI dashboard (WebKit) for extra Codex data (code review + breakdown).
    @AppStorage("openAIDashboardEnabled") var openAIDashboardEnabled: Bool = false {
        didSet { self.objectWillChange.send() }
    }

    /// Optional: collapse provider icons into a single menu bar item with an in-menu switcher.
    @AppStorage("mergeIcons") var mergeIcons: Bool = true {
        didSet { self.objectWillChange.send() }
    }

    @AppStorage("selectedMenuProvider") private var selectedMenuProviderRaw: String?

    /// Optional override for the loading animation pattern, exposed via the Debug tab.
    var debugLoadingPattern: LoadingPattern? {
        get { self.debugLoadingPatternRaw.flatMap(LoadingPattern.init(rawValue:)) }
        set {
            self.objectWillChange.send()
            self.debugLoadingPatternRaw = newValue?.rawValue
        }
    }

    var selectedMenuProvider: UsageProvider? {
        get { self.selectedMenuProviderRaw.flatMap(UsageProvider.init(rawValue:)) }
        set {
            self.objectWillChange.send()
            self.selectedMenuProviderRaw = newValue?.rawValue
        }
    }

    @AppStorage("providerDetectionCompleted") private var providerDetectionCompleted: Bool = false

    private let userDefaults: UserDefaults
    private let toggleStore: ProviderToggleStore

    struct CCUsageAvailability: Sendable, Equatable {
        let claudePath: String?
        let codexPath: String?

        var isAnyInstalled: Bool { self.claudePath != nil || self.codexPath != nil }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: "sessionQuotaNotificationsEnabled") == nil {
            userDefaults.set(true, forKey: "sessionQuotaNotificationsEnabled")
        }
        let raw = userDefaults.string(forKey: "refreshFrequency") ?? RefreshFrequency.fiveMinutes.rawValue
        self.refreshFrequency = RefreshFrequency(rawValue: raw) ?? .fiveMinutes
        self.toggleStore = ProviderToggleStore(userDefaults: userDefaults)
        self.toggleStore.purgeLegacyKeys()
        LaunchAtLoginManager.setEnabled(self.launchAtLogin)
        self.runInitialProviderDetectionIfNeeded()
        self.refreshCCUsageAvailability()
    }

    func isProviderEnabled(provider: UsageProvider, metadata: ProviderMetadata) -> Bool {
        self.toggleStore.isEnabled(metadata: metadata)
    }

    func setProviderEnabled(provider: UsageProvider, metadata: ProviderMetadata, enabled: Bool) {
        self.objectWillChange.send()
        self.toggleStore.setEnabled(enabled, metadata: metadata)
    }

    func rerunProviderDetection() {
        self.runInitialProviderDetectionIfNeeded(force: true)
    }

    // MARK: - Private

    nonisolated static func ccusageAvailability(
        env: [String: String] = ProcessInfo.processInfo.environment,
        loginPATH: [String]? = LoginShellPathCache.shared.current,
        commandV: (String, String?, TimeInterval, FileManager) -> String? = ShellCommandLocator.commandV,
        fileManager: FileManager = .default) -> CCUsageAvailability
    {
        func find(_ binary: String, in paths: [String]) -> String? {
            for path in paths where !path.isEmpty {
                let candidate = "\(path.hasSuffix("/") ? String(path.dropLast()) : path)/\(binary)"
                if fileManager.isExecutableFile(atPath: candidate) { return candidate }
            }
            return nil
        }

        func resolve(_ binary: String, hardcoded: [String]) -> String? {
            // 1) Login-shell PATH (captured once per launch)
            if let loginPATH,
               let pathHit = find(binary, in: loginPATH)
            {
                return pathHit
            }

            // 2) Existing PATH
            if let existingPATH = env["PATH"]?.split(separator: ":").map(String.init),
               let pathHit = find(binary, in: existingPATH)
            {
                return pathHit
            }

            // 3) Interactive login shell lookup (captures nvm/fnm/mise paths from .zshrc/.bashrc)
            if let shellHit = commandV(binary, env["SHELL"], 2.0, fileManager),
               fileManager.isExecutableFile(atPath: shellHit)
            {
                return shellHit
            }

            // 4) Hardcoded locations
            for candidate in hardcoded where fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }

            return nil
        }

        let claudePath = resolve(
            "ccusage",
            hardcoded: ["/opt/homebrew/bin/ccusage", "/usr/local/bin/ccusage"])
        let codexPath = resolve(
            "ccusage-codex",
            hardcoded: ["/opt/homebrew/bin/ccusage-codex", "/usr/local/bin/ccusage-codex"])
        return CCUsageAvailability(claudePath: claudePath, codexPath: codexPath)
    }

    func isCCUsageInstalled(for provider: UsageProvider) -> Bool {
        switch provider {
        case .claude:
            self.ccusageAvailability.claudePath != nil
        case .codex:
            self.ccusageAvailability.codexPath != nil
        case .gemini:
            false
        }
    }

    func isCCUsageCostUsageEffectivelyEnabled(for provider: UsageProvider) -> Bool {
        self.ccusageCostUsageEnabled && self.isCCUsageInstalled(for: provider)
    }

    private func runInitialProviderDetectionIfNeeded(force: Bool = false) {
        guard force || !self.providerDetectionCompleted else { return }
        guard let codexMeta = ProviderRegistry.shared.metadata[.codex],
              let claudeMeta = ProviderRegistry.shared.metadata[.claude],
              let geminiMeta = ProviderRegistry.shared.metadata[.gemini] else { return }

        LoginShellPathCache.shared.captureOnce { [weak self] _ in
            Task { @MainActor in
                self?.applyProviderDetection(codexMeta: codexMeta, claudeMeta: claudeMeta, geminiMeta: geminiMeta)
            }
        }
    }

    private func applyProviderDetection(
        codexMeta: ProviderMetadata,
        claudeMeta: ProviderMetadata,
        geminiMeta: ProviderMetadata)
    {
        guard !self.providerDetectionCompleted else { return }
        let codexInstalled = BinaryLocator.resolveCodexBinary() != nil
        let claudeInstalled = BinaryLocator.resolveClaudeBinary() != nil
        let geminiInstalled = BinaryLocator.resolveGeminiBinary() != nil

        // If none installed, keep Codex enabled to match previous behavior.
        let noneInstalled = !codexInstalled && !claudeInstalled && !geminiInstalled
        let enableCodex = codexInstalled || noneInstalled
        let enableClaude = claudeInstalled
        let enableGemini = geminiInstalled

        self.objectWillChange.send()
        self.toggleStore.setEnabled(enableCodex, metadata: codexMeta)
        self.toggleStore.setEnabled(enableClaude, metadata: claudeMeta)
        self.toggleStore.setEnabled(enableGemini, metadata: geminiMeta)
        self.providerDetectionCompleted = true
    }

    func refreshCCUsageAvailability() {
        LoginShellPathCache.shared.captureOnce { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let availability = await Task.detached(priority: .utility) {
                    Self.ccusageAvailability()
                }.value
                self.ccusageAvailability = availability
                self.applyCCUsageDefaultIfNeeded(availability: availability)
            }
        }
    }

    private func applyCCUsageDefaultIfNeeded(availability: CCUsageAvailability) {
        // @AppStorage always reads/writes UserDefaults.standard.
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "tokenCostUsageEnabled") == nil else { return }
        guard availability.isAnyInstalled else { return }
        let enabledByDefault = availability.isAnyInstalled
        defaults.set(enabledByDefault, forKey: "tokenCostUsageEnabled")
        self.ccusageCostUsageEnabled = enabledByDefault
    }
}

enum LaunchAtLoginManager {
    @MainActor
    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13, *) else { return }
        let service = SMAppService.mainApp
        if enabled {
            try? service.register()
        } else {
            try? service.unregister()
        }
    }
}
