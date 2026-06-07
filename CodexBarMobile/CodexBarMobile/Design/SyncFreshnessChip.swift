import CodexBarSync
import SwiftUI

enum SyncFreshnessPlacement {
    case header
    case footer
}

struct SyncFreshnessState {
    enum Kind {
        case demo
        case synced(syncTimestamp: Date, isStale: Bool)
    }

    static let staleThreshold: TimeInterval = 3600

    let kind: Kind

    var isStale: Bool {
        switch self.kind {
        case .demo:
            false
        case .synced(_, let isStale):
            isStale
        }
    }

    static func resolve(isDemoMode: Bool, snapshot: SyncedUsageSnapshot?) -> SyncFreshnessState? {
        if isDemoMode {
            return SyncFreshnessState(kind: .demo)
        }
        guard let snapshot else { return nil }
        let age = Date().timeIntervalSince(snapshot.syncTimestamp)
        return SyncFreshnessState(kind: .synced(
            syncTimestamp: snapshot.syncTimestamp,
            isStale: age > Self.staleThreshold))
    }
}

struct SyncStatusChipView: View {
    let placement: SyncFreshnessPlacement
    let isDemoMode: Bool
    let snapshot: SyncedUsageSnapshot?

    var body: some View {
        if let state = SyncFreshnessState.resolve(isDemoMode: self.isDemoMode, snapshot: self.snapshot) {
            switch self.placement {
            case .header:
                self.headerChip(state)
            case .footer:
                self.footerChip(state)
            }
        }
    }

    @ViewBuilder
    private func headerChip(_ state: SyncFreshnessState) -> some View {
        switch state.kind {
        case .demo:
            QKStatusChip(
                text: String(localized: "Demo mode"),
                style: .demo,
                systemImage: "play.circle.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
        case .synced(_, let isStale):
            QKStatusChip(
                text: isStale
                    ? String(localized: "Stale · pull to refresh")
                    : String(localized: "Live · synced from Mac"),
                style: isStale ? .stale : .live,
                systemImage: isStale ? "clock.badge.exclamationmark" : "checkmark.circle.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func footerChip(_ state: SyncFreshnessState) -> some View {
        switch state.kind {
        case .demo:
            EmptyView()
        case .synced(let syncTimestamp, let isStale):
            QKStatusChip(
                text: String(
                    format: String(localized: "Synced %@"),
                    syncTimestamp.formatted(.relative(presentation: .named))),
                style: isStale ? .stale : .live,
                systemImage: "arrow.triangle.2.circlepath")
        }
    }
}
