import CodexBarSync
import Foundation

/// What Lite has published to CloudKit, persisted so a restart neither re-uploads everything nor forgets which
/// records to clean up (068 §6.2, §6.3). Deletes go by these record names, not by a `deviceID` query, which can
/// come back empty right after a write (Phase 0, Q4).
public struct SyncLedger: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var provider: LiteProvider
        public var hash: Int
        public var writtenAt: Date

        public init(provider: LiteProvider, hash: Int, writtenAt: Date) {
            self.provider = provider
            self.hash = hash
            self.writtenAt = writtenAt
        }
    }

    /// Keyed by CloudKit record name.
    public var records: [String: Entry]

    public init(records: [String: Entry] = [:]) {
        self.records = records
    }

    /// Records written in one cycle, ready for `CloudSyncManager.pushPerProviderRecords`.
    public struct Write: Sendable, Equatable {
        public let recordName: String
        public let provider: LiteProvider
        public let hash: Int
        public let snapshot: ProviderUsageSnapshot
    }

    public struct Plan: Sendable, Equatable {
        public var writes: [Write]
        /// Record names to delete, in sorted order. Sent only after the writes succeed.
        public var deletes: [String]

        public var isEmpty: Bool {
            self.writes.isEmpty && self.deletes.isEmpty
        }
    }

    /// The 30-minute heartbeat: an unchanged record is rewritten this often, so the iPhone's "updated" time stays
    /// right (§6.2).
    public static let heartbeat: TimeInterval = 30 * 60

    /// Decides one sync cycle.
    ///
    /// - A provider's record is written when its content hash changed, when it is new, or when it is a heartbeat old.
    /// - Records of disabled providers are deleted, and so is a provider's old record once its account changed.
    /// - An enabled provider with nothing to publish keeps its record: an empty fetch shouldn't remove a card.
    public func plan(
        states: [ProviderState],
        enabled: Set<LiteProvider>,
        deviceID: String,
        now: Date) -> Plan
    {
        var writes: [Write] = []
        var current: [LiteProvider: String] = [:]
        for state in states where enabled.contains(state.provider) {
            guard let snapshot = SyncSnapshot.make(for: state, now: now),
                  let hash = SyncSnapshot.contentHash(for: state, now: now)
            else { continue }
            let name = SyncSnapshot.recordName(
                deviceID: deviceID,
                provider: state.provider,
                accountEmail: snapshot.accountEmail)
            current[state.provider] = name
            let entry = self.records[name]
            let isDue = entry.map { $0.hash != hash || now.timeIntervalSince($0.writtenAt) >= Self.heartbeat } ?? true
            if isDue {
                writes.append(Write(recordName: name, provider: state.provider, hash: hash, snapshot: snapshot))
            }
        }
        let deletes = self.records.compactMap { name, entry -> String? in
            guard enabled.contains(entry.provider) else { return name }
            guard let currentName = current[entry.provider] else { return nil }
            return currentName == name ? nil : name
        }
        return Plan(writes: writes, deletes: deletes.sorted())
    }

    /// Records a successful write.
    public mutating func recordWrites(_ writes: [Write], at now: Date) {
        for write in writes {
            self.records[write.recordName] = Entry(provider: write.provider, hash: write.hash, writtenAt: now)
        }
    }

    /// Records a successful delete.
    public mutating func recordDeletes(_ names: [String]) {
        for name in names {
            self.records[name] = nil
        }
    }
}

/// Reads and writes the ledger as JSON next to `state.json`.
public struct SyncLedgerStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        LiteStateStore.defaultFileURL().deletingLastPathComponent().appendingPathComponent("sync.json")
    }

    /// An unreadable or missing file is an empty ledger: the worst case is one re-upload.
    public func load() -> SyncLedger {
        guard let data = try? Data(contentsOf: self.fileURL),
              let ledger = try? JSONDecoder().decode(SyncLedger.self, from: data)
        else { return SyncLedger() }
        return ledger
    }

    public func save(_ ledger: SyncLedger) throws {
        try FileManager.default.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try JSONEncoder().encode(ledger).write(to: self.fileURL, options: .atomic)
    }
}
