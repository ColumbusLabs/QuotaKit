import CodexBarSync
import Foundation
import SwiftUI

/// Account-scoped banked Codex reset inventory. The backend count is
/// authoritative; detail rows are best-effort because the API can report more
/// available credits than it includes in the accompanying array.
struct CodexResetCreditsCard: View {
    let credits: SyncCodexResetCredits
    let tintColor: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            self.content(at: context.date)
        }
    }

    private func content(at now: Date) -> some View {
        let availableCredits = Self.displayedCredits(self.credits, at: now)
        let availableCount = self.credits.authoritativeAvailableCount

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(
                    localized: "codex_reset_credits_title",
                    defaultValue: "Limit reset credits"))
                    .font(.headline)

                Spacer()

                Text(String(
                    format: String(
                        localized: "codex_reset_credits_available_format",
                        defaultValue: "%lld available"),
                    Int64(availableCount)))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(self.tintColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(self.tintColor.opacity(0.14), in: Capsule())
                    .accessibilityIdentifier("codex-reset-credits-count")
            }

            ForEach(Array(availableCredits.enumerated()), id: \.element.id) { index, credit in
                if index > 0 {
                    Divider()
                }
                self.creditRow(credit, index: index)
            }

            if availableCredits.count < availableCount {
                Label {
                    Text(String(
                        format: String(
                            localized: "codex_reset_credits_partial_details_format",
                            defaultValue: "Expiration details are available for %1$lld of %2$lld resets."),
                        Int64(availableCredits.count),
                        Int64(availableCount)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("codex-reset-credits-partial-details")
            }
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codex-reset-credits-card")
    }

    nonisolated static func displayedCredits(
        _ credits: SyncCodexResetCredits,
        at date: Date) -> [SyncCodexResetCredit]
    {
        Array(credits.availableCredits(at: date).prefix(credits.authoritativeAvailableCount))
    }

    private func creditRow(_ credit: SyncCodexResetCredit, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(self.tintColor)

            Text(String(
                format: String(
                    localized: "codex_reset_credit_number_format",
                    defaultValue: "Reset %lld"),
                Int64(index + 1)))
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 8)

            Text(self.expirationText(for: credit))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("codex-reset-credit-\(credit.id)")
    }

    private func expirationText(for credit: SyncCodexResetCredit) -> String {
        guard let expiresAt = credit.expiresAt else {
            return String(
                localized: "codex_reset_credit_no_expiry",
                defaultValue: "No expiry")
        }
        return String(
            format: String(
                localized: "codex_reset_credit_expires_format",
                defaultValue: "Expires %@"),
            Self.formattedExpiration(expiresAt))
    }

    nonisolated static func formattedExpiration(
        _ date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current) -> String
    {
        var style = Date.FormatStyle.dateTime
            .year()
            .month(.abbreviated)
            .day()
            .hour()
            .minute()
            .second()
            .timeZone(.specificName(.short))
            .locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

#Preview("Banked resets") {
    CodexResetCreditsCard(
        credits: SyncCodexResetCredits(
            credits: [
                SyncCodexResetCredit(
                    id: "reset-1",
                    resetType: "codex_rate_limits",
                    status: "available",
                    grantedAt: .now.addingTimeInterval(-3600),
                    expiresAt: .now.addingTimeInterval(86400)),
                SyncCodexResetCredit(
                    id: "reset-2",
                    resetType: "codex_rate_limits",
                    status: "available",
                    grantedAt: .now.addingTimeInterval(-3600),
                    expiresAt: nil),
            ],
            availableCount: 3,
            updatedAt: .now),
        tintColor: .blue)
        .padding()
}
