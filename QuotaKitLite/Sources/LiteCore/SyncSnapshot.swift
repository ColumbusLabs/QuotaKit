import CodexBarSync
import Foundation

/// Builds the `ProviderUsageSnapshot` Lite publishes for one provider (068 §6.1), shaped like the full app's
/// `SyncCoordinator.buildProviderUsageSnapshot` so the iPhone renders and merges both the same way:
///
/// - every window goes into `rateWindows`, and the first two are repeated as `primary` and `secondary`;
/// - each window carries its lane as `identity` and the menu's pace text as `pace`;
/// - `loginMethod` is the raw plan, `accountIdentities` follow §4;
/// - a status that isn't live data travels as `statusMessage` with `isError`, like the full app's error string;
/// - `quotaWarnings` carries the alert thresholds, so the iPhone's markers sit where alerts fire (§6.4);
/// - every cost, budget, history and provider-specific extension stays nil.
///
/// Only fetched windows are published, never the local reset projection (§5.3); the iPhone projects on its own.
public enum SyncSnapshot {
    /// The snapshot for `state`, or nil when it has no usable signal (the iPhone's `SnapshotCache.isGhost` rule,
    /// which the full app also applies before writing).
    public static func make(
        for state: ProviderState,
        now: Date,
        quotaWarnings: SyncQuotaWarningConfig? = nil) -> ProviderUsageSnapshot?
    {
        self.make(for: state, now: now, lastUpdated: state.lastFetched ?? now, quotaWarnings: quotaWarnings)
    }

    /// FNV-1a over the sorted-key JSON, as the full app's per-provider diff does, but with `lastUpdated` pinned so
    /// a fetch that changes nothing else doesn't count as a change (§6.2).
    public static func contentHash(
        for state: ProviderState,
        now: Date,
        quotaWarnings: SyncQuotaWarningConfig? = nil) -> Int?
    {
        guard let snapshot = self.make(
            for: state,
            now: now,
            lastUpdated: Date(timeIntervalSinceReferenceDate: 0),
            quotaWarnings: quotaWarnings),
            let data = try? self.hashEncoder.encode(snapshot)
        else { return nil }
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01B3
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: hash))
    }

    /// The CloudKit record name, `CloudSyncManager.perProviderRecordName`'s wire contract.
    public static func recordName(deviceID: String, provider: LiteProvider, accountEmail: String?) -> String {
        "\(deviceID)|\(provider.rawValue)|\(accountEmail ?? "_")"
    }

    private static let hashEncoder: JSONEncoder = {
        let encoder = CloudSyncConstants.makeJSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static func make(
        for state: ProviderState,
        now: Date,
        lastUpdated: Date,
        quotaWarnings: SyncQuotaWarningConfig?) -> ProviderUsageSnapshot?
    {
        let windows = state.windows.map { self.rateWindow(for: $0, provider: state.provider, now: now) }
        let statusMessage = self.statusMessage(for: state)
        guard !windows.isEmpty || statusMessage != nil else { return nil }
        // The full app's legacy pair is the first two windows. Antigravity's four windows instead put the
        // lowest 5-hour and the lowest weekly window up front, so the iPhone's two bars show the binding limits.
        let primary: SyncRateWindow?
        let secondary: SyncRateWindow?
        if state.provider == .antigravity {
            primary = state.windows.representative(.session, for: .antigravity)
                .map { self.rateWindow(for: $0, provider: .antigravity, now: now) }
            secondary = state.windows.representative(.weekly, for: .antigravity)
                .map { self.rateWindow(for: $0, provider: .antigravity, now: now) }
        } else {
            primary = windows.first
            secondary = windows.count > 1 ? windows[1] : nil
        }
        return ProviderUsageSnapshot(
            providerID: state.provider.rawValue,
            providerName: state.provider.displayName,
            primary: primary,
            secondary: secondary,
            accountEmail: state.accountEmail,
            loginMethod: state.plan,
            statusMessage: statusMessage,
            isError: statusMessage != nil,
            lastUpdated: lastUpdated,
            rateWindows: windows,
            accountIdentities: state.accountIdentities.isEmpty ? nil : state.accountIdentities,
            quotaWarnings: quotaWarnings)
    }

    static func rateWindow(for window: QuotaWindow, provider: LiteProvider, now: Date) -> SyncRateWindow {
        let pace = PaceText.detail(for: window, provider: provider, now: now).map { detail in
            SyncUsagePace(
                stage: detail.pace.stage,
                deltaPercent: detail.pace.deltaPercent,
                expectedUsedPercent: detail.pace.expectedUsedPercent,
                actualUsedPercent: detail.pace.actualUsedPercent,
                leftLabel: detail.leftLabel,
                rightLabel: detail.rightLabel)
        }
        return SyncRateWindow(
            label: window.label,
            usedPercent: window.usedPercent,
            windowMinutes: window.windowMinutes,
            resetsAt: window.resetsAt,
            resetDescription: nil,
            pace: pace,
            identity: window.lane)
    }

    /// The card subtitle for anything but live data. Paused never reaches here: nothing syncs while paused.
    static func statusMessage(for state: ProviderState) -> String? {
        switch state.status {
        case .ok, .paused: nil
        default: CardPresentation.subtitle(for: state, now: .distantFuture).text
        }
    }
}
