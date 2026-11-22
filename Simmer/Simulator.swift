import Foundation

/// One running simulator, as found in the process list.
struct Simulator: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case phone, tablet, watch, tv, vision, other

        /// The SF Symbol shown until a picture of the screen arrives.
        var symbol: String {
            switch self {
            case .phone: "iphone"
            case .tablet: "ipad"
            case .watch: "applewatch"
            case .tv: "appletv"
            case .vision: "visionpro"
            case .other: "macwindow"
            }
        }

        init(deviceType: String) {
            let type = deviceType.lowercased()
            if type.contains("iphone") || type.contains("ipod") {
                self = .phone
            } else if type.contains("ipad") {
                self = .tablet
            } else if type.contains("watch") {
                self = .watch
            } else if type.contains("apple-tv") {
                self = .tv
            } else if type.contains("vision") {
                self = .vision
            } else {
                self = .other
            }
        }
    }

    /// The device's UDID, or a stand-in built from the process ID when the
    /// device's details couldn't be read.
    let id: String
    /// The simulator's own launchd, the parent of everything running in it.
    let pid: pid_t
    let name: String
    /// For example "iOS 27.2". Empty when unknown.
    let runtime: String
    let kind: Kind
    let bootedAt: Date
    /// The folder of devices this one belongs to. Nil when the device's
    /// details couldn't be read, in which case simctl can't address it.
    let deviceSet: URL?

    /// Where the simulator came from, when it isn't one of the regular ones
    /// listed in Xcode. These are the easiest to forget about.
    var origin: String? {
        guard let path = deviceSet?.path else { return nil }
        if path.contains("/Previews/") { return "Xcode Previews" }
        if path.contains("/XCTestDevices") { return "Test run" }
        return nil
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-27-2" becomes "iOS 27.2".
    /// Some runtimes are built for one device and say so after the version,
    /// as in "iOS-27-2-iPhone19-4". That part is left off.
    static func runtimeName(from identifier: String) -> String {
        guard let last = identifier.split(separator: ".").last else { return "" }
        var parts = last.split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return "" }
        var system = parts.removeFirst()
        if system == "xrOS" { system = "visionOS" }
        let version = parts.prefix { $0.allSatisfy(\.isNumber) }
        return version.isEmpty ? system : system + " " + version.joined(separator: ".")
    }
}
