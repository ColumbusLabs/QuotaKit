import CodexBarSync
import SwiftUI

struct ProviderUsageView: View {
    let provider: ProviderUsageSnapshot
    /// 1-based ordinal among cards sharing this same `providerID`. `nil`
    /// when this is the only card for its providerID — subtitle then stays
    /// in its pre-T5 single-card form.
    var duplicateOrdinal: Int?
    @AppStorage(MobileSettingsKeys.hidePersonalInfo) private var hidePersonalInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Provider header
            providerHeader
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            // Usage metrics — dynamic count per provider
            VStack(spacing: 10) {
                ForEach(Array(self.provider.allRateWindows.enumerated()), id: \.offset) { index, window in
                    UsageCardView(
                        label: window.label ?? self.defaultLabel(at: index),
                        window: window,
                        tintColor: self.providerColor,
                        percentageAccessibilityIdentifier: "usage-card-percent-\(self.provider.providerID)-\(index)")
                }
            }
            .padding(.horizontal, 16)

            // Error / status message
            if let message = self.provider.statusMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            // Cost teaser + tap chevron
            HStack {
                if let cost = self.provider.costSummary {
                    self.costTeaserText(cost)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer().frame(height: 20)
        }
        .modifier(ProviderCardBackgroundModifier())
    }

    // MARK: - Provider Header

    @ViewBuilder
    private var providerHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(self.provider.providerName)
                    .font(.title3)
                    .fontWeight(.bold)

                Spacer()

                if self.provider.isError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }

            HStack(spacing: 8) {
                if let line = self.subtitleLine() {
                    HStack(spacing: 4) {
                        Image(systemName: "person.circle.fill")
                            .font(.caption)
                        Text(line)
                            .font(.subheadline)
                            .accessibilityIdentifier("provider-card-subtitle-\(self.provider.providerID)")
                    }
                    .foregroundStyle(.secondary)
                }

                if let plan = self.provider.loginMethod {
                    Text(MobilePersonalInfoRedactor.redactEmails(in: plan, isEnabled: self.hidePersonalInfo) ?? plan)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }

            Text(self.provider.lastUpdated.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private var providerColor: Color {
        ProviderColorPalette.color(for: self.provider.providerID)
    }

    /// Selects the subtitle string under the provider name. Prefers the
    /// account email (honoring the redactor), falls back to a localized
    /// ordinal (`"Codex 2"`) when email is nil AND this card is one of
    /// multiple for the same `providerID`, otherwise returns nil so the
    /// single-card layout stays minimal.
    ///
    /// Exposed as `internal` (no `private`) so unit tests can pin the
    /// selection rule without going through SwiftUI's view hierarchy.
    func subtitleLine() -> String? {
        if let email = self.provider.accountEmail, !email.isEmpty {
            return MobilePersonalInfoRedactor.redactEmail(email, isEnabled: self.hidePersonalInfo)
        }
        if let ordinal = self.duplicateOrdinal {
            // Localized format: "%@ %lld" → `"Codex 2"` / `"Codex 2 号账户"`
            // depending on locale. No-email-but-single-card keeps nil.
            let template = String(localized: "provider-account-ordinal")
            return String(format: template, self.provider.providerName, ordinal)
        }
        return nil
    }

    @ViewBuilder
    private func costTeaserText(_ cost: SyncCostSummary) -> some View {
        // Route "Today" through `todayTotals()` so this card's teaser and the
        // detail page's "Today" summary stay in lockstep (Build 78 fixed the
        // detail page; this card was still reading `sessionCostUSD` directly,
        // causing Usage-tab teaser ≠ detail-page "Today" mid-day). Same
        // class-of-bug as the Subscription Utilization aggregate/detail
        // mismatch fixed in Build 77.
        let today = cost.todayTotals()
        let parts: [String] = [
            today.costUSD.map { "\(String(localized: "Today")): \(Self.formatUSD($0))" },
            cost.last30DaysCostUSD.map { "\(String(localized: "30d")): \(Self.formatUSD($0))" },
        ].compactMap { $0 }

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func defaultLabel(at index: Int) -> String {
        switch index {
        case 0: return String(localized: "Session")
        case 1: return String(localized: "Weekly")
        default: return "\(String(localized: "Limit")) \(index + 1)"
        }
    }

    private static func formatUSD(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}

private enum MobilePersonalInfoRedactor {
    private static var emailPlaceholder: String {
        String(localized: "Hidden")
    }

    private static let emailRegex: NSRegularExpression? = {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    static func redactEmail(_ email: String?, isEnabled: Bool) -> String {
        guard let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        guard isEnabled else { return email }
        return Self.emailPlaceholder
    }

    static func redactEmails(in text: String?, isEnabled: Bool) -> String? {
        guard let text else { return nil }
        guard isEnabled else { return text }
        guard let regex = Self.emailRegex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: Self.emailPlaceholder)
    }
}

/// Unified with Cost tab's card style — `.ultraThinMaterial` on all iOS versions.
///
/// Commit `408ce6f25` (2026-03-19) had drive-by replaced the original
/// `.regularMaterial + glassEffect` pair with `.thickMaterial`. On a solid
/// `systemGroupedBackground`, material thickness is visually indistinguishable
/// (verified by user inspection 2026-04-20), but `.thickMaterial` costs
/// significantly more on first-frame GPU compositing — large Gaussian blur
/// radius, heavier tint overlay, independent compositing pass per card.
///
/// Matching Cost's `.ultraThinMaterial` (`CostMetricCard.swift:38`,
/// `ContentView.swift:563,641`, `BudgetProgressView.swift:57`) cuts the
/// Usage-tab first-render cost users perceived as ~1s blank after cold start.
private struct ProviderCardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Previews

#Preview("Claude") {
    ScrollView {
        ProviderUsageView(provider: PreviewData.claudeProvider)
            .padding()
    }
}

#Preview("OpenRouter (Error)") {
    ScrollView {
        ProviderUsageView(provider: PreviewData.openRouterProvider)
            .padding()
    }
}
