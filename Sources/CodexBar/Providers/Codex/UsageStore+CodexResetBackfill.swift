import CodexBarCore
import Foundation

/// Reset-time backfill for Codex rate windows: rebuilds raw snapshot slots from cached lane data so
/// missing reset timestamps survive refreshes without disturbing fresh quota values.
extension UsageStore {
    nonisolated static func codexBackfillingResetWindows(
        _ snapshot: UsageSnapshot,
        from cached: UsageSnapshot) -> UsageSnapshot
    {
        guard CodexWeeklyResetConfirmation.accountsAreCompatible(snapshot, cached),
              CodexWeeklyResetConfirmation.plansAreCompatible(snapshot, cached)
        else { return snapshot }
        let primary = self.codexBackfilledSlotWindow(
            slotWindow: snapshot.primary,
            lane: .session,
            snapshot: snapshot,
            cached: cached)
        let secondary = self.codexBackfilledSlotWindow(
            slotWindow: snapshot.secondary,
            lane: .weekly,
            snapshot: snapshot,
            cached: cached)
        guard primary != snapshot.primary || secondary != snapshot.secondary else { return snapshot }
        return snapshot.with(primary: primary, secondary: secondary)
    }

    /// Rebuilds one raw snapshot slot during reset backfill. Monthly-classified windows live outside
    /// the session/weekly lane lookup, so a fresh 30-day window must be preserved in place (with its
    /// own reset backfill) instead of being dropped or overwritten by a stale cached lane window.
    private nonisolated static func codexBackfilledSlotWindow(
        slotWindow: RateWindow?,
        lane: CodexConsumerProjection.RateLane,
        snapshot: UsageSnapshot,
        cached: UsageSnapshot) -> RateWindow?
    {
        if let slotWindow, slotWindow.windowMinutes == CodexConsumerProjection.monthlyWindowMinutes {
            let cachedMonthly = [cached.primary, cached.secondary, cached.tertiary]
                .compactMap(\.self)
                .first { $0.windowMinutes == CodexConsumerProjection.monthlyWindowMinutes }
            return self.codexBackfillingResetWindow(slotWindow, from: cachedMonthly)
        }
        return self.codexBackfillingResetWindow(
            CodexConsumerProjection.sourceRateWindow(for: lane, snapshot: snapshot),
            from: CodexConsumerProjection.sourceRateWindow(for: lane, snapshot: cached))
    }

    nonisolated static func codexMergedResetBackfillSnapshot(
        _ snapshots: [UsageSnapshot],
        now: Date = Date()) -> UsageSnapshot?
    {
        guard let latestUpdatedAt = snapshots.map(\.updatedAt).max() else { return nil }
        let latestSnapshots = snapshots.filter { $0.updatedAt == latestUpdatedAt }
        let latestEmails = Set(latestSnapshots.compactMap {
            CodexIdentityResolver.normalizeEmail($0.accountEmail(for: .codex))
        })
        guard latestEmails.count <= 1,
              latestEmails.isEmpty || latestSnapshots.allSatisfy({
                  CodexIdentityResolver.normalizeEmail($0.accountEmail(for: .codex)) != nil
              })
        else { return nil }
        let accountCompatibleSnapshots: [UsageSnapshot]
        if let latestEmail = latestEmails.first {
            accountCompatibleSnapshots = snapshots.filter {
                CodexIdentityResolver.normalizeEmail($0.accountEmail(for: .codex)) == latestEmail
            }
        } else if snapshots.contains(where: {
            CodexIdentityResolver.normalizeEmail($0.accountEmail(for: .codex)) != nil
        }) {
            // An unknown latest identity cannot inherit reset evidence from a known older account.
            return nil
        } else {
            accountCompatibleSnapshots = snapshots
        }
        guard let accountCompatibleLatestAt = accountCompatibleSnapshots.map(\.updatedAt).max() else { return nil }
        let accountCompatibleLatest = accountCompatibleSnapshots.filter { $0.updatedAt == accountCompatibleLatestAt }
        let latestPlans = Set(accountCompatibleLatest.compactMap(CodexWeeklyResetConfirmation.normalizedPlan))
        guard latestPlans.count <= 1,
              latestPlans.isEmpty || accountCompatibleLatest.allSatisfy({
                  CodexWeeklyResetConfirmation.normalizedPlan($0) != nil
              })
        else { return nil }
        let latestPlan = latestPlans.first
        let compatibleSnapshots: [UsageSnapshot]
        if let latestPlan {
            compatibleSnapshots = accountCompatibleSnapshots.filter {
                CodexWeeklyResetConfirmation.normalizedPlan($0) == latestPlan
            }
        } else if accountCompatibleSnapshots.contains(where: {
            CodexWeeklyResetConfirmation.normalizedPlan($0) != nil
        }) {
            // A newer observation with no plan cannot inherit reset evidence from an older known plan.
            return nil
        } else {
            compatibleSnapshots = accountCompatibleSnapshots
        }
        var primary = self.codexPreferredResetBackfillWindow(
            compatibleSnapshots.enumerated().compactMap { index, snapshot in
                CodexConsumerProjection.sourceRateWindow(for: .session, snapshot: snapshot)
                    .map { (window: $0, updatedAt: snapshot.updatedAt, priority: index) }
            },
            now: now)
        var secondary = self.codexPreferredResetBackfillWindow(
            compatibleSnapshots.enumerated().compactMap { index, snapshot in
                CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: snapshot)
                    .map { (window: $0, updatedAt: snapshot.updatedAt, priority: index) }
            },
            now: now)
        let monthly = self.codexPreferredResetBackfillWindow(
            compatibleSnapshots.enumerated().compactMap { index, snapshot in
                Self.monthlyRateWindow(in: snapshot)
                    .map { (window: $0, updatedAt: snapshot.updatedAt, priority: index) }
            },
            now: now)
        if let monthly, let monthlyReset = monthly.resetsAt {
            if primary == nil {
                primary = monthly
            } else if secondary == nil {
                secondary = monthly
            } else if let primaryReset = primary?.resetsAt, monthlyReset > primaryReset {
                primary = monthly
            } else if let secondaryReset = secondary?.resetsAt, monthlyReset > secondaryReset {
                secondary = monthly
            }
        }
        guard primary != nil || secondary != nil else { return nil }
        let latestCompatibleIdentity = compatibleSnapshots.enumerated()
            .max { lhs, rhs in
                if lhs.element.updatedAt != rhs.element.updatedAt {
                    return lhs.element.updatedAt < rhs.element.updatedAt
                }
                return lhs.offset < rhs.offset
            }?
            .element.identity(for: UsageProvider.codex.instanceID)
        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            updatedAt: compatibleSnapshots.map(\.updatedAt).max() ?? now,
            identity: latestCompatibleIdentity)
    }

    private nonisolated static func monthlyRateWindow(in snapshot: UsageSnapshot) -> RateWindow? {
        [snapshot.primary, snapshot.secondary, snapshot.tertiary]
            .compactMap(\.self)
            .first { $0.windowMinutes == CodexConsumerProjection.monthlyWindowMinutes }
    }

    private nonisolated static func codexPreferredResetBackfillWindow(
        _ windows: [(window: RateWindow, updatedAt: Date, priority: Int)],
        now: Date) -> RateWindow?
    {
        windows
            .filter { ($0.window.resetsAt ?? .distantPast) > now }
            .max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                if lhs.priority != rhs.priority {
                    return lhs.priority < rhs.priority
                }
                let lhsReset = lhs.window.resetsAt ?? .distantPast
                let rhsReset = rhs.window.resetsAt ?? .distantPast
                if lhsReset != rhsReset {
                    return lhsReset < rhsReset
                }
                return (lhs.window.windowMinutes ?? 0) < (rhs.window.windowMinutes ?? 0)
            }
            .map(\.window)
    }

    private nonisolated static func codexBackfillingResetWindow(
        _ window: RateWindow?,
        from cached: RateWindow?) -> RateWindow?
    {
        guard let cached,
              let resetsAt = cached.resetsAt,
              resetsAt > Date()
        else {
            return window
        }
        if let window {
            return window.backfillingResetTime(from: cached)
        }
        guard let windowMinutes = cached.windowMinutes, windowMinutes > 0 else { return nil }
        return RateWindow(
            usedPercent: cached.usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt,
            resetDescription: cached.resetDescription)
    }
}
