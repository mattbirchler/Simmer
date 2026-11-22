#if DEBUG
import AppKit
import SwiftUI

/// Saves a picture of the menu to a file, for the README and for checking
/// layout changes without clicking around. Debug builds only:
///
///     Simmer.app/Contents/MacOS/Simmer --snapshot menu.png
///
/// Add `--dark` for the dark appearance, and `--pretend-hours 3` or
/// `--pretend-ages 0,1.5,3` to make simulators look like they have been
/// running for longer.
@MainActor
enum Snapshot {
    /// The file to write, when the app was started with `--snapshot <file>`.
    static var destination: URL? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot"), flag + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[flag + 1])
    }

    /// Hours to add to the clock, from `--pretend-hours <n>`, to see how
    /// long-running simulators look without waiting.
    static let pretendHours: Double = {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--pretend-hours"), flag + 1 < arguments.count else { return 0 }
        return Double(arguments[flag + 1]) ?? 0
    }()

    /// Extra hours for each simulator in turn, from `--pretend-ages 0,1.5,3`,
    /// so one picture can show simulators of different ages.
    static let pretendAges: [Double] = {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--pretend-ages"), flag + 1 < arguments.count else { return [] }
        return arguments[flag + 1].split(separator: ",").compactMap { Double($0) }
    }()

    /// The simulators with their start times moved back by `pretendAges`.
    static func aged(_ simulators: [Simulator]) -> [Simulator] {
        guard !pretendAges.isEmpty else { return simulators }
        return simulators.enumerated().map { index, simulator in
            guard index < pretendAges.count else { return simulator }
            return Simulator(id: simulator.id, pid: simulator.pid, name: simulator.name, runtime: simulator.runtime,
                             kind: simulator.kind, bootedAt: simulator.bootedAt - pretendAges[index] * 3600,
                             deviceSet: simulator.deviceSet)
        }
    }

    /// Whether to take the picture in the dark appearance, from `--dark`.
    static var isDark: Bool { CommandLine.arguments.contains("--dark") }

    /// The file to write the menu bar gems to, from `--gems <file>`.
    static var gemsDestination: URL? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--gems"), flag + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[flag + 1])
    }

    /// Every menu bar gem, enlarged, on a light and a dark strip.
    static func saveGems(to file: URL) {
        let moods: [Mood?] = [nil] + Mood.allCases.map { $0 }
        let scale: CGFloat = 6
        let cell = NSSize(width: 12 * scale + 24, height: 16 * scale + 24)
        let image = NSImage(size: NSSize(width: cell.width * CGFloat(moods.count), height: cell.height * 2), flipped: false) { rect in
            for (row, background) in [NSColor(white: 0.93, alpha: 1), NSColor(white: 0.16, alpha: 1)].enumerated() {
                background.setFill()
                NSRect(x: 0, y: cell.height * CGFloat(row), width: rect.width, height: cell.height).fill()
                for (column, mood) in moods.enumerated() {
                    let original = MenuBarGem.image(for: mood)
                    var gem = original
                    if original.isTemplate {
                        // Stand in for what the menu bar does to templates.
                        gem = NSImage(size: original.size, flipped: false) { area in
                            original.draw(in: area)
                            (row == 0 ? NSColor.black : NSColor.white).set()
                            area.fill(using: .sourceAtop)
                            return true
                        }
                    }
                    gem.draw(in: NSRect(x: cell.width * CGFloat(column) + 12, y: cell.height * CGFloat(row) + 12,
                                        width: 12 * scale, height: 16 * scale))
                }
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
    }

    /// Whether the app was started with `--shut-down-all`, which shuts down
    /// every simulator the same way the menu's button does, then quits.
    static var shutsDownAll: Bool { CommandLine.arguments.contains("--shut-down-all") }

    static func shutDownAll(_ monitor: SimulatorMonitor) async {
        monitor.refresh()
        print("Shutting down \(monitor.simulators.map(\.name))")
        monitor.shutDownAll()
        while !monitor.simulators.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
        }
        print("All simulators are shut down")
    }

    static func save(_ monitor: SimulatorMonitor, to file: URL) async {
        monitor.refresh()
        monitor.loadMemory()
        monitor.loadPreviews()
        // Give the screen pictures a moment to come back.
        for _ in 0..<40 where monitor.previews.count < monitor.simulators.count {
            try? await Task.sleep(for: .milliseconds(250))
        }

        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let view = NSHostingView(rootView: MenuView()
            .environment(monitor)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(shape)
            .overlay(shape.strokeBorder(.primary.opacity(0.15), lineWidth: 1)))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: view.fittingSize),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        if isDark {
            window.appearance = NSAppearance(named: .darkAqua)
        }
        view.layoutSubtreeIfNeeded()

        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: image)
        try? image.representation(using: .png, properties: [:])?.write(to: file)
    }
}
#endif
