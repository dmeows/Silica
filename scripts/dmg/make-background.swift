// Draws the DMG window's background: soft iridescent color behind a glass card, an
// arrow from the app to Applications, and a caption. scripts/dmg/layout.applescript
// places the icons on top of it, so the two have to agree on the positions below.
//
//   swift scripts/dmg/make-background.swift scripts/dmg
//
// writes background.png and background@2x.png, which tiffutil combines into
// background.tiff (see scripts/dmg/README.md).

import AppKit

let size = NSSize(width: 640, height: 400)
/// Icon centers, measured from the window's top left, as layout.applescript sets them.
let appIcon = NSPoint(x: 170, y: 185)
let applicationsIcon = NSPoint(x: 470, y: 185)

/// Converts from top-left coordinates (Finder's) to AppKit's bottom-left ones.
func flip(_ point: NSPoint) -> NSPoint { NSPoint(x: point.x, y: size.height - point.y) }

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

/// A soft blob of color fading out to nothing.
func glow(_ hex: UInt32, alpha: CGFloat, at center: NSPoint, radius: CGFloat) {
    let gradient = NSGradient(colors: [color(hex, alpha), color(hex, alpha * 0.45), color(hex, 0)],
                              atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
    gradient.draw(fromCenter: flip(center), radius: 0, toCenter: flip(center), radius: radius, options: [])
}

func drawBackground() {
    let bounds = NSRect(origin: .zero, size: size)

    NSGradient(starting: color(0xFBF9FF), ending: color(0xF2EFF8))!.draw(in: bounds, angle: -35)
    glow(0xFF9FD0, alpha: 0.55, at: NSPoint(x: 60, y: 360), radius: 300)
    glow(0x9CC2FF, alpha: 0.55, at: NSPoint(x: 600, y: 40), radius: 300)
    glow(0xFFCB96, alpha: 0.45, at: NSPoint(x: 620, y: 390), radius: 230)
    glow(0xCDB5FF, alpha: 0.50, at: NSPoint(x: 300, y: -60), radius: 260)

    // The glass card the icons sit on, like the editor's card in the app. It stays
    // light so Finder's dark icon labels read on it.
    let card = NSRect(x: 50, y: size.height - 300, width: size.width - 100, height: 220)
    let cardPath = NSBezierPath(roundedRect: card, xRadius: 28, yRadius: 28)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x4B3F72, 0.10)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    shadow.set()
    color(0xFFFFFF, 0.55).setFill()
    cardPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0xFFFFFF, 0.35), ending: color(0xFFFFFF, 0))!.draw(in: cardPath, angle: -90)
    color(0xFFFFFF, 0.85).setStroke()
    cardPath.lineWidth = 1
    cardPath.stroke()

    // Arrow from the app to Applications, clear of both 128 pt icons.
    let start = flip(NSPoint(x: appIcon.x + 88, y: appIcon.y))
    let end = flip(NSPoint(x: applicationsIcon.x - 88, y: applicationsIcon.y))
    let arrow = NSBezierPath()
    arrow.move(to: start)
    arrow.line(to: end)
    arrow.move(to: NSPoint(x: end.x - 13, y: end.y + 13))
    arrow.line(to: end)
    arrow.line(to: NSPoint(x: end.x - 13, y: end.y - 13))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(0x6B6488, 0.55).setStroke()
    arrow.stroke()

    let caption = "Drag Silica to Applications to install it"
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: color(0x57506F, 0.85),
        .paragraphStyle: style,
    ]
    let text = NSAttributedString(string: caption, attributes: attributes)
    let height = text.size().height
    text.draw(in: NSRect(x: 0, y: size.height - 344 - height / 2, width: size.width, height: height))
}

func render(scale: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawBackground()
    NSGraphicsContext.restoreGraphicsState()
    let srgb = rep.converting(to: .sRGB, renderingIntent: .default) ?? rep
    try srgb.representation(using: .png, properties: [:])!.write(to: url)
}

let directory = URL(filePath: CommandLine.arguments.dropFirst().first ?? ".")
try render(scale: 1, to: directory.appending(path: "background.png"))
try render(scale: 2, to: directory.appending(path: "background@2x.png"))
