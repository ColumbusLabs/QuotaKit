import Foundation

/// Records every model name the fallback resolver had to substitute
/// because the local pricing table didn't contain an exact match.
///
/// The Debug pane reads `snapshot()` to surface a list users can
/// screenshot / report to us when their bill doesn't match expectations.
/// Logging is rate-limited: the first 5 unique unknown names emit a
/// `LogCategories.pricing` warning; subsequent hits for the same name
/// only bump the count to avoid flooding the log on a hot loop.
///
/// Storage is in-memory and session-scoped — restarting CodexBar wipes
/// the list. We deliberately don't persist: if a model was unknown at
/// build time and later got a pricing-table row in a Mac update, the
/// next session naturally clears it from the panel without us needing
/// invalidation logic.
public actor UnknownModelDiagnostics {
    /// Single record kept per unique `(providerKey, rawModel)` observed.
    public struct Entry: Sendable, Equatable, Identifiable {
        public let providerKey: String
        public let rawModel: String
        public let fallbackKey: String
        public let strategyName: String
        public let firstSeenAt: Date
        public var occurrenceCount: Int

        /// Stable composite identifier for SwiftUI `ForEach`. The actor's
        /// dedup key is `(providerKey, rawModel)` — keying just on
        /// `rawModel` lets a same name under two providers collide and
        /// drop one row in the diagnostic panel.
        public var id: String {
            "\(self.providerKey)|\(self.rawModel)"
        }
    }

    public static let shared = UnknownModelDiagnostics()

    private var entries: [String: Entry] = [:]
    private var loggedCount = 0

    /// Cap on how many unique unknown names emit a `pricing` warning per
    /// session. After this many distinct names have logged, we stop
    /// emitting new warnings and rely on the Debug pane / counter for
    /// further visibility.
    private let warningCap = 5

    private let log = CodexBarLog.logger(LogCategories.pricing)

    public init() {}

    /// Record an unknown-model fallback hit. Safe to call from any
    /// thread; the actor serializes mutation. The dedup key is
    /// `"{providerKey}|{rawModel}"` so the same name across providers
    /// (rare in practice) tracks separately.
    public func record(
        providerKey: String,
        rawModel: String,
        fallbackKey: String,
        strategyName: String,
        now: Date = Date())
    {
        let dedupKey = "\(providerKey)|\(rawModel)"
        if var existing = self.entries[dedupKey] {
            existing.occurrenceCount += 1
            self.entries[dedupKey] = existing
            return
        }

        let entry = Entry(
            providerKey: providerKey,
            rawModel: rawModel,
            fallbackKey: fallbackKey,
            strategyName: strategyName,
            firstSeenAt: now,
            occurrenceCount: 1)
        self.entries[dedupKey] = entry

        // Rate-limited warning. Subsequent unique names beyond the cap
        // still get tracked in `entries` — they just don't write to the
        // log. The Debug pane sees them all.
        if self.loggedCount < self.warningCap {
            self.log.warning(
                "Unknown model '\(rawModel)' (provider: \(providerKey)) → "
                    + "fallback '\(fallbackKey)' via \(strategyName)",
                metadata: [:])
            self.loggedCount += 1
        }
    }

    /// Sorted snapshot for UI display. Sort: most-recently-first-seen
    /// first, ties broken by occurrence count desc, then provider/raw
    /// alphabetical for determinism.
    public func snapshot() -> [Entry] {
        self.entries.values.sorted { lhs, rhs in
            if lhs.firstSeenAt != rhs.firstSeenAt {
                return lhs.firstSeenAt > rhs.firstSeenAt
            }
            if lhs.occurrenceCount != rhs.occurrenceCount {
                return lhs.occurrenceCount > rhs.occurrenceCount
            }
            if lhs.providerKey != rhs.providerKey {
                return lhs.providerKey < rhs.providerKey
            }
            return lhs.rawModel < rhs.rawModel
        }
    }

    /// Clear all recorded entries. Used by tests; not exposed in UI.
    public func reset() {
        self.entries.removeAll()
        self.loggedCount = 0
    }
}
