import SwiftUI

@main
struct SimmerApp: App {
    @State private var monitor = SimulatorMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(monitor)
        } label: {
            // A gem: hollow when nothing is running, and filled with a
            // count when something is, green through red as things worsen.
            let count = monitor.simulators.count
            Group {
                if count > 0 {
                    Image(nsImage: MenuBarGem.image(for: monitor.mood))
                    Text("\(count)")
                } else {
                    Image(nsImage: MenuBarGem.image(for: nil))
                }
            }
            #if DEBUG
            .task {
                if let file = Snapshot.gemsDestination {
                    Snapshot.saveGems(to: file)
                    NSApplication.shared.terminate(nil)
                } else if let file = Snapshot.destination {
                    await Snapshot.save(monitor, to: file)
                    NSApplication.shared.terminate(nil)
                } else if Snapshot.shutsDownAll {
                    await Snapshot.shutDownAll(monitor)
                    NSApplication.shared.terminate(nil)
                }
            }
            #endif
        }
        .menuBarExtraStyle(.window)
    }
}
