import Foundation

/// Decides whether an event in a credential directory is real activity: only when one of the root's signal files
/// appeared or got a newer modification date since the last look (068 §5.1). Pure: the watcher passes in a
/// metadata-only listing, and no file is ever read.
public struct ActivitySignalGate: Sendable {
    /// File name → modification date, for the files in one directory.
    public typealias Listing = [String: Date]

    private var seen: [String: [String: Date]] = [:]

    public init() {}

    /// Records the current dates without reporting activity. Call when watching starts.
    public mutating func seed(_ root: ActivityRoots.Root, listing: Listing) {
        self.seen[root.path] = Self.signals(in: listing, for: root)
    }

    /// True when a signal file is new or newer than last time. Updates what was seen either way.
    public mutating func hasNewSignal(_ root: ActivityRoots.Root, listing: Listing) -> Bool {
        let current = Self.signals(in: listing, for: root)
        let previous = self.seen[root.path]
        self.seen[root.path] = current
        guard let previous else { return !current.isEmpty }
        return current.contains { name, date in
            guard let before = previous[name] else { return true }
            return date > before
        }
    }

    private static func signals(in listing: Listing, for root: ActivityRoots.Root) -> [String: Date] {
        listing.filter { name, _ in root.signalFiles.contains { $0.matches(name) } }
    }
}
