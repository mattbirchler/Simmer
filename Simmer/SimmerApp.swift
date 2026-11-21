import SwiftUI

@main
struct SimmerApp: App {
    @State private var monitor = SimulatorMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(monitor)
        } label: {
            // A phone, with the number of running simulators beside it
            // whenever there are any.
            let count = monitor.simulators.count
            if count > 0 {
                Image(systemName: "iphone")
                Text("\(count)")
            } else {
                Image(systemName: "iphone")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
