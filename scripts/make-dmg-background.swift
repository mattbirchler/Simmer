// Draws the picture behind the icons in Simmer's disk image, at regular
// and Retina sizes in one file.
// Run from the project folder: swift scripts/make-dmg-background.swift
import AppKit

// The window's content area, in points. scripts/make-dmg.sh places the app
// at (166, 206) and the Applications folder at (496, 206), measured from
// the top left, so the arrow sits between them.
let width = 660, height = 400

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func draw(scale: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    // Telling it its size in points is what marks the larger one as Retina.
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext

    context.setFillColor(color(0xF1F6EE))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // The gem from the app icon, far larger than the window and very faint.
    let top = CGPoint(x: 330, y: 440), bottom = CGPoint(x: 330, y: -70)
    let left = CGPoint(x: 90, y: 210), right = CGPoint(x: 570, y: 210)
    let front = CGPoint(x: 330, y: 160)
    let facets: [([CGPoint], UInt32)] = [
        ([top, left, front], 0xDCEFD6),
        ([top, front, right], 0xCFE8C8),
        ([left, bottom, front], 0xE6F3E1),
        ([front, bottom, right], 0xD8ECD2),
    ]
    for (points, hex) in facets {
        context.addLines(between: points)
        context.closePath()
        context.setFillColor(color(hex, alpha: 0.5))
        context.fillPath()
    }

    // An arrow from the app to the Applications folder.
    context.setStrokeColor(color(0x23A043))
    context.setLineWidth(7)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: 262, y: 194))
    context.addLine(to: CGPoint(x: 386, y: 194))
    context.strokePath()
    context.addLines(between: [CGPoint(x: 364, y: 214), CGPoint(x: 388, y: 194), CGPoint(x: 364, y: 174)])
    context.strokePath()

    let headline = NSAttributedString(string: "Drag Simmer to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 21, weight: .semibold),
        .foregroundColor: NSColor(cgColor: color(0x163A22))!,
    ])
    let size = headline.size()
    headline.draw(at: NSPoint(x: (CGFloat(width) - size.width) / 2, y: 326))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let folder = URL(fileURLWithPath: "scripts/dmg")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let file = folder.appendingPathComponent("background.tiff")
let tiff = NSBitmapImageRep.representationOfImageReps(in: [draw(scale: 1), draw(scale: 2)], using: .tiff,
                                                      properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue])!
try tiff.write(to: file)
print("Wrote \(file.path)")
