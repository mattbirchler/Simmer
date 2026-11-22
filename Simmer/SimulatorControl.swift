import Foundation

/// Talks to simulators through `xcrun simctl`, the tool that ships with Xcode.
enum SimulatorControl {
    private static let defaultDeviceSet = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Developer/CoreSimulator/Devices").standardizedFileURL

    /// Asks the simulator to shut down. Returns whether simctl reported success.
    static func shutDown(_ simulator: Simulator) async -> Bool {
        guard let base = simctl(for: simulator) else { return false }
        return await run(base + ["shutdown", simulator.id]) == 0
    }

    /// A JPEG of what's on the simulator's screen right now.
    static func screenshot(of simulator: Simulator) async -> Data? {
        guard let base = simctl(for: simulator) else { return nil }
        if let picture = await screenshot(of: simulator, display: nil, simctl: base) { return picture }
        // A folding iPhone has two screens, and simctl won't choose between
        // them. Take both: the one that's switched off comes back black,
        // which makes for a far smaller file, so keep the larger.
        var best: Data?
        for display in ["primary", "primary-1"] {
            if let picture = await screenshot(of: simulator, display: display, simctl: base),
               picture.count > best?.count ?? 0 {
                best = picture
            }
        }
        return best
    }

    private static func screenshot(of simulator: Simulator, display: String?, simctl base: [String]) async -> Data? {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("Simmer-\(simulator.id)-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: file) }
        var arguments = base + ["io", simulator.id, "screenshot", "--type=jpeg"]
        if let display { arguments.append("--display=\(display)") }
        guard await run(arguments + [file.path]) == 0 else { return nil }
        return try? Data(contentsOf: file)
    }

    /// The start of a simctl command that can reach this simulator. Ones
    /// outside the regular folder (previews, test runs) need it named.
    private static func simctl(for simulator: Simulator) -> [String]? {
        guard let set = simulator.deviceSet else { return nil }
        if set.standardizedFileURL == defaultDeviceSet { return ["simctl"] }
        return ["simctl", "--set", set.path]
    }

    private static func run(_ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }
    }
}
