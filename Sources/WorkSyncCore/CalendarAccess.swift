import Foundation

/// The calendar permission the process currently holds, read without asking
/// for it.
///
/// EventKit-free so checks against it are unit-testable with no TCC grant in
/// CI, and separate from `requestAccess()` because that method deliberately
/// falls through `.notDetermined` and `.writeOnly` into
/// `requestFullAccessToEvents`, which raises a permission dialog. A diagnostic
/// must never do that: showing a prompt to someone who ran a checkup is
/// startling, and on `.notDetermined` it would then report success for a
/// permission that was granted *to the diagnostic* — hiding the fact that the
/// user never granted it interactively the way SPEC §3 requires.
public enum CalendarAccess: String, Codable, CaseIterable, Sendable {
    case fullAccess
    case writeOnly
    case denied
    case restricted
    case notDetermined

    /// Only full access can enumerate events, which is the whole job.
    public var canSync: Bool {
        self == .fullAccess
    }

    public var summary: String {
        switch self {
        case .fullAccess:
            "Full calendar access granted"
        case .writeOnly:
            "Write-only calendar access"
        case .denied:
            "Calendar access denied"
        case .restricted:
            "Calendar access restricted by device policy"
        case .notDetermined:
            "Calendar access has never been requested"
        }
    }

    public var detail: String? {
        switch self {
        case .fullAccess:
            nil
        case .writeOnly:
            // The nastiest of these states by far: nothing errors. Queries
            // succeed against a virtual calendar and return zero events, so
            // every pass reports a clean run having mirrored nothing.
            "Write-only access cannot read events. Queries succeed and return nothing, "
                + "so syncs look successful while mirroring nothing at all."
        case .denied:
            "Every calendar check below is unknowable until this is granted."
        case .restricted:
            "A profile or parental control is blocking calendar access; this cannot be granted here."
        case .notDetermined:
            "macOS shows the permission prompt only to an app the user launched, "
                + "so this stays unanswered until WorkSync is run interactively."
        }
    }

    /// Never "open System Settings and hope": each state has a different fix,
    /// and `notDetermined` in particular is fixed by running the app, not by
    /// visiting Settings, where WorkSync will not even be listed yet.
    public var remediation: String? {
        switch self {
        case .fullAccess:
            nil
        case .writeOnly, .denied:
            "Turn on Full Access in System Settings > Privacy & Security > Calendars, then re-run."
        case .restricted:
            "Ask whoever manages this Mac's configuration profile to allow calendar access."
        case .notDetermined:
            "Run `worksync sync --dry-run` from Terminal, or launch WorkSync.app, and accept the prompt."
        }
    }
}
