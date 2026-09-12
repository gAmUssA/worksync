import Foundation
import ServiceManagement
import WorkSyncCore
import WorkSyncKit
import XCTest
@testable import worksync

/// What the fake services were asked to do.
///
/// A recording, not a policy. Nothing here decides whether a rename is allowed,
/// which source owns a draft, or whether a save proceeds — those stay in the
/// model under test. A fake that answered them would be the hand-written mirror
/// this target exists to delete.
@MainActor
final class MenuBarRecorder {
    // What the services return.
    var config: Config?
    var configError: Error?
    var saveOutcome: ConfigWriteOutcome = .preserved
    var saveError: Error?
    var calendars: [CalendarRef] = []
    var health = DoctorReport(findings: [])
    var passOutcome = PassOutcome(disposition: .completed, result: nil, diagnostics: nil)
    var loginStatus: SMAppService.Status = .notRegistered
    var loginError: Error?
    var fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

    // What they were asked.
    private(set) var savedConfigs: [(config: Config, origins: [String: String])] = []
    private(set) var openedURLs: [URL] = []
    private(set) var pausedWrites: [Bool] = []
    private(set) var loginCommands: [String] = []
    private(set) var logLines: [String] = []
    private(set) var notifications: [PassNotification] = []
    private(set) var scheduledDelays: [TimeInterval] = []
    private(set) var passRuns = 0
    private(set) var healthRuns = 0
    private(set) var calendarLookups = 0

    /// The change-debounce action, fired by hand rather than by waiting.
    private(set) var scheduledAction: (@MainActor () -> Void)?
    private(set) var cancelledSchedules = 0

    func record(_ notification: PassNotification) {
        notifications.append(notification)
    }

    func fireScheduledAction() {
        let action = scheduledAction
        scheduledAction = nil
        action?()
    }

    fileprivate func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        scheduledDelays.append(delay)
        scheduledAction = action
    }

    fileprivate func cancelSchedule() {
        cancelledSchedules += 1
        scheduledAction = nil
    }

    fileprivate func noteSave(_ config: Config, _ origins: [String: String]) {
        savedConfigs.append((config, origins))
    }

    fileprivate func note(url: URL) {
        openedURLs.append(url)
    }

    fileprivate func note(paused: Bool) {
        pausedWrites.append(paused)
    }

    fileprivate func note(login command: String) {
        loginCommands.append(command)
    }

    fileprivate func note(log line: String) {
        logLines.append(line)
    }

    fileprivate func notePass() {
        passRuns += 1
    }

    fileprivate func noteHealth() {
        healthRuns += 1
    }

    fileprivate func noteCalendars() {
        calendarLookups += 1
    }
}

private struct RecordedSchedule: MenuBarScheduledAction {
    let recorder: MenuBarRecorder

    func cancel() {
        MainActor.assumeIsolated { recorder.cancelSchedule() }
    }
}

/// A `Notifier` that keeps what it was given instead of posting it.
final class RecordingNotifier: Notifier, @unchecked Sendable {
    private let recorder: MenuBarRecorder

    init(recorder: MenuBarRecorder) {
        self.recorder = recorder
    }

    func post(_ notification: PassNotification) {
        MainActor.assumeIsolated { recorder.record(notification) }
    }
}

/// A calendar-change observer that records instead of subscribing to EventKit.
@MainActor
final class FakeChangeObserver: CalendarChangeObserver {
    private(set) var started = 0
    private(set) var stopped = 0
    private var onChange: (() -> Void)?

    nonisolated init() {}

    nonisolated func start(onChange: @escaping () -> Void) {
        MainActor.assumeIsolated {
            started += 1
            self.onChange = onChange
        }
    }

    nonisolated func stop() {
        MainActor.assumeIsolated {
            stopped += 1
            onChange = nil
        }
    }

    func fire() {
        onChange?()
    }
}

@MainActor
enum MenuBarFixture {
    /// Services that fail the test if anything calls them.
    ///
    /// The inert initializer must call none of them: that is what makes a model
    /// safe to build on a fresh machine and in CI.
    static func failOnCall(file: StaticString = #filePath, line: UInt = #line) -> MenuBarServices {
        func fail<T>(_ name: String, _ value: T) -> T {
            XCTFail("constructing the model called \(name)", file: file, line: line)
            return value
        }
        return MenuBarServices(
            configURL: { fail("configURL", URL(fileURLWithPath: "/dev/null")) },
            loadConfig: { fail("loadConfig", nil) ?? Self.emptyConfig },
            saveConfig: { _, _ in fail("saveConfig", ConfigWriteOutcome.preserved) },
            loadLastRun: { fail("loadLastRun", nil) },
            writePaused: { _ in _ = fail("writePaused", ()) },
            log: { _, _ in _ = fail("log", ()) },
            logURL: { fail("logURL", URL(fileURLWithPath: "/dev/null")) },
            loginItemStatus: { fail("loginItemStatus", SMAppService.Status.notRegistered) },
            registerLoginItem: { _ = fail("registerLoginItem", ()) },
            unregisterLoginItem: { _ = fail("unregisterLoginItem", ()) },
            openLoginItemSettings: { _ = fail("openLoginItemSettings", ()) },
            healthReport: { fail("healthReport", DoctorReport(findings: [])) },
            calendarChoices: { fail("calendarChoices", []) },
            runPass: { fail("runPass", PassOutcome(disposition: .completed, result: nil, diagnostics: nil)) },
            notifier: FailingNotifier(file: file, line: line),
            makeChangeObserver: { fail("makeChangeObserver", FakeChangeObserver()) },
            now: { fail("now", Date(timeIntervalSince1970: 0)) },
            scheduleChange: { _, _ in fail("scheduleChange", NoSchedule()) },
            openURL: { _ in _ = fail("openURL", ()) }
        )
    }

    /// Services backed by `recorder`. Every operation is fake and none of them
    /// touches the machine: no EventKit, no UserDefaults, no log directory, no
    /// `SMAppService`, no timers.
    static func services(
        recorder: MenuBarRecorder,
        observer: FakeChangeObserver? = nil
    ) -> MenuBarServices {
        let observer = observer ?? FakeChangeObserver()
        return
            MenuBarServices(
                configURL: { URL(fileURLWithPath: "/fixture/config.toml") },
                loadConfig: {
                    if let error = recorder.configError {
                        throw error
                    }
                    guard let config = recorder.config else { throw ConfigError.emptySourceID }
                    return config
                },
                saveConfig: { config, origins in
                    recorder.noteSave(config, origins)
                    if let error = recorder.saveError {
                        throw error
                    }
                    return recorder.saveOutcome
                },
                loadLastRun: { nil },
                writePaused: { recorder.note(paused: $0) },
                log: { _, message in recorder.note(log: message) },
                logURL: { URL(fileURLWithPath: "/fixture/worksync.log") },
                loginItemStatus: { recorder.loginStatus },
                registerLoginItem: {
                    recorder.note(login: "register")
                    if let error = recorder.loginError {
                        throw error
                    }
                },
                unregisterLoginItem: {
                    recorder.note(login: "unregister")
                    if let error = recorder.loginError {
                        throw error
                    }
                },
                openLoginItemSettings: { recorder.note(login: "openSettings") },
                healthReport: {
                    await MainActor.run { recorder.noteHealth() }
                    return await MainActor.run { recorder.health }
                },
                calendarChoices: {
                    await MainActor.run { recorder.noteCalendars() }
                    return await MainActor.run { recorder.calendars }
                },
                runPass: {
                    await MainActor.run { recorder.notePass() }
                    return await MainActor.run { recorder.passOutcome }
                },
                notifier: RecordingNotifier(recorder: recorder),
                makeChangeObserver: { observer },
                now: { recorder.fixedNow },
                scheduleChange: { delay, action in
                    recorder.schedule(delay, action)
                    return RecordedSchedule(recorder: recorder)
                },
                openURL: { recorder.note(url: $0) }
            )
    }

    /// A model with the given config already loadable, nothing started.
    static func model(
        config: Config? = nil,
        calendars: [CalendarRef] = [],
        savedSourceIDs: Set<String> = [],
        recorder: MenuBarRecorder? = nil,
        observer: FakeChangeObserver? = nil
    ) -> (model: MenuBarModel, recorder: MenuBarRecorder, observer: FakeChangeObserver) {
        let recorder = recorder ?? MenuBarRecorder()
        let observer = observer ?? FakeChangeObserver()
        recorder.config = config
        recorder.calendars = calendars
        let model = MenuBarModel(
            initialState: MenuBarInitialState(
                isPaused: false, lastRun: nil, savedSourceIDs: savedSourceIDs
            ),
            services: services(recorder: recorder, observer: observer)
        )
        return (model, recorder, observer)
    }

    /// Opens the settings screen and waits for the calendar list the form asks
    /// for, so a test sees the state the user would.
    static func opened(
        config: Config,
        calendars: [CalendarRef] = [],
        savedSourceIDs: Set<String> = []
    ) async -> (model: MenuBarModel, recorder: MenuBarRecorder, observer: FakeChangeObserver) {
        let made = model(
            config: config, calendars: calendars, savedSourceIDs: savedSourceIDs
        )
        made.model.openSettings()
        await made.model.calendarChoicesTask?.value
        return made
    }

    static let emptyConfig = Config(
        general: GeneralConfig(), target: TargetConfig(account: "Work", calendar: "Calendar"), sources: []
    )

    /// Two documented sources, the shape most of these tests need.
    static func twoSources() throws -> Config {
        try ConfigLoader.parse("""
        [target]
        account = "Work"
        calendar = "Calendar"

        [[source]]
        id = "personal"
        account = "iCloud"
        calendar = "Personal"
        title_matches = ["1:1"]

        [[source]]
        id = "travel"
        account = "Google"
        calendar = "Travel"
        title_matches = ["flight", "hotel"]
        """)
    }
}

private struct NoSchedule: MenuBarScheduledAction {
    func cancel() {}
}

private final class FailingNotifier: Notifier, @unchecked Sendable {
    let file: StaticString
    let line: UInt

    init(file: StaticString, line: UInt) {
        self.file = file
        self.line = line
    }

    func post(_: PassNotification) {
        XCTFail("constructing the model posted a notification", file: file, line: line)
    }
}
