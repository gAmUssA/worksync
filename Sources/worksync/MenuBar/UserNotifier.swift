import Foundation
import UserNotifications
import WorkSyncCore

/// Posts pass notifications through UNUserNotificationCenter, falling back to
/// AppleScript when that is unavailable.
///
/// The fallback is not defensive padding. `UNUserNotificationCenter` requires a
/// registered app bundle: run the same binary directly and every setting comes
/// back `notSupported` (SPEC §3.1 rule 2), so a user running `worksync sync`
/// from a terminal would otherwise get silence with no explanation. osascript
/// posts through Script Editor's own bundle, which has its own grant.
final class UserNotifier: Notifier, @unchecked Sendable {
    private let logger: Logger
    /// Requested once, lazily, the first time something is actually worth
    /// showing — never at launch. Asking for notification permission before
    /// there is anything to notify about is how an app gets denied by reflex.
    private var authorizationRequested = false
    private let lock = NSLock()

    init(logger: Logger) {
        self.logger = logger
    }

    func post(_ notification: PassNotification) {
        guard hasBundleIdentity else {
            postViaAppleScript(notification)
            return
        }
        requestAuthorizationOnce()

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        if notification.isError {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            // nil trigger means deliver now.
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [logger] error in
            guard let error else { return }
            // Never escalated: a pass that did its work must not be reported
            // as failed because a banner could not be shown.
            logger.debug("notification not delivered: \(error.localizedDescription)")
        }
    }

    /// `UNUserNotificationCenter.current()` raises an Objective-C exception —
    /// not a Swift error, so it cannot be caught — when there is no bundle
    /// identifier. It has to be checked before the call, not around it.
    private var hasBundleIdentity: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private func requestAuthorizationOnce() {
        lock.lock()
        defer { lock.unlock() }
        guard !authorizationRequested else { return }
        authorizationRequested = true

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { [logger] granted, error in
            if let error {
                logger.debug("notification authorization failed: \(error.localizedDescription)")
            } else if !granted {
                // Logged rather than retried: asking again on every pass would
                // be nagging, and `worksync doctor` reports this state with a
                // remediation the user can act on when they choose to.
                logger.info("notifications denied; run `worksync doctor` for how to enable them")
            }
        }
    }

    private func postViaAppleScript(_ notification: PassNotification) {
        let title = AppleScriptString.escaped(notification.title)
        let body = AppleScriptString.escaped(notification.body)
        let script = "display notification \"\(body)\" with title \"\(title)\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                logger.debug("osascript notification failed (exit \(process.terminationStatus))")
            }
        } catch {
            logger.debug("osascript could not run: \(error.localizedDescription)")
        }
    }
}
