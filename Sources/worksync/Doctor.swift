import ArgumentParser
import Foundation
import ServiceManagement
import UserNotifications
import WorkSyncCore
import WorkSyncKit

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check everything that can quietly stop WorkSync from working.",
        discussion: """
        Read-only: doctor never prompts for permission, never writes, never \
        syncs, and never prints event titles or attendees — its output is safe \
        to paste into a bug report.

        Exit codes match the rest of the tool: 0 healthy, 1 config problem, \
        2 calendar permission, 3 something could not be checked. Warnings do \
        not change the exit code unless --strict is given.
        """
    )

    @OptionGroup var configOption: ConfigOption

    @Flag(name: .long, help: "Emit findings as JSON")
    var json = false

    @Flag(name: .shortAndLong, help: "Show detail for passing checks too")
    var verbose = false

    @Flag(name: .long, help: "Exit 1 on warnings as well as errors (for CI)")
    var strict = false

    func run() throws {
        let report = DoctorChecks.run(DoctorFacts.gather(configPath: configOption.config))

        if json {
            try print(report.json())
        } else {
            // STDOUT, so `worksync doctor | grep` works. brew doctor writes
            // everything to stderr and is ungreppable as a result.
            print(report.text(verbose: verbose))
        }
        Foundation.exit(report.exitCode(strict: strict))
    }
}

/// Collects what the checks need from the outside world.
///
/// Kept apart from `DoctorChecks` so the judgement stays a pure function: the
/// side of this that touches EventKit, launchd, and codesign cannot run in CI,
/// and the side that decides what is wrong must.
enum DoctorFacts {
    static func gather(configPath: String) -> DoctorInputs {
        let config = Result { try ConfigLoader.load(path: configPath) }
        let store = EventKitStore()
        // Reads the existing grant. Never requestAccess(), which prompts.
        let access = store.authorizationStatus()

        // Only when the answer can mean anything. Listing calendars under
        // write-only access returns a virtual calendar with no events, which
        // would make every downstream check confidently wrong.
        let calendars: Result<[CalendarRef], Error>? = access.canSync
            ? Result { try store.calendars() }
            : nil

        return DoctorInputs(
            configPath: configPath,
            config: config,
            access: access,
            calendars: calendars,
            scheduling: scheduling(),
            signing: signing(),
            notifications: notifications(config: try? config.get()),
            lastRun: LastRunStore.load(path: LastRunStore.path(forConfigAt: configPath)),
            logBytes: logBytes()
        )
    }

    // MARK: Scheduling

    private static func scheduling() -> SchedulingFacts {
        let status = LoginItem.status
        return SchedulingFacts(
            loginItemEnabled: status == .enabled,
            launchAgentLoaded: launchAgentLoaded(),
            menubar: menubarProbe(),
            // requiresApproval is the trap here: registration succeeded, so
            // every other signal looks like success, and nothing ever runs.
            loginItemDetail: status == .enabled ? nil : "login item: \(LoginItem.describe(status))"
        )
    }

    /// Asks launchd what is actually loaded rather than trusting the plist on
    /// disk: a file left behind by a failed bootstrap looks identical to a
    /// working install.
    private static func launchAgentLoaded() -> Bool {
        shell(["/bin/launchctl", "print", "gui/\(getuid())/io.gamov.worksync"]) == 0
    }

    /// A menu bar app holds the instance lock for its whole life, so failing
    /// to take it means one is running. Cheaper and more accurate than
    /// scanning the process list, which also matches this very command.
    private static func menubarProbe() -> MenubarProbe {
        do {
            guard let lock = try RunLock.acquire(path: RunLock.instancePath) else { return .running }
            // Taken and released immediately: doctor must not keep a lock that
            // would then block the app it just reported as absent.
            lock.unlock()
            return .notRunning
        } catch {
            // Reported as unknown, never as running. `RunLock.acquire` returns
            // nil for contention and throws only when the lock file could not
            // be opened at all, so this branch means the environment is
            // broken — exactly when a false all-clear does the most damage.
            return .unknown(error.localizedDescription)
        }
    }

    // MARK: Code signature

    private static func signing() -> SigningFacts {
        let bundlePath = Bundle.main.bundlePath
        guard let output = shellOutput([
            "/usr/bin/codesign", "-d", "--requirements", "-", bundlePath,
        ]) else {
            return SigningFacts()
        }
        // codesign writes the requirement to stderr as `designated => <req>`.
        guard let range = output.range(of: "designated =>") else { return SigningFacts() }
        let requirement = output[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SigningFacts(designatedRequirement: requirement.isEmpty ? nil : requirement)
    }

    // MARK: Notifications

    private static func notifications(config: Config?) -> NotificationFacts {
        guard let config, config.general.notify != .off else { return .notApplicable }

        // Only the menu bar app posts notifications (SPEC §4.1). Invoked
        // through a symlink on PATH — which is how Homebrew installs the CLI,
        // and how the README tells everyone else to — this process is not
        // inside the bundle, so the notification centre reports every setting
        // as unsupported. Warning about that would fire on every healthy
        // machine that uses the CLI, which is the one thing these checks may
        // not do; and it would be describing a capability the CLI never uses.
        guard Bundle.main.bundlePath.hasSuffix(".app") else {
            return .unavailable("only checkable from the app; the CLI does not post notifications")
        }

        guard Bundle.main.bundleIdentifier != nil else {
            // No bundle identifier means UNUserNotificationCenter.current()
            // traps rather than returning an error (SPEC §3.1 rule 2).
            return .unsupported
        }

        let semaphore = DispatchSemaphore(value: 0)
        var facts: NotificationFacts = .unavailable("notification settings did not answer in time")
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            facts = interpret(settings)
            semaphore.signal()
        }
        // Bounded: a diagnostic that hangs is worse than one that reports it
        // could not tell.
        if semaphore.wait(timeout: .now() + 3) == .timedOut {
            return .unavailable("notification settings did not answer in time")
        }
        return facts
    }

    private static func interpret(_ settings: UNNotificationSettings) -> NotificationFacts {
        // Every individual setting reading NotSupported is the signature of a
        // bundle macOS is not treating as an app — mis-assembled, or launched
        // by path instead of through LaunchServices.
        let allUnsupported = [
            settings.alertSetting, settings.badgeSetting, settings.soundSetting,
            settings.notificationCenterSetting, settings.lockScreenSetting,
        ].allSatisfy { $0 == .notSupported }
        if allUnsupported {
            return .unsupported
        }

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable("unrecognized notification authorization status")
        }
    }

    // MARK: Log

    private static func logBytes() -> Int? {
        let path = (Logger.defaultDirectory as NSString).appendingPathComponent("worksync.log")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int else { return nil }
        return size
    }
}

/// Runs a command and returns its combined output, or nil if it could not run.
///
/// Separate from `shell(_:)` because `codesign` writes the requirement it is
/// asked for to stderr, so discarding output is not an option here.
private func shellOutput(_ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: arguments[0])
    process.arguments = Array(arguments.dropFirst())
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        // Read before waiting: a full pipe buffer would deadlock the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    } catch {
        return nil
    }
}
