import AppKit
import LiteCore

/// Draws the status item in one of the §7.3 styles: each provider's template logo followed by its percent (the
/// full app's brand icon with percent mode), or the logo with two hairline bars under it. The result is one
/// image, redrawn only when what it shows changes (068 §7.3).
@MainActor
final class StatusItemRenderer {
    struct Segment: Equatable {
        enum Content: Equatable {
            /// The remaining percent, or nil before the first fetch.
            case percent(String?)
            /// Session and weekly bars, or nil before the first fetch.
            case bars(MenuBarText.Bars?)
        }

        let provider: LiteProvider
        let content: Content
    }

    private static let iconSize: CGFloat = 16
    private static let iconTextGap: CGFloat = 3
    private static let segmentGap: CGFloat = 8
    private static let height: CGFloat = 22
    /// `MenuBarLayoutRenderer.fontSize` for the normal size.
    private static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    private static let barSegmentWidth: CGFloat = 18
    private static let barIconSize: CGFloat = 13
    private static let barHeight: CGFloat = 2

    private var lastSegments: [Segment]?

    /// Updates the button only when the segments differ from the last render.
    func render(_ segments: [Segment], into button: NSStatusBarButton?) {
        guard let button, segments != self.lastSegments else { return }
        self.lastSegments = segments
        button.image = Self.image(for: segments)
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("QuotaKit Lite: " + segments.map(Self.accessibilityText).joined(separator: ", "))
    }

    private static func accessibilityText(_ segment: Segment) -> String {
        let name = segment.provider.displayName
        switch segment.content {
        case let .percent(text):
            return "\(name) \(text.map { "\($0) left" } ?? "no data")"
        case let .bars(bars):
            guard let bars else { return "\(name) no data" }
            let parts = [("session", bars.session), ("weekly", bars.weekly)].compactMap { label, value in
                value.map { "\(label) \(Int(($0 * 100).rounded()))% left" }
            }
            return "\(name) " + parts.joined(separator: ", ")
        }
    }

    private static func image(for segments: [Segment]) -> NSImage {
        // A critical bar is drawn in red, so that image can't be a template; it draws in the label colour instead.
        let isTemplate = !segments.contains { segment in
            if case let .bars(bars) = segment.content { return bars?.isCritical ?? false }
            return false
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: self.font, .foregroundColor: NSColor.black]
        let pieces = segments.map { segment -> (Segment, NSImage?, NSAttributedString?) in
            switch segment.content {
            case let .percent(text):
                (
                    segment,
                    LiteResources.templateIcon(named: segment.provider.iconName, pointSize: self.iconSize),
                    text.map { NSAttributedString(string: $0, attributes: attributes) })
            case .bars:
                (
                    segment,
                    LiteResources.templateIcon(named: segment.provider.iconName, pointSize: self.barIconSize),
                    nil)
            }
        }

        var width: CGFloat = 0
        for (index, piece) in pieces.enumerated() {
            if index > 0 { width += self.segmentGap }
            width += self.width(of: piece.0, text: piece.2)
        }

        let image = NSImage(
            size: NSSize(width: max(width, self.iconSize), height: self.height),
            flipped: false)
        { _ in
            let ink: NSColor = isTemplate ? .black : .labelColor
            var x: CGFloat = 0
            for (index, piece) in pieces.enumerated() {
                if index > 0 { x += self.segmentGap }
                switch piece.0.content {
                case .percent:
                    // Percent segments only appear in template images; red is limited to the bars style.
                    let iconRect = NSRect(
                        x: x,
                        y: (self.height - self.iconSize) / 2,
                        width: self.iconSize,
                        height: self.iconSize)
                    piece.1?.draw(in: iconRect)
                    if let text = piece.2 {
                        let size = text.size()
                        text.draw(at: NSPoint(
                            x: x + self.iconSize + self.iconTextGap,
                            y: (self.height - size.height) / 2))
                    }
                case let .bars(bars):
                    let iconRect = NSRect(
                        x: x + (self.barSegmentWidth - self.barIconSize) / 2,
                        y: self.height - self.barIconSize - 1,
                        width: self.barIconSize,
                        height: self.barIconSize)
                    self.drawIcon(piece.1, in: iconRect, ink: ink, tinted: !isTemplate)
                    let fill = bars?.isCritical == true ? NSColor.systemRed : ink
                    self.drawBar(bars?.session, x: x, y: 4.5, ink: ink, fill: fill)
                    self.drawBar(bars?.weekly, x: x, y: 1, ink: ink, fill: fill)
                }
                x += self.width(of: piece.0, text: piece.2)
            }
            return true
        }
        image.isTemplate = isTemplate
        return image
    }

    private static func width(of segment: Segment, text: NSAttributedString?) -> CGFloat {
        switch segment.content {
        case .percent:
            self.iconSize + (text.map { self.iconTextGap + ceil($0.size().width) } ?? 0)
        case .bars:
            self.barSegmentWidth
        }
    }

    /// Draws a template logo. In a non-template image it is tinted, because a template image draws its raw black.
    private static func drawIcon(_ icon: NSImage?, in rect: NSRect, ink: NSColor, tinted: Bool) {
        guard let icon else { return }
        icon.draw(in: rect)
        guard tinted else { return }
        ink.set()
        rect.fill(using: .sourceAtop)
    }

    /// One hairline bar: a faint track with what's left filled in. A lane the provider lacks draws nothing.
    private static func drawBar(_ remaining: Double?, x: CGFloat, y: CGFloat, ink: NSColor, fill: NSColor) {
        guard let remaining else { return }
        let track = NSRect(x: x + 1, y: y, width: self.barSegmentWidth - 2, height: self.barHeight)
        ink.withAlphaComponent(0.3).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()
        let filled = NSRect(
            x: track.minX,
            y: track.minY,
            width: track.width * min(max(remaining, 0), 1),
            height: track.height)
        guard filled.width > 0 else { return }
        fill.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 1, yRadius: 1).fill()
    }
}

extension LiteProvider {
    /// The logo's resource name in the app bundle.
    var iconName: String {
        "ProviderIcon-\(self.rawValue)"
    }
}
