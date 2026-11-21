import AppKit
import SwiftUI

/// How much attention a simulator wants, shown by the gem's color. Like the
/// gem in the game Simmer nods to, greener is better.
enum Mood: Int, Comparable, CaseIterable {
    /// Started within the hour.
    case fresh
    /// On for an hour or more.
    case lingering
    /// On for two hours or more, which usually means forgotten.
    case forgotten
    /// On for a day or more.
    case neglected

    init(runningFor seconds: TimeInterval) {
        switch seconds {
        case ..<3600: self = .fresh
        case ..<7200: self = .lingering
        case ..<86400: self = .forgotten
        default: self = .neglected
        }
    }

    static func < (left: Mood, right: Mood) -> Bool { left.rawValue < right.rawValue }

    var nsColor: NSColor {
        switch self {
        case .fresh: .systemGreen
        case .lingering: .systemYellow
        case .forgotten: .systemOrange
        case .neglected: .systemRed
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// Read out by VoiceOver, so the color isn't the only way to tell.
    var spoken: String {
        switch self {
        case .fresh: "started recently"
        case .lingering: "on for over an hour"
        case .forgotten: "probably forgotten"
        case .neglected: "on for over a day"
        }
    }
}
