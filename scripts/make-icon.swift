// Draws Simmer's app icon and writes every size the asset catalog needs.
// Run from the project folder: swift scripts/make-icon.swift
import AppKit

let folder = URL(fileURLWithPath: "Simmer/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    // Everything below is laid out on a 1024 point canvas.
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    // The rounded square, inset the way macOS icons are.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
                      color: NSColor.black.withAlphaComponent(0.3).cgColor)
    context.addPath(tilePath)
    context.setFillColor(color(0x0E3A1D))
    context.fillPath()
    context.restoreGState()

    // Deep green, lighter at the top, with a soft glow behind the gem.
    let space = CGColorSpaceCreateDeviceRGB()
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let tileColors = [color(0x215A31), color(0x071F10)] as CFArray
    let tileGradient = CGGradient(colorsSpace: space, colors: tileColors, locations: [0, 1])!
    context.drawLinearGradient(tileGradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let glowColors = [color(0x7DFF6A, alpha: 0.45), color(0x7DFF6A, alpha: 0)] as CFArray
    let glow = CGGradient(colorsSpace: space, colors: glowColors, locations: [0, 1])!
    let middle = CGPoint(x: 512, y: 512)
    context.drawRadialGradient(glow, startCenter: middle, startRadius: 0, endCenter: middle, endRadius: 380, options: [])
    context.restoreGState()

    // The gem: four facets around a point just below the middle, each a
    // different green so it reads as lit from the top left.
    let top = CGPoint(x: 512, y: 812), bottom = CGPoint(x: 512, y: 212)
    let left = CGPoint(x: 332, y: 532), right = CGPoint(x: 692, y: 532)
    let front = CGPoint(x: 512, y: 492)
    let facets: [([CGPoint], UInt32)] = [
        ([top, left, front], 0xB4F78E),
        ([top, front, right], 0x5FD94A),
        ([left, bottom, front], 0x34B440),
        ([front, bottom, right], 0x1A8734),
    ]
    for (points, hex) in facets {
        context.addLines(between: points)
        context.closePath()
        context.setFillColor(color(hex))
        context.fillPath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try drawIcon(pixels: size * scale).write(to: folder.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: folder.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(folder.path)")
