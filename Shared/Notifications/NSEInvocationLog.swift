import Foundation

/// Append-only ring buffer of NSE invocation entries persisted to the
/// `group.com.o1xhack.codexbar` App Group's shared `UserDefaults`. The NSE
/// (`CodexBarMobilePushExtension`) writes one entry per push it receives,
/// the host app's Push Setup diagnostic view reads them — no IPC needed
/// because the App Group container is the shared sandbox.
///
/// We deliberately use a single `UserDefaults` array of `[String: Any]`
/// dictionaries rather than a file: NSE's 30-second execution budget makes
/// every saved nanosecond matter, and `UserDefaults` is the fastest
/// process-local persistent store iOS exposes.
public enum NSEInvocationEvent: String, Codable, Sendable {
    /// `didReceive(...)` entered, before any parsing. Always logged first.
    case woke
    /// Push wasn't recognised as a quota-zone notification.
    case zoneNil
    /// CloudKit fetch returned nothing — no records in the zone.
    case fetchNil
    /// CloudKit fetch threw — message captures the error.
    case fetchError
    /// Body / title rewritten successfully.
    case ok
}

public struct NSEInvocationEntry: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let event: NSEInvocationEvent
    public let zoneName: String?
    public let detail: String

    public init(timestamp: Date, event: NSEInvocationEvent, zoneName: String?, detail: String) {
        self.timestamp = timestamp
        self.event = event
        self.zoneName = zoneName
        self.detail = detail
    }
}

/// Cross-process log backed by `NSUbiquitousKeyValueStore` (iCloud KV store).
///
/// **Why iCloud KV instead of an App Group?** App Groups require manual
/// registration on Apple Developer Portal AND inclusion in the
/// provisioning profile — `xcodebuild -allowProvisioningUpdates` can
/// generate provisioning but cannot create App Group IDs. Build 124's
/// signed binary had `application-groups: []` (empty) because the
/// portal-side App Group was never registered, which silently broke the
/// IPC. The iCloud KV identifier `com.codexbar.shared` is already
/// provisioned for the host app (used for `NSUbiquitousKeyValueStore`),
/// and adding the same entitlement key to the NSE auto-includes it in
/// the NSE's provisioning profile via Xcode's managed signing. Zero
/// portal touchpoints needed.
///
/// **Same-device IPC trade-offs:** iCloud KV is designed for cross-device
/// sync, but within a single device's two-process boundary it works for
/// read-after-write within a few hundred milliseconds (much faster than
/// the cross-device case, which can take seconds). Each process calls
/// `synchronize()` on its side: NSE after every write, the iOS app
/// before reading. The 1 MB quota / 1024 key limit is irrelevant for
/// a 100-entry diagnostic log encoded as a single JSON blob.
///
/// `@unchecked Sendable` is sound because the only mutable state lives in
/// `NSUbiquitousKeyValueStore.default`, which Apple documents as
/// thread-safe.
public final class NSEInvocationLog: @unchecked Sendable {
    /// Hard cap so the shared store can't grow unboundedly. 100 entries ≈
    /// last ~100 pushes, which covers any reasonable debug session.
    public static let maxEntries = 100
    /// Key under `NSUbiquitousKeyValueStore.default`.
    private static let storageKey = "NSEInvocationLog.entries"

    public static let shared = NSEInvocationLog()

    private let store: NSUbiquitousKeyValueStore

    private init() {
        self.store = NSUbiquitousKeyValueStore.default
    }

    /// Appends one entry, evicting the oldest if we exceed `maxEntries`.
    /// Calls `synchronize()` after the write so the host app sees fresh
    /// data on its next read. NSE has a 30-second budget; one
    /// synchronize call here adds a negligible amount.
    public func recordEntry(
        timestamp: Date,
        event: NSEInvocationEvent,
        zoneName: String?,
        detail: String)
    {
        let entry = NSEInvocationEntry(
            timestamp: timestamp,
            event: event,
            zoneName: zoneName,
            detail: detail)
        var entries = self.loadInternal()
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        if let data = try? JSONEncoder().encode(entries) {
            self.store.set(data, forKey: Self.storageKey)
            self.store.synchronize()
        }
    }

    /// Loads all entries, newest last. Forces a synchronize first so the
    /// caller picks up writes from the NSE process that may not yet have
    /// propagated to this process's in-memory cache.
    public func loadAll() -> [NSEInvocationEntry] {
        self.store.synchronize()
        return self.loadInternal()
    }

    /// Clears the log — surfaced in the diagnostic UI as a "Clear" button so
    /// the user can reset between test runs.
    public func clear() {
        self.store.removeObject(forKey: Self.storageKey)
        self.store.synchronize()
    }

    private func loadInternal() -> [NSEInvocationEntry] {
        guard let data = self.store.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([NSEInvocationEntry].self, from: data)) ?? []
    }
}
