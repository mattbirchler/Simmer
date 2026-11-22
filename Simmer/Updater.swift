import AppKit
import Observation
import Sparkle

/// Keeps Simmer up to date with Sparkle. It checks once a day. Because
/// Simmer lives in the menu bar, a new version found in the background
/// doesn't throw a window over whatever you're doing: it shows as a button
/// in the menu, and Sparkle's window opens when that's clicked.
@MainActor
@Observable
final class Updater: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    /// A newer version found by a background check that hasn't been looked
    /// at yet, such as "1.3".
    private(set) var availableVersion: String?
    /// False for development builds, which shouldn't replace themselves.
    let isEnabled: Bool

    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    override init() {
        #if DEBUG
        isEnabled = false
        #else
        isEnabled = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        #endif
        super.init()
        if isEnabled {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        }
    }

    /// Looks for a new version now and shows what it finds, or opens the
    /// update that's already waiting.
    func checkForUpdates() {
        // Simmer has no Dock icon, so bring it forward or the window can
        // open behind everything else.
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    // MARK: Quiet reminders

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle may show its window right away only when Simmer has just
    /// been opened. Otherwise the menu's button does the reminding.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if !handleShowingUpdate {
            availableVersion = update.displayVersionString
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
