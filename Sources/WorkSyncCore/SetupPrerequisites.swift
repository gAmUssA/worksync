import Foundation

/// Which doctor checks stand between a fresh install and a working sync.
///
/// Setup and the Health section render the same findings; this is the filter
/// and the ordering that separate them (`worksync-vynu`). It lives in the core
/// rather than the menu bar target for the reason every other rule here does:
/// a definition the view owns is a second answer to a question doctor already
/// answers, free to drift from it.
///
/// Four of the nine checks are deliberately NOT prerequisites. Signature
/// stability, log size, notification permission and staleness are all real
/// findings, and none of them stop a first sync — they are noise to someone
/// who has not synced once, and gating on them would be the exit-code mistake
/// (`brew doctor`'s, per SPEC §16) moved into the UI: a gate the user learns
/// to route around.
public enum SetupPrerequisites {
    /// The gating checks, in DEPENDENCY order.
    ///
    /// Not severity order, which is what doctor sorts by. Doctor's checks are
    /// independent and it ranks them by how bad they are; setup walks a user
    /// forwards, and each of these is only answerable once the one before it
    /// is. Access first, because without it the rest are unknowable; then a
    /// config to read, then names that resolve, then a target that accepts
    /// writes, then something that will actually run.
    public static let ordered: [String] = [
        "calendar-access",
        "config",
        "calendars-resolve",
        "target-writable",
        "scheduling",
    ]

    /// Checks that are reported but never gate setup.
    ///
    /// Listed explicitly rather than inferred as "everything else", so a check
    /// added later is classified by hand instead of defaulting into silence.
    /// `testEveryCheckIsClassified` fails until it appears in one list.
    public static let nonGating: [String] = [
        "code-signature",
        "last-run",
        "log-size",
        "notifications",
    ]

    public static func isPrerequisite(_ id: String) -> Bool {
        ordered.contains(id)
    }

    /// `findings` reduced to the prerequisites, in dependency order.
    ///
    /// A prerequisite the report does not mention is omitted rather than
    /// invented: the report is the authority on what was checked.
    public static func gating(in findings: [DoctorFinding]) -> [DoctorFinding] {
        ordered.compactMap { id in findings.first { $0.id == id } }
    }

    /// Why setup cannot finish yet.
    ///
    /// A missing prerequisite is its own case rather than a nil finding: a
    /// caller rendering "waiting on X" needs to name it either way, and a
    /// check that did not report is a different problem from one that failed.
    public enum Blocker: Equatable, Sendable {
        /// The check ran and is not satisfied.
        case failing(DoctorFinding)
        /// The report does not mention this check at all.
        case notReported(id: String)

        public var id: String {
            switch self {
            case let .failing(finding): finding.id
            case let .notReported(id): id
            }
        }
    }

    /// The first prerequisite, in dependency order, that is not satisfied.
    ///
    /// `.skipped` is not satisfied. A check that could not run because an
    /// earlier one failed is exactly the state setup exists to walk out of,
    /// and treating "unknown" as "fine" would drop the user into a dashboard
    /// that cannot work.
    public static func blocking(in findings: [DoctorFinding]) -> Blocker? {
        for id in ordered {
            guard let finding = findings.first(where: { $0.id == id }) else {
                return .notReported(id: id)
            }
            if finding.severity != .ok, finding.severity != .warning {
                return .failing(finding)
            }
        }
        return nil
    }

    /// Whether every prerequisite is satisfied.
    ///
    /// Derived from `blocking` rather than computed again: two answers to one
    /// question drift, and they did — an earlier version reported unsatisfied
    /// while `blocking` returned nil for a prerequisite missing from the
    /// report, so a caller could not say what it was waiting for.
    public static func isSatisfied(by findings: [DoctorFinding]) -> Bool {
        blocking(in: findings) == nil
    }
}
