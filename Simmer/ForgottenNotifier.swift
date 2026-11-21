import Foundation
@preconcurrency import UserNotifications

private let enabledKey = "notifiesWhenForgotten"
private let categoryID = "forgotten"
private let shutDownActionID = "shutDown"
private let simulatorKey = "simulator"

/// Posts a notification when a simulator has been on long enough to look
/// forgotten, with a button to shut it down. Off until it's turned on from
/// the gear menu.
@MainActor
final class ForgottenNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called with a simulator's ID when a notification's Shut Down button
    /// is clicked.
    var onShutDown: ((String) -> Void)?

    private(set) var isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    /// The notification sent for each simulator, by simulator ID, so each
    /// one is only announced once and can be cleared when it stops.
    private var sent: [String: String] = [:]
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        let shutDown = UNNotificationAction(identifier: shutDownActionID, title: "Shut Down")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: categoryID, actions: [shutDown], intentIdentifiers: []),
        ])
    }

    /// Turning it on asks macOS for permission the first time. Returns
    /// whether it ended up on, which it won't if permission was refused.
    func setEnabled(_ enabled: Bool) async -> Bool {
        var allowed = enabled
        if enabled {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        isEnabled = allowed
        UserDefaults.standard.set(allowed, forKey: enabledKey)
        if !allowed {
            center.removeDeliveredNotifications(withIdentifiers: Array(sent.values))
            sent = [:]
        }
        return allowed
    }

    /// Announces any simulator that has newly become forgotten, and clears
    /// the notifications of ones that have stopped.
    func update(simulators: [Simulator], isForgotten: (Simulator) -> Bool) {
        let running = Set(simulators.map(\.id))
        let stopped = sent.filter { !running.contains($0.key) }
        if !stopped.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: Array(stopped.values))
            stopped.keys.forEach { sent[$0] = nil }
        }

        guard isEnabled else { return }
        for simulator in simulators where sent[simulator.id] == nil && isForgotten(simulator) {
            let content = UNMutableNotificationContent()
            content.title = "\(simulator.name) is still running"
            content.body = "It has been on for over two hours. Shut it down if you're done with it."
            content.categoryIdentifier = categoryID
            content.userInfo = [simulatorKey: simulator.id]
            let id = "forgotten-\(simulator.id)-\(Int(simulator.bootedAt.timeIntervalSince1970))"
            sent[simulator.id] = id
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
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
