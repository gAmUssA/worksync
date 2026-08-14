import Foundation

/// How bad one check's result is.
///
/// `skipped` exists because of the calendar-access check: when access is
/// denied, every calendar check downstream is *unknowable*, not failing.
/// Reporting five red lines for one root cause sends the user hunting through
/// symptoms; `skipped (needs calendar access)` points at the one thing to fix.
public enum DoctorSeverity: String, Codable, CaseIterable, Comparable, Sendable {
    case ok
    case skipped
    case warning
    case error

    private var rank: Int {
        switch self {
        case .ok: 0
        case .skipped: 1
        case .warning: 2
        case .error: 3
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Carries the severity on its own, so output stays readable through a
    /// pipe, in a bug report, and for anyone who cannot distinguish the
    /// colours. Colour is decoration layered on top, never the signal.
    public var glyph: String {
        switch self {
        case .ok: "✓"
        case .skipped: "–"
        case .warning: "!"
        case .error: "✗"
        }
    }
}

/// A failure that is real but is not a config, permission, or lock problem —
/// the machine is not set up the way the tool needs.
///
/// Exists so such a finding still gets its exit code from
/// `ExitCodes.code(for:)` rather than from a second mapping written here that
/// could drift from the documented contract.
public enum DoctorError: Error, LocalizedError, Equatable {
    case nothingScheduled
    case checkFailed(check: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case .nothingScheduled:
            "Nothing is set up to run WorkSync: no login item, no launchd agent, and no menu bar app running"
        case let .checkFailed(check, detail):
            "The \"\(check)\" check could not complete: \(detail)"
        }
    }
}

/// One check's result.
///
/// A value type rather than printed text, because the CLI, `--json`, and the
/// menu bar all render the same findings. Homebrew had to retrofit exactly
/// this shape before `brew doctor --json` was possible.
public struct DoctorFinding: Equatable, Codable, Sendable {
    /// Stable machine key (`calendar-access`, `config-parses`). Never
    /// localized and never derived from the title, so `--json` consumers and
    /// the menu bar can match on it after the wording changes.
    public let id: String
    public let title: String
    public let severity: DoctorSeverity
    /// Extra lines under the headline. Calendar and account *titles* only —
    /// never event titles or attendees (SPEC §16): doctor output is what
    /// people paste into bug reports.
    public let detail: [String]
    /// Something the user can actually run or click. Required on anything
    /// that is not `ok`.
    public let remediation: String?
    /// What this finding alone would exit with, taken from the shared
    /// `ExitCodes` mapping rather than decided here.
    public let exitCode: Int32

    public init(
        id: String,
        title: String,
        severity: DoctorSeverity,
        detail: [String] = [],
        remediation: String? = nil,
        exitCode: Int32 = ExitCodes.success
    ) {
        self.id = id
        self.title = title
        self.severity = severity
        self.detail = detail
        self.remediation = remediation
        self.exitCode = exitCode
    }

    public static func ok(id: String, _ title: String, detail: [String] = []) -> Self {
        Self(id: id, title: title, severity: .ok, detail: detail)
    }

    /// Warnings never change the exit code, so they carry `success`.
    public static func warning(
        id: String,
        _ title: String,
        detail: [String] = [],
        remediation: String
    ) -> Self {
        Self(id: id, title: title, severity: .warning, detail: detail, remediation: remediation)
    }

    /// The check could not be evaluated because something upstream failed.
    /// Not a failure of its own, so it carries `success` too.
    public static func skipped(id: String, _ title: String, because reason: String) -> Self {
        Self(
            id: id,
            title: title,
            severity: .skipped,
            detail: ["skipped (\(reason))"],
            remediation: nil
        )
    }

    /// Takes its exit code from the error, so the documented contract has
    /// exactly one implementation and `ExitCodesTests` keeps covering it.
    public static func failure(
        id: String,
        _ title: String,
        cause: Error,
        detail: [String] = [],
        remediation: String
    ) -> Self {
        Self(
            id: id,
            title: title,
            severity: .error,
            detail: detail.isEmpty
                ? [(cause as? LocalizedError)?.errorDescription ?? cause.localizedDescription]
                : detail,
            remediation: remediation,
            exitCode: ExitCodes.code(for: cause)
        )
    }
}

/// Everything doctor found, plus how to exit and how to print it.
public struct DoctorReport: Equatable, Codable, Sendable {
    public let findings: [DoctorFinding]

    public init(findings: [DoctorFinding]) {
        self.findings = findings
    }

    public var worstSeverity: DoctorSeverity {
        findings.map(\.severity).max() ?? .ok
    }

    public var hasWarnings: Bool {
        findings.contains { $0.severity == .warning }
    }

    /// - Parameter strict: promotes warnings to `configError`, for CI.
    ///   Opt-in on purpose: `brew doctor` exits 1 on anything at all — four
    ///   cosmetic warnings are enough — which trains people to ignore it.
    public func exitCode(strict: Bool = false) -> Int32 {
        let codes = Set(findings.map(\.exitCode))
        // Precedence, not numeric order. Permission comes first because
        // without calendar access every other calendar answer is a guess, so
        // it is the one to report even when a config error is also present.
        for code in [ExitCodes.permissionError, ExitCodes.configError, ExitCodes.partialFailure]
            where codes.contains(code) {
            return code
        }
        if strict, hasWarnings {
            return ExitCodes.configError
        }
        return ExitCodes.success
    }

    /// The human rendering: one headline line per check, detail indented
    /// under it.
    ///
    /// - Parameter verbose: include detail under passing checks too. Passing
    ///   checks themselves always print — with nine checks, the green lines
    ///   are what distinguishes "everything else is fine" from "everything
    ///   else was skipped".
    public func text(verbose: Bool = false) -> String {
        var lines: [String] = []
        for finding in findings {
            lines.append("\(finding.severity.glyph) \(finding.title)")
            if finding.severity != .ok || verbose {
                lines += finding.detail.map { "    • \($0)" }
            }
            if let remediation = finding.remediation, finding.severity != .ok {
                lines += remediation
                    .components(separatedBy: "\n")
                    .map { "    → \($0)" }
            }
        }
        lines.append("")
        lines.append(summaryLine)
        return lines.joined(separator: "\n")
    }

    public var summaryLine: String {
        let errors = findings.count { $0.severity == .error }
        let warnings = findings.count { $0.severity == .warning }
        let skipped = findings.count { $0.severity == .skipped }
        if errors == 0, warnings == 0, skipped == 0 {
            return "All \(findings.count) checks passed."
        }
        var parts: [String] = []
        if errors > 0 {
            parts.append("\(errors) error\(errors == 1 ? "" : "s")")
        }
        if warnings > 0 {
            parts.append("\(warnings) warning\(warnings == 1 ? "" : "s")")
        }
        if skipped > 0 {
            parts.append("\(skipped) skipped")
        }
        return "\(findings.count) checks: " + parts.joined(separator: ", ") + "."
    }

    public func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Snake case so the keys read like the rest of the tool's surface
        // (config.toml, the log lines) rather than like Swift.
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let payload = try encoder.encode(Payload(
            exitCode: exitCode(),
            summary: summaryLine,
            findings: findings
        ))
        return String(decoding: payload, as: UTF8.self)
    }

    private struct Payload: Encodable {
        let exitCode: Int32
        let summary: String
        let findings: [DoctorFinding]
    }
}

/// Where the UI can send someone to fix a finding.
///
/// Keyed on the finding id rather than on its wording, and defined here rather
/// than in the view, so the CLI and the panel cannot drift: a check whose text
/// changes keeps its destination, and a check with no destination is stated as
/// such instead of silently rendering a dead button.
public enum DoctorDestination: Equatable, Sendable {
    case calendarPrivacySettings
    case notificationSettings
    case loginItemSettings
    case configFile

    public static func forFinding(id: String) -> DoctorDestination? {
        switch id {
        case "calendar-access": .calendarPrivacySettings
        case "notifications": .notificationSettings
        case "scheduling": .loginItemSettings
        case "config", "calendars-resolve", "target-writable": .configFile
        // code-signature, last-run and log-size are fixed in a terminal, so
        // they show their command rather than a button that cannot do it.
        default: nil
        }
    }

    public var buttonTitle: String {
        switch self {
        case .calendarPrivacySettings: "Open Calendar Privacy"
        case .notificationSettings: "Open Notifications"
        case .loginItemSettings: "Open Login Items"
        case .configFile: "Open config"
        }
    }
}
