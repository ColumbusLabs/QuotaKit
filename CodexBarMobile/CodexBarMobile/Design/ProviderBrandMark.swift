import SwiftUI
import UIKit

enum ProviderBrandAsset {
    private static let assetPrefix = "ProviderIcon-"

    private static let canonicalIconIDs: Set<String> = [
        "claude",
        "codex",
        "cursor",
        "grok",
    ]

    static func assetName(for providerIdentifier: String) -> String? {
        let normalized = ProviderColorPalette.normalized(providerIdentifier)
        guard !normalized.isEmpty else { return nil }

        if self.canonicalIconIDs.contains(normalized) {
            return "\(self.assetPrefix)\(normalized)"
        }

        return nil
    }

    static func image(for providerIdentifier: String, in bundle: Bundle = .main) -> UIImage? {
        guard let assetName = self.assetName(for: providerIdentifier) else { return nil }
        return UIImage(named: assetName, in: bundle, compatibleWith: nil)
    }
}

struct ProviderBrandMark: View {
    let providerID: String
    var size: CGFloat = 18
    var tint: Color?
    var accessibilityLabel: String?

    var body: some View {
        self.mark
            .frame(width: self.size, height: self.size)
            .accessibilityHidden(self.accessibilityLabel == nil)
            .accessibilityLabel(Text(self.accessibilityLabel ?? ""))
    }

    @ViewBuilder
    private var mark: some View {
        let color = self.tint ?? ProviderColorPalette.color(for: self.providerID)
        if let image = ProviderBrandAsset.image(for: self.providerID) {
            Image(uiImage: image)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(color)
        } else {
            Image(systemName: "circle.dotted")
                .font(.system(size: self.size, weight: .regular))
                .foregroundStyle(color)
        }
    }
}
