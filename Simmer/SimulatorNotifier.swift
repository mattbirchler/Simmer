import AppKit
@preconcurrency import UserNotifications

private let categoryID = "simulator"
private let shutDownActionID = "shutDown"
private let simulatorKey = "simulator"

/// Posts notifications about simulators, each with a button to shut the
/// simulator down. Both kinds are off until turned on from the gear menu.
@MainActor
final class SimulatorNotifier: NSObject, UNUserNotificationCenterDelegate {
    enum Kind: CaseIterable {
        /// A simulator has just started up.
        case started
        /// A simulator has been on long enough to look forgotten.
        case forgotten

        fileprivate var enabledKey: String {
            switch self {
            case .started: "notifiesWhenStarted"
            case .forgotten: "notifiesWhenForgotten"
            }
        }
    }

    /// Called with a simulator's ID when a notification's Shut Down button
    /// is clicked.
    var onShutDown: ((String) -> Void)?

    private var enabled: Set<Kind> = Set(Kind.allCases.filter { UserDefaults.standard.bool(forKey: $0.enabledKey) })
    /// The notifications sent for each simulator, by simulator ID, so each
    /// one is only announced once and can be cleared when it stops.
    private var sent: [Kind: [String: String]] = [:]
    /// The simulators already known to be running, as their start
    /// notifications' IDs. Nil until the first look, when whatever is
    /// already running isn't news.
    private var noticed: Set<String>?
    private let center = UNUserNotificationCenter.current()

    /// How long a simulator has to have been up before it's announced.
    /// Xcode starts the simulator a moment before it opens the Simulator
    /// app, and this gives the app time to appear.
    private static let settlingTime: TimeInterval = 5

    override init() {
        super.init()
        center.delegate = self
        let shutDown = UNNotificationAction(identifier: shutDownActionID, title: "Shut Down")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: categoryID, actions: [shutDown], intentIdentifiers: []),
        ])
    }

    func isEnabled(_ kind: Kind) -> Bool {
        enabled.contains(kind)
    }

    /// Turning one on asks macOS for permission the first time. Returns
    /// whether it ended up on, which it won't if permission was refused.
    func setEnabled(_ kind: Kind, _ isOn: Bool) async -> Bool {
        var allowed = isOn
        if isOn {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        if allowed {
            enabled.insert(kind)
        } else {
            enabled.remove(kind)
            center.removeDeliveredNotifications(withIdentifiers: Array((sent[kind] ?? [:]).values))
            sent[kind] = nil
        }
        UserDefaults.standard.set(allowed, forKey: kind.enabledKey)
        return allowed
    }

    /// Announces any simulator that has newly started or newly become
    /// forgotten, and clears the notifications of ones that have stopped.
    func update(simulators: [Simulator], now: Date, isForgotten: (Simulator) -> Bool) {
        let running = Set(simulators.map(\.id))
        for (kind, notifications) in sent {
            let stopped = notifications.filter { !running.contains($0.key) }
            guard !stopped.isEmpty else { continue }
            center.removeDeliveredNotifications(withIdentifiers: Array(stopped.values))
            stopped.keys.forEach { sent[kind]?[$0] = nil }
        }

        let starts = Set(simulators.map(Self.startID))
        var noticed = noticed ?? starts
        for simulator in simulators where !noticed.contains(Self.startID(of: simulator))
            && now.timeIntervalSince(simulator.bootedAt) >= Self.settlingTime {
            noticed.insert(Self.startID(of: simulator))
            guard isEnabled(.started) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(simulator.name) started"
            content.subtitle = simulator.runtime
            content.body = Self.startDetails(of: simulator, runningCount: simulators.count)
            post(content, id: Self.startID(of: simulator), kind: .started, for: simulator)
        }
        self.noticed = noticed.intersection(starts)

        guard isEnabled(.forgotten) else { return }
        for simulator in simulators where sent[.forgotten]?[simulator.id] == nil && isForgotten(simulator) {
            let content = UNMutableNotificationContent()
            content.title = "\(simulator.name) is still running"
            content.body = "It has been on for over two hours. Shut it down if you're done with it."
            let id = "forgotten-\(simulator.id)-\(Int(simulator.bootedAt.timeIntervalSince1970))"
            post(content, id: id, kind: .forgotten, for: simulator)
        }
    }

    private func post(_ content: UNMutableNotificationContent, id: String, kind: Kind, for simulator: Simulator) {
        content.categoryIdentifier = categoryID
        content.userInfo = [simulatorKey: simulator.id]
        sent[kind, default: [:]][simulator.id] = id
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// Different each time the same simulator is started.
    private static func startID(of simulator: Simulator) -> String {
        "started-\(simulator.id)-\(Int(simulator.bootedAt.timeIntervalSince1970))"
    }

    /// What's worth knowing about a simulator that just started: what
    /// started it, when that wasn't you, and how many are running now.
    private static func startDetails(of simulator: Simulator, runningCount: Int) -> String {
        var sentences: [String] = []
        switch simulator.origin {
        case "Xcode Previews": sentences.append("Started by Xcode Previews.")
        case "Test run": sentences.append("Started by a test run.")
        default:
            // Tools like simctl and xcodebuild start simulators without
            // the Simulator app, so there is no window to notice.
            if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iphonesimulator").isEmpty {
                sentences.append("Started in the background, with no Simulator window.")
            }
        }
        sentences.append(runningCount == 1 ? "It's the only simulator running."
                         : "\(runningCount) simulators are now running.")
        return sentences.joined(separator: " ")
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == shutDownActionID,
              let id = response.notification.request.content.userInfo[simulatorKey] as? String else { return }
        await MainActor.run { self.onShutDown?(id) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
