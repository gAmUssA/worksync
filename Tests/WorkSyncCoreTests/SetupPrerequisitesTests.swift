import XCTest
@testable import WorkSyncCore

/// The filter that separates setup from Health (`worksync-vynu`).
final class SetupPrerequisitesTests: XCTestCase {
    private var personalCal: CalendarRef {
        CalendarRef(id: "1", title: "Personal", accountTitle: "iCloud", allowsModifications: true)
    }

    private var workCal: CalendarRef {
        CalendarRef(id: "2", title: "Calendar", accountTitle: "Work", allowsModifications: true)
    }

    private func config() -> Config {
        Config(
            general: GeneralConfig(),
            target: TargetConfig(account: "Work", calendar: "Calendar"),
            sources: [SourceConfig(id: "personal", account: "iCloud", calendar: "Personal")]
        )
    }

    private func healthyInputs() -> DoctorInputs {
        DoctorInputs(
            configPath: "/tmp/config.toml",
            config: .success(config()),
            access: .fullAccess,
            calendars: .success([personalCal, workCal]),
            scheduling: SchedulingFacts(loginItemEnabled: true),
            signing: SigningFacts(
                designatedRequirement: "identifier \"io.gamov.worksync\" and anchor apple generic"
            ),
            notifications: .notApplicable,
            lastRun: LastRun(
                finishedAt: Date(timeIntervalSince1970: 1_757_000_000),
                succeeded: true,
                summary: "1 created"
            ),
            logBytes: 4096,
            now: Date(timeIntervalSince1970: 1_757_000_000)
        )
    }

    // MARK: The set itself

    func testTheFiveGatingChecks() {
        XCTAssertEqual(
            SetupPrerequisites.ordered,
            ["calendar-access", "config", "calendars-resolve", "target-writable", "scheduling"]
        )
    }

    /// The guard that keeps this honest as checks are added: a new check must
    /// be put in one list or the other, deliberately. Without this, "everything
    /// else is not a prerequisite" quietly swallows a check that should gate.
    func testEveryCheckIsClassified() {
        let report = DoctorChecks.run(healthyInputs())
        let classified = Set(SetupPrerequisites.ordered + SetupPrerequisites.nonGating)
        let produced = Set(report.findings.map(\.id))

        XCTAssertTrue(
            produced.subtracting(classified).isEmpty,
            "unclassified check(s): \(produced.subtracting(classified).sorted()) — "
                + "add each to SetupPrerequisites.ordered or .nonGating"
        )
        XCTAssertTrue(
            classified.subtracting(produced).isEmpty,
            "classified but never produced: \(classified.subtracting(produced).sorted())"
        )
    }

    func testTheTwoListsDoNotOverlap() {
        XCTAssertTrue(
            Set(SetupPrerequisites.ordered).isDisjoint(with: Set(SetupPrerequisites.nonGating))
        )
    }

    // MARK: Ordering is dependency order, not severity order

    func testGatingFindingsComeBackInDependencyOrder() {
        // Handed in reverse, so a filter that preserved the report's order
        // rather than imposing its own would fail here.
        let findings = SetupPrerequisites.ordered.reversed().map {
            DoctorFinding.ok(id: $0, $0)
        }
        XCTAssertEqual(
            SetupPrerequisites.gating(in: findings).map(\.id), SetupPrerequisites.ordered
        )
    }

    func testAPrerequisiteMissingFromTheReportIsNotInvented() {
        let findings = [DoctorFinding.ok(id: "config", "config")]
        XCTAssertEqual(SetupPrerequisites.gating(in: findings).map(\.id), ["config"])
    }

    // MARK: What counts as satisfied

    func testAHealthyMachineSatisfiesEveryPrerequisite() {
        let report = DoctorChecks.run(healthyInputs())
        XCTAssertTrue(SetupPrerequisites.isSatisfied(by: report.findings))
        XCTAssertNil(SetupPrerequisites.blocking(in: report.findings))
    }

    func testAWarningNeverGates() {
        var findings = SetupPrerequisites.ordered.map { DoctorFinding.ok(id: $0, $0) }
        findings.append(
            DoctorFinding(
                id: "log-size", title: "Log is large", severity: .error,
                remediation: "rotate it", exitCode: 1
            )
        )
        XCTAssertTrue(
            SetupPrerequisites.isSatisfied(by: findings),
            "a non-prerequisite cannot hold setup open, whatever its severity"
        )
    }

    func testASkippedPrerequisiteIsNotSatisfied() {
        var findings = SetupPrerequisites.ordered.map { DoctorFinding.ok(id: $0, $0) }
        findings[2] = .skipped(id: "calendars-resolve", "resolve", because: "needs calendar access")

        XCTAssertFalse(
            SetupPrerequisites.isSatisfied(by: findings),
            "a check that could not run is exactly what setup exists to walk out of"
        )
        XCTAssertEqual(SetupPrerequisites.blocking(in: findings)?.id, "calendars-resolve")
    }

    func testAMissingPrerequisiteIsNotSatisfied() {
        let findings = SetupPrerequisites.ordered.dropLast().map { DoctorFinding.ok(id: $0, $0) }
        XCTAssertFalse(
            SetupPrerequisites.isSatisfied(by: Array(findings)),
            "a check that did not report is not a check that passed"
        )
    }

    func testBlockingIsTheFirstUnsatisfiedInDependencyOrder() {
        var findings = SetupPrerequisites.ordered.map { DoctorFinding.ok(id: $0, $0) }
        findings[0] = DoctorFinding(
            id: "calendar-access", title: "No access", severity: .error,
            remediation: "grant it", exitCode: 2
        )
        findings[3] = DoctorFinding(
            id: "target-writable", title: "Read only", severity: .error,
            remediation: "pick another", exitCode: 1
        )
        XCTAssertEqual(
            SetupPrerequisites.blocking(in: findings)?.id, "calendar-access",
            "the earliest one, since the later one may only be failing because of it"
        )
    }

    /// Revoking access has to re-enter setup with no extra code path — the
    /// decision this whole milestone rests on (`worksync-n2bv`).
    func testRevokedAccessLeavesTheSetupStateUnsatisfied() {
        var inputs = healthyInputs()
        inputs.access = .denied
        let report = DoctorChecks.run(inputs)

        XCTAssertFalse(SetupPrerequisites.isSatisfied(by: report.findings))
        XCTAssertEqual(SetupPrerequisites.blocking(in: report.findings)?.id, "calendar-access")
    }
}
