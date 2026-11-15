import AppKit
import Foundation

extension MenuBarLayoutRenderer {
    /// High contrast keeps the full mark and both rows in the attributed-title path, so AppKit
    /// cannot dim just the mark on an inactive display. The handler preserves the destination scale.
    static func spanningIconTitle(
        _ icon: NSImage,
        title: NSAttributedString,
        font: NSFont,
        options: MenuBarLayoutRenderOptions) -> NSAttributedString
    {
        let baseline = (title.attribute(.baselineOffset, at: 0, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
        let unshifted = NSMutableAttributedString(attributedString: title)
        // Meter runs put their shift in attachment bounds instead of baselineOffset. Normalize
        // those as well before moving the complete title, otherwise meters move twice.
        title.enumerateAttributes(in: NSRange(location: 0, length: title.length)) { attributes, range, _ in
            guard attributes[.baselineOffset] == nil,
                  let source = attributes[.attachment] as? NSTextAttachment else { return }
            let attachment = NSTextAttachment()
            attachment.image = source.image
            attachment.bounds = source.bounds.offsetBy(dx: 0, dy: -baseline)
            unshifted.addAttribute(.attachment, value: attachment, range: range)
        }
        unshifted.removeAttribute(.baselineOffset, range: NSRange(location: 0, length: title.length))
        let immutableTitle = NSAttributedString(attributedString: unshifted)
        let bounds = immutableTitle.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let size = NSSize(width: max(1, ceil(icon.size.width + bounds.width)), height: 22)
        let titleRect = NSRect(
            x: icon.size.width - bounds.minX,
            y: floor((size.height - bounds.height) / 2) - bounds.minY + baseline + 1,
            width: bounds.width,
            height: bounds.height)
        let mark = Self.offsetLeadingIcon(
            Self.attachmentImage(icon, tint: .labelColor), adjustment: options.verticalAdjustment)
        let iconRect = NSRect(
            x: 0,
            y: (size.height - mark.size.height) / 2,
            width: mark.size.width,
            height: mark.size.height)
        let appearance = NSAppearance(named: NSAppearance.Name(rawValue: options.appearanceName))
        // No renderer, options, mutable attributed strings, or actor-isolated state escapes here.
        let image = NSImage(size: size, flipped: false) { _ in
            let draw = {
                mark.draw(in: iconRect)
                immutableTitle.draw(with: titleRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
            if let appearance {
                appearance.performAsCurrentDrawingAppearance(draw)
            } else {
                draw()
            }
            return true
        }
        image.isTemplate = false
        let attachment = NSTextAttachment()
        attachment.image = image
        // AppKit rounds the font descent down to a whole point when measuring the title line.
        // Match that baseline so the attachment stays exactly 22pt and lands on whole pixels.
        attachment.bounds = NSRect(x: 0, y: floor(font.descender), width: size.width, height: size.height)
        let result = NSMutableAttributedString(attachment: attachment)
        result.addAttribute(.font, value: font, range: NSRange(location: 0, length: result.length))
        return result
    }

    static func offsetLeadingIcon(_ image: NSImage, adjustment: Int) -> NSImage {
        // Bake the offset into the surfaced image so the status button and preferences preview share it.
        // Cap the canvas at the 22 pt menu bar content height to avoid proportional downscaling.
        let maxShift = max(0, floor((22 - image.size.height) / 2))
        let shift = min(CGFloat(abs(adjustment)), maxShift)
        guard adjustment != 0, shift > 0 else { return image }

        let offsetImage = NSImage(
            size: NSSize(width: image.size.width, height: image.size.height + 2 * shift),
            flipped: false)
        { _ in
            image.draw(
                in: NSRect(
                    x: 0,
                    y: adjustment > 0 ? 2 * shift : 0,
                    width: image.size.width,
                    height: image.size.height))
            return true
        }
        offsetImage.isTemplate = image.isTemplate
        return offsetImage
    }

    static func attachmentImage(_ image: NSImage, tint: NSColor, isMonochrome: Bool = true) -> NSImage {
        guard image.isTemplate else { return image }

        // NSTextAttachment draws an NSImage directly instead of through an image cell, so AppKit does not
        // apply template tinting here. Keep a template image for monochrome status-item semantics while drawing its
        // mask with the dynamic foreground color. Provider-colored marks retain their tint by remaining non-template.
        let tintedImage = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            tint.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        tintedImage.isTemplate = isMonochrome
        return tintedImage
    }
}
