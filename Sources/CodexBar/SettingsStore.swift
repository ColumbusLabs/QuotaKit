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
    /// Persisted provider display order.
    ///
    /// Stored as raw `UsageProvider` strings so new providers can be appended automatically without breaking.
    var providerOrderRaw: [String] {
        didSet { self.userDefaults.set(self.providerOrderRaw, forKey: "providerOrder") }
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

    private var codexCookieSourceRaw: String? {
        didSet {
            if let raw = self.codexCookieSourceRaw {
                self.userDefaults.set(raw, forKey: "codexCookieSource")
            } else {
                self.userDefaults.removeObject(forKey: "codexCookieSource")
            }
        }
    }

    private var claudeCookieSourceRaw: String? {
        didSet {
            if let raw = self.claudeCookieSourceRaw {
                self.userDefaults.set(raw, forKey: "claudeCookieSource")
            } else {
                self.userDefaults.removeObject(forKey: "claudeCookieSource")
            }
        }
    }

    private var cursorCookieSourceRaw: String? {
        didSet {
            if let raw = self.cursorCookieSourceRaw {
                self.userDefaults.set(raw, forKey: "cursorCookieSource")
            } else {
                self.userDefaults.removeObject(forKey: "cursorCookieSource")
            }
        }
    }

    private var opencodeCookieSourceRaw: String? {
        didSet {
            if let raw = self.opencodeCookieSourceRaw {
                self.userDefaults.set(raw, forKey: "opencodeCookieSource")
            } else {
                self.userDefaults.removeObject(forKey: "opencodeCookieSource")
            }
        }
    }

    private var opencodeWorkspaceIDRaw: String? {
        didSet {
            self.updateProviderConfig(provider: .opencode) { entry in
                entry.workspaceID = self.opencodeWorkspaceIDRaw
            }
        }
    }

    private var factoryCookieSourceRaw: String? {
        didSet {
            if let raw = self.factoryCookieSourceRaw {
                self.userDefaults.set(raw, forKey: "factoryCookieSource")
            } else {
                self.userDefaults.removeObject(forKey: "factoryCookieSource")
            }
        }
    }

    private var minimaxCookieSourceRaw: String? {
        didSet {
            if let raw = self.minimaxCookieSourceRaw {
                self.userDefaults.set(raw, forKey: "minimaxCookieSource")
            } else {
                self.userDefaults.removeObject(forKey: "minimaxCookieSource")
            }
        }
    }

    private var kimiCookieSourceRaw: String? {
        didSet {
            if let raw = self.kimiCookieSourceRaw {
                self.userDefaults.set(raw, forKey: "kimiCookieSource")
            } else {
                self.userDefaults.removeObject(forKey: "kimiCookieSource")
            }
        }
    }

    private var augmentCookieSourceRaw: String? {
        didSet {
            if let raw = self.augmentCookieSourceRaw {
                self.userDefaults.set(raw, forKey: "augmentCookieSource")
            } else {
                self.userDefaults.removeObject(forKey: "augmentCookieSource")
            }
        }
    }

    private var ampCookieSourceRaw: String? {
        didSet {
            if let raw = self.ampCookieSourceRaw {
                self.userDefaults.set(raw, forKey: "ampCookieSource")
            } else {
                self.userDefaults.removeObject(forKey: "ampCookieSource")
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

    /// MiniMax API region (stored in UserDefaults).
    var minimaxAPIRegion: MiniMaxAPIRegion {
        didSet {
            self.updateProviderConfig(provider: .minimax) { entry in
                entry.region = self.minimaxAPIRegion.rawValue
            }
        }
    }

    /// z.ai API region (stored in UserDefaults).
    var zaiAPIRegion: ZaiAPIRegion {
        didSet {
            self.updateProviderConfig(provider: .zai) { entry in
                entry.region = self.zaiAPIRegion.rawValue
            }
        }
    }

    /// z.ai API token (stored in Keychain).
    var zaiAPIToken: String {
        didSet { self.schedulePersistZaiAPIToken() }
    }

    /// Synthetic API key (stored in Keychain).
    var syntheticAPIToken: String {
        didSet { self.schedulePersistSyntheticAPIToken() }
    }

    /// Codex OpenAI cookie header (stored in Keychain).
    var codexCookieHeader: String {
        didSet { self.schedulePersistCodexCookieHeader() }
    }

    /// Claude session cookie header (stored in Keychain).
    var claudeCookieHeader: String {
        didSet { self.schedulePersistClaudeCookieHeader() }
    }

    /// Cursor session cookie header (stored in Keychain).
    var cursorCookieHeader: String {
        didSet { self.schedulePersistCursorCookieHeader() }
    }

    /// OpenCode session cookie header (stored in Keychain).
    var opencodeCookieHeader: String {
        didSet { self.schedulePersistOpenCodeCookieHeader() }
    }

    /// Optional OpenCode workspace ID override.
    var opencodeWorkspaceID: String {
        get { self.opencodeWorkspaceIDRaw ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            self.opencodeWorkspaceIDRaw = trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Factory session cookie header (stored in Keychain).
    var factoryCookieHeader: String {
        didSet { self.schedulePersistFactoryCookieHeader() }
    }

    /// MiniMax session cookie header (stored in Keychain).
    var minimaxCookieHeader: String {
        didSet { self.schedulePersistMiniMaxCookieHeader() }
    }

    /// MiniMax API token (stored in Keychain).
    var minimaxAPIToken: String {
        didSet { self.schedulePersistMiniMaxAPIToken() }
    }

    /// Augment session cookie header (stored in Keychain).
    var augmentCookieHeader: String {
        didSet { self.schedulePersistAugmentCookieHeader() }
    }

    /// Amp session cookie header (stored in Keychain).
    var ampCookieHeader: String {
        didSet { self.schedulePersistAmpCookieHeader() }
    }

    /// Copilot API token (stored in Keychain).
    var copilotAPIToken: String {
        didSet { self.schedulePersistCopilotAPIToken() }
    }

    /// Kimi auth token (stored in Keychain).
    var kimiManualCookieHeader: String {
        didSet { self.schedulePersistKimiAuthToken() }
    }

    /// Kimi K2 API token (stored in Keychain).
    var kimiK2APIToken: String {
        didSet { self.schedulePersistKimiK2APIToken() }
    }

    /// Token accounts loaded from the local config file.
    var tokenAccountsByProvider: [UsageProvider: ProviderTokenAccountData] {
        didSet { self.schedulePersistTokenAccounts() }
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
            self.resolvedCookieSource(self.codexCookieSourceRaw, fallback: .auto)
        }
        set {
            self.codexCookieSourceRaw = newValue.rawValue
            self.openAIWebAccessEnabled = newValue.isEnabled
        }
    }

    var claudeCookieSource: ProviderCookieSource {
        get {
            self.resolvedCookieSource(self.claudeCookieSourceRaw, fallback: .auto)
        }
        set { self.claudeCookieSourceRaw = newValue.rawValue }
    }

    var cursorCookieSource: ProviderCookieSource {
        get {
            self.resolvedCookieSource(self.cursorCookieSourceRaw, fallback: .auto)
        }
        set { self.cursorCookieSourceRaw = newValue.rawValue }
    }

    var opencodeCookieSource: ProviderCookieSource {
        get {
            self.resolvedCookieSource(self.opencodeCookieSourceRaw, fallback: .auto)
        }
        set { self.opencodeCookieSourceRaw = newValue.rawValue }
    }

    var factoryCookieSource: ProviderCookieSource {
        get {
            self.resolvedCookieSource(self.factoryCookieSourceRaw, fallback: .auto)
        }
        set { self.factoryCookieSourceRaw = newValue.rawValue }
    }

    var minimaxCookieSource: ProviderCookieSource {
        get {
            self.resolvedCookieSource(self.minimaxCookieSourceRaw, fallback: .auto)
        }
        set { self.minimaxCookieSourceRaw = newValue.rawValue }
    }

    var kimiCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(self.kimiCookieSourceRaw, fallback: .auto) }
        set { self.kimiCookieSourceRaw = newValue.rawValue }
    }

    var augmentCookieSource: ProviderCookieSource {
        get {
            self.resolvedCookieSource(self.augmentCookieSourceRaw, fallback: .auto)
        }
        set { self.augmentCookieSourceRaw = newValue.rawValue }
    }

    var ampCookieSource: ProviderCookieSource {
        get {
            self.resolvedCookieSource(self.ampCookieSourceRaw, fallback: .auto)
        }
        set { self.ampCookieSourceRaw = newValue.rawValue }
    }

    private func resolvedCookieSource(_ raw: String?, fallback: ProviderCookieSource) -> ProviderCookieSource {
        let source = ProviderCookieSource(rawValue: raw ?? "") ?? fallback
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
    @ObservationIgnored let toggleStore: ProviderToggleStore
    @ObservationIgnored private let zaiTokenStore: any ZaiTokenStoring
    @ObservationIgnored private var zaiTokenPersistTask: Task<Void, Never>?
    @ObservationIgnored private var zaiTokenLoaded = false
    @ObservationIgnored private var zaiTokenLoading = false
    @ObservationIgnored private let syntheticTokenStore: any SyntheticTokenStoring
    @ObservationIgnored private var syntheticTokenPersistTask: Task<Void, Never>?
    @ObservationIgnored private var syntheticTokenLoaded = false
    @ObservationIgnored private var syntheticTokenLoading = false
    @ObservationIgnored private let codexCookieStore: any CookieHeaderStoring
    @ObservationIgnored private var codexCookiePersistTask: Task<Void, Never>?
    @ObservationIgnored private var codexCookieLoaded = false
    @ObservationIgnored private var codexCookieLoading = false
    @ObservationIgnored private let claudeCookieStore: any CookieHeaderStoring
    @ObservationIgnored private var claudeCookiePersistTask: Task<Void, Never>?
    @ObservationIgnored private var claudeCookieLoaded = false
    @ObservationIgnored private var claudeCookieLoading = false
    @ObservationIgnored private let cursorCookieStore: any CookieHeaderStoring
    @ObservationIgnored private var cursorCookiePersistTask: Task<Void, Never>?
    @ObservationIgnored private var cursorCookieLoaded = false
    @ObservationIgnored private var cursorCookieLoading = false
    @ObservationIgnored private let opencodeCookieStore: any CookieHeaderStoring
    @ObservationIgnored private var opencodeCookiePersistTask: Task<Void, Never>?
    @ObservationIgnored private var opencodeCookieLoaded = false
    @ObservationIgnored private var opencodeCookieLoading = false
    @ObservationIgnored private let factoryCookieStore: any CookieHeaderStoring
    @ObservationIgnored private var factoryCookiePersistTask: Task<Void, Never>?
    @ObservationIgnored private var factoryCookieLoaded = false
    @ObservationIgnored private var factoryCookieLoading = false
    @ObservationIgnored private let minimaxCookieStore: any MiniMaxCookieStoring
    @ObservationIgnored private var minimaxCookiePersistTask: Task<Void, Never>?
    @ObservationIgnored private var minimaxCookieLoaded = false
    @ObservationIgnored private var minimaxCookieLoading = false
    @ObservationIgnored private let minimaxAPITokenStore: any MiniMaxAPITokenStoring
    @ObservationIgnored private var minimaxAPITokenPersistTask: Task<Void, Never>?
    @ObservationIgnored private var minimaxAPITokenLoaded = false
    @ObservationIgnored private var minimaxAPITokenLoading = false
    @ObservationIgnored private let kimiTokenStore: any KimiTokenStoring
    @ObservationIgnored private var kimiTokenPersistTask: Task<Void, Never>?
    @ObservationIgnored private var kimiTokenLoaded = false
    @ObservationIgnored private var kimiTokenLoading = false
    @ObservationIgnored private let kimiK2TokenStore: any KimiK2TokenStoring
    @ObservationIgnored private var kimiK2TokenPersistTask: Task<Void, Never>?
    @ObservationIgnored private var kimiK2TokenLoaded = false
    @ObservationIgnored private var kimiK2TokenLoading = false
    @ObservationIgnored private let augmentCookieStore: any CookieHeaderStoring
    @ObservationIgnored private var augmentCookiePersistTask: Task<Void, Never>?
    @ObservationIgnored private var augmentCookieLoaded = false
    @ObservationIgnored private var augmentCookieLoading = false
    @ObservationIgnored private let ampCookieStore: any CookieHeaderStoring
    @ObservationIgnored private var ampCookiePersistTask: Task<Void, Never>?
    @ObservationIgnored private var ampCookieLoaded = false
    @ObservationIgnored private var ampCookieLoading = false
    @ObservationIgnored private let copilotTokenStore: any CopilotTokenStoring
    @ObservationIgnored private var copilotTokenPersistTask: Task<Void, Never>?
    @ObservationIgnored private var copilotTokenLoaded = false
    @ObservationIgnored private var copilotTokenLoading = false
    @ObservationIgnored private let tokenAccountStore: any ProviderTokenAccountStoring
    @ObservationIgnored private var tokenAccountsPersistTask: Task<Void, Never>?
    @ObservationIgnored private var tokenAccountsLoaded = false
    @ObservationIgnored private var tokenAccountsLoading = false
    // Cache enablement so tight UI loops (menu bar animations) don't hit UserDefaults each tick.
    @ObservationIgnored var cachedProviderEnablement: [UsageProvider: Bool] = [:]
    @ObservationIgnored var cachedProviderEnablementRevision: Int = -1
    @ObservationIgnored var cachedEnabledProviders: [UsageProvider] = []
    @ObservationIgnored var cachedEnabledProvidersRevision: Int = -1
    @ObservationIgnored var cachedEnabledProvidersOrderRaw: [String] = []
    // Cache order to avoid re-building sets/arrays every animation tick.
    @ObservationIgnored var cachedProviderOrder: [UsageProvider] = []
    @ObservationIgnored var cachedProviderOrderRaw: [String] = []
    var providerToggleRevision: Int = 0

    init(
        userDefaults: UserDefaults = .standard,
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
        let configStore = CodexBarConfigStore()
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
        self.zaiTokenStore = zaiTokenStore
        self.syntheticTokenStore = syntheticTokenStore
        self.codexCookieStore = codexCookieStore
        self.claudeCookieStore = claudeCookieStore
        self.cursorCookieStore = cursorCookieStore
        self.opencodeCookieStore = opencodeCookieStore
        self.factoryCookieStore = factoryCookieStore
        self.minimaxCookieStore = minimaxCookieStore
        self.minimaxAPITokenStore = minimaxAPITokenStore
        self.kimiTokenStore = kimiTokenStore
        self.kimiK2TokenStore = kimiK2TokenStore
        self.augmentCookieStore = augmentCookieStore
        self.ampCookieStore = ampCookieStore
        self.copilotTokenStore = copilotTokenStore
        self.tokenAccountStore = tokenAccountStore
        self.providerOrderRaw = config.orderedProviders().map(\.rawValue)
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
        let codexCookieRaw = userDefaults.string(forKey: "codexCookieSource")
        if let codexCookieRaw {
            self.codexCookieSourceRaw = codexCookieRaw
        } else {
            let fallback = openAIWebAccessEnabled ? ProviderCookieSource.auto : .off
            self.codexCookieSourceRaw = fallback.rawValue
        }
        self.claudeCookieSourceRaw = userDefaults.string(forKey: "claudeCookieSource")
            ?? ProviderCookieSource.auto.rawValue
        self.cursorCookieSourceRaw = userDefaults.string(forKey: "cursorCookieSource")
            ?? ProviderCookieSource.auto.rawValue
        self.opencodeCookieSourceRaw = userDefaults.string(forKey: "opencodeCookieSource")
            ?? ProviderCookieSource.auto.rawValue
        self.opencodeWorkspaceIDRaw = config.providerConfig(for: .opencode)?.workspaceID
        self.factoryCookieSourceRaw = userDefaults.string(forKey: "factoryCookieSource")
            ?? ProviderCookieSource.auto.rawValue
        self.minimaxCookieSourceRaw = userDefaults.string(forKey: "minimaxCookieSource")
            ?? ProviderCookieSource.auto.rawValue
        self.kimiCookieSourceRaw = userDefaults.string(forKey: "kimiCookieSource")
            ?? ProviderCookieSource.auto.rawValue
        self.augmentCookieSourceRaw = userDefaults.string(forKey: "augmentCookieSource")
            ?? ProviderCookieSource.auto.rawValue
        self.ampCookieSourceRaw = userDefaults.string(forKey: "ampCookieSource")
            ?? ProviderCookieSource.auto.rawValue
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
        self.toggleStore = ProviderToggleStore(userDefaults: userDefaults); self.toggleStore.purgeLegacyKeys()
        LaunchAtLoginManager.setEnabled(self.launchAtLogin); self.runInitialProviderDetectionIfNeeded()
        self.applyTokenCostDefaultIfNeeded()
        if self.claudeUsageDataSource != .cli { self.claudeWebExtrasEnabled = false }
        self.openAIWebAccessEnabled = self.codexCookieSource.isEnabled
        Self.sharedDefaults?.set(self.debugDisableKeychainAccess, forKey: "debugDisableKeychainAccess")
        KeychainAccessGate.isDisabled = self.debugDisableKeychainAccess
    }

    func runInitialProviderDetectionIfNeeded(force: Bool = false) {
        guard force || !self.providerDetectionCompleted else { return }
        guard let codexMeta = ProviderRegistry.shared.metadata[.codex],
              let claudeMeta = ProviderRegistry.shared.metadata[.claude],
              let geminiMeta = ProviderRegistry.shared.metadata[.gemini],
              let antigravityMeta = ProviderRegistry.shared.metadata[.antigravity] else { return }

        LoginShellPathCache.shared.captureOnce { [weak self] _ in
            Task { @MainActor in
                await self?.applyProviderDetection(
                    codexMeta: codexMeta,
                    claudeMeta: claudeMeta,
                    geminiMeta: geminiMeta,
                    antigravityMeta: antigravityMeta)
            }
        }
    }

    private func applyProviderDetection(
        codexMeta: ProviderMetadata,
        claudeMeta: ProviderMetadata,
        geminiMeta: ProviderMetadata,
        antigravityMeta: ProviderMetadata) async
    {
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
        self.toggleStore.setEnabled(enableCodex, metadata: codexMeta)
        self.toggleStore.setEnabled(enableClaude, metadata: claudeMeta)
        self.toggleStore.setEnabled(enableGemini, metadata: geminiMeta)
        self.toggleStore.setEnabled(enableAntigravity, metadata: antigravityMeta)
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

    private func schedulePersistConfig() {
        guard !self.configLoading else { return }
        self.configPersistTask?.cancel()
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

    private func schedulePersistZaiAPIToken() {
        if self.zaiTokenLoading { return }
        self.zaiTokenPersistTask?.cancel()
        let token = self.zaiAPIToken
        let tokenStore = self.zaiTokenStore
        self.zaiTokenPersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try tokenStore.storeToken(token)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                // Keep value in memory; persist best-effort.
                CodexBarLog.logger("zai-token-store").error("Failed to persist z.ai token: \(error)")
            }
        }
    }

    private func schedulePersistSyntheticAPIToken() {
        if self.syntheticTokenLoading { return }
        self.syntheticTokenPersistTask?.cancel()
        let token = self.syntheticAPIToken
        let tokenStore = self.syntheticTokenStore
        self.syntheticTokenPersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try tokenStore.storeToken(token)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("synthetic-token-store")
                    .error("Failed to persist Synthetic API key: \(error)")
            }
        }
    }

    private func schedulePersistCodexCookieHeader() {
        if self.codexCookieLoading { return }
        self.codexCookiePersistTask?.cancel()
        let header = self.codexCookieHeader
        let cookieStore = self.codexCookieStore
        self.codexCookiePersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try cookieStore.storeCookieHeader(header)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("codex-cookie-store").error("Failed to persist Codex cookie: \(error)")
            }
        }
    }

    private func schedulePersistClaudeCookieHeader() {
        if self.claudeCookieLoading { return }
        self.claudeCookiePersistTask?.cancel()
        let header = self.claudeCookieHeader
        let cookieStore = self.claudeCookieStore
        self.claudeCookiePersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try cookieStore.storeCookieHeader(header)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("claude-cookie-store").error("Failed to persist Claude cookie: \(error)")
            }
        }
    }

    private func schedulePersistCursorCookieHeader() {
        if self.cursorCookieLoading { return }
        self.cursorCookiePersistTask?.cancel()
        let header = self.cursorCookieHeader
        let cookieStore = self.cursorCookieStore
        self.cursorCookiePersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try cookieStore.storeCookieHeader(header)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("cursor-cookie-store").error("Failed to persist Cursor cookie: \(error)")
            }
        }
    }

    private func schedulePersistOpenCodeCookieHeader() {
        if self.opencodeCookieLoading { return }
        self.opencodeCookiePersistTask?.cancel()
        let header = self.opencodeCookieHeader
        let cookieStore = self.opencodeCookieStore
        self.opencodeCookiePersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try cookieStore.storeCookieHeader(header)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("opencode-cookie-store").error("Failed to persist OpenCode cookie: \(error)")
            }
        }
    }

    private func schedulePersistAugmentCookieHeader() {
        if self.augmentCookieLoading { return }
        self.augmentCookiePersistTask?.cancel()
        let header = self.augmentCookieHeader
        let cookieStore = self.augmentCookieStore
        self.augmentCookiePersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try cookieStore.storeCookieHeader(header)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("augment-cookie-store").error("Failed to persist Augment cookie: \(error)")
            }
        }
    }

    private func schedulePersistAmpCookieHeader() {
        if self.ampCookieLoading { return }
        self.ampCookiePersistTask?.cancel()
        let header = self.ampCookieHeader
        let cookieStore = self.ampCookieStore
        self.ampCookiePersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try cookieStore.storeCookieHeader(header)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("amp-cookie-store").error("Failed to persist Amp cookie: \(error)")
            }
        }
    }

    private func schedulePersistFactoryCookieHeader() {
        if self.factoryCookieLoading { return }
        self.factoryCookiePersistTask?.cancel()
        let header = self.factoryCookieHeader
        let cookieStore = self.factoryCookieStore
        self.factoryCookiePersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try cookieStore.storeCookieHeader(header)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("factory-cookie-store").error("Failed to persist Factory cookie: \(error)")
            }
        }
    }

    private func schedulePersistMiniMaxCookieHeader() {
        if self.minimaxCookieLoading { return }
        self.minimaxCookiePersistTask?.cancel()
        let header = self.minimaxCookieHeader
        let cookieStore = self.minimaxCookieStore
        self.minimaxCookiePersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try cookieStore.storeCookieHeader(header)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("minimax-cookie-store").error("Failed to persist MiniMax cookie: \(error)")
            }
        }
    }

    private func schedulePersistMiniMaxAPIToken() {
        if self.minimaxAPITokenLoading { return }
        self.minimaxAPITokenPersistTask?.cancel()
        let token = self.minimaxAPIToken
        let tokenStore = self.minimaxAPITokenStore
        self.minimaxAPITokenPersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try tokenStore.storeToken(token)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("minimax-api-token-store").error("Failed to persist MiniMax API token: \(error)")
            }
        }
    }

    private func schedulePersistCopilotAPIToken() {
        if self.copilotTokenLoading { return }
        self.copilotTokenPersistTask?.cancel()
        let token = self.copilotAPIToken
        let tokenStore = self.copilotTokenStore
        self.copilotTokenPersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try tokenStore.storeToken(token)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("copilot-token-store").error("Failed to persist Copilot token: \(error)")
            }
        }
    }

    private func schedulePersistTokenAccounts() {
        if self.tokenAccountsLoading { return }
        self.tokenAccountsPersistTask?.cancel()
        let accounts = self.tokenAccountsByProvider
        let tokenStore = self.tokenAccountStore
        self.tokenAccountsPersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try tokenStore.storeAccounts(accounts)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("token-account-store").error("Failed to persist token accounts: \(error)")
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

    private func schedulePersistKimiAuthToken() {
        if self.kimiTokenLoading { return }
        self.kimiTokenPersistTask?.cancel()
        let token = self.kimiManualCookieHeader
        let tokenStore = self.kimiTokenStore
        self.kimiTokenPersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try tokenStore.storeToken(token)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("kimi-token-store").error("Failed to persist Kimi token: \(error)")
            }
        }
    }

    private func schedulePersistKimiK2APIToken() {
        if self.kimiK2TokenLoading { return }
        self.kimiK2TokenPersistTask?.cancel()
        let token = self.kimiK2APIToken
        let tokenStore = self.kimiK2TokenStore
        self.kimiK2TokenPersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let error: (any Error)? = await Task.detached(priority: .utility) { () -> (any Error)? in
                do {
                    try tokenStore.storeToken(token)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let error {
                CodexBarLog.logger("kimi-k2-token-store").error("Failed to persist Kimi K2 token: \(error)")
            }
        }
    }

    func ensureZaiAPITokenLoaded() {
        guard !self.zaiTokenLoaded else { return }
        self.zaiTokenLoading = true
        self.zaiAPIToken = (try? self.zaiTokenStore.loadToken()) ?? ""
        self.zaiTokenLoading = false
        self.zaiTokenLoaded = true
    }

    func ensureSyntheticAPITokenLoaded() {
        guard !self.syntheticTokenLoaded else { return }
        self.syntheticTokenLoading = true
        self.syntheticAPIToken = (try? self.syntheticTokenStore.loadToken()) ?? ""
        self.syntheticTokenLoading = false
        self.syntheticTokenLoaded = true
    }

    func ensureCodexCookieLoaded() {
        guard !self.codexCookieLoaded else { return }
        self.codexCookieLoading = true
        self.codexCookieHeader = (try? self.codexCookieStore.loadCookieHeader()) ?? ""
        self.codexCookieLoading = false
        self.codexCookieLoaded = true
    }

    func ensureClaudeCookieLoaded() {
        guard !self.claudeCookieLoaded else { return }
        self.claudeCookieLoading = true
        self.claudeCookieHeader = (try? self.claudeCookieStore.loadCookieHeader()) ?? ""
        self.claudeCookieLoading = false
        self.claudeCookieLoaded = true
    }

    func ensureCursorCookieLoaded() {
        guard !self.cursorCookieLoaded else { return }
        self.cursorCookieLoading = true
        self.cursorCookieHeader = (try? self.cursorCookieStore.loadCookieHeader()) ?? ""
        self.cursorCookieLoading = false
        self.cursorCookieLoaded = true
    }

    func ensureOpenCodeCookieLoaded() {
        guard !self.opencodeCookieLoaded else { return }
        self.opencodeCookieLoading = true
        self.opencodeCookieHeader = (try? self.opencodeCookieStore.loadCookieHeader()) ?? ""
        self.opencodeCookieLoading = false
        self.opencodeCookieLoaded = true
    }

    func ensureFactoryCookieLoaded() {
        guard !self.factoryCookieLoaded else { return }
        self.factoryCookieLoading = true
        self.factoryCookieHeader = (try? self.factoryCookieStore.loadCookieHeader()) ?? ""
        self.factoryCookieLoading = false
        self.factoryCookieLoaded = true
    }

    func minimaxAuthMode(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> MiniMaxAuthMode
    {
        let apiToken = MiniMaxAPISettingsReader.apiToken(environment: environment) ?? self.minimaxAPIToken
        let cookieHeader = MiniMaxSettingsReader.cookieHeader(environment: environment) ?? self.minimaxCookieHeader
        return MiniMaxAuthMode.resolve(apiToken: apiToken, cookieHeader: cookieHeader)
    }

    func ensureMiniMaxCookieLoaded() {
        guard !self.minimaxCookieLoaded else { return }
        self.minimaxCookieLoading = true
        self.minimaxCookieHeader = (try? self.minimaxCookieStore.loadCookieHeader()) ?? ""
        self.minimaxCookieLoading = false
        self.minimaxCookieLoaded = true
    }

    func ensureMiniMaxAPITokenLoaded() {
        guard !self.minimaxAPITokenLoaded else { return }
        self.minimaxAPITokenLoading = true
        self.minimaxAPIToken = (try? self.minimaxAPITokenStore.loadToken()) ?? ""
        self.minimaxAPITokenLoading = false
        self.minimaxAPITokenLoaded = true
    }

    func ensureKimiAuthTokenLoaded() {
        guard !self.kimiTokenLoaded else { return }
        self.kimiTokenLoading = true
        var token = (try? self.kimiTokenStore.loadToken()) ?? ""
        if token.isEmpty {
            if let oldToken = self.userDefaults.string(forKey: "kimiManualCookieHeader"), !oldToken.isEmpty {
                token = oldToken
                try? self.kimiTokenStore.storeToken(oldToken)
                self.userDefaults.removeObject(forKey: "kimiManualCookieHeader")
            }
        }
        self.kimiManualCookieHeader = token
        self.kimiTokenLoading = false
        self.kimiTokenLoaded = true
    }

    func ensureKimiK2APITokenLoaded() {
        guard !self.kimiK2TokenLoaded else { return }
        self.kimiK2TokenLoading = true
        self.kimiK2APIToken = (try? self.kimiK2TokenStore.loadToken()) ?? ""
        self.kimiK2TokenLoading = false
        self.kimiK2TokenLoaded = true
    }

    func ensureAugmentCookieLoaded() {
        guard !self.augmentCookieLoaded else { return }
        self.augmentCookieLoading = true
        self.augmentCookieHeader = (try? self.augmentCookieStore.loadCookieHeader()) ?? ""
        self.augmentCookieLoading = false
        self.augmentCookieLoaded = true
    }

    func ensureAmpCookieLoaded() {
        guard !self.ampCookieLoaded else { return }
        self.ampCookieLoading = true
        self.ampCookieHeader = (try? self.ampCookieStore.loadCookieHeader()) ?? ""
        self.ampCookieLoading = false
        self.ampCookieLoaded = true
    }

    func ensureCopilotAPITokenLoaded() {
        guard !self.copilotTokenLoaded else { return }
        self.copilotTokenLoading = true
        self.copilotAPIToken = (try? self.copilotTokenStore.loadToken()) ?? ""
        self.copilotTokenLoading = false
        self.copilotTokenLoaded = true
    }

    func ensureTokenAccountsLoaded() {
        guard !self.tokenAccountsLoaded else { return }
        self.tokenAccountsLoading = true
        self.tokenAccountsByProvider = (try? self.tokenAccountStore.loadAccounts()) ?? [:]
        for (provider, data) in self.tokenAccountsByProvider where !data.accounts.isEmpty {
            self.applyTokenAccountSideEffects(for: provider)
        }
        self.tokenAccountsLoading = false
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
            let url = try self.tokenAccountStore.ensureFileExists()
            NSWorkspace.shared.open(url)
        } catch {
            CodexBarLog.logger("token-account-store").error("Failed to open token accounts file: \(error)")
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
