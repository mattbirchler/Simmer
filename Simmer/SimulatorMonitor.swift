import AppKit
import Observation

/// Keeps the list of running simulators up to date and shuts them down.
@MainActor
@Observable
final class SimulatorMonitor {
    private(set) var simulators: [Simulator] = []
    /// Pictures of each simulator's screen, by simulator ID.
    private(set) var previews: [String: NSImage] = [:]
    /// Simulators that have been told to shut down and haven't gone yet.
    private(set) var shuttingDown: Set<String> = []
    /// Updated on every check so "running for" times stay current.
    private(set) var now = Date()

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var loadingPreviews: Set<String> = []

    init() {
        refresh()
        // Checking is a quick look at the process list, so doing it every
        // few seconds costs next to nothing. The tolerance lets macOS
        // bundle it with other wake-ups.
        let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Left on for two hours or more, which usually means forgotten.
    func isForgotten(_ simulator: Simulator) -> Bool {
        now.timeIntervalSince(simulator.bootedAt) >= 2 * 60 * 60
    }

    var hasForgotten: Bool { simulators.contains(where: isForgotten) }

    func refresh() {
        let known = Dictionary(simulators.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let found = SimulatorScanner.scan(known: known)
        if found != simulators {
            simulators = found
            let ids = Set(found.map(\.id))
            previews = previews.filter { ids.contains($0.key) }
            shuttingDown.formIntersection(ids)
        }
        now = Date()
    }

    /// Fetches a fresh picture of every simulator's screen. Called while the
    /// menu is open, never in the background.
    func loadPreviews() {
        for simulator in simulators
        where !shuttingDown.contains(simulator.id) && !loadingPreviews.contains(simulator.id) {
            loadingPreviews.insert(simulator.id)
            Task {
                let data = await SimulatorControl.screenshot(of: simulator)
                loadingPreviews.remove(simulator.id)
                guard let data, let image = NSImage(data: data),
                      simulators.contains(where: { $0.id == simulator.id }) else { return }
                previews[simulator.id] = image
            }
        }
    }

    func shutDown(_ simulator: Simulator) {
        guard !shuttingDown.contains(simulator.id) else { return }
        shuttingDown.insert(simulator.id)
        Task {
            let asked = await SimulatorControl.shutDown(simulator)
            if !asked { quit(simulator, signal: SIGTERM) }
            if await !waitUntilGone(simulator) {
                // Still there after a polite request: stop it outright.
                quit(simulator, signal: SIGKILL)
                _ = await waitUntilGone(simulator)
            }
            shuttingDown.remove(simulator.id)
        }
    }

    func shutDownAll() {
        simulators.forEach(shutDown)
    }

    private func quit(_ simulator: Simulator, signal: Int32) {
        guard SimulatorScanner.isSimulator(simulator.pid) else { return }
        kill(simulator.pid, signal)
    }

    private func waitUntilGone(_ simulator: Simulator) async -> Bool {
        for _ in 0..<20 {
            refresh()
            if !simulators.contains(where: { $0.pid == simulator.pid }) { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }
}
