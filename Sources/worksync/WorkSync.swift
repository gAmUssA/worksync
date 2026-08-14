import ArgumentParser
import Foundation
import WorkSyncCore
import WorkSyncKit

let worksyncVersion = "0.1.0"

/// Exit codes per SPEC §8.
enum ExitCode {
    static let success: Int32 = 0
    static let configError: Int32 = 1
    static let permissionError: Int32 = 2
    static let partialFailure: Int32 = 3
}

struct WorkSync: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "worksync",
        abstract: "Mirrors busy time from source calendars onto a work calendar as sanitized blockers.",
        version: worksyncVersion,
        subcommands: [
            Sync.self,
            Menubar.self,
            Calendars.self,
            Status.self,
            Purge.self,
            InstallAgent.self,
            UninstallAgent.self,
            SmokeTest.self,
        ]
    )
}

struct ConfigOption: ParsableArguments {
    @Option(name: .long, help: "Path to config.toml (default: ~/.config/worksync/config.toml)")
    var config: String = ConfigLoader.defaultPath
}

/// Loads config and exits with the right code + message on failure.
func loadConfigOrExit(path: String) -> Config {
    do {
        return try ConfigLoader.load(path: path)
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        Foundation.exit(ExitCode.configError)
    }
}

/// Requests calendar access and exits 2 with remediation text on denial.
func requestAccessOrExit(_ store: CalendarStore) {
    do {
        try store.requestAccess()
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        Foundation.exit(ExitCode.permissionError)
    }
}

// MARK: - Subcommand stubs (implemented in later milestones)

struct Menubar: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run as menu bar app (scheduler + status UI). Arrives in M4."
    )
    func run() throws {
        print("worksync menubar is not implemented yet (milestone M4).")
        throw ArgumentParser.ExitCode(ExitCode.configError)
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Managed-event counts per source and last-run info. Arrives in M4."
    )
    func run() throws {
        print("worksync status is not implemented yet (milestone M4).")
        throw ArgumentParser.ExitCode(ExitCode.configError)
    }
}

struct Purge: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete ALL managed events (or one source's). Arrives in M2."
    )
    @Option(name: .long, help: "Only purge events of this source id") var source: String?
    @Flag(name: .long, help: "Actually delete (default: count only)") var yes = false
    func run() throws {
        print("worksync purge is not implemented yet (milestone M2).")
        throw ArgumentParser.ExitCode(ExitCode.configError)
    }
}

struct InstallAgent: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-agent",
        abstract: "Register launch-at-login. Arrives in M4."
    )
    @Flag(name: .long, help: "Install a headless launchd agent instead of the login item") var headless = false
    func run() throws {
        print("worksync install-agent is not implemented yet (milestone M4).")
        throw ArgumentParser.ExitCode(ExitCode.configError)
    }
}

struct UninstallAgent: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall-agent",
        abstract: "Unregister launch-at-login. Arrives in M4."
    )
    func run() throws {
        print("worksync uninstall-agent is not implemented yet (milestone M4).")
        throw ArgumentParser.ExitCode(ExitCode.configError)
    }
}
