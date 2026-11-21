#if DEBUG
import AppKit
import SwiftUI

/// Saves a picture of the menu to a file, for the README and for checking
/// layout changes without clicking around. Debug builds only:
///
///     Simmer.app/Contents/MacOS/Simmer --snapshot menu.png
@MainActor
enum Snapshot {
    /// The file to write, when the app was started with `--snapshot <file>`.
    static var destination: URL? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot"), flag + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[flag + 1])
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
        view.layoutSubtreeIfNeeded()

        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: image)
        try? image.representation(using: .png, properties: [:])?.write(to: file)
    }
}
#endif
