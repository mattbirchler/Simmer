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

/// The gem as it appears in the menu bar.
@MainActor
enum MenuBarGem {
    /// Nothing is running.
    static let hollow = image(filled: false, tint: nil)
    /// At least one simulator is running.
    static let solid = image(filled: true, tint: nil)
    /// A simulator has been left on long enough to look forgotten.
    static let forgotten = image(filled: true, tint: .systemOrange)

    private static func image(filled: Bool, tint: NSColor?) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 16), flipped: false) { rect in
            let box = rect.insetBy(dx: 1.2, dy: 1)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: box.midX, y: box.maxY))
            path.line(to: NSPoint(x: box.minX, y: box.minY + box.height * 0.533))
            path.line(to: NSPoint(x: box.midX, y: box.minY))
            path.line(to: NSPoint(x: box.maxX, y: box.minY + box.height * 0.533))
            path.close()
            path.lineJoinStyle = .round
            path.lineWidth = 1.3
            (tint ?? .black).set()
            if filled { path.fill() }
            path.stroke()
            return true
        }
        // Without a tint, macOS colors it to suit the menu bar.
        image.isTemplate = tint == nil
        return image
    }
}
