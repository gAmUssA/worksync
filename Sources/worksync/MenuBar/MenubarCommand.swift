import AppKit
import ArgumentParser
import Foundation
import WorkSyncCore

struct Menubar: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run as a menu bar app: scheduler plus status panel."
    )

    @OptionGroup var configOption: ConfigOption

    func run() throws {
        // Validate before taking over the run loop, so a broken config fails
        // with a message instead of a menu bar icon that can do nothing.
        _ = loadConfigOrExit(path: configOption.config)
        MainActor.assumeIsolated {
            // ParsableCommand.run() is nonisolated, but this is the main
            // thread: the process has not started a run loop yet.
            MenubarApp.run(configPath: configOption.config)
        }
    }
}

/// Owns the NSApplication lifecycle explicitly.
///
/// Never `@main`/`@NSApplicationMain`: with no nib or storyboard those reach
/// `[NSApplication run]` without ever instantiating the delegate, so setup code
/// silently never executes and the app appears to start and do nothing
/// (SPEC §3.1 rule 3).
@MainActor
enum MenubarApp {
    private static var delegate: AppDelegate?

    static func run(configPath: String) {
        let app = NSApplication.shared
        let appDelegate = AppDelegate(configPath: configPath)
        delegate = appDelegate
        app.delegate = appDelegate
        // Accessory behavior comes from LSUIElement in Info.plist; setting the
        // policy here too would only add a Dock-icon flash (SPEC §3).
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configPath: String
    private var controller: StatusItemController?
    /// Held for the process lifetime. Releasing it early would let a second
    /// instance start while this one is still running.
    private var instanceLock: RunLock?

    init(configPath: String) {
        self.configPath = configPath
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard claimSingleInstance() else { return }

        let model = MenuBarModel(configPath: configPath)
        let controller = StatusItemController(model: model)
        self.controller = controller

        // Logged because the failure this guards against is silent: if the
        // delegate is never instantiated (SPEC §3.1 rule 3) the process runs
        // with no icon and no error, and the log is the only way to tell that
        // apart from "the icon is hidden behind a menu bar manager".
        let logger = Logger(level: (try? ConfigLoader.load(path: configPath).general.logLevel) ?? .info)
        logger.info("menubar started: status item visible=\(controller.hasStatusItemButton)")
    }

    /// Ensures exactly one menu bar instance. Two instances mean two status
    /// items, which looks like a bug in the app rather than in how it was
    /// started — and it is easy to reach, since `open WorkSync.app` and running
    /// the inner binary from a terminal are both normal things to do.
    ///
    /// Uses a kernel `flock` rather than looking for another running copy via
    /// LaunchServices: that snapshot can still list an instance that is midway
    /// through exiting, and deferring to a corpse leaves ZERO instances
    /// running. A flock is released by the kernel on exit, crash, or kill.
    private func claimSingleInstance() -> Bool {
        do {
            guard let lock = try RunLock.acquire(path: RunLock.instancePath) else {
                FileHandle.standardError.write(Data(
                    "WorkSync is already running; this copy will exit.\n".utf8
                ))
                NSApp.terminate(nil)
                // MUST return. terminate(_:) unwinds asynchronously and can be
                // cancelled, so execution continues past it — without this the
                // method goes on to create the second status item it exists to
                // prevent.
                return false
            }
            instanceLock = lock
            return true
        } catch {
            // The lock file itself could not be opened. Refusing to launch over
            // that would be worse than the duplicate it guards against, so
            // start anyway and say so.
            let message = "warning: could not take the single-instance lock"
                + " (\(error.localizedDescription)); a second copy could start.\n"
            FileHandle.standardError.write(Data(message.utf8))
            return true
        }
    }
}
