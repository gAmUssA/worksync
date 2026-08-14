import Foundation

/// What to show the user after a pass.
public struct PassNotification: Equatable, Sendable {
    public let title: String
    public let body: String
    /// Errors are worth a sound; a routine "3 created" is not. A utility that
    /// chimes every ten minutes gets its notifications turned off entirely,
    /// which silences the failures too.
    public let isError: Bool

    public init(title: String, body: String, isError: Bool) {
        self.title = title
        self.body = body
        self.isError = isError
    }
}

/// Posts a notification. Implemented outside the core so this stays
/// EventKit- and UserNotifications-free and the policy above can be tested
/// without a bundle.
public protocol Notifier: Sendable {
    /// Best-effort by contract: a pass must never be reported as failed
    /// because a banner could not be shown.
    func post(_ notification: PassNotification)
}

/// Decides whether a pass is worth interrupting the user for.
///
/// Pure and separate from the posting so the "which passes notify" question —
/// the one with actual product judgement in it — is unit-testable, and so the
/// CLI and the menu bar cannot answer it differently.
public enum NotificationPolicy {
    public static func notification(for outcome: PassOutcome, mode: NotifyMode) -> PassNotification? {
        guard mode != .off else { return nil }

        switch outcome.disposition {
        case .skippedLocked:
            // Nothing happened. Another process is doing this same work, and
            // on a machine running both the menu bar app and a launchd agent
            // that is the common case, not an event — notifying would produce
            // a banner every interval saying nothing occurred (SPEC §9).
            return nil

        case let .failed(message):
            return PassNotification(
                title: "WorkSync failed",
                // The underlying error text verbatim: a notification saying
                // "sync failed" with no reason sends the user to the log to
                // find what could have been on screen.
                body: message,
                isError: true
            )

        case .completed:
            // Per-write failures leave the pass "completed" but partial, and
            // that is a failure the user needs to see even under "errors".
            if outcome.result?.hasFailures == true {
                return PassNotification(
                    title: "WorkSync finished with errors",
                    body: outcome.summary,
                    isError: true
                )
            }
            guard mode == .always else { return nil }
            return PassNotification(
                title: "WorkSync",
                // The same summary string the log and the menu bar header
                // show, so there is one source of truth for "what happened".
                body: outcome.summary,
                isError: false
            )
        }
    }
}

/// Escapes a string for embedding in an AppleScript string literal.
///
/// Backslashes MUST be escaped before quotes: doing it the other way round
/// re-escapes the backslashes just inserted for the quotes, so a title
/// containing `"` produces a script that does not compile — and the fallback
/// notifier silently stops working precisely when a calendar has a quote in
/// its name.
public enum AppleScriptString {
    public static func escaped(_ raw: String) -> String {
        raw
            .replacing("\\", with: "\\\\")
            .replacing("\"", with: "\\\"")
            // Literal newlines terminate an AppleScript statement.
            .replacing("\n", with: " ")
            .replacing("\r", with: " ")
    }
}
