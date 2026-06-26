import CodexBarSync
import SwiftUI

struct ProviderUsageView: View {
    let provider: ProviderUsageSnapshot
    /// 1-based ordinal among cards sharing this same `providerID`. `nil`
    /// when this is the only card for its providerID — subtitle then stays
    /// in its pre-T5 single-card form.
    ///
    /// **Note (Phase G):** since the Usage list now groups by providerID
    /// (one row per `ProviderAccountGroup`), this is always passed `nil`
    /// from the list. The field is kept for the few legacy call sites
    /// (RawProviderDetailView previews, tests) that still drive a single
    /// snapshot through the card.
    var duplicateOrdinal: Int?
    /// **Phase G:** when the row represents a multi-account group, this
    /// is the count (≥ 2). The card renders a small "· N" badge after
    /// the provider name so the user knows "tap → see N tabs". `nil`
    /// for single-account groups (suppress badge).
    var accountCount: Int?
    /// Optional linkage candidate when this card is part of a
    /// cross-version-detected pair (Research/019 §7). When non-nil and
    /// `onConfirmMerge` is provided, the card renders an inline prompt
    /// for the user to confirm or dismiss the merge.
    var linkageCandidate: MultiAccountLinkageCandidate?
    /// Set when this card represents an already-merged composite that
    /// the user can revoke. Driven from `SyncedUsageData.providerLinkages`
    /// — a context menu "Unmerge accounts" item writes the inverse
    /// LinkageRecord. nil → no unmerge available.
    var activeLinkage: ProviderAccountLinkage?
    var showsSyntheticDataIndicator = true
    var onConfirmMerge: ((MultiAccountLinkageCandidate) -> Void)?
    var onDismissMergeCandidate: ((MultiAccountLinkageCandidate) -> Void)?
    var onRevokeLinkage: ((ProviderAccountLinkage) -> Void)?
    @AppStorage(MobileSettingsKeys.hidePersonalInfo) private var hidePersonalInfo = false
    @Environment(\.quotaKitTheme) private var theme

    /// True when this is a synthetic mock provider injected by Mac's
    /// `MockProviderInjector` (per `MockProviderDetector`). Drives the
    /// purple accent ring + MOCK badge in the header.
    private var isMockProvider: Bool {
        MockProviderDetector.isMock(self.provider)
    }

    var body: some View {
        QKSurfaceCard(
            elevation: .surface,
            accentColor: self.usesSyntheticDataTreatment ? .purple : self.providerColor,
            cornerRadius: 16)
        {
            VStack(alignment: .leading, spacing: 0) {
                self.providerHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                self.usageMetricsSection
                    .padding(.horizontal, 16)

                if let message = self.provider.statusMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(self.theme.textMuted)
                            .lineLimit(3)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                HStack {
                    if let cost = self.provider.costSummary {
                        self.costTeaserText(cost)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(self.theme.textMuted)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                if let candidate = self.linkageCandidate,
                   let onConfirm = self.onConfirmMerge
                {
                    self.linkagePromptSection(
                        candidate: candidate,
                        onConfirm: onConfirm,
                        onDismiss: self.onDismissMergeCandidate ?? { _ in })
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                Spacer().frame(height: 20)
            }
        }
        .contextMenu {
            if let active = self.activeLinkage, let onRevoke = self.onRevokeLinkage {
                Button(role: .destructive) {
                    onRevoke(active)
                } label: {
                    Label(String(localized: "Unmerge Accounts"), systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    // MARK: - Provider Header

    private var providerHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                ProviderBrandMark(
                    providerID: self.provider.providerID,
                    size: 18,
                    tint: self.providerColor)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(self.provider.providerName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(self.theme.textPrimary)

                    if let count = self.accountCount, count > 1 {
                        // Multi-account group indicator. Mirrors Mac's
                        // implicit "N tabs at top of provider menu" hint.
                        Text("· \(count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text(String(
                                format: String(localized: "provider-account-count-label"),
                                count)))
                            .accessibilityIdentifier("provider-account-count")
                    }
                }

                if self.usesSyntheticDataTreatment {
                    MockBadgeView()
                }

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
                        .background(self.theme.surfaceElevated, in: Capsule())
                        .foregroundStyle(self.theme.textMuted)
                }
            }

            Text(self.provider.lastUpdated.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var usageMetricsSection: some View {
        VStack(spacing: 10) {
            ForEach(Array(self.provider.allRateWindows.enumerated()), id: \.offset) { index, window in
                let warning = self.provider.quotaWarning(forWindowIndex: index)
                UsageCardView(
                    label: window.label ?? self.defaultLabel(at: index),
                    window: window,
                    tintColor: self.providerColor,
                    percentageAccessibilityIdentifier:
                    "usage-card-percent-\(self.provider.providerID)-\(index)",
                    quotaWarningThresholds: warning.thresholds,
                    quotaWarningsEnabled: warning.enabled)
            }
        }
    }

    // MARK: - Helpers

    private var providerColor: Color {
        ProviderColorPalette.color(for: self.provider.providerID)
    }

    private var usesSyntheticDataTreatment: Bool {
        self.showsSyntheticDataIndicator && self.isMockProvider
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

    // MARK: - Linkage prompt (Research/019 §7 + §9)

    private func linkagePromptSection(
        candidate: MultiAccountLinkageCandidate,
        onConfirm: @escaping (MultiAccountLinkageCandidate) -> Void,
        onDismiss: @escaping (MultiAccountLinkageCandidate) -> Void) -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    // Primary line — Research/019 §9 framing: "another Mac
                    // looks like the same account but is too old/inconsistent
                    // to auto-merge".
                    Text(self.linkagePromptHeadline(candidate: candidate))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(self.linkagePromptDetail(candidate: candidate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                Button {
                    onConfirm(candidate)
                } label: {
                    Label(
                        String(localized: "Yes, same account"),
                        systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(self.providerColor)

                Button {
                    onDismiss(candidate)
                } label: {
                    Text(String(localized: "Keep separate"))
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5))
        .accessibilityIdentifier("linkage-prompt-\(candidate.hashKey)")
    }

    private func linkagePromptHeadline(candidate: MultiAccountLinkageCandidate) -> String {
        // "Looks like the same Codex account on another Mac."
        let template = String(localized: "linkage-prompt-headline")
        return String(format: template, candidate.named.providerName)
    }

    private func linkagePromptDetail(candidate: MultiAccountLinkageCandidate) -> String {
        // "The other Mac (CodexBar 0.23.6) reports this provider without an
        // account email, so iOS can't auto-link them. Confirm if it's the
        // same login."
        if let version = candidate.legacyMacVersion {
            let template = String(localized: "linkage-prompt-detail-with-version")
            return String(format: template, version)
        }
        return String(localized: "linkage-prompt-detail")
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
        ].compactMap(\.self)

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption.monospacedDigit())
                .foregroundStyle(self.theme.textMuted)
        }
    }

    private func defaultLabel(at index: Int) -> String {
        switch index {
        case 0: String(localized: "Session")
        case 1: String(localized: "Weekly")
        default: "\(String(localized: "Limit")) \(index + 1)"
        }
    }

    private static func formatUSD(_ value: Double) -> String {
        CostFormatting.usd(value)
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
