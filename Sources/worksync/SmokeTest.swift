import ArgumentParser
import Foundation
import UserNotifications

/// Hidden diagnostic: validates the app-bundle architecture (SPEC §3.1 rule 2).
/// UNUserNotificationCenter.current() aborts the process when there is no
/// genuine registered bundle, and reports settings as NotSupported when the
/// bundle is mis-assembled — this command surfaces both, plus the
/// authorization prompt on first run.
struct SmokeTest: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "smoke-test",
        abstract: "Validate bundle identity and notification authorization.",
        shouldDisplay: false
    )

    @Option(name: .long, help: "Also write results to this file (open(1) swallows stdout)")
    var output: String?

    func run() throws {
        var lines: [String] = []
        func report(_ line: String) {
            print(line)
            lines.append(line)
        }
        defer {
            if let output {
                try? lines.joined(separator: "\n").appending("\n")
                    .write(toFile: output, atomically: true, encoding: .utf8)
            }
        }

        report("bundlePath: \(Bundle.main.bundlePath)")
        report("bundleIdentifier: \(Bundle.main.bundleIdentifier ?? "nil")")

        guard Bundle.main.bundleIdentifier == "io.gamov.worksync" else {
            report("FAIL: bundle identifier not resolved — not running from the bundle?")
            throw ArgumentParser.ExitCode(1)
        }

        // The crash point for non-bundled processes (NSInternalInconsistencyException).
        let center = UNUserNotificationCenter.current()
        report("UNUserNotificationCenter.current(): ok")

        let semaphore = DispatchSemaphore(value: 0)
        var authError: String?
        var grantedResult = false
        center.requestAuthorization(options: [.alert]) { granted, error in
            grantedResult = granted
            authError = error.map { String(describing: $0) }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 120) == .timedOut {
            report("FAIL: authorization request timed out (no prompt delivered?)")
            throw ArgumentParser.ExitCode(1)
        }
        report("authorization granted: \(grantedResult) error: \(authError ?? "none")")

        var status = "?"
        var alertSetting = "?"
        let settingsSemaphore = DispatchSemaphore(value: 0)
        center.getNotificationSettings { settings in
            status = String(describing: settings.authorizationStatus.rawValue)
            alertSetting = String(describing: settings.alertSetting.rawValue)
            settingsSemaphore.signal()
        }
        _ = settingsSemaphore.wait(timeout: .now() + 30)
        // authorizationStatus: 0 notDetermined, 1 denied, 2 authorized
        // alertSetting: 0 notSupported, 1 disabled, 2 enabled
        report("authorizationStatus: \(status) (0=notDetermined 1=denied 2=authorized)")
        report("alertSetting: \(alertSetting) (0=NOTSUPPORTED 1=disabled 2=enabled)")

        if alertSetting == "0" {
            report("FAIL: alertSetting is NotSupported — macOS does not accept this bundle as a real app")
            throw ArgumentParser.ExitCode(1)
        }
        report("SMOKE TEST PASSED")
    }
}
