import AppKit

/// The two overlapping windows that identify OpenSwitchr.
///
/// The same mark has to work at 1024 pt on the app icon and at 15 pt in the
/// menu bar. Drawing it twice is how an app ends up looking like two different
/// apps, so the geometry lives here once — in fractions of the front window's
/// width — and each caller asks for it at the size and weight it needs.
///
/// The mark carries its own alpha and is rendered onto transparency rather than
/// onto its background. That is what lets one drawing serve both uses: on the
/// app icon it is composited in white over a blue plate, and in the menu bar it
/// is a black template image the system tints. Every interior detail is
/// therefore a *hole* punched in the fill rather than a lighter colour painted
/// on top, because "lighter" points opposite ways on those two backgrounds
/// while "less opaque" points the same way on both.
public enum WindowMark {

    /// Solid art carries an app icon and collapses into a blob at menu bar
    /// sizes; line art is the opposite. The system's own glyphs are shipped in
    /// both weights for the same reason — `macwindow` against `macwindow.fill`
    /// — so the mark is too.
    public enum Style {
        case filled
        case outlined
    }

    // Fractions of the front window's width.
    private static let windowHeight = 0.72
    private static let stackOffset = 0.1417
    private static let cornerRadius = 0.11
    private static let strokeWidth = 0.058

    /// Fraction of the front window's height taken by its title bar.
    private static let titleBarHeight = 0.26

    /// Fill each part keeps, as a fraction of the front window's.
    private static let filledBackWindowAlpha = 0.45
    private static let titleBarAlpha = 0.45
    private static let dotAlpha = 0.15

    /// Dot diameter as a fraction of the title bar's height.
    private static let dotDiameter = 0.32

    /// Below this the dots cover barely a pixel and read as a smudge along the
    /// title bar, so they are dropped rather than shrunk. The menu bar glyph
    /// lands under it even on a Retina display, and is cleaner for it.
    private static let smallestLegibleDot = 2.5

    /// Width over height of the whole mark, the offset stack included.
    public static var aspectRatio: Double {
        (1 + stackOffset) / (windowHeight + stackOffset)
    }

    /// Renders the mark `pixelWidth` pixels wide onto transparency.
    public static func representation(
        pixelWidth: Int,
        color: NSColor,
        style: Style = .filled
    ) -> NSBitmapImageRep {
        let width = Double(pixelWidth)
        let pixelHeight = max(1, Int((width / aspectRatio).rounded()))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            fatalError("could not allocate a \(pixelWidth)x\(pixelHeight) bitmap")
        }
        rep.size = NSSize(width: width, height: Double(pixelHeight))

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            fatalError("could not create a drawing context")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        draw(
            in: NSRect(x: 0, y: 0, width: width, height: Double(pixelHeight)),
            color: color,
            style: style
        )
        NSGraphicsContext.restoreGraphicsState()

        return rep
    }

    /// The mark as a template image, which the menu bar and any control that
    /// tints its content can use directly.
    public static func templateImage(
        width: Double,
        style: Style = .outlined,
        scales: [Double] = [1, 2]
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: width / aspectRatio))
        for scale in scales {
            let rep = representation(
                pixelWidth: max(1, Int((width * scale).rounded())),
                color: .black,
                style: style
            )
            rep.size = image.size
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        return image
    }

    /// The menu bar's usable height is 22 pt and the system expects air around
    /// a glyph, so the mark is sized by height rather than width: it is wider
    /// than it is tall, and sizing by width would push it past the bar's
    /// vertical margins.
    public static func menuBarImage(height: Double = 15) -> NSImage {
        templateImage(width: height * aspectRatio)
    }

    /// Draws the mark `width` points wide, centred in `container`.
    ///
    /// The mark is rendered to its own bitmap first — see the type comment —
    /// and `NSBitmapImageRep.draw(in:)` will not composite one faithfully: it
    /// ignores the alpha channel and paints the whole rect opaque, which turns
    /// two overlapping windows into a solid block. Going through `NSImage` is
    /// what keeps the transparency.
    public static func draw(
        centeredIn container: NSRect,
        width: Double,
        color: NSColor,
        style: Style = .filled
    ) {
        let rep = representation(pixelWidth: max(1, Int(width.rounded())), color: color, style: style)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        image.draw(in: NSRect(
            x: container.midX - rep.size.width / 2,
            y: container.midY - rep.size.height / 2,
            width: rep.size.width,
            height: rep.size.height
        ))
    }

    private static func draw(in bounds: NSRect, color: NSColor, style: Style) {
        // An outline is centred on its path, so half of it falls outside the
        // window it traces. Both dimensions have to give that half back, or the
        // stroke is clipped by the edge of the bitmap.
        let line = style == .outlined
            ? max(1, (bounds.width / (1 + stackOffset) * strokeWidth).rounded())
            : 0

        let windowWidth = min(
            (bounds.width - line) / (1 + stackOffset),
            (bounds.height - line) / (windowHeight + stackOffset)
        )
        let height = windowWidth * windowHeight
        let offset = windowWidth * stackOffset
        let radius = windowWidth * cornerRadius

        let originX = bounds.midX - (windowWidth + offset) / 2
        let originY = bounds.midY - (height + offset) / 2

        // The back window sits up and to the left, so the front one reads as
        // the window that would come forward.
        let frontRect = NSRect(x: originX + offset, y: originY, width: windowWidth, height: height)
        let backRect = NSRect(x: originX, y: originY + offset, width: windowWidth, height: height)
        let front = NSBezierPath(roundedRect: frontRect, xRadius: radius, yRadius: radius)
        let back = NSBezierPath(roundedRect: backRect, xRadius: radius, yRadius: radius)

        switch style {
        case .filled:
            color.withAlphaComponent(filledBackWindowAlpha).setFill()
            back.fill()
            color.setFill()
            front.fill()

        case .outlined:
            // At 15 pt a 45 %-alpha stroke is a grey blur, so the back window
            // is drawn at full strength and the stacking is carried by
            // occlusion instead: the front window clears the lines behind it
            // the way a real window would.
            color.setStroke()
            back.lineWidth = line
            back.stroke()

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: frontRect.insetBy(dx: -line, dy: -line),
                xRadius: radius + line,
                yRadius: radius + line
            ).fill()
            NSGraphicsContext.restoreGraphicsState()

            front.lineWidth = line
            front.stroke()
        }

        NSGraphicsContext.saveGraphicsState()
        front.setClip()

        let barHeight = height * titleBarHeight
        let bar = NSRect(
            x: frontRect.minX,
            y: frontRect.maxY - barHeight,
            width: windowWidth,
            height: barHeight
        )

        switch style {
        case .filled:
            // `destinationOut` scales what is already there by `1 - source
            // alpha`, so the punch is expressed as the fill that should
            // survive it.
            NSColor.black.withAlphaComponent(1 - titleBarAlpha).setFill()
            bar.fill(using: .destinationOut)
        case .outlined:
            // Nothing to punch out of an outline, so the bar is what fills.
            color.setFill()
            bar.fill()
        }

        let dot = barHeight * dotDiameter
        if dot >= smallestLegibleDot {
            // `NSBezierPath` fills through the context's compositing operation,
            // where `NSRect` takes one directly.
            let previous = NSGraphicsContext.current?.compositingOperation
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let survives = style == .filled ? dotAlpha / titleBarAlpha : dotAlpha
            NSColor.black.withAlphaComponent(1 - survives).setFill()
            for index in 0..<3 {
                let x = frontRect.minX + barHeight * 0.42 + Double(index) * dot * 1.9
                let box = NSRect(x: x, y: bar.midY - dot / 2, width: dot, height: dot)
                NSBezierPath(ovalIn: box).fill()
            }
            NSGraphicsContext.current?.compositingOperation = previous ?? .sourceOver
        }

        NSGraphicsContext.restoreGraphicsState()
    }
}
