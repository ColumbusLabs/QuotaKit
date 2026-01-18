import AppKit
import CodexBarCore
import Observation
import ServiceManagement

enum RefreshFrequency: String, CaseIterable, Identifiable {
    case manual
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes

    var id: String { self.rawValue }

    var seconds: TimeInterval? {
        switch self {
        case .manual: nil
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1800
        }
    }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .oneMinute: "1 min"
        case .twoMinutes: "2 min"
        case .fiveMinutes: "5 min"
        case .fifteenMinutes: "15 min"
        case .thirtyMinutes: "30 min"
        }
    }
}

enum MenuBarMetricPreference: String, CaseIterable, Identifiable {
    case automatic
    case primary
    case secondary
    case average

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .primary: "Primary"
        case .secondary: "Secondary"
        case .average: "Average"
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    private static let sharedDefaults = UserDefaults(suiteName: "group.com.steipete.codexbar")
    private static let isRunningTests: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["TESTING_LIBRARY_VERSION"] != nil { return true }
        if env["SWIFT_TESTING"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }()

    /// Persisted provider display order (config-backed).
    var providerOrderRaw: [String] {
        self.config.providers.map(\.id.rawValue)
    }

    var refreshFrequency: RefreshFrequency {
        didSet { self.userDefaults.set(self.refreshFrequency.rawValue, forKey: "refreshFrequency") }
    }

    var launchAtLogin: Bool {
        didSet {
            self.userDefaults.set(self.launchAtLogin, forKey: "launchAtLogin")
            LaunchAtLoginManager.setEnabled(self.launchAtLogin)
        }
    }

    /// Hidden toggle to reveal debug-only menu items (enable via defaults write com.steipete.CodexBar debugMenuEnabled
    /// -bool YES).
    var debugMenuEnabled: Bool {
        didSet { self.userDefaults.set(self.debugMenuEnabled, forKey: "debugMenuEnabled") }
    }

    /// Disable all Keychain access (browser cookie imports fall back to manual input).
    var debugDisableKeychainAccess: Bool {
        didSet {
            self.userDefaults.set(self.debugDisableKeychainAccess, forKey: "debugDisableKeychainAccess")
            Self.sharedDefaults?.set(self.debugDisableKeychainAccess, forKey: "debugDisableKeychainAccess")
            KeychainAccessGate.isDisabled = self.debugDisableKeychainAccess
        }
    }

    private var debugLoadingPatternRaw: String? {
        didSet {
            if let raw = self.debugLoadingPatternRaw {
                self.userDefaults.set(raw, forKey: "debugLoadingPattern")
            } else {
                self.userDefaults.removeObject(forKey: "debugLoadingPattern")
            }
        }
    }

    var statusChecksEnabled: Bool {
        didSet { self.userDefaults.set(self.statusChecksEnabled, forKey: "statusChecksEnabled") }
    }

    var sessionQuotaNotificationsEnabled: Bool {
        didSet {
            self.userDefaults.set(self.sessionQuotaNotificationsEnabled, forKey: "sessionQuotaNotificationsEnabled")
        }
    }

    /// When enabled, progress bars show "percent used" instead of "percent left".
    var usageBarsShowUsed: Bool {
        didSet { self.userDefaults.set(self.usageBarsShowUsed, forKey: "usageBarsShowUsed") }
    }

    /// Optional: show reset times as absolute clock values instead of countdowns.
    var resetTimesShowAbsolute: Bool {
        didSet { self.userDefaults.set(self.resetTimesShowAbsolute, forKey: "resetTimesShowAbsolute") }
    }

    /// Optional: use provider branding icons with a percentage in the menu bar.
    var menuBarShowsBrandIconWithPercent: Bool {
        didSet {
            self.userDefaults.set(self.menuBarShowsBrandIconWithPercent, forKey: "menuBarShowsBrandIconWithPercent")
        }
    }

    /// Controls what the menu bar displays when brand icon mode is enabled.
    private var menuBarDisplayModeRaw: String? {
        didSet {
            if let raw = self.menuBarDisplayModeRaw {
                self.userDefaults.set(raw, forKey: "menuBarDisplayMode")
            } else {
                self.userDefaults.removeObject(forKey: "menuBarDisplayMode")
            }
        }
    }

    /// Optional: show all token accounts stacked in the menu (otherwise show a switcher bar).
    var showAllTokenAccountsInMenu: Bool {
        didSet { self.userDefaults.set(self.showAllTokenAccountsInMenu, forKey: "showAllTokenAccountsInMenu") }
    }

    /// Optional: choose which quota window drives the menu bar percentage.
    private(set) var menuBarMetricPreferencesRaw: [String: String] {
        didSet { self.userDefaults.set(self.menuBarMetricPreferencesRaw, forKey: "menuBarMetricPreferences") }
    }

    /// Optional: show provider cost summary from local usage logs (Codex + Claude).
    var costUsageEnabled: Bool {
        didSet { self.userDefaults.set(self.costUsageEnabled, forKey: "tokenCostUsageEnabled") }
    }

    /// Optional: hide personal info (emails) in menu bar + menu content.
    var hidePersonalInfo: Bool {
        didSet { self.userDefaults.set(self.hidePersonalInfo, forKey: "hidePersonalInfo") }
    }

    var randomBlinkEnabled: Bool {
        didSet { self.userDefaults.set(self.randomBlinkEnabled, forKey: "randomBlinkEnabled") }
    }

    /// Optional: auto-select the provider with highest usage in the merged menu bar icon.
    var menuBarShowsHighestUsage: Bool {
        didSet { self.userDefaults.set(self.menuBarShowsHighestUsage, forKey: "menuBarShowsHighestUsage") }
    }

    /// Optional: augment Claude usage with claude.ai web API (via cookies),
    /// incl. "Extra usage" spend.
    var claudeWebExtrasEnabled: Bool {
        get { self.claudeWebExtrasEnabledRaw }
        set { self.claudeWebExtrasEnabledRaw = newValue }
    }

    private var claudeWebExtrasEnabledRaw: Bool {
        didSet { self.userDefaults.set(self.claudeWebExtrasEnabledRaw, forKey: "claudeWebExtrasEnabled") }
    }

    /// Optional: show Codex credits + Claude extra usage sections in the menu UI.
    var showOptionalCreditsAndExtraUsage: Bool {
        didSet {
            self.userDefaults.set(self.showOptionalCreditsAndExtraUsage, forKey: "showOptionalCreditsAndExtraUsage")
        }
    }

    /// Optional: fetch OpenAI web dashboard extras for Codex (browser cookies).
    var openAIWebAccessEnabled: Bool {
        didSet { self.userDefaults.set(self.openAIWebAccessEnabled, forKey: "openAIWebAccessEnabled") }
    }

    private var codexUsageDataSourceRaw: String? {
        didSet {
            self.updateProviderSource(provider: .codex, raw: self.codexUsageDataSourceRaw)
        }
    }

    private var claudeUsageDataSourceRaw: String? {
        didSet {
            self.updateProviderSource(provider: .claude, raw: self.claudeUsageDataSourceRaw)
        }
    }

    private var opencodeWorkspaceIDRaw: String? {
        didSet {
            self.updateProviderConfig(provider: .opencode) { entry in
                entry.workspaceID = self.opencodeWorkspaceIDRaw
            }
        }
    }

    /// JetBrains IDE base path for quota file lookup.
    var jetbrainsIDEBasePath: String {
        didSet { self.userDefaults.set(self.jetbrainsIDEBasePath, forKey: "jetbrainsIDEBasePath") }
    }

    /// Optional: collapse provider icons into a single menu bar item with an in-menu switcher.
    var mergeIcons: Bool {
        didSet { self.userDefaults.set(self.mergeIcons, forKey: "mergeIcons") }
    }

    /// Optional: show provider icons in the in-menu switcher.
    var switcherShowsIcons: Bool {
        didSet { self.userDefaults.set(self.switcherShowsIcons, forKey: "switcherShowsIcons") }
    }

    /// MiniMax API region (stored in config).
    var minimaxAPIRegion: MiniMaxAPIRegion {
        didSet {
            self.updateProviderConfig(provider: .minimax) { entry in
                entry.region = self.minimaxAPIRegion.rawValue
            }
        }
    }

    /// z.ai API region (stored in config).
    var zaiAPIRegion: ZaiAPIRegion {
        didSet {
            self.updateProviderConfig(provider: .zai) { entry in
                entry.region = self.zaiAPIRegion.rawValue
            }
        }
    }

    /// z.ai API token (stored in config).
    var zaiAPIToken: String {
        didSet {
            self.updateProviderConfig(provider: .zai) { entry in
                entry.apiKey = self.normalizedConfigValue(self.zaiAPIToken)
            }
        }
    }

    /// Synthetic API key (stored in config).
    var syntheticAPIToken: String {
        didSet {
            self.updateProviderConfig(provider: .synthetic) { entry in
                entry.apiKey = self.normalizedConfigValue(self.syntheticAPIToken)
            }
        }
    }

    /// Codex OpenAI cookie header (stored in config).
    var codexCookieHeader: String {
        didSet {
            self.updateProviderConfig(provider: .codex) { entry in
                entry.cookieHeader = self.normalizedConfigValue(self.codexCookieHeader)
            }
        }
    }

    /// Claude session cookie header (stored in config).
    var claudeCookieHeader: String {
        didSet {
            self.updateProviderConfig(provider: .claude) { entry in
                entry.cookieHeader = self.normalizedConfigValue(self.claudeCookieHeader)
            }
        }
    }

    /// Cursor session cookie header (stored in config).
    var cursorCookieHeader: String {
        didSet {
            self.updateProviderConfig(provider: .cursor) { entry in
                entry.cookieHeader = self.normalizedConfigValue(self.cursorCookieHeader)
            }
        }
    }

    /// OpenCode session cookie header (stored in config).
    var opencodeCookieHeader: String {
        didSet {
            self.updateProviderConfig(provider: .opencode) { entry in
                entry.cookieHeader = self.normalizedConfigValue(self.opencodeCookieHeader)
            }
        }
    }

    /// Optional OpenCode workspace ID override.
    var opencodeWorkspaceID: String {
        get { self.opencodeWorkspaceIDRaw ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            self.opencodeWorkspaceIDRaw = trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Factory session cookie header (stored in config).
    var factoryCookieHeader: String {
        didSet {
            self.updateProviderConfig(provider: .factory) { entry in
                entry.cookieHeader = self.normalizedConfigValue(self.factoryCookieHeader)
            }
        }
    }

    /// MiniMax session cookie header (stored in config).
    var minimaxCookieHeader: String {
        didSet {
            self.updateProviderConfig(provider: .minimax) { entry in
                entry.cookieHeader = self.normalizedConfigValue(self.minimaxCookieHeader)
            }
        }
    }

    /// MiniMax API token (stored in config).
    var minimaxAPIToken: String {
        didSet {
            self.updateProviderConfig(provider: .minimax) { entry in
                entry.apiKey = self.normalizedConfigValue(self.minimaxAPIToken)
            }
        }
    }

    /// Augment session cookie header (stored in config).
    var augmentCookieHeader: String {
        didSet {
            self.updateProviderConfig(provider: .augment) { entry in
                entry.cookieHeader = self.normalizedConfigValue(self.augmentCookieHeader)
            }
        }
    }

    /// Amp session cookie header (stored in config).
    var ampCookieHeader: String {
        didSet {
            self.updateProviderConfig(provider: .amp) { entry in
                entry.cookieHeader = self.normalizedConfigValue(self.ampCookieHeader)
            }
        }
    }

    /// Copilot API token (stored in config).
    var copilotAPIToken: String {
        didSet {
            self.updateProviderConfig(provider: .copilot) { entry in
                entry.apiKey = self.normalizedConfigValue(self.copilotAPIToken)
            }
        }
    }

    /// Kimi auth token (stored in config).
    var kimiManualCookieHeader: String {
        didSet {
            self.updateProviderConfig(provider: .kimi) { entry in
                entry.cookieHeader = self.normalizedConfigValue(self.kimiManualCookieHeader)
            }
        }
    }

    /// Kimi K2 API token (stored in config).
    var kimiK2APIToken: String {
        didSet {
            self.updateProviderConfig(provider: .kimik2) { entry in
                entry.apiKey = self.normalizedConfigValue(self.kimiK2APIToken)
            }
        }
    }

    /// Token accounts loaded from the local config file.
    var tokenAccountsByProvider: [UsageProvider: ProviderTokenAccountData] {
        didSet {
            self.updateProviderTokenAccounts(self.tokenAccountsByProvider)
        }
    }

    private var selectedMenuProviderRaw: String? {
        didSet {
            if let raw = self.selectedMenuProviderRaw {
                self.userDefaults.set(raw, forKey: "selectedMenuProvider")
            } else {
                self.userDefaults.removeObject(forKey: "selectedMenuProvider")
            }
        }
    }

    /// Optional override for the loading animation pattern, exposed via the Debug tab.
    var debugLoadingPattern: LoadingPattern? {
        get { self.debugLoadingPatternRaw.flatMap(LoadingPattern.init(rawValue:)) }
        set {
            self.debugLoadingPatternRaw = newValue?.rawValue
        }
    }

    var selectedMenuProvider: UsageProvider? {
        get { self.selectedMenuProviderRaw.flatMap(UsageProvider.init(rawValue:)) }
        set {
            self.selectedMenuProviderRaw = newValue?.rawValue
        }
    }

    var codexUsageDataSource: CodexUsageDataSource {
        get { CodexUsageDataSource(rawValue: self.codexUsageDataSourceRaw ?? "") ?? .auto }
        set {
            self.codexUsageDataSourceRaw = newValue.rawValue
        }
    }

    var claudeUsageDataSource: ClaudeUsageDataSource {
        get { ClaudeUsageDataSource(rawValue: self.claudeUsageDataSourceRaw ?? "") ?? .auto }
        set {
            self.claudeUsageDataSourceRaw = newValue.rawValue
            if newValue != .cli {
                self.claudeWebExtrasEnabled = false
            }
        }
    }

    var codexCookieSource: ProviderCookieSource {
        get {
            let fallback: ProviderCookieSource = self.openAIWebAccessEnabled ? .auto : .off
            return self.resolvedCookieSource(provider: .codex, fallback: fallback)
        }
        set {
            self.updateProviderConfig(provider: .codex) { entry in
                entry.cookieSource = newValue
            }
            self.openAIWebAccessEnabled = newValue.isEnabled
        }
    }

    var claudeCookieSource: ProviderCookieSource {
        get {
            self.resolvedCookieSource(provider: .claude, fallback: .auto)
        }
        set {
            self.updateProviderConfig(provider: .claude) { entry in
                entry.cookieSource = newValue
            }
        }
    }

    var cursorCookieSource: ProviderCookieSource {
        get {
            self.resolvedCookieSource(provider: .cursor, fallback: .auto)
        }
        set {
            self.updateProviderConfig(provider: .cursor) { entry in
                entry.cookieSource = newValue
            }
        }
    }

    var opencodeCookieSource: ProviderCookieSource {
        get {
            self.resolvedCookieSource(provider: .opencode, fallback: .auto)
        }
        set {
            self.updateProviderConfig(provider: .opencode) { entry in
                entry.cookieSource = newValue
            }
        }
    }

    var factoryCookieSource: ProviderCookieSource {
        get {
            self.resolvedCookieSource(provider: .factory, fallback: .auto)
        }
        set {
            self.updateProviderConfig(provider: .factory) { entry in
                entry.cookieSource = newValue
            }
        }
    }

    var minimaxCookieSource: ProviderCookieSource {
        get {
            self.resolvedCookieSource(provider: .minimax, fallback: .auto)
        }
        set {
            self.updateProviderConfig(provider: .minimax) { entry in
                entry.cookieSource = newValue
            }
        }
    }

    var kimiCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .kimi, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .kimi) { entry in
                entry.cookieSource = newValue
            }
        }
    }

    var augmentCookieSource: ProviderCookieSource {
        get {
            self.resolvedCookieSource(provider: .augment, fallback: .auto)
        }
        set {
            self.updateProviderConfig(provider: .augment) { entry in
                entry.cookieSource = newValue
            }
        }
    }

    var ampCookieSource: ProviderCookieSource {
        get {
            self.resolvedCookieSource(provider: .amp, fallback: .auto)
        }
        set {
            self.updateProviderConfig(provider: .amp) { entry in
                entry.cookieSource = newValue
            }
        }
    }

    private func resolvedCookieSource(
        provider: UsageProvider,
        fallback: ProviderCookieSource) -> ProviderCookieSource
    {
        let source = self.config.providerConfig(for: provider)?.cookieSource ?? fallback
        guard self.debugDisableKeychainAccess else { return source }
        return source == .off ? .off : .manual
    }

    private var providerDetectionCompleted: Bool {
        didSet { self.userDefaults.set(self.providerDetectionCompleted, forKey: "providerDetectionCompleted") }
    }

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let configStore: CodexBarConfigStore
    @ObservationIgnored private var config: CodexBarConfig
    @ObservationIgnored private var configPersistTask: Task<Void, Never>?
    @ObservationIgnored private var configLoading = false
    @ObservationIgnored private var tokenAccountsLoaded = false
    // Cache enablement so tight UI loops (menu bar animations) don't hit UserDefaults each tick.
    @ObservationIgnored private var cachedProviderEnablement: [UsageProvider: Bool] = [:]
    @ObservationIgnored private var cachedProviderEnablementRevision: Int = -1
    @ObservationIgnored private var cachedEnabledProviders: [UsageProvider] = []
    @ObservationIgnored private var cachedEnabledProvidersRevision: Int = -1
    @ObservationIgnored private var cachedEnabledProvidersOrderRaw: [String] = []
    // Cache order to avoid re-building sets/arrays every animation tick.
    @ObservationIgnored private var cachedProviderOrder: [UsageProvider] = []
    @ObservationIgnored private var cachedProviderOrderRaw: [String] = []
    private(set) var providerToggleRevision: Int = 0

    init(
        userDefaults: UserDefaults = .standard,
        configStore: CodexBarConfigStore = CodexBarConfigStore(),
        zaiTokenStore: any ZaiTokenStoring = KeychainZaiTokenStore(),
        syntheticTokenStore: any SyntheticTokenStoring = KeychainSyntheticTokenStore(),
        codexCookieStore: any CookieHeaderStoring = KeychainCookieHeaderStore(
            account: "codex-cookie",
            promptKind: .codexCookie),
        claudeCookieStore: any CookieHeaderStoring = KeychainCookieHeaderStore(
            account: "claude-cookie",
            promptKind: .claudeCookie),
        cursorCookieStore: any CookieHeaderStoring = KeychainCookieHeaderStore(
            account: "cursor-cookie",
            promptKind: .cursorCookie),
        opencodeCookieStore: any CookieHeaderStoring = KeychainCookieHeaderStore(
            account: "opencode-cookie",
            promptKind: .opencodeCookie),
        factoryCookieStore: any CookieHeaderStoring = KeychainCookieHeaderStore(
            account: "factory-cookie",
            promptKind: .factoryCookie),
        minimaxCookieStore: any MiniMaxCookieStoring = KeychainMiniMaxCookieStore(),
        minimaxAPITokenStore: any MiniMaxAPITokenStoring = KeychainMiniMaxAPITokenStore(),
        kimiTokenStore: any KimiTokenStoring = KeychainKimiTokenStore(),
        kimiK2TokenStore: any KimiK2TokenStoring = KeychainKimiK2TokenStore(),
        augmentCookieStore: any CookieHeaderStoring = KeychainCookieHeaderStore(
            account: "augment-cookie",
            promptKind: .augmentCookie),
        ampCookieStore: any CookieHeaderStoring = KeychainCookieHeaderStore(
            account: "amp-cookie",
            promptKind: .ampCookie),
        copilotTokenStore: any CopilotTokenStoring = KeychainCopilotTokenStore(),
        tokenAccountStore: any ProviderTokenAccountStoring = FileTokenAccountStore())
    {
        let legacyStores = CodexBarConfigMigrator.LegacyStores(
            zaiTokenStore: zaiTokenStore,
            syntheticTokenStore: syntheticTokenStore,
            codexCookieStore: codexCookieStore,
            claudeCookieStore: claudeCookieStore,
            cursorCookieStore: cursorCookieStore,
            opencodeCookieStore: opencodeCookieStore,
            factoryCookieStore: factoryCookieStore,
            minimaxCookieStore: minimaxCookieStore,
            minimaxAPITokenStore: minimaxAPITokenStore,
            kimiTokenStore: kimiTokenStore,
            kimiK2TokenStore: kimiK2TokenStore,
            augmentCookieStore: augmentCookieStore,
            ampCookieStore: ampCookieStore,
            copilotTokenStore: copilotTokenStore,
            tokenAccountStore: tokenAccountStore)
        let config = CodexBarConfigMigrator.loadOrMigrate(
            configStore: configStore,
            userDefaults: userDefaults,
            stores: legacyStores)
        self.userDefaults = userDefaults
        self.configStore = configStore
        self.config = config
        self.configLoading = true
        let raw = userDefaults.string(forKey: "refreshFrequency") ?? RefreshFrequency.fiveMinutes.rawValue
        self.refreshFrequency = RefreshFrequency(rawValue: raw) ?? .fiveMinutes
        self.launchAtLogin = userDefaults.object(forKey: "launchAtLogin") as? Bool ?? false
        self.debugMenuEnabled = userDefaults.object(forKey: "debugMenuEnabled") as? Bool ?? false
        if let stored = userDefaults.object(forKey: "debugDisableKeychainAccess") as? Bool {
            self.debugDisableKeychainAccess = stored
        } else if let shared = Self.sharedDefaults?.object(forKey: "debugDisableKeychainAccess") as? Bool {
            self.debugDisableKeychainAccess = shared
            userDefaults.set(shared, forKey: "debugDisableKeychainAccess")
        } else {
            self.debugDisableKeychainAccess = false
        }
        self.debugLoadingPatternRaw = userDefaults.string(forKey: "debugLoadingPattern")
        self.statusChecksEnabled = userDefaults.object(forKey: "statusChecksEnabled") as? Bool ?? true
        let sessionQuotaDefault = userDefaults.object(forKey: "sessionQuotaNotificationsEnabled") as? Bool
        self.sessionQuotaNotificationsEnabled = sessionQuotaDefault ?? true
        if sessionQuotaDefault == nil { self.userDefaults.set(true, forKey: "sessionQuotaNotificationsEnabled") }
        self.usageBarsShowUsed = userDefaults.object(forKey: "usageBarsShowUsed") as? Bool ?? false
        self.resetTimesShowAbsolute = userDefaults.object(forKey: "resetTimesShowAbsolute") as? Bool ?? false
        self.menuBarShowsBrandIconWithPercent = userDefaults.object(
            forKey: "menuBarShowsBrandIconWithPercent") as? Bool ?? false
        self.menuBarDisplayModeRaw = userDefaults.string(forKey: "menuBarDisplayMode")
            ?? MenuBarDisplayMode.percent.rawValue
        self.showAllTokenAccountsInMenu = userDefaults.object(forKey: "showAllTokenAccountsInMenu") as? Bool ?? false
        let storedPreferences = userDefaults.dictionary(forKey: "menuBarMetricPreferences") as? [String: String] ?? [:]
        var resolvedPreferences = storedPreferences
        if resolvedPreferences.isEmpty,
           let menuBarMetricRaw = userDefaults.string(forKey: "menuBarMetricPreference"),
           let legacyPreference = MenuBarMetricPreference(rawValue: menuBarMetricRaw)
        {
            resolvedPreferences = Dictionary(
                uniqueKeysWithValues: UsageProvider.allCases.map { ($0.rawValue, legacyPreference.rawValue) })
        }
        self.menuBarMetricPreferencesRaw = resolvedPreferences
        self.costUsageEnabled = userDefaults.object(forKey: "tokenCostUsageEnabled") as? Bool ?? false
        self.hidePersonalInfo = userDefaults.object(forKey: "hidePersonalInfo") as? Bool ?? false
        self.randomBlinkEnabled = userDefaults.object(forKey: "randomBlinkEnabled") as? Bool ?? false
        self.menuBarShowsHighestUsage = userDefaults.object(forKey: "menuBarShowsHighestUsage") as? Bool ?? false
        self.claudeWebExtrasEnabledRaw = userDefaults.object(forKey: "claudeWebExtrasEnabled") as? Bool ?? false
        let creditsExtrasDefault = userDefaults.object(forKey: "showOptionalCreditsAndExtraUsage") as? Bool
        self.showOptionalCreditsAndExtraUsage = creditsExtrasDefault ?? true
        if creditsExtrasDefault == nil { self.userDefaults.set(true, forKey: "showOptionalCreditsAndExtraUsage") }
        let openAIWebAccessDefault = userDefaults.object(forKey: "openAIWebAccessEnabled") as? Bool
        let openAIWebAccessEnabled = openAIWebAccessDefault ?? true
        self.openAIWebAccessEnabled = openAIWebAccessEnabled
        if openAIWebAccessDefault == nil { self.userDefaults.set(true, forKey: "openAIWebAccessEnabled") }
        self.codexUsageDataSourceRaw = Self.codexSourceRaw(from: config.providerConfig(for: .codex)?.source)
        self.claudeUsageDataSourceRaw = Self.claudeSourceRaw(from: config.providerConfig(for: .claude)?.source)
        self.opencodeWorkspaceIDRaw = config.providerConfig(for: .opencode)?.workspaceID
        self.jetbrainsIDEBasePath = userDefaults.string(forKey: "jetbrainsIDEBasePath") ?? ""
        self.mergeIcons = userDefaults.object(forKey: "mergeIcons") as? Bool ?? true
        self.switcherShowsIcons = userDefaults.object(forKey: "switcherShowsIcons") as? Bool ?? true
        let minimaxRegionRaw = config.providerConfig(for: .minimax)?.region
        self.minimaxAPIRegion = MiniMaxAPIRegion(rawValue: minimaxRegionRaw ?? "") ?? .global
        let zaiRegionRaw = config.providerConfig(for: .zai)?.region
        self.zaiAPIRegion = ZaiAPIRegion(rawValue: zaiRegionRaw ?? "") ?? .global
        self.zaiAPIToken = config.providerConfig(for: .zai)?.sanitizedAPIKey ?? ""
        self.syntheticAPIToken = config.providerConfig(for: .synthetic)?.sanitizedAPIKey ?? ""
        self.codexCookieHeader = config.providerConfig(for: .codex)?.sanitizedCookieHeader ?? ""
        self.claudeCookieHeader = config.providerConfig(for: .claude)?.sanitizedCookieHeader ?? ""
        self.cursorCookieHeader = config.providerConfig(for: .cursor)?.sanitizedCookieHeader ?? ""
        self.opencodeCookieHeader = config.providerConfig(for: .opencode)?.sanitizedCookieHeader ?? ""
        self.factoryCookieHeader = config.providerConfig(for: .factory)?.sanitizedCookieHeader ?? ""
        self.minimaxCookieHeader = config.providerConfig(for: .minimax)?.sanitizedCookieHeader ?? ""
        self.minimaxAPIToken = config.providerConfig(for: .minimax)?.sanitizedAPIKey ?? ""
        self.kimiManualCookieHeader = config.providerConfig(for: .kimi)?.sanitizedCookieHeader ?? ""
        self.kimiK2APIToken = config.providerConfig(for: .kimik2)?.sanitizedAPIKey ?? ""
        self.augmentCookieHeader = config.providerConfig(for: .augment)?.sanitizedCookieHeader ?? ""
        self.ampCookieHeader = config.providerConfig(for: .amp)?.sanitizedCookieHeader ?? ""
        self.copilotAPIToken = config.providerConfig(for: .copilot)?.sanitizedAPIKey ?? ""
        self.tokenAccountsByProvider = Dictionary(uniqueKeysWithValues: config.providers.compactMap { entry in
            guard let accounts = entry.tokenAccounts else { return nil }
            return (entry.id, accounts)
        })
        self.selectedMenuProviderRaw = userDefaults.string(forKey: "selectedMenuProvider")
        self.providerDetectionCompleted = userDefaults.object(forKey: "providerDetectionCompleted") as? Bool ?? false
        userDefaults.removeObject(forKey: "showCodexUsage")
        userDefaults.removeObject(forKey: "showClaudeUsage")
        self.configLoading = false
        LaunchAtLoginManager.setEnabled(self.launchAtLogin); self.runInitialProviderDetectionIfNeeded()
        self.applyTokenCostDefaultIfNeeded()
        if self.claudeUsageDataSource != .cli { self.claudeWebExtrasEnabled = false }
        self.openAIWebAccessEnabled = self.codexCookieSource.isEnabled
        Self.sharedDefaults?.set(self.debugDisableKeychainAccess, forKey: "debugDisableKeychainAccess")
        KeychainAccessGate.isDisabled = self.debugDisableKeychainAccess
    }

    func providerConfig(for provider: UsageProvider) -> ProviderConfig? {
        self.config.providerConfig(for: provider)
    }

    func orderedProviders() -> [UsageProvider] {
        let raw = self.providerOrderRaw
        if raw == self.cachedProviderOrderRaw, !self.cachedProviderOrder.isEmpty {
            return self.cachedProviderOrder
        }
        let ordered = Self.effectiveProviderOrder(raw: raw)
        self.cachedProviderOrderRaw = raw
        self.cachedProviderOrder = ordered
        return ordered
    }

    func moveProvider(fromOffsets: IndexSet, toOffset: Int) {
        var order = self.orderedProviders()
        order.move(fromOffsets: fromOffsets, toOffset: toOffset)
        self.setProviderOrder(order)
    }

    func isProviderEnabled(provider: UsageProvider, metadata: ProviderMetadata) -> Bool {
        _ = self.providerToggleRevision
        return self.config.providerConfig(for: provider)?.enabled ?? metadata.defaultEnabled
    }

    func isProviderEnabledCached(
        provider: UsageProvider,
        metadataByProvider: [UsageProvider: ProviderMetadata]) -> Bool
    {
        self.refreshProviderEnablementCacheIfNeeded(metadataByProvider: metadataByProvider)
        return self.cachedProviderEnablement[provider] ?? false
    }

    func enabledProvidersOrdered(metadataByProvider: [UsageProvider: ProviderMetadata]) -> [UsageProvider] {
        self.refreshProviderEnablementCacheIfNeeded(metadataByProvider: metadataByProvider)
        let orderRaw = self.providerOrderRaw
        let revision = self.cachedProviderEnablementRevision
        if revision == self.cachedEnabledProvidersRevision,
           orderRaw == self.cachedEnabledProvidersOrderRaw,
           !self.cachedEnabledProviders.isEmpty
        {
            return self.cachedEnabledProviders
        }
        let enabled = self.orderedProviders().filter { self.cachedProviderEnablement[$0] ?? false }
        self.cachedEnabledProviders = enabled
        self.cachedEnabledProvidersRevision = revision
        self.cachedEnabledProvidersOrderRaw = orderRaw
        return enabled
    }

    func setProviderEnabled(provider: UsageProvider, metadata _: ProviderMetadata, enabled: Bool) {
        self.providerToggleRevision &+= 1
        self.updateProviderConfig(provider: provider) { entry in
            entry.enabled = enabled
        }
    }

    func rerunProviderDetection() {
        self.runInitialProviderDetectionIfNeeded(force: true)
    }

    // MARK: - Private

    func isCostUsageEffectivelyEnabled(for provider: UsageProvider) -> Bool {
        self.costUsageEnabled
            && ProviderDescriptorRegistry.descriptor(for: provider).tokenCost.supportsTokenCost
    }

    private static func effectiveProviderOrder(raw: [String]) -> [UsageProvider] {
        var seen: Set<UsageProvider> = []
        var ordered: [UsageProvider] = []

        for rawValue in raw {
            guard let provider = UsageProvider(rawValue: rawValue) else { continue }
            guard !seen.contains(provider) else { continue }
            seen.insert(provider)
            ordered.append(provider)
        }

        if ordered.isEmpty {
            ordered = UsageProvider.allCases
            seen = Set(ordered)
        }

        if !seen.contains(.factory), let zaiIndex = ordered.firstIndex(of: .zai) {
            ordered.insert(.factory, at: zaiIndex)
            seen.insert(.factory)
        }

        if !seen.contains(.minimax), let zaiIndex = ordered.firstIndex(of: .zai) {
            let insertIndex = ordered.index(after: zaiIndex)
            ordered.insert(.minimax, at: insertIndex)
            seen.insert(.minimax)
        }

        for provider in UsageProvider.allCases where !seen.contains(provider) {
            ordered.append(provider)
        }

        return ordered
    }

    private func refreshProviderEnablementCacheIfNeeded(
        metadataByProvider: [UsageProvider: ProviderMetadata])
    {
        let revision = self.providerToggleRevision
        guard revision != self.cachedProviderEnablementRevision else { return }
        var cache: [UsageProvider: Bool] = [:]
        for (provider, metadata) in metadataByProvider {
            cache[provider] = self.config.providerConfig(for: provider)?.enabled ?? metadata.defaultEnabled
        }
        self.cachedProviderEnablement = cache
        self.cachedProviderEnablementRevision = revision
    }

    private func runInitialProviderDetectionIfNeeded(force: Bool = false) {
        guard force || !self.providerDetectionCompleted else { return }
        LoginShellPathCache.shared.captureOnce { [weak self] _ in
            Task { @MainActor in
                await self?.applyProviderDetection()
            }
        }
    }

    private func applyProviderDetection() async {
        guard !self.providerDetectionCompleted else { return }
        let codexInstalled = BinaryLocator.resolveCodexBinary() != nil
        let claudeInstalled = BinaryLocator.resolveClaudeBinary() != nil
        let geminiInstalled = BinaryLocator.resolveGeminiBinary() != nil
        let antigravityRunning = await AntigravityStatusProbe.isRunning()

        // If none installed, keep Codex enabled to match previous behavior.
        let noneInstalled = !codexInstalled && !claudeInstalled && !geminiInstalled && !antigravityRunning
        let enableCodex = codexInstalled || noneInstalled
        let enableClaude = claudeInstalled
        let enableGemini = geminiInstalled
        let enableAntigravity = antigravityRunning

        self.providerToggleRevision &+= 1
        self.updateProviderConfig(provider: .codex) { entry in
            entry.enabled = enableCodex
        }
        self.updateProviderConfig(provider: .claude) { entry in
            entry.enabled = enableClaude
        }
        self.updateProviderConfig(provider: .gemini) { entry in
            entry.enabled = enableGemini
        }
        self.updateProviderConfig(provider: .antigravity) { entry in
            entry.enabled = enableAntigravity
        }
        self.providerDetectionCompleted = true
    }

    private func applyTokenCostDefaultIfNeeded() {
        // Settings are persisted in UserDefaults.standard.
        guard UserDefaults.standard.object(forKey: "tokenCostUsageEnabled") == nil else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let hasSources = await Task.detached(priority: .utility) {
                Self.hasAnyTokenCostUsageSources()
            }.value
            guard hasSources else { return }
            guard UserDefaults.standard.object(forKey: "tokenCostUsageEnabled") == nil else { return }
            self.costUsageEnabled = true
        }
    }

    nonisolated static func hasAnyTokenCostUsageSources(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default) -> Bool
    {
        func hasAnyJsonl(in root: URL) -> Bool {
            guard fileManager.fileExists(atPath: root.path) else { return false }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { return false }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "jsonl" {
                return true
            }
            return false
        }

        let codexRoot: URL = {
            let raw = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let raw, !raw.isEmpty {
                return URL(fileURLWithPath: raw).appendingPathComponent("sessions", isDirectory: true)
            }
            return fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        }()
        if hasAnyJsonl(in: codexRoot) { return true }

        let claudeRoots: [URL] = {
            if let env = env["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !env.isEmpty
            {
                return env.split(separator: ",").map { part in
                    let raw = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
                    let url = URL(fileURLWithPath: raw)
                    if url.lastPathComponent == "projects" {
                        return url
                    }
                    return url.appendingPathComponent("projects", isDirectory: true)
                }
            }

            let home = fileManager.homeDirectoryForCurrentUser
            return [
                home.appendingPathComponent(".config/claude/projects", isDirectory: true),
                home.appendingPathComponent(".claude/projects", isDirectory: true),
            ]
        }()

        return claudeRoots.contains(where: hasAnyJsonl(in:))
    }
}

extension SettingsStore {
    private static func codexSourceRaw(from source: ProviderSourceMode?) -> String? {
        guard let source else { return nil }
        switch source {
        case .auto, .web, .api:
            return CodexUsageDataSource.auto.rawValue
        case .cli:
            return CodexUsageDataSource.cli.rawValue
        case .oauth:
            return CodexUsageDataSource.oauth.rawValue
        }
    }

    private static func claudeSourceRaw(from source: ProviderSourceMode?) -> String? {
        guard let source else { return nil }
        switch source {
        case .auto, .api:
            return ClaudeUsageDataSource.auto.rawValue
        case .web:
            return ClaudeUsageDataSource.web.rawValue
        case .cli:
            return ClaudeUsageDataSource.cli.rawValue
        case .oauth:
            return ClaudeUsageDataSource.oauth.rawValue
        }
    }

    private func updateProviderConfig(provider: UsageProvider, mutate: (inout ProviderConfig) -> Void) {
        guard !self.configLoading else { return }
        var config = self.config
        if let index = config.providers.firstIndex(where: { $0.id == provider }) {
            var entry = config.providers[index]
            mutate(&entry)
            config.providers[index] = entry
        } else {
            var entry = ProviderConfig(id: provider)
            mutate(&entry)
            config.providers.append(entry)
        }
        self.config = config.normalized()
        self.schedulePersistConfig()
    }

    private func updateProviderSource(provider: UsageProvider, raw: String?) {
        guard !self.configLoading else { return }
        let source: ProviderSourceMode? = {
            switch provider {
            case .codex:
                let dataSource = CodexUsageDataSource(rawValue: raw ?? "") ?? .auto
                switch dataSource {
                case .auto: return .auto
                case .oauth: return .oauth
                case .cli: return .cli
                }
            case .claude:
                let dataSource = ClaudeUsageDataSource(rawValue: raw ?? "") ?? .auto
                switch dataSource {
                case .auto: return .auto
                case .oauth: return .oauth
                case .web: return .web
                case .cli: return .cli
                }
            default:
                return nil
            }
        }()
        self.updateProviderConfig(provider: provider) { entry in
            entry.source = source
        }
    }

    private func updateProviderTokenAccounts(_ accounts: [UsageProvider: ProviderTokenAccountData]) {
        guard !self.configLoading else { return }
        var config = self.config
        var seen: Set<UsageProvider> = []
        for index in config.providers.indices {
            let provider = config.providers[index].id
            config.providers[index].tokenAccounts = accounts[provider]
            seen.insert(provider)
        }
        for (provider, data) in accounts where !seen.contains(provider) {
            config.providers.append(ProviderConfig(id: provider, tokenAccounts: data))
        }
        self.config = config.normalized()
        self.schedulePersistConfig()
    }

    private func setProviderOrder(_ order: [UsageProvider]) {
        guard !self.configLoading else { return }
        let configsByID = Dictionary(uniqueKeysWithValues: self.config.providers.map { ($0.id, $0) })
        var seen: Set<UsageProvider> = []
        var ordered: [ProviderConfig] = []
        ordered.reserveCapacity(max(order.count, self.config.providers.count))

        for provider in order {
            guard !seen.contains(provider) else { continue }
            seen.insert(provider)
            ordered.append(configsByID[provider] ?? ProviderConfig(id: provider))
        }

        for provider in UsageProvider.allCases where !seen.contains(provider) {
            ordered.append(configsByID[provider] ?? ProviderConfig(id: provider))
        }

        var config = self.config
        config.providers = ordered
        self.config = config.normalized()
        self.schedulePersistConfig()
    }

    private func normalizedConfigValue(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func schedulePersistConfig() {
        guard !self.configLoading else { return }
        self.configPersistTask?.cancel()
        if Self.isRunningTests {
            do {
                try self.configStore.save(self.config)
            } catch {
                CodexBarLog.logger("config-store").error("Failed to persist config: \(error)")
            }
            return
        }
        let store = self.configStore
        self.configPersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let snapshot = self.config
            let error: (any Error)? = await Task.detached(priority: .utility) {
                do {
                    try store.save(snapshot)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("config-store").error("Failed to persist config: \(error)")
            }
        }
    }
}

extension SettingsStore {
    func menuBarMetricPreference(for provider: UsageProvider) -> MenuBarMetricPreference {
        if provider == .zai { return .primary }
        let raw = self.menuBarMetricPreferencesRaw[provider.rawValue] ?? ""
        let preference = MenuBarMetricPreference(rawValue: raw) ?? .automatic
        if preference == .average, !self.menuBarMetricSupportsAverage(for: provider) {
            return .automatic
        }
        return preference
    }

    func setMenuBarMetricPreference(_ preference: MenuBarMetricPreference, for provider: UsageProvider) {
        if provider == .zai {
            self.menuBarMetricPreferencesRaw[provider.rawValue] = MenuBarMetricPreference.primary.rawValue
            return
        }
        self.menuBarMetricPreferencesRaw[provider.rawValue] = preference.rawValue
    }

    func menuBarMetricSupportsAverage(for provider: UsageProvider) -> Bool {
        provider == .gemini
    }

    func ensureZaiAPITokenLoaded() {}

    func ensureSyntheticAPITokenLoaded() {}

    func ensureCodexCookieLoaded() {}

    func ensureClaudeCookieLoaded() {}

    func ensureCursorCookieLoaded() {}

    func ensureOpenCodeCookieLoaded() {}

    func ensureFactoryCookieLoaded() {}

    func minimaxAuthMode(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> MiniMaxAuthMode
    {
        let apiToken = MiniMaxAPISettingsReader.apiToken(environment: environment) ?? self.minimaxAPIToken
        let cookieHeader = MiniMaxSettingsReader.cookieHeader(environment: environment) ?? self.minimaxCookieHeader
        return MiniMaxAuthMode.resolve(apiToken: apiToken, cookieHeader: cookieHeader)
    }

    func ensureMiniMaxCookieLoaded() {}

    func ensureMiniMaxAPITokenLoaded() {}

    func ensureKimiAuthTokenLoaded() {}

    func ensureKimiK2APITokenLoaded() {}

    func ensureAugmentCookieLoaded() {}

    func ensureAmpCookieLoaded() {}

    func ensureCopilotAPITokenLoaded() {}

    func ensureTokenAccountsLoaded() {
        guard !self.tokenAccountsLoaded else { return }
        for (provider, data) in self.tokenAccountsByProvider where !data.accounts.isEmpty {
            self.applyTokenAccountSideEffects(for: provider)
        }
        self.tokenAccountsLoaded = true
    }

    func tokenAccountsData(for provider: UsageProvider) -> ProviderTokenAccountData? {
        self.ensureTokenAccountsLoaded()
        return self.tokenAccountsByProvider[provider]
    }

    func tokenAccounts(for provider: UsageProvider) -> [ProviderTokenAccount] {
        self.tokenAccountsData(for: provider)?.accounts ?? []
    }

    func selectedTokenAccount(for provider: UsageProvider) -> ProviderTokenAccount? {
        guard let data = self.tokenAccountsData(for: provider), !data.accounts.isEmpty else { return nil }
        let index = data.clampedActiveIndex()
        guard index < data.accounts.count else { return nil }
        return data.accounts[index]
    }

    func setTokenAccounts(_ data: ProviderTokenAccountData?, for provider: UsageProvider) {
        self.ensureTokenAccountsLoaded()
        if let data {
            self.tokenAccountsByProvider[provider] = data
        } else {
            self.tokenAccountsByProvider.removeValue(forKey: provider)
        }
    }

    func setActiveTokenAccountIndex(_ index: Int, for provider: UsageProvider) {
        self.ensureTokenAccountsLoaded()
        guard var data = self.tokenAccountsByProvider[provider] else { return }
        let clamped = min(max(index, 0), max(0, data.accounts.count - 1))
        data = ProviderTokenAccountData(version: data.version, accounts: data.accounts, activeIndex: clamped)
        self.tokenAccountsByProvider[provider] = data
    }

    func addTokenAccount(provider: UsageProvider, label: String, token: String) {
        self.ensureTokenAccountsLoaded()
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, !trimmedToken.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        var data = self.tokenAccountsByProvider[provider]
            ?? ProviderTokenAccountData(version: 1, accounts: [], activeIndex: 0)
        let account = ProviderTokenAccount(
            id: UUID(),
            label: trimmedLabel,
            token: trimmedToken,
            addedAt: now,
            lastUsed: now)
        data = ProviderTokenAccountData(
            version: data.version,
            accounts: data.accounts + [account],
            activeIndex: max(0, data.accounts.count))
        self.tokenAccountsByProvider[provider] = data
        self.applyTokenAccountSideEffects(for: provider)
    }

    func removeTokenAccount(provider: UsageProvider, accountID: UUID) {
        self.ensureTokenAccountsLoaded()
        guard let data = self.tokenAccountsByProvider[provider] else { return }
        let remaining = data.accounts.filter { $0.id != accountID }
        if remaining.isEmpty {
            self.tokenAccountsByProvider.removeValue(forKey: provider)
            return
        }
        let newIndex = min(data.clampedActiveIndex(), max(0, remaining.count - 1))
        self.tokenAccountsByProvider[provider] = ProviderTokenAccountData(
            version: data.version,
            accounts: remaining,
            activeIndex: newIndex)
    }

    func reloadTokenAccounts() {
        self.tokenAccountsLoaded = false
        self.ensureTokenAccountsLoaded()
    }

    func openTokenAccountsFile() {
        do {
            if (try? self.configStore.load()) == nil {
                try self.configStore.save(self.config)
            }
            NSWorkspace.shared.open(self.configStore.fileURL)
        } catch {
            CodexBarLog.logger("config-store").error("Failed to open config file: \(error)")
        }
    }
}

extension SettingsStore {
    var resetTimeDisplayStyle: ResetTimeDisplayStyle {
        self.resetTimesShowAbsolute ? .absolute : .countdown
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        get { MenuBarDisplayMode(rawValue: self.menuBarDisplayModeRaw ?? "") ?? .percent }
        set { self.menuBarDisplayModeRaw = newValue.rawValue }
    }

    private func applyTokenAccountSideEffects(for provider: UsageProvider) {
        guard let support = TokenAccountSupportCatalog.support(for: provider),
              support.requiresManualCookieSource
        else {
            return
        }
        switch provider {
        case .claude:
            self.claudeCookieSource = .manual
        case .cursor:
            self.cursorCookieSource = .manual
        case .opencode:
            self.opencodeCookieSource = .manual
        case .factory:
            self.factoryCookieSource = .manual
        case .minimax:
            self.minimaxCookieSource = .manual
        case .augment:
            self.augmentCookieSource = .manual
        default:
            break
        }
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
