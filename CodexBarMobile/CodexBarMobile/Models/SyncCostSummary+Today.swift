import CodexBarSync
import Foundation

/// Namespaced mobile-only source-revision markers used to retain the local
/// contributor vector after CloudSyncReader combines per-device summaries.
/// They are display/cache metadata, never a proof for the combined cost.
enum LocalCostEvidenceRevision {
    private struct DayContributor: Codable {
        let deviceID: String
        let dayEvidence: SyncDayEvidence?
    }

    private struct DayVector: Codable {
        let dayKey: String
        let contributors: [DayContributor]
    }

    private static let inventoryPrefix = "local-contributor-inventory-v1:"
    private static let dayFreshnessPrefix = "local-day-evidence-freshness-v1:"
    private static let dayVectorPrefix = "local-day-evidence-vector-v1:"
    static let requiresVerifiedDaysKey = "local-day-evidence-required-v1"

    static func inventoryKey(deviceIDs: [String]) -> String {
        self.inventoryPrefix + self.base64URL(self.canonicalJSON(deviceIDs.sorted()))
    }

    static func dayFreshnessKey(dayKey: String) -> String {
        self.dayFreshnessPrefix + self.base64URL(Data(dayKey.utf8))
    }

    static func dayVectorKey(dayKey: String, contributors: [(String, SyncDayEvidence?)]) -> String {
        let vector = DayVector(
            dayKey: dayKey,
            contributors: contributors
                .sorted { $0.0 < $1.0 }
                .map { deviceID, evidence in
                    DayContributor(deviceID: deviceID, dayEvidence: evidence)
                })
        return Self.dayVectorPrefix + Self.base64URL(Self.canonicalJSON(vector))
    }

    static func hasMultipleContributors(sourceRevisions: [String: Date]?) -> Bool {
        guard let marker = sourceRevisions?.keys.first(where: { $0.hasPrefix(Self.inventoryPrefix) })
        else { return false }
        let encoded = marker.dropFirst(Self.inventoryPrefix.count)
        guard let data = Self.decodeBase64URL(String(encoded)),
              let deviceIDs = try? JSONDecoder().decode([String].self, from: data)
        else { return false }
        return Set(deviceIDs).count > 1
    }

    static func completeDayFreshness(dayKey: String, sourceRevisions: [String: Date]?) -> Date? {
        sourceRevisions?[self.dayFreshnessKey(dayKey: dayKey)]
    }

    static func requiresVerifiedDays(sourceRevisions: [String: Date]?) -> Bool {
        sourceRevisions?[self.requiresVerifiedDaysKey] != nil
    }

    private static func canonicalJSON(_ value: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data()
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeBase64URL(_ encoded: String) -> Data? {
        let base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: padded)
    }
}

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
    struct DailyWindowTotals {
        let costUSD: Double
        let totalTokens: Int
        let isPartial: Bool
        let hasPoints: Bool
    }

    /// Stable revision vector for mobile cache and ledger identity. New Mac
    /// producers publish each contributing source independently. Legacy
    /// summaries fall back to the aggregate timestamps.
    func mobileRevisionKey(
        providerLastUpdated: Date,
        includeDayEvidence: Bool = true) -> String
    {
        let summaryRevision: String
        if let sourceRevisions, !sourceRevisions.isEmpty {
            summaryRevision = sourceRevisions.keys.sorted().compactMap { source in
                sourceRevisions[source].map {
                    "\(source):\($0.timeIntervalSince1970)"
                }
            }.joined(separator: ",")
        } else {
            let payloadRevision = self.costUpdatedAt ?? providerLastUpdated
            let totalRevision = self.totalCostUpdatedAt ?? payloadRevision
            summaryRevision = "legacy:\(payloadRevision.timeIntervalSince1970):\(totalRevision.timeIntervalSince1970)"
        }

        guard includeDayEvidence else { return summaryRevision }
        let dayProofs = self.daily.compactMap { point -> String? in
            guard let evidence = point.dayEvidence,
                  evidence.isValid,
                  let encoded = Self.canonicalEvidenceKey(evidence)
            else { return nil }
            return "\(point.dayKey)=\(encoded)"
        }.sorted()
        guard !dayProofs.isEmpty else { return summaryRevision }
        return "\(summaryRevision)|dayEvidenceV1=\(dayProofs.joined(separator: ";"))"
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
        /// True when `costUSD` is only the priced portion of today's usage.
        /// Cost availability is independent from `tokens`: an unpriced zero
        /// stays unavailable without discarding the day's known token count.
        let isPartial: Bool
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
            lastReportedDayKey: String?,
            isPartial: Bool = false)
        {
            self.availability = availability
            self.source = source
            self.costUSD = costUSD
            self.tokens = tokens
            self.isEstimated = isEstimated
            self.updatedAt = updatedAt
            self.isStale = isStale
            self.lastReportedDayKey = lastReportedDayKey
            self.isPartial = isPartial
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
        if let todayPoint = self.daily.first(where: { $0.dayKey == todayKey }) {
            // A point-level flag is more specific than the summary fallback.
            // If an older point omitted its marker, the summary flag still
            // prevents a known subtotal from being presented as complete.
            let isPartial = (todayPoint.costIsKnown ?? self.costIsKnown) == false
            let hasUsableSubtotal = !isPartial || todayPoint.costUSD > 0
            // Per-day verification is the freshness clock for a verified
            // local contribution. Provider quota refreshes do not refresh
            // this spend value.
            let hasMultipleLocalContributors = LocalCostEvidenceRevision.hasMultipleContributors(
                sourceRevisions: self.sourceRevisions)
            let requiresVerifiedDays = LocalCostEvidenceRevision.requiresVerifiedDays(
                sourceRevisions: self.sourceRevisions)
                || self.daily.contains(where: { $0.dayEvidence?.isValid == true })
            let dayUpdatedAt: Date? = if hasMultipleLocalContributors, requiresVerifiedDays {
                LocalCostEvidenceRevision.completeDayFreshness(
                    dayKey: todayKey,
                    sourceRevisions: self.sourceRevisions)
            } else {
                todayPoint.dayEvidence.flatMap { $0.isValid ? $0.verifiedAt : nil }
                    ?? (requiresVerifiedDays ? nil : effectiveUpdatedAt)
            }
            return TodayTotals(
                availability: hasUsableSubtotal ? .reported : .unavailable,
                source: .daily,
                costUSD: hasUsableSubtotal ? todayPoint.costUSD : nil,
                tokens: todayPoint.totalTokens,
                isEstimated: todayPoint.isEstimated,
                updatedAt: dayUpdatedAt,
                isStale: requiresVerifiedDays && dayUpdatedAt == nil
                    || Self.isStale(dayUpdatedAt, at: now),
                lastReportedDayKey: lastReportedDayKey,
                isPartial: isPartial)
        }

        // `sessionCostUSD` is not a day total by itself. Without an explicit
        // current-day freshness marker it may be yesterday's last session,
        // so do not use it as today's spend.
        if self.sessionCostUSD != nil,
           let effectiveUpdatedAt,
           Calendar.current.isDate(effectiveUpdatedAt, inSameDayAs: now)
        {
            let isPartial = self.costIsKnown == false
            let sessionCost = self.sessionCostUSD
            let hasUsableSubtotal = !isPartial || (sessionCost ?? 0) > 0
            return TodayTotals(
                availability: hasUsableSubtotal ? .reported : .unavailable,
                source: .session,
                costUSD: hasUsableSubtotal ? sessionCost : nil,
                tokens: self.sessionTokens,
                isEstimated: nil,
                updatedAt: effectiveUpdatedAt,
                isStale: Self.isStale(effectiveUpdatedAt, at: now),
                lastReportedDayKey: lastReportedDayKey,
                isPartial: isPartial)
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

    /// Totals daily points over the same inclusive, producer-local calendar
    /// window requested by the Mac. Legacy summaries without `historyDays`
    /// use the 30-day default. A bounded window prevents a long retained
    /// history from being mislabeled as a smaller range when the aggregate
    /// field is absent.
    func dailyTotals(windowDays: Int? = nil, asOf now: Date = Date()) -> DailyWindowTotals {
        let points = self.dailyPoints(inWindowDays: windowDays ?? self.historyDays ?? 30, asOf: now)
        return DailyWindowTotals(
            costUSD: points.reduce(0) { $0 + $1.costUSD },
            totalTokens: points.reduce(0) { $0 + $1.totalTokens },
            isPartial: points.isEmpty
                ? self.costIsKnown == false
                : points.contains { ($0.costIsKnown ?? self.costIsKnown) == false },
            hasPoints: !points.isEmpty)
    }

    /// Selects an inclusive trailing window of producer-local calendar days.
    /// Day keys are compared lexicographically only after using the same
    /// `yyyy-MM-dd` formatter as Today resolution.
    func dailyPoints(inWindowDays windowDays: Int, asOf now: Date = Date()) -> [SyncDailyPoint] {
        let days = max(1, min(windowDays, 365))
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        let formatter = Self.iso8601DayKeyFormatter()
        let sinceKey = formatter.string(from: start)
        let untilKey = formatter.string(from: end)
        return self.daily.filter { sinceKey <= $0.dayKey && $0.dayKey <= untilKey }
    }

    private static func isStale(_ updatedAt: Date?, at now: Date) -> Bool {
        guard let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) > 60 * 60
    }

    /// Encodes all proof identity and revision fields into a deterministic,
    /// delimiter-safe cache component. This lets intermediate-device proof
    /// changes invalidate mobile view memoization even when aggregate dates
    /// and the newest source revision stay unchanged.
    private static func canonicalEvidenceKey(_ evidence: SyncDayEvidence) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(evidence) else { return nil }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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
