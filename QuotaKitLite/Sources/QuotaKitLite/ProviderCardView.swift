import LiteCore
import SwiftUI

/// One provider's menu card, laid out like the full app's usage card: `UsageMenuCardHeaderView`, a divider, then
/// one `MetricRow` per window (Sources/CodexBar/MenuCardView.swift, MenuCardMetricRow.swift). Spacing comes from
/// the full app's `UsageMenuCardLayout`.
struct ProviderCardView: View {
    static let width: CGFloat = 310

    let card: CardPresentation
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                self.header
                Divider()
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(self.card.metrics.enumerated()), id: \.offset) { _, metric in
                    MetricRowView(metric: metric, tint: self.tint)
                }
                if let placeholder = self.card.placeholder {
                    Text(placeholder)
                        .font(.subheadline)
                        .foregroundStyle(MenuHighlightStyle.secondary(false))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .frame(width: Self.width, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(self.card.providerName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer()
                if let email = self.card.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(MenuHighlightStyle.secondary(false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(self.card.subtitle)
                    .font(.footnote)
                    .foregroundStyle(
                        self.card.subtitleIsError ? MenuHighlightStyle.error(false) : MenuHighlightStyle
                            .secondary(false))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer()
                if let plan = self.card.plan {
                    Text(plan)
                        .font(.footnote)
                        .foregroundStyle(MenuHighlightStyle.secondary(false))
                        .lineLimit(1)
                        .layoutPriority(2)
                }
            }
        }
    }
}

/// The full app's `MetricRow` and `MetricRowHeader` in their default (non-compact) form.
private struct MetricRowView: View {
    let metric: MetricPresentation
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.metric.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                if let resetText = self.metric.resetText {
                    Text(resetText)
                        .font(.footnote)
                        .foregroundStyle(MenuHighlightStyle.secondary(false))
                        .lineLimit(1)
                }
            }
            UsageProgressBar(
                percent: self.metric.fillPercent,
                tint: self.tint,
                accessibilityLabel: self.metric.title,
                pacePercent: self.metric.pacePercent,
                paceOnTop: self.metric.paceOnTop)
            if let metaText = self.metric.metaText {
                Text(metaText)
                    .font(.footnote)
                    .foregroundStyle(MenuHighlightStyle.secondary(false))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension LiteProvider {
    /// `branding.color` from each provider's descriptor in the full app (068 §7.2).
    var brandColor: Color {
        switch self {
        case .claude: Color(red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        case .codex: Color(red: 73 / 255, green: 163 / 255, blue: 176 / 255)
        case .antigravity: Color(red: 96 / 255, green: 186 / 255, blue: 126 / 255)
        }
    }
}
