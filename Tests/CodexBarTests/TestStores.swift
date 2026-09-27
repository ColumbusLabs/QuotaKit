import CodexBarCore
import Foundation
@testable import CodexBar
#if os(macOS)
import AppKit
#endif

/// Dictionary-backed defaults for credential and sync fixtures. No persistent search-domain fallback.
final class InMemoryUserDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any]

    init(values: [String: Any] = [:]) {
        self.values = values
        super.init(suiteName: "InMemoryUserDefaults-\(UUID().uuidString)")!
    }

    override func object(forKey key: String) -> Any? { self.lock.withLock { self.values[key] } }
    override func set(_ value: Any?, forKey key: String) { self.lock.withLock { self.values[key] = value } }
    override func removeObject(forKey key: String) { self.set(nil as Any?, forKey: key) }
    override func bool(forKey key: String) -> Bool { (self.object(forKey: key) as? NSNumber)?.boolValue ?? false }
    override func integer(forKey key: String) -> Int { (self.object(forKey: key) as? NSNumber)?.intValue ?? 0 }
    override func float(forKey key: String) -> Float { (self.object(forKey: key) as? NSNumber)?.floatValue ?? 0 }
    override func double(forKey key: String) -> Double { (self.object(forKey: key) as? NSNumber)?.doubleValue ?? 0 }
    override func string(forKey key: String) -> String? { self.object(forKey: key) as? String }
    override func array(forKey key: String) -> [Any]? { self.object(forKey: key) as? [Any] }
    override func dictionary(forKey key: String) -> [String: Any]? { self.object(forKey: key) as? [String: Any] }
    override func data(forKey key: String) -> Data? { self.object(forKey: key) as? Data }
    override func stringArray(forKey key: String) -> [String]? { self.object(forKey: key) as? [String] }
    override func url(forKey key: String) -> URL? { self.object(forKey: key) as? URL }
    override func set(_ value: Bool, forKey key: String) { self.set(value as Any, forKey: key) }
    override func set(_ value: Int, forKey key: String) { self.set(value as Any, forKey: key) }
    override func set(_ value: Float, forKey key: String) { self.set(value as Any, forKey: key) }
    override func set(_ value: Double, forKey key: String) { self.set(value as Any, forKey: key) }
    override func set(_ url: URL?, forKey key: String) { self.set(url as Any?, forKey: key) }
    override func dictionaryRepresentation() -> [String: Any] { self.lock.withLock { self.values } }
}

final class InMemoryCookieHeaderStore: CookieHeaderStoring, @unchecked Sendable {
    var value: String?

    init(value: String? = nil) {
        self.value = value
    }

    func loadCookieHeader() throws -> String? {
        self.value
    }

    func storeCookieHeader(_ header: String?) throws {
        self.value = header
    }
}

final class InMemoryMiniMaxCookieStore: MiniMaxCookieStoring, @unchecked Sendable {
    var value: String?

    init(value: String? = nil) {
        self.value = value
    }

    func loadCookieHeader() throws -> String? {
        self.value
    }

    func storeCookieHeader(_ header: String?) throws {
        self.value = header
    }
}

final class InMemoryMiniMaxAPITokenStore: MiniMaxAPITokenStoring, @unchecked Sendable {
    var value: String?

    init(value: String? = nil) {
        self.value = value
    }

    func loadToken() throws -> String? {
        self.value
    }

    func storeToken(_ token: String?) throws {
        self.value = token
    }
}

final class InMemoryKimiTokenStore: KimiTokenStoring, @unchecked Sendable {
    var value: String?

    init(value: String? = nil) {
        self.value = value
    }

    func loadToken() throws -> String? {
        self.value
    }

    func storeToken(_ token: String?) throws {
        self.value = token
    }
}

final class InMemoryCopilotTokenStore: CopilotTokenStoring, @unchecked Sendable {
    var value: String?

    init(value: String? = nil) {
        self.value = value
    }

    func loadToken() throws -> String? {
        self.value
    }

    func storeToken(_ token: String?) throws {
        self.value = token
    }
}

final class InMemoryTokenAccountStore: ProviderTokenAccountStoring, @unchecked Sendable {
    var accounts: [UsageProvider: ProviderTokenAccountData] = [:]
    private let fileURL: URL

    init(fileURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "token-accounts-\(UUID().uuidString).json"))
    {
        self.fileURL = fileURL
    }

    func loadAccounts() throws -> [UsageProvider: ProviderTokenAccountData] {
        self.accounts
    }

    func storeAccounts(_ accounts: [UsageProvider: ProviderTokenAccountData]) throws {
        self.accounts = accounts
    }

    func ensureFileExists() throws -> URL {
        self.fileURL
    }
}

func testConfigStore(suiteName: String, reset: Bool = true) -> CodexBarConfigStore {
    let sanitized = suiteName.replacingOccurrences(of: "/", with: "-")
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("codexbar-tests", isDirectory: true)
        .appendingPathComponent(sanitized, isDirectory: true)
    let url = base.appendingPathComponent("config.json")
    if reset {
        try? FileManager.default.removeItem(at: url)
    }
    return CodexBarConfigStore(fileURL: url)
}

@MainActor
func testSettingsStore(
    suiteName: String,
    tokenAccountStore: any ProviderTokenAccountStoring = InMemoryTokenAccountStore(),
    config: CodexBarConfig? = nil,
    userDefaults: UserDefaults? = nil,
    prepareDefaults: ((UserDefaults) -> Void)? = nil,
    keychainAccessPolicy: SettingsStoreKeychainAccessPolicy = .init(
        setDisabled: { _ in }, isExplicitlyDisabled: { false })) -> SettingsStore
{
    let isolatedSuiteName = "\(suiteName)-\(UUID().uuidString)"
    guard let defaults = userDefaults ?? UserDefaults(suiteName: isolatedSuiteName) else {
        preconditionFailure("Could not create test defaults suite")
    }
    if userDefaults == nil {
        defaults.removePersistentDomain(forName: isolatedSuiteName)
    }
    prepareDefaults?(defaults)
    let configStore = testConfigStore(suiteName: isolatedSuiteName)
    if let config {
        do {
            try configStore.save(config)
        } catch {
            preconditionFailure("Could not save test config: \(error)")
        }
    }
    return SettingsStore(
        userDefaults: defaults,
        configStore: configStore,
        zaiTokenStore: NoopZaiTokenStore(),
        syntheticTokenStore: NoopSyntheticTokenStore(),
        codexCookieStore: InMemoryCookieHeaderStore(),
        claudeCookieStore: InMemoryCookieHeaderStore(),
        cursorCookieStore: InMemoryCookieHeaderStore(),
        opencodeCookieStore: InMemoryCookieHeaderStore(),
        factoryCookieStore: InMemoryCookieHeaderStore(),
        minimaxCookieStore: InMemoryMiniMaxCookieStore(),
        minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
        kimiTokenStore: InMemoryKimiTokenStore(),
        augmentCookieStore: InMemoryCookieHeaderStore(),
        ampCookieStore: InMemoryCookieHeaderStore(),
        copilotTokenStore: InMemoryCopilotTokenStore(),
        tokenAccountStore: tokenAccountStore,
        keychainAccessPolicy: keychainAccessPolicy)
}

#if os(macOS)
@MainActor
func testStatusBar() -> NSStatusBar {
    // Standalone NSStatusBar instances can crash during swiftpm-testing-helper teardown.
    .system
}

@MainActor
@discardableResult
func withStatusItemControllerForTesting<T>(
    store: UsageStore,
    settings: SettingsStore,
    fetcher: UsageFetcher,
    account: AccountInfo? = nil,
    statusBar: NSStatusBar = .system,
    operation: (StatusItemController) throws -> T) rethrows -> T
{
    let controller = StatusItemController(
        store: store,
        settings: settings,
        account: account ?? AccountInfo(email: nil, plan: nil),
        updater: DisabledUpdaterController(),
        preferencesSelection: PreferencesSelection(),
        statusBar: statusBar)
    defer { controller.releaseStatusItemsForTesting() }
    return try operation(controller)
}

@MainActor
@discardableResult
func withStatusItemControllerForTesting<T>(
    store: UsageStore,
    settings: SettingsStore,
    fetcher: UsageFetcher,
    account: AccountInfo? = nil,
    statusBar: NSStatusBar = .system,
    operation: (StatusItemController) async throws -> T) async rethrows -> T
{
    let controller = StatusItemController(
        store: store,
        settings: settings,
        account: account ?? AccountInfo(email: nil, plan: nil),
        updater: DisabledUpdaterController(),
        preferencesSelection: PreferencesSelection(),
        statusBar: statusBar)
    defer { controller.releaseStatusItemsForTesting() }
    return try await operation(controller)
}
#endif

func testPlanUtilizationHistoryStore(suiteName: String, reset: Bool = true) -> PlanUtilizationHistoryStore {
    let sanitized = suiteName.replacingOccurrences(of: "/", with: "-")
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("codexbar-tests", isDirectory: true)
        .appendingPathComponent(sanitized, isDirectory: true)
    let url = base.appendingPathComponent("history", isDirectory: true)
    if reset {
        try? FileManager.default.removeItem(at: url)
    }
    return PlanUtilizationHistoryStore(directoryURL: url)
}

@MainActor
func testConfigWithAllProvidersDisabled() -> CodexBarConfig {
    CodexBarConfig(providers: UsageProvider.allCases.map {
        ProviderConfig(id: $0.instanceID, enabled: false)
    })
}

@MainActor
func enableTestProviders(_ providers: [UsageProvider], settings: SettingsStore) {
    for provider in UsageProvider.allCases {
        settings.updateProviderConfig(provider: provider) { $0.enabled = providers.contains(provider) }
    }
}
