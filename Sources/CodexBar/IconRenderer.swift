import AppKit

enum IconRenderer {
    private static let creditsCap: Double = 1000
    private static let baseSize = NSSize(width: 18, height: 18)
    // Render to an 18×18 pt template (36×36 px at 2×) to match the system menu bar size.
    private static let outputSize = NSSize(width: 18, height: 18)
    private static let outputScale: CGFloat = 2

    // swiftlint:disable function_body_length
    static func makeIcon(
        primaryRemaining: Double?,
        weeklyRemaining: Double?,
        creditsRemaining: Double?,
        stale: Bool,
        style: IconStyle,
        blink: CGFloat = 0,
        wiggle: CGFloat = 0,
        tilt: CGFloat = 0,
        statusIndicator: ProviderStatusIndicator = .none) -> NSImage
    {
        let image = self.renderImage {
            // Keep monochrome template icons; Claude uses subtle shape cues only.
            let baseFill = NSColor.labelColor
            let trackColor = NSColor.labelColor.withAlphaComponent(stale ? 0.28 : 0.5)
            let fillColor = baseFill.withAlphaComponent(stale ? 0.55 : 1.0)

            func drawBar(
                y: CGFloat,
                remaining: Double?,
                height: CGFloat,
                alpha: CGFloat = 1.0,
                addNotches: Bool = false,
                addFace: Bool = false,
                blink: CGFloat = 0)
            {
                // Slightly wider bars to better fill the menu bar slot.
                let width: CGFloat = 14
                let x: CGFloat = Self.snap((self.baseSize.width - width) / 2)
                let radius = height / 2
                let trackRect = Self.snapRect(x: x, y: y, width: width, height: height)
                let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)
                trackColor.setStroke()
                trackPath.lineWidth = 1.2
                trackPath.stroke()

                // When remaining is unknown, do not render a full bar; draw only the track (and decorations) unless a
                // value exists.
                guard let rawRemaining = remaining ?? (addNotches ? 0 : nil) else { return }
                // Clamp fill because backend might occasionally send >100 or <0.
                let clamped = max(0, min(rawRemaining / 100, 1))
                let fillRect = Self.snapRect(x: x, y: y, width: width * clamped, height: height)
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
                fillColor.withAlphaComponent(alpha).setFill()
                fillPath.fill()

                // Codex face: eye cutouts plus faint eyelids to give the prompt some personality.
                if addFace {
                    let ctx = NSGraphicsContext.current?.cgContext
                    let eyeSize: CGFloat = 2
                    let eyeY = Self.snap(y + height * 0.55)
                    let eyeOffset: CGFloat = 3
                    let center = x + width / 2

                    ctx?.saveGState()
                    if abs(tilt) > 0.0001 {
                        // Tilt the face cluster slightly around its center and nudge upward a bit.
                        let faceCenter = CGPoint(x: center, y: eyeY)
                        ctx?.translateBy(x: faceCenter.x, y: faceCenter.y)
                        ctx?.rotate(by: tilt)
                        ctx?.translateBy(x: -faceCenter.x, y: -faceCenter.y - abs(tilt) * 1.2)
                    }

                    ctx?.saveGState()
                    ctx?.setBlendMode(.clear)
                    ctx?.addEllipse(in: Self.snapRect(
                        x: center - eyeOffset - eyeSize / 2,
                        y: eyeY - eyeSize / 2,
                        width: eyeSize,
                        height: eyeSize))
                    ctx?.addEllipse(in: Self.snapRect(
                        x: center + eyeOffset - eyeSize / 2,
                        y: eyeY - eyeSize / 2,
                        width: eyeSize,
                        height: eyeSize))
                    ctx?.fillPath()
                    ctx?.restoreGState()

                    // Eyelids sit slightly above the eyes; barely-there stroke to keep the icon template-friendly.
                    let lidWidth: CGFloat = 3
                    let lidHeight: CGFloat = 1
                    let lidYOffset: CGFloat = 0
                    let lidThickness: CGFloat = 1
                    let lidColor = fillColor.withAlphaComponent(alpha * 0.9)

                    func drawLid(at cx: CGFloat) {
                        let lidRect = Self.snapRect(
                            x: cx - lidWidth / 2,
                            y: eyeY + lidYOffset,
                            width: lidWidth,
                            height: lidHeight)
                        let lidPath = NSBezierPath(ovalIn: lidRect)
                        lidPath.lineWidth = lidThickness
                        lidColor.setStroke()
                        lidPath.stroke()
                    }

                    drawLid(at: center - eyeOffset)
                    drawLid(at: center + eyeOffset)

                    // Blink: refill eyes from the top down using the bar fill color.
                    if blink > 0.001 {
                        let clamped = max(0, min(blink, 1))
                        let blinkHeight = eyeSize * clamped
                        fillColor.withAlphaComponent(alpha).setFill()
                        let blinkRectLeft = Self.snapRect(
                            x: center - eyeOffset - eyeSize / 2,
                            y: eyeY + eyeSize / 2 - blinkHeight,
                            width: eyeSize,
                            height: blinkHeight)
                        let blinkRectRight = Self.snapRect(
                            x: center + eyeOffset - eyeSize / 2,
                            y: eyeY + eyeSize / 2 - blinkHeight,
                            width: eyeSize,
                            height: blinkHeight)
                        NSBezierPath(ovalIn: blinkRectLeft).fill()
                        NSBezierPath(ovalIn: blinkRectRight).fill()
                    }

                    // Hat: a tiny cap hovering above the eyes to give the face more character.
                    let hatWidth: CGFloat = 9
                    let hatHeight: CGFloat = 2
                    let hatRect = Self.snapRect(
                        x: center - hatWidth / 2,
                        y: y + height - hatHeight,
                        width: hatWidth,
                        height: hatHeight)
                    let hatPath = NSBezierPath(roundedRect: hatRect, xRadius: hatHeight / 2, yRadius: hatHeight / 2)
                    fillColor.withAlphaComponent(alpha).setFill()
                    hatPath.fill()

                    ctx?.restoreGState()
                }

                // Claude twist: tiny eye cutouts + side “ears” and small legs to feel more characterful.
                if addNotches {
                    let ctx = NSGraphicsContext.current?.cgContext
                    let wiggleOffset = wiggle * 0.6
                    ctx?.saveGState()
                    ctx?.setBlendMode(.clear)
                    let eyeSize: CGFloat = 2
                    let eyeY = Self.snap(y + height * 0.50 + wiggleOffset * 0.3)
                    let eyeOffset: CGFloat = 3
                    let center = x + width / 2
                    ctx?.addEllipse(in: Self.snapRect(
                        x: center - eyeOffset - eyeSize / 2,
                        y: eyeY - eyeSize / 2,
                        width: eyeSize,
                        height: eyeSize))
                    ctx?.addEllipse(in: Self.snapRect(
                        x: center + eyeOffset - eyeSize / 2,
                        y: eyeY - eyeSize / 2,
                        width: eyeSize,
                        height: eyeSize))
                    ctx?.fillPath()

                    if blink > 0.001 {
                        let clamped = max(0, min(blink, 1))
                        let blinkHeight = eyeSize * clamped
                        fillColor.withAlphaComponent(alpha).setFill()
                        let blinkRectLeft = Self.snapRect(
                            x: center - eyeOffset - eyeSize / 2,
                            y: eyeY + eyeSize / 2 - blinkHeight,
                            width: eyeSize,
                            height: blinkHeight)
                        let blinkRectRight = Self.snapRect(
                            x: center + eyeOffset - eyeSize / 2,
                            y: eyeY + eyeSize / 2 - blinkHeight,
                            width: eyeSize,
                            height: blinkHeight)
                        NSBezierPath(ovalIn: blinkRectLeft).fill()
                        NSBezierPath(ovalIn: blinkRectRight).fill()
                    }

                    // Ears: outward bumps on both ends (clear to carve) then refill to accent edges.
                    let earWidth: CGFloat = 3
                    let earHeight: CGFloat = 6
                    ctx?.addRect(Self.snapRect(
                        x: x - 0.6,
                        y: y + (height - earHeight) / 2,
                        width: earWidth,
                        height: earHeight))
                    ctx?.addRect(Self.snapRect(
                        x: x + width - earWidth + 0.6,
                        y: y + (height - earHeight) / 2,
                        width: earWidth,
                        height: earHeight))
                    ctx?.fillPath()
                    ctx?.restoreGState()

                    // Refill outward “ears” so they protrude slightly beyond the bar using the fill color.
                    fillColor.withAlphaComponent(alpha).setFill()
                    let earWiggle = wiggleOffset
                    NSBezierPath(
                        roundedRect: Self.snapRect(
                            x: x - 0.8,
                            y: y + (height - earHeight) / 2 + earWiggle,
                            width: earWidth * 0.8,
                            height: earHeight),
                        xRadius: 0.9,
                        yRadius: 0.9).fill()
                    NSBezierPath(
                        roundedRect: Self.snapRect(
                            x: x + width - earWidth * 0.8 + 0.8,
                            y: y + (height - earHeight) / 2 - earWiggle,
                            width: earWidth * 0.8,
                            height: earHeight),
                        xRadius: 0.9,
                        yRadius: 0.9).fill()

                    // Tiny legs under the bar.
                    let legWidth: CGFloat = 2
                    let legHeight: CGFloat = 2
                    let legY = y - 1
                    let legOffsets: [CGFloat] = [-4, -1, 1, 4]
                    for (idx, offset) in legOffsets.enumerated() {
                        let lx = center + offset - legWidth / 2
                        let jiggle = (idx.isMultiple(of: 2) ? -wiggleOffset : wiggleOffset) * 0.6
                        NSBezierPath(rect: Self.snapRect(x: lx, y: legY + jiggle, width: legWidth, height: legHeight))
                            .fill()
                    }
                }
            }

            let topValue = primaryRemaining
            let bottomValue = weeklyRemaining
            let creditsRatio = creditsRemaining.map { min($0 / Self.creditsCap * 100, 100) }

            let weeklyAvailable = (weeklyRemaining ?? 0) > 0
            let claudeExtraHeight: CGFloat = style == .claude ? 1 : 0
            let creditsHeight: CGFloat = 8 + claudeExtraHeight
            let topHeight: CGFloat = 5 + claudeExtraHeight
            let bottomHeight: CGFloat = 3
            let creditsAlpha: CGFloat = 1.0

            if weeklyAvailable {
                // Normal: top=5h, bottom=weekly, no credits.
                drawBar(
                    y: 9,
                    remaining: topValue,
                    height: topHeight,
                    addNotches: style == .claude,
                    addFace: style == .codex,
                    blink: blink)
                drawBar(y: 4, remaining: bottomValue, height: bottomHeight)
            } else {
                // Weekly exhausted/missing: show credits on top (thicker), weekly (likely 0) on bottom.
                if let ratio = creditsRatio {
                    drawBar(
                        y: 9,
                        remaining: ratio,
                        height: creditsHeight,
                        alpha: creditsAlpha,
                        addNotches: style == .claude,
                        addFace: style == .codex,
                        blink: blink)
                } else {
                    // No credits available; fall back to 5h if present.
                    drawBar(
                        y: 9,
                        remaining: topValue,
                        height: topHeight,
                        addNotches: style == .claude,
                        addFace: style == .codex,
                        blink: blink)
                }
                drawBar(y: 3, remaining: bottomValue, height: bottomHeight)
            }

            Self.drawStatusOverlay(indicator: statusIndicator)
        }

        return image
    }

    // swiftlint:enable function_body_length

    /// Morph helper: unbraids a simplified knot into our bar icon.
    static func makeMorphIcon(progress: Double, style: IconStyle) -> NSImage {
        let clamped = max(0, min(progress, 1))
        let image = self.renderImage {
            self.drawUnbraidMorph(t: clamped, style: style)
        }
        return image
    }

    private static func drawUnbraidMorph(t: Double, style: IconStyle) {
        let t = CGFloat(max(0, min(t, 1)))
        let size = Self.baseSize
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let baseColor = NSColor.labelColor

        struct Segment {
            let startCenter: CGPoint
            let endCenter: CGPoint
            let startAngle: CGFloat
            let endAngle: CGFloat
            let startLength: CGFloat
            let endLength: CGFloat
            let startThickness: CGFloat
            let endThickness: CGFloat
            let fadeOut: Bool
        }

        let segments: [Segment] = [
            // Upper ribbon -> top bar
            .init(
                startCenter: center.offset(dx: 0, dy: 2),
                endCenter: CGPoint(x: center.x, y: 9.0),
                startAngle: -30,
                endAngle: 0,
                startLength: 16,
                endLength: 14,
                startThickness: 3.4,
                endThickness: 3.0,
                fadeOut: false),
            // Lower ribbon -> bottom bar
            .init(
                startCenter: center.offset(dx: 0, dy: -2),
                endCenter: CGPoint(x: center.x, y: 4.0),
                startAngle: 210,
                endAngle: 0,
                startLength: 16,
                endLength: 12,
                startThickness: 3.4,
                endThickness: 2.4,
                fadeOut: false),
            // Side ribbon fades away
            .init(
                startCenter: center,
                endCenter: center.offset(dx: 0, dy: 6),
                startAngle: 90,
                endAngle: 0,
                startLength: 16,
                endLength: 8,
                startThickness: 3.4,
                endThickness: 1.8,
                fadeOut: true),
        ]

        for seg in segments {
            let p = seg.fadeOut ? t * 1.1 : t
            let c = seg.startCenter.lerp(to: seg.endCenter, p: p)
            let angle = seg.startAngle.lerp(to: seg.endAngle, p: p)
            let length = seg.startLength.lerp(to: seg.endLength, p: p)
            let thickness = seg.startThickness.lerp(to: seg.endThickness, p: p)
            let alpha = seg.fadeOut ? (1 - p) : 1

            self.drawRoundedRibbon(
                center: c,
                length: length,
                thickness: thickness,
                angle: angle,
                color: baseColor.withAlphaComponent(alpha))
        }

        // Cross-fade in bar fill emphasis near the end of the morph.
        if t > 0.55 {
            let barT = (t - 0.55) / 0.45
            let bars = self.makeIcon(
                primaryRemaining: 100,
                weeklyRemaining: 100,
                creditsRemaining: nil,
                stale: false,
                style: style)
            bars.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: barT)
        }
    }

    private static func drawRoundedRibbon(
        center: CGPoint,
        length: CGFloat,
        thickness: CGFloat,
        angle: CGFloat,
        color: NSColor)
    {
        var transform = AffineTransform.identity
        transform.translate(x: center.x, y: center.y)
        transform.rotate(byDegrees: angle)
        transform.translate(x: -center.x, y: -center.y)

        let rect = CGRect(
            x: center.x - length / 2,
            y: center.y - thickness / 2,
            width: length,
            height: thickness)

        let path = NSBezierPath(roundedRect: rect, xRadius: thickness / 2, yRadius: thickness / 2)
        path.transform(using: transform)
        color.setFill()
        path.fill()
    }

    private static func drawStatusOverlay(indicator: ProviderStatusIndicator) {
        guard indicator.hasIssue else { return }
        let color = NSColor.labelColor

        switch indicator {
        case .minor, .maintenance:
            let size: CGFloat = 4
            let rect = Self.snapRect(
                x: Self.baseSize.width - size - 2,
                y: 2,
                width: size,
                height: size)
            let path = NSBezierPath(ovalIn: rect)
            color.setFill()
            path.fill()
        case .major, .critical, .unknown:
            let lineRect = Self.snapRect(
                x: Self.baseSize.width - 6,
                y: 4,
                width: 2.0,
                height: 6)
            let linePath = NSBezierPath(roundedRect: lineRect, xRadius: 1, yRadius: 1)
            color.setFill()
            linePath.fill()

            let dotRect = Self.snapRect(
                x: Self.baseSize.width - 6,
                y: 2,
                width: 2.0,
                height: 2.0)
            NSBezierPath(ovalIn: dotRect).fill()
        case .none:
            break
        }
    }

    private static func withScaledContext(_ draw: () -> Void) {
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            draw()
            return
        }
        ctx.saveGState()
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .none
        draw()
        ctx.restoreGState()
    }

    private static func snap(_ value: CGFloat) -> CGFloat {
        (value * self.outputScale).rounded() / self.outputScale
    }

    private static func snapRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: self.snap(x), y: self.snap(y), width: self.snap(width), height: self.snap(height))
    }

    private static func renderImage(_ draw: () -> Void) -> NSImage {
        let image = NSImage(size: Self.outputSize)

        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(Self.outputSize.width * Self.outputScale),
            pixelsHigh: Int(Self.outputSize.height * Self.outputScale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)
        {
            rep.size = Self.outputSize // points
            image.addRepresentation(rep)

            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx
                Self.withScaledContext(draw)
            }
            NSGraphicsContext.restoreGraphicsState()
        } else {
            // Fallback to legacy focus if the bitmap rep fails for any reason.
            image.lockFocus()
            Self.withScaledContext(draw)
            image.unlockFocus()
        }

        image.isTemplate = true
        return image
    }
}

extension CGPoint {
    fileprivate func lerp(to other: CGPoint, p: CGFloat) -> CGPoint {
        CGPoint(x: self.x + (other.x - self.x) * p, y: self.y + (other.y - self.y) * p)
    }

    fileprivate func offset(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: self.x + dx, y: self.y + dy)
    }
}

extension CGFloat {
    fileprivate func lerp(to other: CGFloat, p: CGFloat) -> CGFloat {
        self + (other - self) * p
    }
}
