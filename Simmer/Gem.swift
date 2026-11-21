import AppKit
import SwiftUI

/// The corners of the gem from Simmer's app icon, fitted to a rectangle.
private struct GemCorners {
    let top, bottom, left, right, front: CGPoint

    init(in rect: CGRect) {
        top = CGPoint(x: rect.midX, y: rect.minY)
        bottom = CGPoint(x: rect.midX, y: rect.maxY)
        left = CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.467)
        right = CGPoint(x: rect.maxX, y: left.y)
        front = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.533)
    }
}

/// The gem lit up, in the four greens of the app icon.
struct GemFacets: View {
    var body: some View {
        Canvas { context, size in
            let gem = GemCorners(in: CGRect(origin: .zero, size: size))
            let facets: [([CGPoint], Color)] = [
                ([gem.top, gem.left, gem.front], Color(red: 0.71, green: 0.97, blue: 0.56)),
                ([gem.top, gem.front, gem.right], Color(red: 0.37, green: 0.85, blue: 0.29)),
                ([gem.left, gem.bottom, gem.front], Color(red: 0.20, green: 0.71, blue: 0.25)),
                ([gem.front, gem.bottom, gem.right], Color(red: 0.10, green: 0.53, blue: 0.20)),
            ]
            for (points, color) in facets {
                var path = Path()
                path.addLines(points)
                path.closeSubpath()
                context.fill(path, with: .color(color))
            }
        }
    }
}

/// The gem as an outline with its facet lines. Shown unlit in the menu
/// when nothing is running.
struct GemOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let gem = GemCorners(in: rect)
        let (top, bottom, left, right, front) = (gem.top, gem.bottom, gem.left, gem.right, gem.front)

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
