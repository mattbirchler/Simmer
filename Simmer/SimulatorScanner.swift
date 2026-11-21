import Darwin
import Foundation

/// Finds running simulators by looking at the process list.
///
/// Every booted simulator has one `launchd_sim` process, started with the
/// path to a file inside the device's folder. Looking for those is far
/// cheaper than asking `simctl` every few seconds, and it also catches the
/// simulators Xcode boots on its own for previews and test runs.
enum SimulatorScanner {
    /// - Parameter known: Simulators from the last scan by process ID, so
    ///   their details aren't read from disk again.
    static func scan(known: [pid_t: Simulator] = [:]) -> [Simulator] {
        var found: [Simulator] = []
        for pid in allProcessIDs() where processName(pid) == "launchd_sim" {
            guard let started = startDate(of: pid) else { continue }
            if let existing = known[pid], existing.bootedAt == started {
                found.append(existing)
            } else {
                found.append(describe(pid: pid, started: started))
            }
        }
        return found.sorted { ($0.bootedAt, $0.id) < ($1.bootedAt, $1.id) }
    }

    /// Whether this process is still a simulator's launchd, checked before
    /// force-quitting it in case the process ID has been reused.
    static func isSimulator(_ pid: pid_t) -> Bool {
        processName(pid) == "launchd_sim"
    }

    private static func describe(pid: pid_t, started: Date) -> Simulator {
        if let path = arguments(of: pid).dropFirst().first(where: { $0.hasPrefix("/") }) {
            // The path is <device set>/<UDID>/data/var/run/launchd_bootstrap.plist.
            // Walk up until the folder holding the device's details.
            var folder = URL(fileURLWithPath: path).deletingLastPathComponent()
            while folder.path != "/" {
                if let details = deviceDetails(in: folder) {
                    let type = details["deviceType"] as? String ?? ""
                    return Simulator(
                        id: details["UDID"] as? String ?? folder.lastPathComponent,
                        pid: pid,
                        name: details["name"] as? String ?? "Simulator",
                        runtime: Simulator.runtimeName(from: details["runtime"] as? String ?? ""),
                        kind: Simulator.Kind(deviceType: type),
                        bootedAt: started,
                        deviceSet: folder.deletingLastPathComponent()
                    )
                }
                folder.deleteLastPathComponent()
            }
        }
        return Simulator(id: "pid-\(pid)", pid: pid, name: "Simulator", runtime: "",
                         kind: .other, bootedAt: started, deviceSet: nil)
    }

    private static func deviceDetails(in folder: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("device.plist")) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    private static func allProcessIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Room to spare for processes that start between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(max(0, Int(filled))))
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [UInt8](repeating: 0, count: 64)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    private static func startDate(of pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }

    /// The arguments a process was started with.
    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 4 else { return [] }

        // The buffer is: argument count, the executable's path, padding
        // zeros, then each argument ending in a zero.
        let count = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = 4
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        while arguments.count < Int(count), index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}
