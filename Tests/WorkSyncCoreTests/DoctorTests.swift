import XCTest
@testable import WorkSyncCore

/// Doctor exists to answer "why isn't this working" without guesswork, so the
/// thing under test is mostly its *judgement*: what it calls an error, what it
/// refuses to call an error, and what it declines to guess about at all.
final class DoctorTests: XCTestCase {
    // MARK: Fixtures

    private let personalCal = CalendarRef(
        id: "cal-personal", title: "Personal", accountTitle: "iCloud", allowsModifications: true
    )
    private let workCal = CalendarRef(
        id: "cal-work", title: "Calendar", accountTitle: "Work", allowsModifications: true
    )

    private func config(notify: NotifyMode = .off, interval: Int = 10) -> Config {
        var general = GeneralConfig()
        general.notify = notify
        general.intervalMinutes = interval
        return Config(
            general: general,
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
            signing: SigningFacts(designatedRequirement: "identifier \"io.gamov.worksync\" and anchor apple generic"),
            notifications: .notApplicable,
            lastRun: LastRun(finishedAt: Date(), succeeded: true, summary: "1 created"),
            logBytes: 4096,
            now: Date()
        )
    }

    private func finding(_ id: String, in report: DoctorReport) throws -> DoctorFinding {
        try XCTUnwrap(report.findings.first { $0.id == id }, "no finding with id \"\(id)\"")
    }

    // MARK: The healthy machine

    func testAHealthyMachineReportsNoErrorsAndExitsZero() {
        let report = DoctorChecks.run(healthyInputs())
        XCTAssertEqual(report.exitCode(), 0)
        XCTAssertTrue(
            report.findings.filter { $0.severity == .error }.isEmpty,
            "errors on a healthy machine: "
                + report.findings.filter { $0.severity == .error }.map(\.title).joined(separator: ", ")
        )
    }

    func testPassingChecksArePrintedToo() {
        // With nine checks, the green lines are the difference between
        // "everything else is fine" and "everything else was skipped".
        let text = DoctorChecks.run(healthyInputs()).text()
        XCTAssertTrue(text.contains("✓ Calendar access"), text)
        XCTAssertTrue(text.contains("✓ Config"), text)
    }

    func testEveryNonPassingFindingCarriesARemediation() {
        // The rule that makes the output actionable rather than a status wall.
        var inputs = healthyInputs()
        inputs.access = .denied
        inputs.config = .failure(ConfigError.noSources)
        inputs.scheduling = SchedulingFacts()
        inputs.signing = SigningFacts(designatedRequirement: "cdhash H\"abc123\"")
        inputs.notifications = .denied
        inputs.logBytes = 40 * 1024 * 1024
        inputs.lastRun = LastRun(
            finishedAt: Date(timeIntervalSinceNow: -86400), succeeded: true, summary: "0 created"
        )

        for finding in DoctorChecks.run(inputs).findings
            where finding.severity == .error || finding.severity == .warning {
            XCTAssertNotNil(
                finding.remediation,
                "\"\(finding.title)\" tells the user something is wrong but not what to do"
            )
        }
    }

    // MARK: 1. Calendar access — highest precedence

    func testDeniedAccessExitsTwo() {
        var inputs = healthyInputs()
        inputs.access = .denied
        inputs.calendars = nil
        XCTAssertEqual(DoctorChecks.run(inputs).exitCode(), ExitCodes.permissionError)
    }

    func testAccessOutranksAConfigErrorInTheExitCode() {
        // Without calendar access every calendar answer is a guess, so it is
        // the one to report even when config is also broken.
        var inputs = healthyInputs()
        inputs.access = .denied
        inputs.calendars = nil
        inputs.config = .failure(ConfigError.noSources)
        XCTAssertEqual(DoctorChecks.run(inputs).exitCode(), ExitCodes.permissionError)
    }

    func testWriteOnlyAccessIsAnErrorAndSaysWhyItLooksHealthy() throws {
        // The nastiest state: nothing throws. Queries succeed against a virtual
        // calendar and return zero events, so passes report clean runs having
        // mirrored nothing.
        var inputs = healthyInputs()
        inputs.access = .writeOnly
        inputs.calendars = nil

        let found = try finding("calendar-access", in: DoctorChecks.run(inputs))
        XCTAssertEqual(found.severity, .error)
        XCTAssertTrue(
            found.detail.joined(separator: " ").lowercased().contains("cannot read"),
            "write-only must be explained, not just named: \(found.detail)"
        )
    }

    func testNotDeterminedIsFixedByRunningTheAppNotByVisitingSettings() throws {
        var inputs = healthyInputs()
        inputs.access = .notDetermined
        inputs.calendars = nil

        let remediation = try XCTUnwrap(finding("calendar-access", in: DoctorChecks.run(inputs)).remediation)
        XCTAssertFalse(
            remediation.contains("System Settings"),
            "WorkSync is not listed in Settings until it has asked once: \(remediation)"
        )
    }

    func testRestrictedAccessAlsoExitsTwoButSaysItCannotBeSelfServed() throws {
        var inputs = healthyInputs()
        inputs.access = .restricted
        inputs.calendars = nil

        let report = DoctorChecks.run(inputs)
        XCTAssertEqual(report.exitCode(), ExitCodes.permissionError)
        let remediation = try XCTUnwrap(finding("calendar-access", in: report).remediation)
        XCTAssertTrue(remediation.contains("profile"), remediation)
    }

    func testEveryAccessStateIsHandled() {
        // Guards against a new EventKit state defaulting into silence.
        for access in CalendarAccess.allCases where access != .fullAccess {
            XCTAssertNotNil(access.remediation, "\(access) has no remediation")
            XCTAssertNotNil(access.detail, "\(access) has no explanation")
        }
        XCTAssertNil(CalendarAccess.fullAccess.remediation, "nothing to fix when access is granted")
    }

    // MARK: 2. Config

    func testAMissingConfigExitsOneAndPointsAtInit() throws {
        var inputs = healthyInputs()
        inputs.config = .failure(ConfigError.fileNotFound("/tmp/config.toml"))

        let report = DoctorChecks.run(inputs)
        XCTAssertEqual(report.exitCode(), ExitCodes.configError)
        XCTAssertTrue(
            try XCTUnwrap(finding("config", in: report).remediation).contains("worksync init"),
            "a missing config has a one-command fix"
        )
    }

    func testDownstreamChecksAreSkippedNotFailedWhenConfigIsUnusable() throws {
        // One root cause must not print as three red lines.
        var inputs = healthyInputs()
        inputs.config = .failure(ConfigError.noSources)

        let report = DoctorChecks.run(inputs)
        XCTAssertEqual(try finding("calendars-resolve", in: report).severity, .skipped)
        XCTAssertEqual(try finding("target-writable", in: report).severity, .skipped)
    }

    func testDownstreamChecksAreSkippedWhenAccessIsMissing() throws {
        var inputs = healthyInputs()
        inputs.access = .denied
        inputs.calendars = nil

        let report = DoctorChecks.run(inputs)
        let resolve = try finding("calendars-resolve", in: report)
        XCTAssertEqual(resolve.severity, .skipped)
        XCTAssertTrue(
            resolve.detail.joined().contains("calendar access"),
            "the skip must name the thing to fix: \(resolve.detail)"
        )
    }

    // MARK: 3. Resolution

    func testEveryResolutionProblemIsListedNotJustTheFirst() throws {
        // The point of resolveAll: the user edits the file once.
        var broken = config()
        broken.sources = [
            SourceConfig(id: "a", account: "Nope", calendar: "Personal"),
            SourceConfig(id: "b", account: "iCloud", calendar: "Missing"),
        ]
        var inputs = healthyInputs()
        inputs.config = .success(broken)

        let found = try finding("calendars-resolve", in: DoctorChecks.run(inputs))
        XCTAssertEqual(found.severity, .error)
        let text = found.detail.joined(separator: "\n")
        XCTAssertTrue(text.contains("Nope"), text)
        XCTAssertTrue(text.contains("Missing"), text)
    }

    func testResolutionFailureExitsOne() {
        var broken = config()
        broken.sources = [SourceConfig(id: "a", account: "Nope", calendar: "Personal")]
        var inputs = healthyInputs()
        inputs.config = .success(broken)
        XCTAssertEqual(DoctorChecks.run(inputs).exitCode(), ExitCodes.configError)
    }

    func testResolutionOutputNamesCalendarsAndAccountsOnly() throws {
        // Doctor output is what users paste into bug reports, and the tool's
        // whole premise is that personal details must not leak.
        let found = try finding("calendars-resolve", in: DoctorChecks.run(healthyInputs()))
        XCTAssertTrue(found.detail.joined().contains("iCloud / Personal"), "\(found.detail)")
    }

    // MARK: 4. Writability

    func testAReadOnlyTargetIsAnErrorBeforeAPassRatherThanAtWriteTime() throws {
        var inputs = healthyInputs()
        inputs.calendars = .success([
            personalCal,
            CalendarRef(id: "cal-work", title: "Calendar", accountTitle: "Work", allowsModifications: false),
        ])

        let report = DoctorChecks.run(inputs)
        let found = try finding("target-writable", in: report)
        XCTAssertEqual(found.severity, .error)
        XCTAssertEqual(report.exitCode(), ExitCodes.configError, "the fix is in config.toml")
    }

    func testWritabilityRemediationNamesTheConfigActuallyInUse() throws {
        // doctor honours --config, so naming the default path would send a
        // user diagnosing a custom config to edit a file that is not in play —
        // and the edit would then change nothing about the failing run.
        var inputs = healthyInputs()
        inputs.configPath = "/Users/someone/work/alt-worksync.toml"
        inputs.calendars = .success([
            personalCal,
            CalendarRef(id: "cal-work", title: "Calendar", accountTitle: "Work", allowsModifications: false),
        ])

        let remediation = try XCTUnwrap(finding("target-writable", in: DoctorChecks.run(inputs)).remediation)
        XCTAssertTrue(remediation.contains("/Users/someone/work/alt-worksync.toml"), remediation)
        XCTAssertFalse(
            remediation.contains(ConfigLoader.defaultPath),
            "the default path is not the file being diagnosed: \(remediation)"
        )
    }

    func testEveryRemediationThatNamesAConfigFileNamesTheRightOne() {
        // Guards the whole class rather than the one instance the review
        // found: any check that points at a config file must point at the one
        // doctor was actually given.
        var inputs = healthyInputs()
        inputs.configPath = "/Users/someone/work/alt-worksync.toml"
        inputs.config = .failure(ConfigError.noSources)

        for finding in DoctorChecks.run(inputs).findings {
            let text = (finding.detail + [finding.remediation ?? ""]).joined(separator: " ")
            guard text.contains("config.toml") || text.contains(".toml") else { continue }
            XCTAssertFalse(
                text.contains(ConfigLoader.defaultPath),
                "\"\(finding.id)\" names the default config instead of the one in use: \(text)"
            )
        }
    }

    // MARK: 5. Something is running

    func testNothingScheduledIsAnError() throws {
        var inputs = healthyInputs()
        inputs.scheduling = SchedulingFacts()

        let report = DoctorChecks.run(inputs)
        XCTAssertEqual(try finding("scheduling", in: report).severity, .error)
        XCTAssertEqual(report.exitCode(), ExitCodes.partialFailure)
    }

    func testAnyOneSchedulingMechanismIsEnough() throws {
        // Three ways to install it; requiring a particular one would fail on
        // perfectly healthy machines.
        let mechanisms = [
            SchedulingFacts(loginItemEnabled: true),
            SchedulingFacts(launchAgentLoaded: true),
            SchedulingFacts(menubar: .running),
        ]
        for scheduling in mechanisms {
            var inputs = healthyInputs()
            inputs.scheduling = scheduling
            XCTAssertEqual(
                try finding("scheduling", in: DoctorChecks.run(inputs)).severity, .ok,
                "\(scheduling) should satisfy the check on its own"
            )
        }
    }

    func testAnUnverifiableMenuBarProbeIsNotTreatedAsRunning() throws {
        // The failure mode this prevents: folding "could not check" into
        // "running" turns a broken lock directory into a green scheduling
        // check — a false all-clear on the single most common cause of
        // "why didn't this sync", delivered exactly when the machine is
        // already in a bad state.
        var inputs = healthyInputs()
        inputs.scheduling = SchedulingFacts(menubar: .unknown("Permission denied"))

        let found = try finding("scheduling", in: DoctorChecks.run(inputs))
        XCTAssertNotEqual(found.severity, .ok, "an unchecked probe must never read as healthy")
        XCTAssertTrue(
            found.detail.joined(separator: " ").contains("Permission denied"),
            "the reason the probe failed is the actionable part: \(found.detail)"
        )
    }

    func testAnUnverifiableProbeExitsThreeRatherThanClaimingNothingIsScheduled() {
        // Exit 3 is "a check itself blew up". Reporting .nothingScheduled here
        // would overstate what is actually known.
        var inputs = healthyInputs()
        inputs.scheduling = SchedulingFacts(menubar: .unknown("Operation not permitted"))
        XCTAssertEqual(DoctorChecks.run(inputs).exitCode(), ExitCodes.partialFailure)
    }

    func testAConfirmedMechanismStillWinsOverAFailedProbe() throws {
        // A registered login item is proof on its own, so a broken probe must
        // not turn a healthy machine red either.
        var inputs = healthyInputs()
        inputs.scheduling = SchedulingFacts(
            loginItemEnabled: true, menubar: .unknown("Permission denied")
        )
        XCTAssertEqual(try finding("scheduling", in: DoctorChecks.run(inputs)).severity, .ok)
    }

    func testTheProbeFailureNamesItsWiderConsequence() throws {
        // The same failure stops `sync` taking its pass lock, so this is not
        // merely a gap in the diagnostic — nothing runs until it is fixed.
        var inputs = healthyInputs()
        inputs.scheduling = SchedulingFacts(menubar: .unknown("Permission denied"))

        let found = try finding("scheduling", in: DoctorChecks.run(inputs))
        XCTAssertTrue(
            found.detail.joined(separator: " ").contains("worksync sync"),
            "\(found.detail)"
        )
    }

    // MARK: 6. Signing (warning)

    func testABareCdhashRequirementWarnsAndNeverChangesTheExitCode() throws {
        // Release tarballs are ad-hoc signed on purpose, so this fires for
        // every user of one — it must never be fatal.
        var inputs = healthyInputs()
        inputs.signing = SigningFacts(designatedRequirement: "cdhash H\"a1b2c3\"")

        let report = DoctorChecks.run(inputs)
        XCTAssertEqual(try finding("code-signature", in: report).severity, .warning)
        XCTAssertEqual(report.exitCode(), 0, "warnings never change the exit code")
    }

    func testAnIdentifierAnchoredRequirementPasses() {
        XCTAssertFalse(
            SigningFacts(designatedRequirement:
                "identifier \"io.gamov.worksync\" and anchor apple generic").isBareCdhash
        )
        XCTAssertTrue(SigningFacts(designatedRequirement: "cdhash H\"abc\"").isBareCdhash)
        XCTAssertFalse(SigningFacts().isBareCdhash, "unknown is not the same as bad")
    }

    func testAnUnreadableSignatureIsSkippedRatherThanAssumedBad() throws {
        var inputs = healthyInputs()
        inputs.signing = SigningFacts(designatedRequirement: nil)
        XCTAssertEqual(try finding("code-signature", in: DoctorChecks.run(inputs)).severity, .skipped)
    }

    // MARK: 7. Staleness (warning)

    func testStalenessIsGenerousEnoughNotToFireEveryMorning() {
        // A closed laptop is not a fault. Three intervals, floor of 30 minutes.
        XCTAssertEqual(DoctorChecks.stalenessThreshold(intervalMinutes: 10), 30 * 60)
        XCTAssertEqual(DoctorChecks.stalenessThreshold(intervalMinutes: 1), 30 * 60, "the floor holds")
        XCTAssertEqual(DoctorChecks.stalenessThreshold(intervalMinutes: 60), 3 * 3600)
    }

    func testARunJustInsideTheThresholdDoesNotWarn() throws {
        let now = Date()
        var inputs = healthyInputs()
        inputs.now = now
        inputs.lastRun = LastRun(
            finishedAt: now.addingTimeInterval(-29 * 60), succeeded: true, summary: "0 created"
        )
        XCTAssertEqual(try finding("last-run", in: DoctorChecks.run(inputs)).severity, .ok)
    }

    func testAClearlyOverdueRunWarnsWithoutFailing() throws {
        let now = Date()
        var inputs = healthyInputs()
        inputs.now = now
        inputs.lastRun = LastRun(
            finishedAt: now.addingTimeInterval(-6 * 3600), succeeded: true, summary: "0 created"
        )

        let report = DoctorChecks.run(inputs)
        XCTAssertEqual(try finding("last-run", in: report).severity, .warning)
        XCTAssertEqual(report.exitCode(), 0)
    }

    func testNeverHavingRunIsSkippedNotStale() throws {
        var inputs = healthyInputs()
        inputs.lastRun = nil
        XCTAssertEqual(
            try finding("last-run", in: DoctorChecks.run(inputs)).severity, .skipped,
            "staleness is unknowable with nothing to measure from"
        )
    }

    // MARK: 8. Notifications (warning)

    func testNotificationsAreNotCheckedWhenNotifyIsOff() throws {
        // A check that fires on a healthy machine is worse than no check.
        XCTAssertEqual(try finding("notifications", in: DoctorChecks.run(healthyInputs())).severity, .skipped)
    }

    func testUnsupportedNotificationsAreNotReportedAsDenied() throws {
        // All-settings-NotSupported means a mis-assembled or directly-launched
        // bundle. Calling it "denied" sends the user to a Settings pane where
        // WorkSync is not listed.
        var inputs = healthyInputs()
        inputs.notifications = .unsupported

        let found = try finding("notifications", in: DoctorChecks.run(inputs))
        XCTAssertEqual(found.severity, .warning)
        let text = (found.detail + [found.remediation ?? ""]).joined(separator: " ")
        XCTAssertFalse(text.lowercased().contains("denied"), text)
        XCTAssertTrue(text.contains("bundle"), text)
    }

    func testAnUnknowableNotificationStateIsSkippedRatherThanWarned() throws {
        // Invoked through a symlink on PATH — how Homebrew installs the CLI —
        // the process is outside the bundle and the notification centre calls
        // every setting unsupported. Warning there would fire on every healthy
        // machine using the CLI, about a capability the CLI never uses.
        var inputs = healthyInputs()
        inputs.notifications = .unavailable("only checkable from the app")

        let found = try finding("notifications", in: DoctorChecks.run(inputs))
        XCTAssertEqual(found.severity, .skipped, "unknowable is not the same as wrong")
        XCTAssertEqual(DoctorChecks.run(inputs).exitCode(), 0)
    }

    func testDeniedNotificationsWarnAndOfferBothWaysOut() throws {
        var inputs = healthyInputs()
        inputs.notifications = .denied

        let found = try finding("notifications", in: DoctorChecks.run(inputs))
        XCTAssertEqual(found.severity, .warning)
        let remediation = try XCTUnwrap(found.remediation)
        XCTAssertTrue(remediation.contains("notify"), "turning notifications off is a valid fix too")
    }

    // MARK: 9. Log size (warning)

    func testAnOversizedLogWarnsThatRotationIsBroken() throws {
        var inputs = healthyInputs()
        inputs.logBytes = 40 * 1024 * 1024

        let report = DoctorChecks.run(inputs)
        XCTAssertEqual(try finding("log-size", in: report).severity, .warning)
        XCTAssertEqual(report.exitCode(), 0)
    }

    func testANormalLogDoesNotWarn() throws {
        var inputs = healthyInputs()
        inputs.logBytes = 900 * 1024
        XCTAssertEqual(try finding("log-size", in: DoctorChecks.run(inputs)).severity, .ok)
    }

    // MARK: Exit codes and --strict

    func testWarningsNeverChangeTheExitCodeByDefault() {
        let report = DoctorReport(findings: [
            .ok(id: "a", "A"),
            .warning(id: "b", "B", remediation: "do the thing"),
        ])
        XCTAssertEqual(report.exitCode(), 0)
    }

    func testStrictPromotesWarningsForCI() {
        let report = DoctorReport(findings: [.warning(id: "b", "B", remediation: "do the thing")])
        XCTAssertEqual(report.exitCode(strict: true), ExitCodes.configError)
    }

    func testStrictDoesNotDowngradeARealError() {
        let report = DoctorReport(findings: [
            .warning(id: "b", "B", remediation: "x"),
            .failure(id: "c", "C", cause: CalendarStoreError.accessDenied, remediation: "y"),
        ])
        XCTAssertEqual(report.exitCode(strict: true), ExitCodes.permissionError)
    }

    func testSkippedChecksNeverChangeTheExitCode() {
        let report = DoctorReport(findings: [.skipped(id: "a", "A", because: "needs calendar access")])
        XCTAssertEqual(report.exitCode(), 0)
        XCTAssertEqual(report.exitCode(strict: true), 0, "skipped is not a warning")
    }

    // MARK: Output

    func testGlyphsAreDistinctSoSeveritySurvivesAPipe() {
        let glyphs = DoctorSeverity.allCases.map(\.glyph)
        XCTAssertEqual(Set(glyphs).count, glyphs.count, "colour is decoration; the glyph is the signal")
    }

    func testDetailIsHiddenForPassingChecksUnlessVerbose() {
        let report = DoctorReport(findings: [.ok(id: "a", "A", detail: ["chatty detail"])])
        XCTAssertFalse(report.text().contains("chatty detail"))
        XCTAssertTrue(report.text(verbose: true).contains("chatty detail"))
    }

    func testRemediationIsShownForFailingChecksWithoutVerbose() {
        let report = DoctorReport(findings: [
            .failure(id: "a", "A", cause: ConfigError.noSources, remediation: "run this"),
        ])
        XCTAssertTrue(report.text().contains("→ run this"), report.text())
    }

    func testMultiLineRemediationStaysIndented() {
        // A copy-pasteable command on its own line must not lose its indent and
        // read as another finding.
        let report = DoctorReport(findings: [
            .warning(id: "a", "A", remediation: "Re-sign it:\ncodesign --force --sign X app"),
        ])
        XCTAssertTrue(report.text().contains("    → codesign --force --sign X app"), report.text())
    }

    func testSummaryCountsEachSeverity() {
        let report = DoctorReport(findings: [
            .ok(id: "a", "A"),
            .warning(id: "b", "B", remediation: "x"),
            .skipped(id: "c", "C", because: "y"),
            .failure(id: "d", "D", cause: ConfigError.noSources, remediation: "z"),
        ])
        XCTAssertEqual(report.summaryLine, "4 checks: 1 error, 1 warning, 1 skipped.")
    }

    func testSummarySaysSoWhenEverythingPassed() {
        XCTAssertEqual(
            DoctorReport(findings: [.ok(id: "a", "A"), .ok(id: "b", "B")]).summaryLine,
            "All 2 checks passed."
        )
    }

    func testJSONCarriesTheExitCodeAndEveryFinding() throws {
        let json = try DoctorChecks.run(healthyInputs()).json()
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        XCTAssertEqual(parsed["exit_code"] as? Int, 0)
        let findings = try XCTUnwrap(parsed["findings"] as? [[String: Any]])
        XCTAssertTrue(findings.contains { $0["id"] as? String == "calendar-access" })
        XCTAssertTrue(findings.allSatisfy { $0["severity"] != nil })
    }

    // MARK: Destinations (the menu bar's buttons)

    func testEveryFixableFindingHasSomewhereToSendTheUser() {
        for id in ["calendar-access", "config", "calendars-resolve", "target-writable", "scheduling"] {
            XCTAssertNotNil(
                DoctorDestination.forFinding(id: id),
                "\"\(id)\" is fixable in the UI but offers no button"
            )
        }
    }

    func testTerminalOnlyFixesOfferNoButtonRatherThanADeadOne() {
        // Re-signing, catching up a stale run, and deleting an oversized log
        // are all commands. A button that cannot run them is worse than the
        // command written out.
        for id in ["code-signature", "last-run", "log-size"] {
            XCTAssertNil(DoctorDestination.forFinding(id: id), "\"\(id)\" should show its command instead")
        }
    }

    func testAnUnknownFindingIDHasNoDestination() {
        XCTAssertNil(DoctorDestination.forFinding(id: "invented-later"))
    }

    func testEveryDestinationIsReachableFromSomeCheck() {
        // Guards the other direction: a destination nothing maps to is dead
        // code that looks like a feature.
        let reachable = Set(
            DoctorChecks.run(healthyInputs()).findings.compactMap { DoctorDestination.forFinding(id: $0.id) }
        )
        XCTAssertEqual(reachable.count, 4, "some destination is unreachable: \(reachable)")
    }

    func testJSONIDsAreStableAcrossWordingChanges() {
        // --json consumers and the menu bar match on ids, so they are part of
        // the contract in a way the titles are not.
        let ids = DoctorChecks.run(healthyInputs()).findings.map(\.id)
        XCTAssertEqual(ids, [
            "calendar-access", "config", "calendars-resolve", "target-writable",
            "scheduling", "code-signature", "last-run", "notifications", "log-size",
        ])
    }
}
