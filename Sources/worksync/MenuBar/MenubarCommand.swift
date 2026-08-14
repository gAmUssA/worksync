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

    init(configPath: String) {
        self.configPath = configPath
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
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
}
