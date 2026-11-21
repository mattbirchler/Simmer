import SwiftUI

@main
struct SimmerApp: App {
    @State private var monitor = SimulatorMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(monitor)
        } label: {
            // A gem: hollow when nothing is running, solid with a count
            // when something is, and orange once one looks forgotten.
            let count = monitor.simulators.count
            Group {
                if count > 0 {
                    Image(nsImage: monitor.hasForgotten ? MenuBarGem.forgotten : MenuBarGem.solid)
                    Text("\(count)")
                } else {
                    Image(nsImage: MenuBarGem.hollow)
                }
            }
            #if DEBUG
            .task {
                if let file = Snapshot.destination {
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
