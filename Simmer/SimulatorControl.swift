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
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("Simmer-\(simulator.id)-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: file) }
        guard await run(base + ["io", simulator.id, "screenshot", "--type=jpeg", file.path]) == 0 else { return nil }
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
