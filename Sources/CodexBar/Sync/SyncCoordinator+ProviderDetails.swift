import CodexBarCore
import CodexBarSync
import Foundation

extension SyncCoordinator {
    static func mapProviderDetails(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> [SyncProviderDetailSection]?
    {
        // Provider-specific by design: Sync Claude promotional dollars; reset inventory stays live-only.
        if provider == .claude {
            guard let snapshot else { return nil }
            let details = snapshot.details
            var sections: [SyncProviderDetailSection] = []
            if let row = details.lazy.filter({ $0.title == ClaudeCloudCreditsSnapshot.detailTitle })
                .flatMap(\.rows).first(where: { $0.id == ClaudeCloudCreditsSnapshot.detailRowID }),
                let status = ClaudeCloudCreditsSnapshot.detailStatus(in: details, now: Date())
            {
                let value: String = switch status {
                case .available: row.value
                case .expired: "Expired"
                case .unavailable: "Unavailable"
                }
                sections.append(SyncProviderDetailSection(
                    title: ClaudeCloudCreditsSnapshot.detailTitle,
                    rows: [.init(
                        label: ClaudeCloudCreditsSnapshot.detailTitle,
                        value: value,
                        secondaryValue: row.secondaryValue)]))
            }
            // Use the existing detail wire/storage contract. Calendar dates stay UTC civil dates;
            // timestamp values retain their instant. Successful missing metadata clears old rows.
            let billingDate = snapshot.subscriptionExpiresAt ?? snapshot.subscriptionRenewsAt
            let isExpiration = snapshot.subscriptionExpiresAt != nil
            if let billingDate {
                let dateOnly = isExpiration
                    ? snapshot.subscriptionExpiresAtIsDateOnly : snapshot.subscriptionRenewsAtIsDateOnly
                let formatter = ISO8601DateFormatter()
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.formatOptions = dateOnly ? [.withFullDate] : [.withInternetDateTime, .withFractionalSeconds]
                sections.append(SyncProviderDetailSection(
                    title: "Subscription",
                    rows: [.init(
                        label: isExpiration ? "Plan expires" : "Renews",
                        value: formatter.string(from: billingDate))]))
            }
            return sections
        }
        // Provider-specific by design: Muse syncs the selected team label without its team list or secrets.
        if provider == .muse {
            // The selected browser team's source is useful on iPhone; the full team list and
            // other plugin rows stay local to the Mac.
            guard snapshot?.dataConfidence == .estimated,
                  let section = snapshot?.details.first(where: { $0.title == "Browser team quota (dev.meta.ai)" }),
                  let team = section.rows.first(where: { $0.label == "Team" }),
                  !team.value.isEmpty
            else { return nil }
            return [SyncProviderDetailSection(
                title: "Browser team quota (dev.meta.ai)",
                rows: [.init(label: "Team", value: team.value)])]
        }
        // Kimi's monthly shares are display-only parts of an existing quota window. Export only
        // the two generated numeric rows, never arbitrary provider detail or account metadata.
        if provider == .kimi {
            guard let snapshot else { return nil }
            let labels = ["kimi-monthly-code": "Kimi Code", "kimi-monthly-other": "Other features"]
            var seen: Set<String> = []
            let rows = snapshot.details
                .filter { $0.title == "Total usage" }
                .flatMap(\.rows)
                .compactMap { row -> SyncProviderDetailSection.Row? in
                    guard let id = row.id, let label = labels[id], row.label == label,
                          let progress = row.progress,
                          progress.used.isFinite, progress.used >= 0,
                          progress.total == 1, seen.insert(id).inserted else { return nil }
                    return .init(label: label, value: "\(UsageFormatter.percentString(progress.used * 100)) used")
                }
            return rows.isEmpty ? [] : [SyncProviderDetailSection(title: "Total usage", rows: rows)]
        }
        // WorkBuddy's generic plugin details can include account or credential metadata. Sync only the finite
        // numeric credit balance rows the iPhone needs, and clear stale details after a successful empty result.
        if provider == .workbuddy {
            guard let snapshot else { return nil }
            let rows = snapshot.details
                .filter { $0.title == "Credits" }
                .flatMap(\.rows)
                .filter { ["Left", "Total", "Reserved"].contains($0.label) && Self.isWorkBuddyCreditNumber($0.value) }
            var seen: Set<String> = []
            let safeRows = rows.compactMap { row -> SyncProviderDetailSection.Row? in
                guard seen.insert(row.label).inserted else { return nil }
                return .init(label: row.label, value: row.value)
            }
            return safeRows.isEmpty ? [] : [SyncProviderDetailSection(title: "Credits", rows: safeRows)]
        }
        if let billingDetails = SyncProviderBillingDetails.map(provider: provider, snapshot: snapshot) {
            return billingDetails
        }
        // These providers expose useful rows that have no dedicated iPhone payload. In particular,
        // DevPass and Poe can have details without a rate window or cost summary.
        let supported: Set<UsageProvider> = [
            .atlascloud, .vercel, .llmman, .devpass, .raycast, .typesafe, .xkiro, .poe, .sakana, .copilot, .lithosai,
            .xapi, .futureagi, .munito,
        ]
        guard supported.contains(provider),
              let details = snapshot?.details,
              !details.isEmpty
        else { return nil }
        return details.map { section in
            SyncProviderDetailSection(
                title: section.title,
                rows: section.rows.map { row in
                    SyncProviderDetailSection.Row(
                        label: row.label,
                        value: row.value,
                        secondaryValue: row.secondaryValue)
                })
        }
    }

    private static func isWorkBuddyCreditNumber(_ raw: String) -> Bool {
        // The plugin formats values as en-US digits with optional comma grouping and a decimal point.
        let pattern = #"^-?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d+)?$"#
        guard raw.range(of: pattern, options: .regularExpression) != nil else { return false }
        return Double(raw.replacingOccurrences(of: ",", with: "")).map { $0.isFinite && $0 >= 0 } ?? false
    }
}
