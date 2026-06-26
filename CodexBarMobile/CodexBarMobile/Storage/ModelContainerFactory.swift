import CodexBarSync
import Foundation
import SwiftData

/// Builds and caches the app-wide `ModelContainer`.
///
/// P2a behavior:
/// - Store path prefers the App Group container
///   (`group.com.columbuslabs.quotakit`), falling back to the app sandbox
///   Application Support directory when the entitlement is absent. This makes
///   the factory work in unit tests + simulator without any provisioning change,
///   while the shipping app (which has the App Group entitlement) still lands
///   in the shared container ready for an App Extension to read.
/// - On any `ModelContainer` init failure — typically a schema migration that
///   SwiftData cannot resolve automatically — the existing store is deleted
///   and recreated. This is acceptable for P2a because SwiftData is being
///   introduced for the first time; the data is a cache of CloudKit and can
///   always be re-populated from the server on next fetch. Future phases
///   must revisit this once real migrations exist.
enum ModelContainerFactory {
    /// App Group identifier shared with the menu bar counterpart. See
    /// `Scripts/package_app.sh:142` on the Mac side.
    static let appGroupID = ProductConfig.appGroupIdentifier

    /// Default SQLite filename inside whichever container we land on.
    static let storeFilename = "QuotaKitStore.sqlite"

    static let storeMigrationFlagKey = "com.columbuslabs.quotakit.storeMigrated.v1"
    private static let legacyStoreSubdirectoryNames = ["CodexBar", "QuotaKit"]

    // `NSLock` is reference-type and inherently thread-safe; access to
    // `sharedContainer` is serialised by the lock below, so marking the
    // stored state `nonisolated(unsafe)` is correct under Swift 6 strict
    // concurrency.
    private static let lock = NSLock()
    private nonisolated(unsafe) static var sharedContainer: ModelContainer?

    /// Returns a lazily-constructed app-wide container. Thread-safe.
    static func shared() -> ModelContainer {
        self.lock.lock()
        defer { lock.unlock() }
        if let existing = sharedContainer { return existing }
        Self.migrateLegacyStoreIfNeeded()
        let container = Self.makeContainer(at: Self.defaultStoreURL())
        self.sharedContainer = container
        return container
    }

    /// Main-actor convenience for view code that wants a `ModelContext` directly.
    @MainActor
    static func sharedMainContext() -> ModelContext {
        self.shared().mainContext
    }

    /// Exposed for tests: build a container at an explicit URL (typically a
    /// temporary directory) without touching the shared singleton.
    static func makeContainer(at storeURL: URL) -> ModelContainer {
        let schema = Schema(CodexBarSwiftDataSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // Recovery path: wipe the on-disk store and retry once. Acceptable
            // in P2a because SwiftData holds only a local mirror of CloudKit.
            print("[CodexBar SwiftData] Initial ModelContainer init failed — " +
                "deleting store and retrying. Error: \(error)")
            Self.deleteStoreFiles(at: storeURL)
            do {
                return try ModelContainer(for: schema, configurations: configuration)
            } catch {
                // If the retry also fails, fall back to a fully in-memory store.
                // The app keeps running; persistence is disabled for this session.
                print("[CodexBar SwiftData] Retry after wipe also failed — " +
                    "falling back to in-memory store. Error: \(error)")
                let memConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true)
                // As a last resort, this will trap if in-memory also fails —
                // which would indicate a schema bug, not a runtime condition.
                return try! ModelContainer(for: schema, configurations: memConfig)
            }
        }
    }

    /// Default on-disk location. Prefers the App Group container; falls back
    /// to the app's Application Support directory.
    static func defaultStoreURL() -> URL {
        let fm = FileManager.default
        let base: URL = {
            if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
                return group
            }
            let appSupport: URL
            do {
                appSupport = try fm.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true)
            } catch {
                appSupport = URL(fileURLWithPath: NSTemporaryDirectory())
            }
            return appSupport
        }()
        let dir = base.appendingPathComponent("QuotaKit", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Self.storeFilename, isDirectory: false)
    }

    /// Copies a pre-app-group SwiftData store into the shared container once.
    static func migrateLegacyStoreIfNeeded(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard)
    {
        guard !defaults.bool(forKey: self.storeMigrationFlagKey) else { return }

        let targetURL = Self.defaultStoreURL()
        if fileManager.fileExists(atPath: targetURL.path) {
            defaults.set(true, forKey: Self.storeMigrationFlagKey)
            return
        }

        guard let legacyURL = Self.legacyStoreURL(fileManager: fileManager),
              fileManager.fileExists(atPath: legacyURL.path)
        else {
            defaults.set(true, forKey: Self.storeMigrationFlagKey)
            return
        }

        do {
            try Self.copyStoreFiles(
                from: legacyURL,
                to: targetURL,
                fileManager: fileManager)
            defaults.set(true, forKey: Self.storeMigrationFlagKey)
        } catch {
            print("[QuotaKit SwiftData] Legacy store migration failed: \(error)")
        }
    }

    static func copyStoreFiles(
        from sourceURL: URL,
        to targetURL: URL,
        fileManager: FileManager = .default) throws
    {
        try fileManager.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: sourceURL.path + suffix)
            let destination = URL(fileURLWithPath: targetURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    static func legacyStoreURL(
        fileManager: FileManager = .default,
        applicationSupportRoot: URL? = nil) -> URL?
    {
        let appSupport: URL
        if let applicationSupportRoot {
            appSupport = applicationSupportRoot
        } else {
            do {
                appSupport = try fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false)
            } catch {
                return nil
            }
        }

        for subdir in Self.legacyStoreSubdirectoryNames {
            let candidate = appSupport
                .appendingPathComponent(subdir, isDirectory: true)
                .appendingPathComponent(Self.storeFilename, isDirectory: false)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Remove the SQLite file + its WAL/SHM sidecars. Safe if files are absent.
    static func deleteStoreFiles(at storeURL: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let path = storeURL.path + suffix
            if fm.fileExists(atPath: path) {
                try? fm.removeItem(atPath: path)
            }
        }
    }

    /// Test hook to clear the cached singleton between test cases.
    static func _resetSharedForTests() {
        self.lock.lock()
        self.sharedContainer = nil
        self.lock.unlock()
    }
}
