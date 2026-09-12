import AppKit
import Foundation
import ServiceManagement
import WorkSyncCore
import WorkSyncKit

/// A `Timer` behind the model's scheduling protocol.
private struct TimerAction: MenuBarScheduledAction {
    let timer: Timer

    func cancel() {
        timer.invalidate()
    }
}

extension MenuBarModel {
    /// The one place the app touches the system.
    ///
    /// Everything here was inline in the model until the model needed to be
    /// testable. The behaviour is unchanged — same paths, same defaults, same
    /// swallowed errors, same detached boundaries — it just has a name now, so
    /// a test can supply a different one.
    static func liveServices(configPath: String, logger: Logger, notifier: Notifier) -> MenuBarServices {
        MenuBarServices(
            configURL: { URL(fileURLWithPath: configPath) },
            loadConfig: { try ConfigLoader.load(path: configPath) },
            saveConfig: { config, origins in
                try ConfigWriter.save(config, to: configPath, sourceOrigins: origins)
            },
            loadLastRun: { LastRunStore.load(path: LastRunStore.path(forConfigAt: configPath)) },
            writePaused: { UserDefaults.standard.set($0, forKey: MenuBarModel.pausedKey) },
            log: { level, message in
                switch level {
                case .debug: logger.debug(message)
                case .info: logger.info(message)
                case .warn: logger.warn(message)
                case .error: logger.error(message)
                }
            },
            logURL: {
                URL(fileURLWithPath: (Logger.defaultDirectory as NSString)
                    .appendingPathComponent("worksync.log"))
            },
            loginItemStatus: { LoginItem.status },
            registerLoginItem: { try SMAppService.mainApp.register() },
            unregisterLoginItem: { try SMAppService.mainApp.unregister() },
            openLoginItemSettings: { SMAppService.openSystemSettingsLoginItems() },
            healthReport: {
                // Detached: shelling out to launchctl and codesign, plus the
                // EventKit calendar listing, must not block the panel.
                await Task.detached(priority: .userInitiated) {
                    DoctorChecks.run(DoctorFacts.gather(configPath: configPath))
                }.value
            },
            calendarChoices: {
                await Task.detached { () -> [CalendarRef] in
                    let store = EventKitStore()
                    guard (try? store.requestAccess()) != nil else { return [] }
                    return (try? store.calendars()) ?? []
                }.value
            },
            runPass: {
                // Off the main actor: EventKit work must not block the panel.
                await Task.detached(priority: .userInitiated) {
                    PassRunner.run(
                        configPath: configPath,
                        makeStore: { EventKitStore() },
                        logger: logger,
                        lastRunPath: LastRunStore.path(forConfigAt: configPath)
                    )
                }.value
            },
            notifier: notifier,
            makeChangeObserver: { EventKitChangeObserver() },
            now: { Date() },
            scheduleChange: { delay, action in
                TimerAction(timer: Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                    Task { @MainActor in action() }
                })
            },
            openURL: { NSWorkspace.shared.open($0) }
        )
    }

    /// The production composition: read what the model starts with, build the
    /// live services, then start the same refreshes the initializer used to
    /// start itself.
    static func live(configPath: String = ConfigLoader.defaultPath) -> MenuBarModel {
        let level = (try? ConfigLoader.load(path: configPath).general.logLevel) ?? .info
        let logger = Logger(level: level)
        let model = MenuBarModel(
            initialState: MenuBarInitialState(
                isPaused: UserDefaults.standard.bool(forKey: MenuBarModel.pausedKey),
                lastRun: LastRunStore.load(path: LastRunStore.path(forConfigAt: configPath)),
                savedSourceIDs: Set(
                    ((try? ConfigLoader.load(path: configPath))?.sources ?? []).map(\.id)
                )
            ),
            services: liveServices(
                configPath: configPath,
                logger: logger,
                notifier: UserNotifier(logger: Logger(level: level))
            )
        )
        model.startInitialRefreshes()
        return model
    }
}
