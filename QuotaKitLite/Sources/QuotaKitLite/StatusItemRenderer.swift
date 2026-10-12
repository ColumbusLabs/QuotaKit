import AppKit

/// Draws the status item: each provider's template logo followed by its percent, like the full app's brand icon
/// with percent mode. The result is one template image, so it follows the menu bar's appearance, and it is only
/// redrawn when the text changes (068 §7.3).
@MainActor
final class StatusItemRenderer {
    struct Segment: Equatable {
        let iconName: String
        let text: String?
    }

    private static let iconSize: CGFloat = 16
    private static let iconTextGap: CGFloat = 3
    private static let segmentGap: CGFloat = 8
    /// `MenuBarLayoutRenderer.fontSize` for the normal size.
    private static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    private var lastSegments: [Segment]?

    /// Updates the button only when the segments differ from the last render.
    func render(_ segments: [Segment], into button: NSStatusBarButton?) {
        guard let button, segments != self.lastSegments else { return }
        self.lastSegments = segments
        button.image = Self.image(for: segments)
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(
            "QuotaKit Lite: " + segments.map { "\($0.iconName.replacingOccurrences(of: "ProviderIcon-", with: "")) " +
                ($0.text ?? "no data")
            }.joined(separator: ", "))
    }

    private static func image(for segments: [Segment]) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [.font: self.font, .foregroundColor: NSColor.black]
        let pieces = segments.map { segment -> (NSImage?, NSAttributedString?) in
            (
                LiteResources.templateIcon(named: segment.iconName, pointSize: self.iconSize),
                segment.text.map { NSAttributedString(string: $0, attributes: attributes) })
        }
        let height: CGFloat = 22
        var width: CGFloat = 0
        for (index, piece) in pieces.enumerated() {
            if index > 0 { width += self.segmentGap }
            width += self.iconSize
            if let text = piece.1 { width += self.iconTextGap + ceil(text.size().width) }
        }

        let image = NSImage(size: NSSize(width: max(width, self.iconSize), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (index, piece) in pieces.enumerated() {
                if index > 0 { x += self.segmentGap }
                piece.0?.draw(in: NSRect(
                    x: x,
                    y: (height - self.iconSize) / 2,
                    width: self.iconSize,
                    height: self.iconSize))
                x += self.iconSize
                if let text = piece.1 {
                    x += self.iconTextGap
                    let size = text.size()
                    text.draw(at: NSPoint(x: x, y: (height - size.height) / 2))
                    x += ceil(size.width)
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
