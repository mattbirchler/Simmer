import AppKit
import SwiftUI

/// The gem from Simmer's app icon, as an outline with its facet lines.
/// Shown unlit in the menu when nothing is running.
struct GemOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.467)
        let right = CGPoint(x: rect.maxX, y: left.y)
        let front = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.533)

        var path = Path()
        path.addLines([top, left, bottom, right])
        path.closeSubpath()
        path.addLines([left, front, right])
        path.move(to: top)
        path.addLine(to: bottom)
        return path
    }
}

/// The gem as it appears in the menu bar: an outline when nothing is
/// running, and filled with the color of the current mood when something is.
@MainActor
enum MenuBarGem {
    private static let size = NSSize(width: 12, height: 16)
    private static var colored: [Mood: NSImage] = [:]

    static func image(for mood: Mood?) -> NSImage {
        guard let mood else { return hollow }
        if let image = colored[mood] { return image }
        let image = filled(mood.nsColor)
        colored[mood] = image
        return image
    }

    private static func outline(in rect: NSRect) -> NSBezierPath {
        let box = rect.insetBy(dx: 1.2, dy: 1)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.midX, y: box.maxY))
        path.line(to: NSPoint(x: box.minX, y: box.minY + box.height * 0.533))
        path.line(to: NSPoint(x: box.midX, y: box.minY))
        path.line(to: NSPoint(x: box.maxX, y: box.minY + box.height * 0.533))
        path.close()
        path.lineJoinStyle = .round
        return path
    }

    /// Colored by macOS to suit the menu bar.
    private static let hollow: NSImage = {
        let image = NSImage(size: size, flipped: false) { rect in
            let path = outline(in: rect)
            path.lineWidth = 1.3
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()

    /// Two tones, lighter on the left, so it reads as a cut gem and holds
    /// its shape on a pale menu bar.
    private static func filled(_ color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let path = outline(in: rect)
            color.setFill()
            path.fill()
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            NSColor.black.withAlphaComponent(0.2).setFill()
            NSRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height).fill()
            NSGraphicsContext.restoreGraphicsState()
            path.lineWidth = 0.8
            (color.blended(withFraction: 0.3, of: .black) ?? color).setStroke()
            path.stroke()
            return true
        }
    }
}
