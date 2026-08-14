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
    private let lock = NSLock()

    /// Authorization is requested once, lazily, the first time something is
    /// actually worth showing — never at launch. Asking before there is
    /// anything to notify about is how an app gets denied by reflex.
    private enum Authorization {
        case notYetAsked
        /// The prompt is up. Anything posted meanwhile has to wait, not race.
        case asking
        case granted
        case denied
    }

    private var authorization: Authorization = .notYetAsked
    /// Notifications posted while the prompt is still up. Delivered once the
    /// answer arrives rather than dropped: the first notification after
    /// enabling the feature is often the interesting one, and under the
    /// default `notify = "errors"` it is by definition a failure — the most
    /// costly banner to lose.
    private var deferred: [PassNotification] = []

    init(logger: Logger) {
        self.logger = logger
    }

    func post(_ notification: PassNotification) {
        guard hasBundleIdentity else {
            postViaAppleScript(notification)
            return
        }

        lock.lock()
        switch authorization {
        case .granted:
            lock.unlock()
            deliver(notification)
        case .denied:
            lock.unlock()
            // Deliberately NOT falling back to AppleScript here: osascript
            // would post through Script Editor's own grant, which is a way of
            // showing a banner to someone who declined banners.
            logger.debug("notification suppressed: authorization denied")
        case .asking:
            deferred.append(notification)
            lock.unlock()
        case .notYetAsked:
            authorization = .asking
            deferred.append(notification)
            lock.unlock()
            requestAuthorization()
        }
    }

    private func deliver(_ notification: PassNotification) {
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

    /// Asks once, then releases whatever was posted while the prompt was up.
    ///
    /// The release is the point. `add(_:)` on an unauthorized centre does not
    /// queue the request for later — it fails — so posting immediately after
    /// calling `requestAuthorization` loses the notification whenever the user
    /// has not answered yet, which is exactly the first one.
    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { [weak self] granted, error in
            guard let self else { return }
            if let error {
                logger.debug("notification authorization failed: \(error.localizedDescription)")
            } else if !granted {
                // Logged rather than re-asked: prompting again on every pass
                // would be nagging, and `worksync doctor` reports this state
                // with a remediation for when the user changes their mind.
                logger.info("notifications denied; run `worksync doctor` for how to enable them")
            }

            lock.lock()
            authorization = granted ? .granted : .denied
            let waiting = deferred
            deferred = []
            let allowed = granted
            lock.unlock()

            guard allowed else { return }
            for notification in waiting {
                deliver(notification)
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
