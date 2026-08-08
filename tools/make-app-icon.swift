import AppKit
import ImageIO
import UniformTypeIdentifiers

// Draws the YTDLP app icon on a 1024pt grid, then rasterises it at every size
// the macOS asset catalog wants.
//
// Geometry follows Apple's macOS convention: the artwork square is 824x824
// centred in a 1024x1024 canvas, leaving a 100pt margin so the system's own
// shadow and (on macOS 26+) its shape mask line up with ours.

let canvas: CGFloat = 1024
let inset: CGFloat = 100
let side = canvas - inset * 2          // 824
let corner: CGFloat = 185              // ~22.5% of the square, Apple's ratio

func drawIcon(into ctx: CGContext) {
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // --- background squircle, warm red gradient -------------------------
    let square = CGRect(x: inset, y: inset, width: side, height: side)
    let body = CGPath(roundedRect: square, cornerWidth: corner, cornerHeight: corner, transform: nil)

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()

    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 1.00, green: 0.36, blue: 0.30, alpha: 1),   // top
            CGColor(red: 0.75, green: 0.05, blue: 0.11, alpha: 1),   // bottom
        ] as CFArray,
        locations: [0, 1]
    )!
    // y is up in Core Graphics, so the "top" stop goes at the higher y.
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: square.maxY),
        end: CGPoint(x: 0, y: square.minY),
        options: []
    )

    // A soft highlight across the top third, so it doesn't read as flat.
    let sheen = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        sheen,
        start: CGPoint(x: 0, y: square.maxY),
        end: CGPoint(x: 0, y: square.midY),
        options: []
    )
    ctx.restoreGState()

    // Hairline edge for definition against a light Dock.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.16))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    // --- glyph: a play triangle rotated into a download arrow -----------
    // Rotating the play symbol 90° gives the arrowhead, so the mark reads as
    // both "video" and "download" at once. Shifted down 14pt so the whole
    // group is optically centred rather than mathematically centred.
    let cx: CGFloat = 512
    let dy: CGFloat = -14
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

    // Baseline bar.
    let bar = CGRect(x: cx - 180, y: 238 + dy, width: 360, height: 78)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 39, cornerHeight: 39, transform: nil))
    ctx.fillPath()

    // Stem, with the bottom tucked under the arrowhead so they read as one shape.
    let stem = CGRect(x: cx - 54, y: 520 + dy, width: 108, height: 268)
    ctx.addPath(CGPath(roundedRect: stem, cornerWidth: 54, cornerHeight: 54, transform: nil))
    ctx.fillPath()

    // Arrowhead: the play triangle, pointed down.
    let head = CGMutablePath()
    let apex = CGPoint(x: cx, y: 380 + dy)
    let left = CGPoint(x: cx - 156, y: 566 + dy)
    let right = CGPoint(x: cx + 156, y: 566 + dy)
    // Rounded joints keep it from looking sharp and cheap at large sizes.
    head.move(to: CGPoint(x: (left.x + apex.x) / 2, y: (left.y + apex.y) / 2))
    head.addArc(tangent1End: apex, tangent2End: right, radius: 34)
    head.addArc(tangent1End: right, tangent2End: left, radius: 34)
    head.addArc(tangent1End: left, tangent2End: apex, radius: 34)
    head.closeSubpath()
    ctx.addPath(head)
    ctx.fillPath()
}

func render(size: Int, to url: URL) throws {
    let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(size) / canvas
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(into: ctx)

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "icon", code: 1) }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "icon", code: 2) }
}

// (filename, pixel size)
let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for (name, size) in outputs {
    try render(size: size, to: dir.appendingPathComponent(name))
    print("wrote \(name) (\(size)px)")
}
