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
    /// Bytes of memory each simulator holds, by simulator ID. Empty until
    /// the menu has been opened.
    private(set) var memory: [String: UInt64] = [:]
    /// Bytes of memory held by all running simulators together.
    var memoryInUse: UInt64 { memory.values.reduce(0, +) }
    /// Updated on every check so "running for" times stay current.
    private(set) var now = Date()

    /// Whether to post a notification when a simulator looks forgotten.
    private(set) var notifiesWhenForgotten = false

    @ObservationIgnored private let notifier = ForgottenNotifier()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var loadingPreviews: Set<String> = []

    /// The simulator that most recently stopped running, whoever stopped
    /// it, and when Simmer noticed. Remembered between launches.
    struct LastShutDown: Equatable {
        let name: String
        let date: Date
    }
    private(set) var lastShutDown: LastShutDown?

    private static let lastNameKey = "lastShutDownName"
    private static let lastDateKey = "lastShutDownDate"

    init() {
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: Self.lastNameKey),
           let date = defaults.object(forKey: Self.lastDateKey) as? Date {
            lastShutDown = LastShutDown(name: name, date: date)
        }
        notifiesWhenForgotten = notifier.isEnabled
        notifier.onShutDown = { [weak self] id in
            guard let self, let simulator = simulators.first(where: { $0.id == id }) else { return }
            shutDown(simulator)
        }
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

    /// How long this simulator has been left on, as a mood.
    func mood(of simulator: Simulator) -> Mood {
        Mood(runningFor: now.timeIntervalSince(simulator.bootedAt))
    }

    /// The worst mood among the running simulators, pushed further when the
    /// Mac is short of memory. Nil when nothing is running.
    var mood: Mood? {
        guard var worst = simulators.map(mood(of:)).max() else { return nil }
        switch memoryPressure {
        case .critical: worst = .neglected
        case .warning: worst = max(worst, .forgotten)
        case .normal: break
        }
        return worst
    }

    /// What macOS says about how tight memory is across the whole Mac.
    enum MemoryPressure { case normal, warning, critical }
    private(set) var memoryPressure = MemoryPressure.normal

    private static func readMemoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        // 1 is normal, 2 is a warning, 4 is critical.
        return level >= 4 ? .critical : level >= 2 ? .warning : .normal
    }

    /// Turning this on asks macOS for permission the first time, and it
    /// stays off if that's refused.
    func setNotifiesWhenForgotten(_ enabled: Bool) {
        notifiesWhenForgotten = enabled
        Task {
            notifiesWhenForgotten = await notifier.setEnabled(enabled)
            refresh()
        }
    }

    func refresh() {
        let known = Dictionary(simulators.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var found = SimulatorScanner.scan(known: known)
        #if DEBUG
        found = Snapshot.aged(found)
        #endif
        if found != simulators {
            let stillRunning = Set(found.map(\.pid))
            if let gone = simulators.last(where: { !stillRunning.contains($0.pid) }) {
                let last = LastShutDown(name: gone.name, date: Date())
                lastShutDown = last
                UserDefaults.standard.set(last.name, forKey: Self.lastNameKey)
                UserDefaults.standard.set(last.date, forKey: Self.lastDateKey)
            }
            simulators = found
            let ids = Set(found.map(\.id))
            previews = previews.filter { ids.contains($0.key) }
            memory = memory.filter { ids.contains($0.key) }
            shuttingDown.formIntersection(ids)
        }
        var date = Date()
        #if DEBUG
        date += Snapshot.pretendHours * 3600
        #endif
        now = date
        // One cheap system call, and only worth asking while something runs.
        let pressure = simulators.isEmpty ? MemoryPressure.normal : Self.readMemoryPressure()
        if pressure != memoryPressure { memoryPressure = pressure }

        #if DEBUG
        // Pictures taken for the README shouldn't set off notifications.
        if Snapshot.destination != nil { return }
        #endif
        notifier.update(simulators: simulators) { mood(of: $0) >= .forgotten }
    }

    /// Adds up the memory the running simulators hold. Called while the
    /// menu is open, never in the background.
    func loadMemory() {
        let held = SimulatorScanner.memory(of: Set(simulators.map(\.pid)))
        memory = Dictionary(simulators.compactMap { simulator in
            held[simulator.pid].map { (simulator.id, $0) }
        }, uniquingKeysWith: +)
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
