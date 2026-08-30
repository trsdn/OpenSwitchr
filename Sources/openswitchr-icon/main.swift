// Renders Resources/AppIcon.icns from the same mark the menu bar draws.
//
// This is a target rather than a loose script so it can import `WindowMark`:
// the icon and the menu bar glyph are the same shape, and the only way to keep
// them that way is for both to come from one drawing. Every size is rendered
// natively instead of downscaled from 1024, because detail that reads at 512
// turns to mush at 16 and is better dropped than shrunk.
//
// Usage: swift run openswitchr-icon

import AppKit
import Foundation
import OpenSwitchrUI

// Apple's macOS icon grid: the rounded plate is 824 pt on a 1024 pt canvas,
// with a 185.4 pt corner radius. Everything here is a fraction of the canvas so
// every size is drawn to the same proportions.
let plateInset = 100.0 / 1024.0
let plateCornerRadius = 185.4 / 824.0
let markWidth = 0.685

let topColor = NSColor(srgbRed: 0.36, green: 0.58, blue: 0.99, alpha: 1)
let bottomColor = NSColor(srgbRed: 0.16, green: 0.29, blue: 0.80, alpha: 1)

func drawPlate(size: Double) -> NSRect {
    let inset = size * plateInset
    let plate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = plate.width * plateCornerRadius
    let path = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

    NSGradient(starting: topColor, ending: bottomColor)?.draw(in: path, angle: -90)

    // A hairline of white inside the edge reads as a lit surface and keeps the
    // plate from looking flat against a dark wallpaper.
    NSGraphicsContext.saveGraphicsState()
    path.setClip()
    let sheen = NSBezierPath(
        roundedRect: plate.insetBy(dx: size * 0.012, dy: size * 0.012),
        xRadius: radius,
        yRadius: radius
    )
    sheen.lineWidth = max(1, size * 0.008)
    NSColor.white.withAlphaComponent(0.22).setStroke()
    sheen.stroke()
    NSGraphicsContext.restoreGraphicsState()

    return plate
}

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("could not allocate a \(pixels)x\(pixels) bitmap")
    }
    rep.size = NSSize(width: Double(pixels), height: Double(pixels))

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not create a drawing context")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let plate = drawPlate(size: Double(pixels))

    // The mark is rendered at whole pixels and drawn 1:1 so it is never
    // resampled, which is what keeps the 16 pt icon from going soft.
    WindowMark.draw(centeredIn: plate, width: plate.width * markWidth, color: .white)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// 16 and 32 each appear twice in an iconset — as the @1x of one slot and the
// @2x of the next one down — so render each pixel size once and write it to
// both names.
let slots: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

// `swift run` starts in the package directory, and `build-app.sh` runs it from
// there too. An explicit argument stays available for anything that does not.
let projectDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

let resources = projectDirectory.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

var rendered: [Int: Data] = [:]

for slot in slots {
    let png: Data
    if let cached = rendered[slot.pixels] {
        png = cached
    } else {
        guard let data = renderIcon(pixels: slot.pixels).representation(using: .png, properties: [:]) else {
            fatalError("could not encode \(slot.pixels)x\(slot.pixels) as PNG")
        }
        rendered[slot.pixels] = data
        png = data
    }
    try png.write(to: iconset.appendingPathComponent("\(slot.name).png"))
}

let icns = resources.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", iconset.path, "--output", icns.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(iconutil.terminationStatus)")
}

// The .iconset is scaffolding for iconutil; only the .icns is consumed by the
// build, so leaving the loose PNGs behind would just invite them to drift.
try FileManager.default.removeItem(at: iconset)

print("Wrote \(icns.path)")
