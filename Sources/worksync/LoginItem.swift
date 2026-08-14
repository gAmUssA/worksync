import ArgumentParser
import Foundation
import ServiceManagement
import WorkSyncCore

/// Launch at login.
///
/// `SMAppService.mainApp` is the modern path and needs a real app bundle —
/// a second independent reason the bundle exists (SPEC §10). Status is always
/// re-read from the system rather than cached: the user can remove the item in
/// System Settings at any time, and a cached bool would report a lie.
enum LoginItem {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: "enabled"
        case .requiresApproval: "waiting for your approval in System Settings > General > Login Items"
        case .notRegistered: "not registered"
        case .notFound: "not found (is the app in its final location?)"
        @unknown default: "unknown"
        }
    }

    static let headlessPlistPath = NSString(string: "~/Library/LaunchAgents/io.gamov.worksync.plist")
        .expandingTildeInPath
}

struct InstallAgent: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-agent",
        abstract: "Launch WorkSync at login.",
        discussion: """
        By default this registers the app itself as a login item, which starts \
        the menu bar app. Use --headless to install a launchd agent that runs \
        the one-shot CLI on a timer instead, with no menu bar icon.
        """
    )

    @OptionGroup var configOption: ConfigOption

    @Flag(name: .long, help: "Install a headless launchd agent instead of the menu bar login item")
    var headless = false

    func run() throws {
        let config = loadConfigOrExit(path: configOption.config)

        if headless {
            try installHeadless(intervalMinutes: config.general.intervalMinutes)
            return
        }

        do {
            try SMAppService.mainApp.register()
        } catch {
            fail("could not register the login item: \(error.localizedDescription)", ExitCodes.partialFailure)
        }

        let status = LoginItem.status
        print("Launch at login: \(LoginItem.describe(status))")
        if status == .requiresApproval {
            // Normal first-run behavior, not an error (SPEC §10).
            print("Approve WorkSync in System Settings > General > Login Items, then it will start at login.")
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func installHeadless(intervalMinutes: Int) throws {
        let binary = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let logPath = (Logger.defaultDirectory as NSString).appendingPathComponent("worksync.log")

        let plist: [String: Any] = [
            "Label": "io.gamov.worksync",
            "ProgramArguments": [binary, "sync"],
            "StartInterval": max(1, intervalMinutes) * 60,
            "RunAtLoad": true,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try FileManager.default.createDirectory(
            atPath: (LoginItem.headlessPlistPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try data.write(to: URL(fileURLWithPath: LoginItem.headlessPlistPath), options: .atomic)

        // Idempotent: bootout any previous copy before bootstrapping.
        _ = shell(["/bin/launchctl", "bootout", "gui/\(getuid())", LoginItem.headlessPlistPath])
        let result = shell(["/bin/launchctl", "bootstrap", "gui/\(getuid())", LoginItem.headlessPlistPath])

        guard result == 0 else {
            fail("launchctl bootstrap failed (exit \(result))", ExitCodes.partialFailure)
        }
        print("Headless agent installed: runs `worksync sync` every \(intervalMinutes) minute(s).")
        print("This path posts no notifications — those are menu bar only (SPEC §4.1).")
    }
}

struct UninstallAgent: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall-agent",
        abstract: "Stop launching WorkSync at login (both the login item and the headless agent)."
    )

    func run() throws {
        // Both paths are reversed unconditionally: a user who switched between
        // them should not have to remember which one they installed.
        if LoginItem.status != .notRegistered {
            try? SMAppService.mainApp.unregister()
            print("Login item: \(LoginItem.describe(LoginItem.status))")
        } else {
            print("Login item: not registered")
        }

        if FileManager.default.fileExists(atPath: LoginItem.headlessPlistPath) {
            _ = shell(["/bin/launchctl", "bootout", "gui/\(getuid())", LoginItem.headlessPlistPath])
            try? FileManager.default.removeItem(atPath: LoginItem.headlessPlistPath)
            print("Headless agent removed.")
        }
    }
}

@discardableResult
func shell(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: arguments[0])
    process.arguments = Array(arguments.dropFirst())
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return -1
    }
}
