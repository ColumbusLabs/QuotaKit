import CodexBarSync
import Foundation

/// Publishes Lite's provider states to CloudKit for the iPhone (068 §6).
///
/// One operation runs at a time, in request order. A sync request made while another is waiting to start is
/// dropped, because the waiting one reads the newest state when it starts. The ledger changes only after
/// CloudKit confirms, so a failed cycle is simply retried by the next request.
@MainActor
public final class SyncBridge {
    public struct Inputs: Sendable {
        public var states: [ProviderState]
        public var enabled: Set<LiteProvider>
        /// The alert thresholds the iPhone draws as markers.
        public var quotaWarnings: SyncQuotaWarningConfig?

        public init(states: [ProviderState], enabled: Set<LiteProvider>, quotaWarnings: SyncQuotaWarningConfig? = nil) {
            self.states = states
            self.enabled = enabled
            self.quotaWarnings = quotaWarnings
        }
    }

    public struct Device: Sendable {
        public var id: String
        public var name: String
        public var appVersion: String?

        public init(id: String, name: String, appVersion: String?) {
            self.id = id
            self.name = name
            self.appVersion = appVersion
        }
    }

    private let pusher: @MainActor () -> any SyncPushing
    private let device: @MainActor () -> Device
    private let inputs: @MainActor () -> Inputs
    private let store: SyncLedgerStore
    private let now: @MainActor () -> Date
    private var ledger: SyncLedger
    private var tail: Task<Void, Never>?
    private var isSyncQueued = false

    /// The last CloudKit failure, cleared by the next success. For the menu.
    public private(set) var lastError: String?

    /// - Parameters:
    ///   - pusher: CloudKit. A closure, so `CloudSyncManager.shared` (and its `CKContainer`) is only created on
    ///     the first real write (§6.2).
    ///   - device: Lite's own device ID and name, also read lazily.
    ///   - inputs: the states and enabled providers, read when an operation starts.
    public init(
        pusher: @escaping @MainActor () -> any SyncPushing,
        device: @escaping @MainActor () -> Device,
        inputs: @escaping @MainActor () -> Inputs,
        store: SyncLedgerStore,
        now: @escaping @MainActor () -> Date = { Date() })
    {
        self.pusher = pusher
        self.device = device
        self.inputs = inputs
        self.store = store
        self.now = now
        self.ledger = store.load()
    }

    /// Whether anything has been published and not yet removed.
    public var hasPublishedRecords: Bool {
        !self.ledger.records.isEmpty
    }

    /// Writes what changed and deletes what no longer belongs. Nothing touches CloudKit when nothing is due.
    public func requestSync() {
        guard !self.isSyncQueued else { return }
        self.isSyncQueued = true
        self.enqueue { bridge in
            bridge.isSyncQueued = false
            await bridge.runSync()
        }
    }

    /// Unpublish from iPhone: deletes every record Lite has written.
    public func unpublishAll() {
        self.enqueue { bridge in
            await bridge.delete(bridge.ledger.records.keys.sorted())
        }
    }

    /// Waits for every queued operation. For tests.
    public func waitUntilIdle() async {
        while let tail = self.tail {
            await tail.value
            if self.tail == tail { return }
        }
    }

    private func enqueue(_ operation: @escaping @MainActor (SyncBridge) async -> Void) {
        let previous = self.tail
        self.tail = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await operation(self)
        }
    }

    private func runSync() async {
        let inputs = self.inputs()
        let now = self.now()
        let device = self.device()
        let plan = self.ledger.plan(
            states: inputs.states,
            enabled: inputs.enabled,
            deviceID: device.id,
            now: now,
            quotaWarnings: inputs.quotaWarnings)
        guard !plan.isEmpty else { return }

        let pusher = self.pusher()
        if !plan.writes.isEmpty {
            let envelopes = plan.writes.map { write in
                ProviderUsageEnvelope(
                    deviceID: device.id,
                    deviceName: device.name,
                    appVersion: device.appVersion,
                    mobileVersion: nil,
                    syncTimestamp: now,
                    notificationPushEnabled: nil,
                    provider: write.snapshot)
            }
            let result = await pusher.pushPerProviderRecords(envelopes)
            guard result.succeeded else {
                self.lastError = result.message ?? "iCloud write failed"
                return
            }
            self.ledger.recordWrites(plan.writes, at: now)
            self.lastError = nil
            self.persist()
        }
        // Only after the new records landed, so a card never disappears before its replacement exists.
        await self.delete(plan.deletes)
    }

    private func delete(_ names: [String]) async {
        guard !names.isEmpty else { return }
        let result = await self.pusher().deletePerProviderRecords(recordNames: names)
        guard result.succeeded else {
            self.lastError = result.message ?? "iCloud delete failed"
            return
        }
        self.ledger.recordDeletes(names)
        self.lastError = nil
        self.persist()
    }

    private func persist() {
        _ = try? self.store.save(self.ledger)
    }
}
