import CodexBarSync
import Foundation

/// iOS-only cost-resolution helpers for `SyncCostSummary`.
///
/// The Cost tab and each provider detail page both display a "Today" number,
/// but historically they sourced it from two different fields:
///   - Cost-tab summary cards (via `CostDashboardInsights`) preferred
///     `daily.first(where: dayKey == todayKey).costUSD` and fell back to
///     `sessionCostUSD` only when today had no daily entry.
///   - `ProviderDetailView.costSummarySection` used `sessionCostUSD` directly.
///
/// `sessionCostUSD` is the most recent session's cost on the reporting Mac; on
/// local-cost providers with multi-device sync it gets *summed* across Macs
/// during merge. `daily[today].costUSD` is the accurate sum-per-calendar-day
/// reading. Right after a fresh midnight sample both numbers agree; mid-day
/// they can diverge (session is stale relative to the accumulated daily point,
/// or vice versa when the daily point hasn't been written yet).
///
/// This extension centralizes the preference order so every view renders the
/// same number. Reported as the same class of bug as the Subscription
/// Utilization aggregate/detail mismatch fixed in Build 77.
extension SyncCostSummary {
    /// Stable revision vector for mobile cache and ledger identity. New Mac
    /// producers publish each contributing source independently. Legacy
    /// summaries fall back to the aggregate timestamps.
    func mobileRevisionKey(providerLastUpdated: Date) -> String {
        if let sourceRevisions, !sourceRevisions.isEmpty {
            return sourceRevisions.keys.sorted().compactMap { source in
                sourceRevisions[source].map {
                    "\(source):\($0.timeIntervalSince1970)"
                }
            }.joined(separator: ",")
        }
        let payloadRevision = self.costUpdatedAt ?? providerLastUpdated
        let totalRevision = self.totalCostUpdatedAt ?? payloadRevision
        return "legacy:\(payloadRevision.timeIntervalSince1970):\(totalRevision.timeIntervalSince1970)"
    }

    enum TodayAvailability: Equatable, Sendable {
        case reported
        case unavailable
    }

    enum TodaySource: Equatable, Sendable {
        case daily
        case session
        case none
    }

    /// The pair of cost + tokens for today's calendar day, resolved together.
    ///
    /// Held as a pair (not two independent accessors) because separate
    /// accessors each calling `Date()` would drift across the midnight
    /// boundary: cost could use yesterday's key while tokens used today's,
    /// yielding an inconsistent `CostMetricCard`. Codex-reviewer caught this
    /// P3 issue in the initial Build 78 patch.
    struct TodayTotals: Equatable, Sendable {
        let availability: TodayAvailability
        let source: TodaySource
        let costUSD: Double?
        let tokens: Int?
        /// `true` when today's cost row was computed via the Mac-side
        /// fallback resolver (model name not in the local pricing
        /// table). `nil` for old payloads from Mac < 0.23 and for the
        /// `sessionCostUSD` fallback path (session totals don't carry
        /// per-model estimation flags).
        let isEstimated: Bool?
        /// Effective freshness of the source that supplied the displayed
        /// totals. New summaries prefer `totalCostUpdatedAt`; legacy summaries
        /// fall back through `costUpdatedAt` to the enclosing provider's
        /// `lastUpdated` supplied to `todayTotals(now:providerLastUpdated:)`.
        let updatedAt: Date?
        /// True when the reported value is more than one hour old. This is
        /// deliberately separate from availability: an old positive value
        /// remains useful and must not be rendered as zero.
        let isStale: Bool
        /// The newest day present in the summary, useful when today's point
        /// is unavailable and the UI needs to explain what is missing.
        let lastReportedDayKey: String?

        var isAvailable: Bool {
            self.availability == .reported
        }

        init(
            availability: TodayAvailability,
            source: TodaySource,
            costUSD: Double?,
            tokens: Int?,
            isEstimated: Bool?,
            updatedAt: Date?,
            isStale: Bool,
            lastReportedDayKey: String?)
        {
            self.availability = availability
            self.source = source
            self.costUSD = costUSD
            self.tokens = tokens
            self.isEstimated = isEstimated
            self.updatedAt = updatedAt
            self.isStale = isStale
            self.lastReportedDayKey = lastReportedDayKey
        }
    }

    /// Returns the cost/tokens for today in the user's current timezone,
    /// resolved from a single `now` timestamp (both fields share the same
    /// day key). Prefers the `daily` point for today. A session fallback is
    /// accepted only when its effective freshness is also today; otherwise
    /// the result is explicitly unavailable instead of silently becoming
    /// zero.
    ///
    /// `now` is injectable so tests can pin a specific date and stay
    /// deterministic across wall-clock midnight crossings.
    func todayTotals(now: Date = Date(), providerLastUpdated: Date? = nil) -> TodayTotals {
        let todayKey = Self.iso8601DayKey(for: now)
        let effectiveUpdatedAt = self.totalCostUpdatedAt
            ?? self.costUpdatedAt
            ?? providerLastUpdated
        let lastReportedDayKey = self.daily.map(\.dayKey).max()
        let stale = Self.isStale(effectiveUpdatedAt, at: now)
        if let todayPoint = self.daily.first(where: { $0.dayKey == todayKey }) {
            return TodayTotals(
                availability: .reported,
                source: .daily,
                costUSD: todayPoint.costUSD,
                tokens: todayPoint.totalTokens,
                isEstimated: todayPoint.isEstimated,
                updatedAt: effectiveUpdatedAt,
                isStale: stale,
                lastReportedDayKey: lastReportedDayKey)
        }

        // `sessionCostUSD` is not a day total by itself. Without an explicit
        // current-day freshness marker it may be yesterday's last session,
        // so do not use it as today's spend.
        if self.sessionCostUSD != nil,
           let effectiveUpdatedAt,
           Calendar.current.isDate(effectiveUpdatedAt, inSameDayAs: now)
        {
            return TodayTotals(
                availability: .reported,
                source: .session,
                costUSD: self.sessionCostUSD,
                tokens: self.sessionTokens,
                isEstimated: nil,
                updatedAt: effectiveUpdatedAt,
                isStale: stale,
                lastReportedDayKey: lastReportedDayKey)
        }

        return TodayTotals(
            availability: .unavailable,
            source: .none,
            costUSD: nil,
            tokens: nil,
            isEstimated: nil,
            updatedAt: effectiveUpdatedAt,
            isStale: false,
            lastReportedDayKey: lastReportedDayKey)
    }

    private static func isStale(_ updatedAt: Date?, at now: Date) -> Bool {
        guard let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) > 60 * 60
    }

    /// Thread-safe ISO 8601 `yyyy-MM-dd` day key, in the user's current
    /// timezone (matches Mac-side `SyncCoordinator.daily[].dayKey`
    /// generation — both sides use `.current` timezone so a user's Mac and
    /// iPhone agree on "today" as long as they're in the same timezone).
    ///
    /// Creates a fresh `DateFormatter` per call rather than sharing a
    /// `static let` instance. Codex-reviewer flagged the shared formatter as
    /// P0: `DateFormatter` is documented NOT thread-safe on iOS and can
    /// crash under concurrent `string(from:)` calls, and `todayTotals(now:)`
    /// is reachable from both view-body rendering (main actor) and
    /// CloudSync background observers.
    ///
    /// The per-call allocation is cheap (formatter init is ~microseconds)
    /// and sync costs aren't on the per-frame hot path — callers that need
    /// to resolve many dates at once should batch through
    /// `iso8601DayKeyFormatter()` once, not via this helper.
    static func iso8601DayKey(for date: Date) -> String {
        self.iso8601DayKeyFormatter().string(from: date)
    }

    /// Returns a fresh `DateFormatter` configured for the day-key wire
    /// format. Use when you need to reuse a formatter for multiple dates
    /// within a **single call site / thread**; do not store in shared state.
    static func iso8601DayKeyFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
