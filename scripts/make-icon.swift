// Draws Simmer's app icon and writes every size the asset catalog needs.
// Run from the project folder: swift scripts/make-icon.swift
import AppKit

let folder = URL(fileURLWithPath: "Simmer/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

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
    context.setFillColor(NSColor(red: 0.95, green: 0.35, blue: 0.15, alpha: 1).cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let colors = [NSColor(red: 1.0, green: 0.72, blue: 0.22, alpha: 1).cgColor,
                  NSColor(red: 0.93, green: 0.22, blue: 0.2, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    // A phone outline.
    let white = NSColor.white.cgColor
    let phone = CGRect(x: 347, y: 232, width: 330, height: 560)
    context.addPath(CGPath(roundedRect: phone, cornerWidth: 72, cornerHeight: 72, transform: nil))
    context.setStrokeColor(white)
    context.setLineWidth(40)
    context.strokePath()

    // A power symbol on its screen: a ring open at the top, and a bar.
    let center = CGPoint(x: 512, y: 498)
    context.setLineCap(.round)
    context.setLineWidth(36)
    context.addArc(center: center, radius: 78, startAngle: .pi / 2 - 0.62, endAngle: .pi / 2 + 0.62, clockwise: true)
    context.strokePath()
    context.move(to: CGPoint(x: center.x, y: center.y + 22))
    context.addLine(to: CGPoint(x: center.x, y: center.y + 104))
    context.strokePath()

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
