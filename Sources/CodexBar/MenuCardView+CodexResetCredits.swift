import CodexBarCore
import SwiftUI

struct CodexResetCreditPresentationItem: Equatable {
    let exactTimeText: String?
    let expiryText: String
    let relativeExpiryText: String?
}

struct CodexResetCreditsPresentation: Equatable {
    let text: String
    let items: [CodexResetCreditPresentationItem]
    let availableCount: Int

    var nearestKnownExpiryText: String? {
        guard let item = self.items.first else { return nil }
        guard let exactTimeText = item.exactTimeText else { return item.expiryText }
        return String(format: L("Next expires %@"), exactTimeText)
    }

    var partialDetailText: String? {
        guard self.items.count < self.availableCount else { return nil }
        return String(format: L("Expiry times: %d of %d"), self.items.count, self.availableCount)
    }

    var helpText: String {
        var lines = self.items.enumerated().map { index, item in
            "\(index + 1). \(item.expiryText)"
        }
        if let partialDetailText {
            lines.append(partialDetailText)
        }
        return lines.joined(separator: "\n")
    }

    var accessibilityLabel: String {
        [L("Limit Reset Credits"), self.text, self.helpText]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func make(
        snapshot: CodexRateLimitResetCreditsSnapshot,
        resetStyle: ResetTimeDisplayStyle,
        now: Date) -> CodexResetCreditsPresentation?
    {
        let availableCount = max(0, snapshot.availableCount)
        guard availableCount > 0 else { return nil }
        let inventory = snapshot.availableInventory(at: now)
        let items = inventory.credits.prefix(availableCount).map { credit in
            Self.presentationItem(for: credit, resetStyle: resetStyle, now: now)
        }
        return CodexResetCreditsPresentation(
            text: Self.availableText(count: availableCount),
            items: items,
            availableCount: availableCount)
    }

    private static func availableText(count: Int) -> String {
        count == 1 ? L("1 available") : String(format: L("%d available"), count)
    }

    private static func presentationItem(
        for credit: CodexRateLimitResetCredit,
        resetStyle: ResetTimeDisplayStyle,
        now: Date) -> CodexResetCreditPresentationItem
    {
        guard let expiresAt = credit.expiresAt else {
            return CodexResetCreditPresentationItem(
                exactTimeText: nil,
                expiryText: L("No expiry"),
                relativeExpiryText: nil)
        }
        let exactTimeText = Self.exactExpiryTimeText(expiresAt)
        let relativeExpiryText = resetStyle == .countdown
            ? Self.relativeExpiryTimeText(expiresAt, now: now)
            : nil
        return CodexResetCreditPresentationItem(
            exactTimeText: exactTimeText,
            expiryText: String(format: L("Expires %@"), exactTimeText),
            relativeExpiryText: relativeExpiryText)
    }

    static func exactExpiryTimeText(_ expiresAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = codexBarLocalizedLocale()
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .long
        return formatter.string(from: expiresAt)
    }

    private static func relativeExpiryTimeText(_ expiresAt: Date, now: Date) -> String {
        let countdown = UsageFormatter.resetCountdownDescription(from: expiresAt, now: now)
        return countdown == "now" ? L("now") : countdown
    }
}

struct CodexResetCreditsContent: View {
    let presentation: CodexResetCreditsPresentation
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Limit Reset Credits"))
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.presentation.text)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if let nearestKnownExpiryText = self.presentation.nearestKnownExpiryText {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(nearestKnownExpiryText)
                            .font(.caption)
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.trailing)
                    }
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .accessibilityHidden(true)
                }
            }
            if let partialDetailText = self.presentation.partialDetailText {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(partialDetailText)
                        .font(.caption)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(self.presentation.helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.presentation.accessibilityLabel)
    }
}

extension UsageMenuCardView.Model {
    static func codexResetCredits(input: Input) -> CodexResetCreditsPresentation? {
        guard input.provider == .codex,
              let resetCredits = input.snapshot?.codexResetCredits
        else {
            return nil
        }
        return CodexResetCreditsPresentation.make(
            snapshot: resetCredits,
            resetStyle: input.resetTimeDisplayStyle,
            now: input.now)
    }
}
