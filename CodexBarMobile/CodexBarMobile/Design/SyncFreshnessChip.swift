import CodexBarSync
import SwiftUI

enum SyncFreshnessPlacement {
    case header
    case footer
}

struct SyncFreshnessState {
    enum Kind: Equatable {
        case demo
        case synced(syncTimestamp: Date, isStale: Bool)
        case refreshing(lastConfirmedSync: Date?)
        case failed(lastConfirmedSync: Date?)
    }

    static let staleThreshold: TimeInterval = 3600

    let kind: Kind

    var isStale: Bool {
        switch self.kind {
        case .demo:
            false
        case let .synced(_, isStale):
            isStale
        case .refreshing:
            false
        case .failed:
            true
        }
    }

    static func resolve(
        isDemoMode: Bool,
        snapshot: SyncedUsageSnapshot?,
        syncStatus: SyncStatus,
        now: Date = Date()) -> SyncFreshnessState?
    {
        if isDemoMode {
            return SyncFreshnessState(kind: .demo)
        }
        switch syncStatus {
        case .syncing:
            return SyncFreshnessState(kind: .refreshing(
                lastConfirmedSync: snapshot?.syncTimestamp))
        case .error:
            guard let snapshot else { return nil }
            return SyncFreshnessState(kind: .failed(
                lastConfirmedSync: snapshot.syncTimestamp))
        case let .synced(lastConfirmedSync):
            let age = now.timeIntervalSince(lastConfirmedSync)
            return SyncFreshnessState(kind: .synced(
                syncTimestamp: lastConfirmedSync,
                isStale: age > Self.staleThreshold))
        case .noData, .incompatibleData:
            break
        }
        guard let snapshot else { return nil }
        let age = now.timeIntervalSince(snapshot.syncTimestamp)
        return SyncFreshnessState(kind: .synced(
            syncTimestamp: snapshot.syncTimestamp,
            isStale: age > Self.staleThreshold))
    }
}

enum SyncFreshnessFormatter {
    static func ageText(since timestamp: Date, now: Date) -> String {
        self.ageText(elapsed: now.timeIntervalSince(timestamp))
    }

    static func ageText(elapsed rawInterval: TimeInterval) -> String {
        let interval = max(0, rawInterval)
        if interval < 60 {
            let seconds = Int(interval.rounded(.down))
            return String.localizedStringWithFormat(
                String(localized: "%lld sec ago"),
                seconds)
        }
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes.formatted()) \(String(localized: "min ago"))"
        }
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours.formatted())\(String(localized: "h ago"))"
        }
        let days = Int(interval / 86400)
        return "\(days.formatted())\(String(localized: "d ago"))"
    }

    static func syncedText(since timestamp: Date, now: Date) -> String {
        String.localizedStringWithFormat(
            String(localized: "Synced %@"),
            self.ageText(since: timestamp, now: now))
    }

    static func lastSyncedText(since timestamp: Date, now: Date) -> String {
        String.localizedStringWithFormat(
            String(localized: "Last synced %@"),
            self.ageText(since: timestamp, now: now))
    }

    static func refreshingText(lastConfirmedSync: Date?, now: Date) -> String {
        guard let lastConfirmedSync else {
            return String(localized: "Refreshing…")
        }
        return String.localizedStringWithFormat(
            String(localized: "Refreshing · last synced %@"),
            self.ageText(since: lastConfirmedSync, now: now))
    }

    static func refreshFailedText(lastConfirmedSync: Date?, now: Date) -> String {
        guard let lastConfirmedSync else {
            return String(localized: "Refresh failed")
        }
        return String.localizedStringWithFormat(
            String(localized: "Refresh failed · last synced %@"),
            self.ageText(since: lastConfirmedSync, now: now))
    }
}

enum SyncFreshnessTimeline {
    static func cadence(since timestamp: Date?, now: Date = Date()) -> TimeInterval {
        guard let timestamp else { return 60 }
        let interval = max(0, now.timeIntervalSince(timestamp))
        if interval < 60 { return 1 }
        if interval < 3600 { return 60 }
        if interval < 86400 { return 300 }
        return 3600
    }
}

struct SyncStatusChipView: View {
    let placement: SyncFreshnessPlacement
    let isDemoMode: Bool
    let snapshot: SyncedUsageSnapshot?
    let syncStatus: SyncStatus
    var refreshAction: (() -> Void)?

    private var isRefreshing: Bool {
        if case .syncing = self.syncStatus { return true }
        return false
    }

    private var timelineReferenceDate: Date? {
        switch self.syncStatus {
        case let .synced(lastConfirmedSync):
            lastConfirmedSync
        case .syncing, .error:
            self.snapshot?.syncTimestamp
        case .noData, .incompatibleData:
            self.snapshot?.syncTimestamp
        }
    }

    var body: some View {
        TimelineView(.periodic(
            from: .now,
            by: SyncFreshnessTimeline.cadence(since: self.timelineReferenceDate)))
        { timeline in
            if let state = SyncFreshnessState.resolve(
                isDemoMode: self.isDemoMode,
                snapshot: self.snapshot,
                syncStatus: self.syncStatus,
                now: timeline.date)
            {
                switch self.placement {
                case .header:
                    self.interactiveChip {
                        self.headerChip(state, now: timeline.date)
                    }
                case .footer:
                    self.interactiveChip {
                        self.footerChip(state, now: timeline.date)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func interactiveChip(
        @ViewBuilder content: () -> some View) -> some View
    {
        if let refreshAction, !self.isDemoMode {
            Button(action: refreshAction) {
                content()
            }
            .buttonStyle(.plain)
            .disabled(self.isRefreshing)
            .accessibilityHint(Text("Refresh synced data"))
        } else {
            content()
        }
    }

    @ViewBuilder
    private func headerChip(_ state: SyncFreshnessState, now: Date) -> some View {
        switch state.kind {
        case .demo:
            QKStatusChip(
                text: String(localized: "Demo mode"),
                style: .demo,
                systemImage: "play.circle.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .synced(_, isStale):
            QKStatusChip(
                text: isStale
                    ? String(localized: "Stale · tap or pull to refresh")
                    : String(localized: "Live · synced from Mac"),
                style: isStale ? .stale : .live,
                systemImage: isStale ? "clock.badge.exclamationmark" : "checkmark.circle.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .refreshing(lastConfirmedSync):
            QKStatusChip(
                text: SyncFreshnessFormatter.refreshingText(
                    lastConfirmedSync: lastConfirmedSync,
                    now: now),
                style: .stale,
                isLoading: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .failed(lastConfirmedSync):
            QKStatusChip(
                text: SyncFreshnessFormatter.refreshFailedText(
                    lastConfirmedSync: lastConfirmedSync,
                    now: now),
                style: .error,
                systemImage: "exclamationmark.triangle.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func footerChip(_ state: SyncFreshnessState, now: Date) -> some View {
        switch state.kind {
        case .demo:
            EmptyView()
        case let .synced(syncTimestamp, isStale):
            QKStatusChip(
                text: SyncFreshnessFormatter.syncedText(
                    since: syncTimestamp,
                    now: now),
                style: isStale ? .stale : .live,
                systemImage: "arrow.triangle.2.circlepath")
        case let .refreshing(lastConfirmedSync):
            QKStatusChip(
                text: SyncFreshnessFormatter.refreshingText(
                    lastConfirmedSync: lastConfirmedSync,
                    now: now),
                style: .stale,
                isLoading: true)
        case let .failed(lastConfirmedSync):
            QKStatusChip(
                text: SyncFreshnessFormatter.refreshFailedText(
                    lastConfirmedSync: lastConfirmedSync,
                    now: now),
                style: .error,
                systemImage: "exclamationmark.triangle.fill")
        }
    }
}
