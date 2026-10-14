import Foundation

extension UsageMenuCardView.Model.Metric {
    struct LinePresentation: Equatable {
        let titleText: String
        var resetText: String?
        let metaText: String?
    }

    func linePresentation(title: String) -> LinePresentation {
        // Keep the title aligned with the configured used/remaining label semantics.
        let metaParts = [
            self.detailLeftText,
            self.detailRightText,
            self.sessionEquivalentDetail?.leftText,
            self.sessionEquivalentDetail?.rightText,
        ].compactMap { text -> String? in
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            return text
        }
        return LinePresentation(
            titleText: "\(title) \(self.percentLabel)",
            resetText: self.resetText,
            metaText: metaParts.isEmpty ? nil : metaParts.joined(separator: " · "))
    }
}
