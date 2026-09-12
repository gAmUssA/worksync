import Foundation
import ServiceManagement
import WorkSyncCore
import WorkSyncKit

/// The state the model starts with, read before it is built.
///
/// Values, not lookups: nothing in here reads a file, a default, or the system,
/// so constructing a model cannot touch the machine it runs on.
@MainActor
struct MenuBarInitialState {
    var isPaused: Bool
    var lastRun: LastRun?
    var savedSourceIDs: Set<String>
}

/// Something scheduled to happen later that can be called off.
///
/// The model arms one of these for the change-driven debounce. In production it
/// is a `Timer`; a test fires it by hand rather than waiting.
protocol MenuBarScheduledAction {
    func cancel()
}

/// Every effect the model has on the world outside itself.
///
/// Closures rather than a protocol per call: there is one production
/// composition (`MenuBarModel.live`) and one test composition, and the model's
/// own decisions stay in the model. Nothing here decides anything — no operation
/// says whether a rename is allowed, which source owns a draft, or whether a
/// save proceeds. A fake that answered those would be the mirror this target
/// exists to delete.
///
/// No default values. A service that defaulted to the live one would make the
/// unsafe composition the easy one to get by accident, which is how a unit test
/// ends up prompting for calendar access.
@MainActor
struct MenuBarServices {
    // Config persistence
    var configURL: () -> URL
    var loadConfig: () throws -> Config
    var saveConfig: (Config, [String: String]) throws -> ConfigWriteOutcome

    // Display persistence
    var loadLastRun: () -> LastRun?
    var writePaused: (Bool) -> Void

    // Logging
    var log: (LogLevel, String) -> Void
    var logURL: () -> URL

    // Login item
    var loginItemStatus: () -> SMAppService.Status
    var registerLoginItem: () throws -> Void
    var unregisterLoginItem: () throws -> Void
    var openLoginItemSettings: () -> Void

    // Asynchronous work, each owning its own off-main execution
    var healthReport: () async -> DoctorReport
    var calendarChoices: () async -> [CalendarRef]
    var runPass: () async -> PassOutcome

    // Notifications and change observation
    var notifier: Notifier
    var makeChangeObserver: () -> CalendarChangeObserver

    // Time and scheduling
    var now: () -> Date
    var scheduleChange: (TimeInterval, @escaping @MainActor () -> Void) -> MenuBarScheduledAction

    /// Opening things outside the app
    var openURL: (URL) -> Void
}
