import AppKit

enum IconRenderer {
    private static let creditsCap: Double = 1000
    private static let baseSize = NSSize(width: 18, height: 18)
    // Render to an 18×18 pt template (36×36 px at 2×) to match the system menu bar size.
    private static let outputSize = NSSize(width: 18, height: 18)
    private static let outputScale: CGFloat = 2
    private static let canvasPx = Int(outputSize.width * outputScale)

    private struct PixelGrid: Sendable {
        let scale: CGFloat

        func pt(_ px: Int) -> CGFloat {
            CGFloat(px) / self.scale
        }

        func rect(x: Int, y: Int, w: Int, h: Int) -> CGRect {
            CGRect(x: self.pt(x), y: self.pt(y), width: self.pt(w), height: self.pt(h))
        }

        func snapDelta(_ value: CGFloat) -> CGFloat {
            (value * self.scale).rounded() / self.scale
        }
    }

    private static let grid = PixelGrid(scale: outputScale)

    private struct RectPx: Hashable, Sendable {
        let x: Int
        let y: Int
        let w: Int
        let h: Int

        var midXPx: Int { self.x + self.w / 2 }
        var midYPx: Int { self.y + self.h / 2 }

        func rect() -> CGRect {
            Self.grid.rect(x: self.x, y: self.y, w: self.w, h: self.h)
        }

        private static let grid = IconRenderer.grid
    }

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
            let trackFillAlpha: CGFloat = stale ? 0.18 : 0.28
            let trackStrokeAlpha: CGFloat = stale ? 0.28 : 0.44
            let fillColor = baseFill.withAlphaComponent(stale ? 0.55 : 1.0)

            let barWidthPx = 30 // 15 pt at 2×, uses the slot better without touching edges.
            let barXPx = (Self.canvasPx - barWidthPx) / 2

            func drawBar(
                rectPx: RectPx,
                remaining: Double?,
                alpha: CGFloat = 1.0,
                addNotches: Bool = false,
                addFace: Bool = false,
                blink: CGFloat = 0)
            {
                let rect = rectPx.rect()
                // Claude reads better as a blockier critter; Codex stays as a capsule.
                let cornerRadiusPx = addNotches ? 0 : rectPx.h / 2
                let radius = Self.grid.pt(cornerRadiusPx)

                let trackPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
                baseFill.withAlphaComponent(trackFillAlpha * alpha).setFill()
                trackPath.fill()

                // Crisp outline: stroke an inset path so the stroke stays within pixel bounds.
                let strokeWidthPx = 2 // 1 pt == 2 px at 2×
                let insetPx = strokeWidthPx / 2
                let strokeRect = Self.grid.rect(
                    x: rectPx.x + insetPx,
                    y: rectPx.y + insetPx,
                    w: max(0, rectPx.w - insetPx * 2),
                    h: max(0, rectPx.h - insetPx * 2))
                let strokePath = NSBezierPath(
                    roundedRect: strokeRect,
                    xRadius: Self.grid.pt(max(0, cornerRadiusPx - insetPx)),
                    yRadius: Self.grid.pt(max(0, cornerRadiusPx - insetPx)))
                strokePath.lineWidth = CGFloat(strokeWidthPx) / Self.outputScale
                baseFill.withAlphaComponent(trackStrokeAlpha * alpha).setStroke()
                strokePath.stroke()

                // Fill: clip to the capsule and paint a left-to-right rect so the progress edge is straight.
                if let remaining {
                    let clamped = max(0, min(remaining / 100, 1))
                    let fillWidthPx = max(0, min(rectPx.w, Int((CGFloat(rectPx.w) * CGFloat(clamped)).rounded())))
                    if fillWidthPx > 0 {
                        NSGraphicsContext.current?.cgContext.saveGState()
                        trackPath.addClip()
                        fillColor.withAlphaComponent(alpha).setFill()
                        NSBezierPath(
                            rect: Self.grid.rect(
                                x: rectPx.x,
                                y: rectPx.y,
                                w: fillWidthPx,
                                h: rectPx.h)).fill()
                        NSGraphicsContext.current?.cgContext.restoreGState()
                    }
                }

                // Codex face: eye cutouts plus faint eyelids to give the prompt some personality.
                if addFace {
                    let ctx = NSGraphicsContext.current?.cgContext
                    let eyeSizePx = 4
                    let eyeOffsetPx = 7
                    let eyeCenterYPx = rectPx.y + rectPx.h / 2
                    let centerXPx = rectPx.midXPx

                    ctx?.saveGState()
                    ctx?.setShouldAntialias(false)
                    ctx?.clear(Self.grid.rect(
                        x: centerXPx - eyeOffsetPx - eyeSizePx / 2,
                        y: eyeCenterYPx - eyeSizePx / 2,
                        w: eyeSizePx,
                        h: eyeSizePx))
                    ctx?.clear(Self.grid.rect(
                        x: centerXPx + eyeOffsetPx - eyeSizePx / 2,
                        y: eyeCenterYPx - eyeSizePx / 2,
                        w: eyeSizePx,
                        h: eyeSizePx))
                    ctx?.restoreGState()

                    // Blink: refill eyes from the top down using the bar fill color.
                    if blink > 0.001 {
                        let clamped = max(0, min(blink, 1))
                        let blinkHeightPx = Int((CGFloat(eyeSizePx) * clamped).rounded())
                        fillColor.withAlphaComponent(alpha).setFill()
                        let blinkRectLeft = Self.grid.rect(
                            x: centerXPx - eyeOffsetPx - eyeSizePx / 2,
                            y: eyeCenterYPx + eyeSizePx / 2 - blinkHeightPx,
                            w: eyeSizePx,
                            h: blinkHeightPx)
                        let blinkRectRight = Self.grid.rect(
                            x: centerXPx + eyeOffsetPx - eyeSizePx / 2,
                            y: eyeCenterYPx + eyeSizePx / 2 - blinkHeightPx,
                            w: eyeSizePx,
                            h: blinkHeightPx)
                        NSBezierPath(rect: blinkRectLeft).fill()
                        NSBezierPath(rect: blinkRectRight).fill()
                    }

                    // Hat: a tiny cap hovering above the eyes to give the face more character.
                    let hatWidthPx = 18
                    let hatHeightPx = 4
                    let hatRect = Self.grid.rect(
                        x: centerXPx - hatWidthPx / 2,
                        y: rectPx.y + rectPx.h - hatHeightPx,
                        w: hatWidthPx,
                        h: hatHeightPx)
                    ctx?.saveGState()
                    if abs(tilt) > 0.0001 {
                        // Tilt only the hat; keep eyes pixel-crisp and axis-aligned.
                        let faceCenter = CGPoint(x: Self.grid.pt(centerXPx), y: Self.grid.pt(eyeCenterYPx))
                        ctx?.translateBy(x: faceCenter.x, y: faceCenter.y)
                        ctx?.rotate(by: tilt)
                        ctx?.translateBy(x: -faceCenter.x, y: -faceCenter.y - abs(tilt) * 1.2)
                    }
                    fillColor.withAlphaComponent(alpha).setFill()
                    NSBezierPath(rect: hatRect).fill()
                    ctx?.restoreGState()
                }

                // Claude twist: blocky crab-style critter (arms + legs + vertical eyes).
                if addNotches {
                    let ctx = NSGraphicsContext.current?.cgContext
                    let wiggleOffset = Self.grid.snapDelta(wiggle * 0.6)
                    let wigglePx = Int((wiggleOffset * Self.outputScale).rounded())

                    fillColor.withAlphaComponent(alpha).setFill()

                    // Arms/claws: mid-height side protrusions.
                    // Keep within the 18×18pt canvas: barX is 3px, so 3px arms reach the edge without clipping.
                    let armWidthPx = 3
                    let armHeightPx = max(0, rectPx.h - 6)
                    let armYPx = rectPx.y + 3 + wigglePx / 6
                    let leftArm = Self.grid.rect(
                        x: rectPx.x - armWidthPx,
                        y: armYPx,
                        w: armWidthPx,
                        h: armHeightPx)
                    let rightArm = Self.grid.rect(
                        x: rectPx.x + rectPx.w,
                        y: armYPx,
                        w: armWidthPx,
                        h: armHeightPx)
                    NSBezierPath(rect: leftArm).fill()
                    NSBezierPath(rect: rightArm).fill()

                    // Legs: 4 little pixels underneath, like a tiny crab.
                    let legCount = 4
                    let legWidthPx = 2
                    let legHeightPx = 3
                    let legYPx = rectPx.y - legHeightPx + wigglePx / 6
                    let stepPx = max(1, rectPx.w / (legCount + 1))
                    for idx in 0..<legCount {
                        let cx = rectPx.x + stepPx * (idx + 1)
                        let leg = Self.grid.rect(
                            x: cx - legWidthPx / 2,
                            y: legYPx,
                            w: legWidthPx,
                            h: legHeightPx)
                        NSBezierPath(rect: leg).fill()
                    }

                    // Eyes: tall vertical cutouts near the top.
                    let eyeWidthPx = 2
                    let eyeHeightPx = 5
                    let eyeOffsetPx = 6
                    let eyeYPx = rectPx.y + rectPx.h - eyeHeightPx - 2 + wigglePx / 8
                    ctx?.saveGState()
                    ctx?.setShouldAntialias(false)
                    ctx?.clear(Self.grid.rect(
                        x: rectPx.midXPx - eyeOffsetPx - eyeWidthPx / 2,
                        y: eyeYPx,
                        w: eyeWidthPx,
                        h: eyeHeightPx))
                    ctx?.clear(Self.grid.rect(
                        x: rectPx.midXPx + eyeOffsetPx - eyeWidthPx / 2,
                        y: eyeYPx,
                        w: eyeWidthPx,
                        h: eyeHeightPx))
                    ctx?.restoreGState()

                    // Blink: fill the eyes from the top down (blocky).
                    if blink > 0.001 {
                        let clamped = max(0, min(blink, 1))
                        let blinkHeightPx = Int((CGFloat(eyeHeightPx) * clamped).rounded())
                        fillColor.withAlphaComponent(alpha).setFill()
                        let leftBlink = Self.grid.rect(
                            x: rectPx.midXPx - eyeOffsetPx - eyeWidthPx / 2,
                            y: eyeYPx + eyeHeightPx - blinkHeightPx,
                            w: eyeWidthPx,
                            h: blinkHeightPx)
                        let rightBlink = Self.grid.rect(
                            x: rectPx.midXPx + eyeOffsetPx - eyeWidthPx / 2,
                            y: eyeYPx + eyeHeightPx - blinkHeightPx,
                            w: eyeWidthPx,
                            h: blinkHeightPx)
                        NSBezierPath(rect: leftBlink).fill()
                        NSBezierPath(rect: rightBlink).fill()
                    }
                }
            }

            let topValue = primaryRemaining
            let bottomValue = weeklyRemaining
            let creditsRatio = creditsRemaining.map { min($0 / Self.creditsCap * 100, 100) }

            let hasWeekly = (weeklyRemaining != nil)
            let weeklyAvailable = hasWeekly && (weeklyRemaining ?? 0) > 0
            let creditsAlpha: CGFloat = 1.0
            let topRectPx = RectPx(x: barXPx, y: 19, w: barWidthPx, h: 12)
            let bottomRectPx = RectPx(x: barXPx, y: 5, w: barWidthPx, h: 8)
            let creditsRectPx = RectPx(x: barXPx, y: 14, w: barWidthPx, h: 16)
            let creditsBottomRectPx = RectPx(x: barXPx, y: 4, w: barWidthPx, h: 6)

            if weeklyAvailable {
                // Normal: top=5h, bottom=weekly, no credits.
                drawBar(
                    rectPx: topRectPx,
                    remaining: topValue,
                    addNotches: style == .claude,
                    addFace: style == .codex,
                    blink: blink)
                drawBar(rectPx: bottomRectPx, remaining: bottomValue)
            } else if !hasWeekly {
                // Weekly missing (e.g. Claude enterprise): keep normal layout but
                // dim the bottom track to indicate N/A.
                if topValue == nil, let ratio = creditsRatio {
                    // Credits-only: show credits prominently (e.g. credits loaded before usage).
                    drawBar(
                        rectPx: creditsRectPx,
                        remaining: ratio,
                        alpha: creditsAlpha,
                        addNotches: style == .claude,
                        addFace: style == .codex,
                        blink: blink)
                    drawBar(rectPx: creditsBottomRectPx, remaining: nil, alpha: 0.45)
                } else {
                    drawBar(
                        rectPx: topRectPx,
                        remaining: topValue,
                        addNotches: style == .claude,
                        addFace: style == .codex,
                        blink: blink)
                    drawBar(rectPx: bottomRectPx, remaining: nil, alpha: 0.45)
                }
            } else {
                // Weekly exhausted/missing: show credits on top (thicker), weekly (likely 0) on bottom.
                if let ratio = creditsRatio {
                    drawBar(
                        rectPx: creditsRectPx,
                        remaining: ratio,
                        alpha: creditsAlpha,
                        addNotches: style == .claude,
                        addFace: style == .codex,
                        blink: blink)
                } else {
                    // No credits available; fall back to 5h if present.
                    drawBar(
                        rectPx: topRectPx,
                        remaining: topValue,
                        addNotches: style == .claude,
                        addFace: style == .codex,
                        blink: blink)
                }
                drawBar(rectPx: creditsBottomRectPx, remaining: bottomValue)
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
