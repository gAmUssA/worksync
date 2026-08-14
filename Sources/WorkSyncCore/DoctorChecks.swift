import Foundation

/// How WorkSync is (or is not) set up to run on its own.
///
/// Three independent mechanisms, because there are three ways to install it
/// and no single one of them is the right answer. Only "none of them" is a
/// problem.
public struct SchedulingFacts: Equatable, Sendable {
    public var loginItemEnabled: Bool
    public var launchAgentLoaded: Bool
    public var menubarRunning: Bool
    /// The live `SMAppService` status in words, when there is something worth
    /// saying — `requiresApproval` in particular looks like success from every
    /// other angle.
    public var loginItemDetail: String?

    public init(
        loginItemEnabled: Bool = false,
        launchAgentLoaded: Bool = false,
        menubarRunning: Bool = false,
        loginItemDetail: String? = nil
    ) {
        self.loginItemEnabled = loginItemEnabled
        self.launchAgentLoaded = launchAgentLoaded
        self.menubarRunning = menubarRunning
        self.loginItemDetail = loginItemDetail
    }

    public var somethingWillRun: Bool {
        loginItemEnabled || launchAgentLoaded || menubarRunning
    }
}

/// The app's designated requirement, which is what TCC keys permission grants
/// against.
public struct SigningFacts: Equatable, Sendable {
    /// nil when the binary could not be read, or is unsigned.
    public var designatedRequirement: String?

    public init(designatedRequirement: String? = nil) {
        self.designatedRequirement = designatedRequirement
    }

    /// A requirement that pins the exact code hash and nothing else.
    ///
    /// Grants made against it are keyed to that one build, so the next update
    /// is a different identity and silently starts with no calendar
    /// permission. The symptom — access mysteriously revoked after updating —
    /// looks nothing like the cause.
    public var isBareCdhash: Bool {
        guard let requirement = designatedRequirement else { return false }
        return requirement.contains("cdhash") && !requirement.contains("identifier")
    }
}

/// Notification permission, checked only when it is actually used.
public enum NotificationFacts: Equatable, Sendable {
    /// `notify = "off"`, so this is nobody's problem.
    case notApplicable
    case authorized
    case denied
    case notDetermined
    /// Every setting came back `NotSupported`, which is what a bundle that was
    /// mis-assembled or launched by path (rather than through LaunchServices)
    /// reports (SPEC §3.1 rule 2). Naming that is the whole value — calling it
    /// "denied" sends the user to a Settings pane where WorkSync is not listed.
    case unsupported
    case unavailable(String)
}

/// Everything doctor needs, gathered before any check runs.
///
/// Plain values rather than closures so `DoctorChecks.run` stays a pure
/// function: every branch — including permission states that cannot be reached
/// on a CI machine at all — is drivable from a unit test.
public struct DoctorInputs {
    public var configPath: String
    public var config: Result<Config, Error>
    public var access: CalendarAccess
    /// nil when listing was not attempted, which is correct whenever access is
    /// not full: the answer would be meaningless, not merely absent.
    public var calendars: Result<[CalendarRef], Error>?
    public var scheduling: SchedulingFacts
    public var signing: SigningFacts
    public var notifications: NotificationFacts
    public var lastRun: LastRun?
    public var logBytes: Int?
    public var now: Date

    public init(
        configPath: String,
        config: Result<Config, Error>,
        access: CalendarAccess,
        calendars: Result<[CalendarRef], Error>? = nil,
        scheduling: SchedulingFacts = SchedulingFacts(),
        signing: SigningFacts = SigningFacts(),
        notifications: NotificationFacts = .notApplicable,
        lastRun: LastRun? = nil,
        logBytes: Int? = nil,
        now: Date = .now
    ) {
        self.configPath = configPath
        self.config = config
        self.access = access
        self.calendars = calendars
        self.scheduling = scheduling
        self.signing = signing
        self.notifications = notifications
        self.lastRun = lastRun
        self.logBytes = logBytes
        self.now = now
    }
}

/// The checks, ranked by how often each one turns out to be the actual answer
/// to "why isn't this working".
///
/// Read-only by construction (SPEC §16): this file has no writes, no sync
/// pass, no network, and no permission requests — it is handed facts and
/// returns findings.
public enum DoctorChecks {
    /// Warn only once a pass is overdue by a wide margin. A closed laptop is
    /// not a fault, and a warning that fires every morning is one nobody reads.
    public static func stalenessThreshold(intervalMinutes: Int) -> TimeInterval {
        max(Double(intervalMinutes) * 60 * 3, 30 * 60)
    }

    /// The log rotates at 1 MB; five times that means rotation is not running.
    public static let logSizeWarningBytes = 5 * 1024 * 1024

    public static func run(_ inputs: DoctorInputs) -> DoctorReport {
        var findings: [DoctorFinding] = []

        findings.append(accessCheck(inputs))
        findings.append(configCheck(inputs))

        let config = try? inputs.config.get()

        // Resolution and writability both need calendars AND a config. When
        // either is missing they are unknowable rather than failing, and
        // saying so keeps one root cause from printing as three red lines.
        let blocker = resolutionBlocker(inputs, config: config)
        if let blocker {
            findings.append(.skipped(id: "calendars-resolve", "Accounts and calendars resolve", because: blocker))
            findings.append(.skipped(id: "target-writable", "Target calendars are writable", because: blocker))
        } else if let config, let calendars = try? inputs.calendars?.get() {
            let report = Resolver.resolveAll(config: config, calendars: calendars)
            findings.append(resolutionCheck(report))
            findings.append(writabilityCheck(report, blockedBy: report.isComplete ? nil : "resolution failed"))
        }

        findings.append(schedulingCheck(inputs))
        findings.append(signingCheck(inputs))
        findings.append(stalenessCheck(inputs, config: config))
        findings.append(notificationCheck(inputs))
        findings.append(logSizeCheck(inputs))

        return DoctorReport(findings: findings)
    }

    // MARK: 1. Calendar authorization — highest precedence

    private static func accessCheck(_ inputs: DoctorInputs) -> DoctorFinding {
        let id = "calendar-access"
        guard !inputs.access.canSync else {
            return .ok(id: id, "Calendar access", detail: [inputs.access.summary])
        }
        return DoctorFinding(
            id: id,
            title: "Calendar access",
            severity: .error,
            detail: [inputs.access.summary] + (inputs.access.detail.map { [$0] } ?? []),
            remediation: inputs.access.remediation,
            // Via the shared mapping, so the documented contract has one
            // implementation. Restricted and denied differ as errors even
            // though both land on exit 2.
            exitCode: ExitCodes.code(
                for: inputs.access == .restricted
                    ? CalendarStoreError.accessRestricted
                    : CalendarStoreError.accessDenied
            )
        )
    }

    // MARK: 2. Config exists, parses, validates

    private static func configCheck(_ inputs: DoctorInputs) -> DoctorFinding {
        let id = "config"
        switch inputs.config {
        case let .success(config):
            return .ok(id: id, "Config", detail: [
                inputs.configPath,
                "\(config.sources.count) source\(config.sources.count == 1 ? "" : "s"), "
                    + "\(config.general.windowDays)-day window, every \(config.general.intervalMinutes) min",
            ])
        case let .failure(error):
            let isMissing = if case .fileNotFound = error as? ConfigError {
                true
            } else {
                false
            }
            return .failure(
                id: id,
                "Config",
                cause: error,
                detail: [
                    inputs.configPath,
                    (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription,
                ],
                remediation: isMissing
                    ? "Run `worksync init` to write a starting config."
                    : "Fix \(inputs.configPath), then re-run `worksync doctor`."
            )
        }
    }

    /// Why resolution cannot be judged, or nil when it can.
    private static func resolutionBlocker(_ inputs: DoctorInputs, config: Config?) -> String? {
        // Deliberately ordered: a missing config file makes everything below
        // meaningless, so it is reported ahead of the permission it would
        // otherwise be blamed on.
        if config == nil {
            return "config could not be loaded"
        }
        guard inputs.access.canSync else { return "needs full calendar access" }
        switch inputs.calendars {
        case .none: return "calendars were not listed"
        case let .failure(error): return "listing calendars failed: \(error.localizedDescription)"
        case .success: return nil
        }
    }

    // MARK: 3. Accounts and calendars resolve

    private static func resolutionCheck(_ report: ResolutionReport) -> DoctorFinding {
        let id = "calendars-resolve"
        guard let first = report.problems.first else {
            let titles = report.resolved.sourceCalendars
                .sorted { $0.key < $1.key }
                // Calendar and account titles only. Never event titles or
                // attendees: this output is what people paste into bug reports.
                .map { "\($0.key) → \($0.value.accountTitle) / \($0.value.title)" }
            return .ok(id: id, "Accounts and calendars resolve", detail: titles)
        }
        return .failure(
            id: id,
            "Accounts and calendars resolve",
            cause: first,
            // Every problem, not just the first: the point is that the user
            // edits the file once.
            detail: report.problems.map { $0.errorDescription ?? "\($0)" },
            remediation: "Run `worksync calendars` for the exact account and calendar titles."
        )
    }

    // MARK: 4. Target calendars are writable

    private static func writabilityCheck(_ report: ResolutionReport, blockedBy: String?) -> DoctorFinding {
        let id = "target-writable"
        let title = "Target calendars are writable"
        if let blockedBy {
            return .skipped(id: id, title, because: blockedBy)
        }
        let readOnly = report.resolved.allTargets.filter { !$0.allowsModifications }
        guard let first = readOnly.first else {
            return .ok(
                id: id, title,
                detail: report.resolved.allTargets.map { "\($0.accountTitle) / \($0.title)" }
            )
        }
        // allowsModifications is already populated on every CalendarRef, but
        // today it only surfaces at write time — after a pass has done all of
        // its reading and has a plan it cannot apply.
        return .failure(
            id: id,
            title,
            cause: CalendarStoreError.calendarNotWritable(first.title),
            detail: readOnly.map { "\($0.accountTitle) / \($0.title) is read-only" },
            remediation: "Point the target at a writable calendar in \(ConfigLoader.defaultPath), "
                + "or make it writable in Calendar.app."
        )
    }

    // MARK: 5. Something is actually set up to run

    private static func schedulingCheck(_ inputs: DoctorInputs) -> DoctorFinding {
        let id = "scheduling"
        let title = "Something is set up to run WorkSync"
        let facts = inputs.scheduling
        var detail: [String] = []
        if facts.loginItemEnabled {
            detail.append("login item registered")
        }
        if facts.launchAgentLoaded {
            detail.append("launchd agent loaded")
        }
        if facts.menubarRunning {
            detail.append("menu bar app running")
        }
        if let extra = facts.loginItemDetail {
            detail.append(extra)
        }

        guard !facts.somethingWillRun else { return .ok(id: id, title, detail: detail) }
        return .failure(
            id: id,
            title,
            cause: DoctorError.nothingScheduled,
            detail: detail.isEmpty ? ["no login item, no launchd agent, no running menu bar app"] : detail,
            remediation: "Open WorkSync.app and turn on “Launch at login”, or run `worksync menubar`."
        )
    }

    // MARK: 6. Designated requirement (warning)

    private static func signingCheck(_ inputs: DoctorInputs) -> DoctorFinding {
        let id = "code-signature"
        let title = "Code signature is stable across updates"
        guard let requirement = inputs.signing.designatedRequirement else {
            return .skipped(id: id, title, because: "the app's signature could not be read")
        }
        guard inputs.signing.isBareCdhash else {
            return .ok(id: id, title, detail: [requirement])
        }
        // Release tarballs are ad-hoc signed on purpose (SPEC §12), so every
        // user of one is in exactly the state build-app.sh refuses to ship.
        return .warning(
            id: id,
            title,
            detail: [
                requirement,
                "TCC keys the calendar grant to this exact build, so updating "
                    + "silently starts over with no calendar access.",
            ],
            remediation: "Re-sign with a stable identity:\n"
                + "codesign --force --sign \"WorkSync Dev\" /Applications/WorkSync.app"
        )
    }

    // MARK: 7. Last run staleness (warning)

    private static func stalenessCheck(_ inputs: DoctorInputs, config: Config?) -> DoctorFinding {
        let id = "last-run"
        let title = "Recent sync"
        guard let lastRun = inputs.lastRun else {
            return .skipped(id: id, title, because: "no sync has run yet")
        }
        let age = inputs.now.timeIntervalSince(lastRun.finishedAt)
        // Localized by construction, and no formatter instance to manage. This
        // one IS meant to read in the user's own conventions — unlike the log
        // timestamps, which are fixed-format on purpose.
        let when = lastRun.finishedAt.formatted(date: .abbreviated, time: .shortened)

        guard age > stalenessThreshold(intervalMinutes: config?.general.intervalMinutes ?? 10) else {
            return .ok(id: id, title, detail: ["last run \(when): \(lastRun.summary)"])
        }
        return .warning(
            id: id,
            title,
            detail: [
                "last run \(when), \(Int(age / 60)) minutes ago",
                lastRun.succeeded ? lastRun.summary : "that run failed",
            ],
            remediation: "Run `worksync sync` to catch up. If this keeps happening, "
                + "check the “\(title)” and scheduling checks above."
        )
    }

    // MARK: 8. Notification authorization (warning)

    private static func notificationCheck(_ inputs: DoctorInputs) -> DoctorFinding {
        let id = "notifications"
        let title = "Notifications"
        switch inputs.notifications {
        case .notApplicable:
            // Checking a permission the config does not use would be a check
            // that fires on a perfectly healthy machine.
            return .skipped(id: id, title, because: "notify = \"off\"")
        case .authorized:
            return .ok(id: id, title, detail: ["authorized"])
        case .denied:
            return .warning(
                id: id, title,
                detail: ["notify is on, but notification permission is denied — syncs run, silently"],
                remediation: "Enable WorkSync in System Settings > Notifications, "
                    + "or set notify = \"off\" in config.toml."
            )
        case .notDetermined:
            return .warning(
                id: id, title,
                detail: ["notify is on, but permission has not been requested yet"],
                remediation: "Launch WorkSync.app once and accept the notification prompt."
            )
        case .unsupported:
            return .warning(
                id: id, title,
                detail: [
                    "notifications are unavailable to this process, which means it is not running "
                        + "as a properly registered app bundle — this is not a permission problem",
                ],
                remediation: "Launch the app with `open /Applications/WorkSync.app` rather than by path, "
                    + "and make sure the bundle is registered with LaunchServices."
            )
        case let .unavailable(reason):
            return .skipped(id: id, title, because: reason)
        }
    }

    // MARK: 9. Log size (warning)

    private static func logSizeCheck(_ inputs: DoctorInputs) -> DoctorFinding {
        let id = "log-size"
        let title = "Log file size"
        guard let bytes = inputs.logBytes else {
            return .skipped(id: id, title, because: "no log file yet")
        }
        // The purpose-built style: picks the unit, localizes the separator, and
        // matches how Finder reports the same file — so the number the user
        // reads here is the one they can go and check.
        let size = bytes.formatted(.byteCount(style: .file))
        guard bytes > logSizeWarningBytes else {
            return .ok(id: id, title, detail: [size])
        }
        return .warning(
            id: id, title,
            detail: ["\(size) — the log rotates at 1 MB, so rotation is not running"],
            remediation: "Delete \(Logger.defaultDirectory)/worksync.log and re-run; "
                + "if it grows again, file a bug."
        )
    }
}
